#!/usr/bin/env bash
set -ex

# Install:
#  * git
#  * cmake
#  * clang
#  * compiler-rt
#  * libc++
#  * libc++abi
#  * libunwind

install_tools() {
	echo "Installing tools"
	yum install -y gcc gcc-c++ git-core
}

build_and_install_cmake() {
	echo "Installing recent cmake..."
	version_minor=3.7
	version=3.7.2
	src=/tmp/cmake
	md5=79bd7e65cd81ea3aa2619484ad6ff25a
	mkdir -p $src

	curl https://cmake.org/files/v${version_minor}/cmake-${version}.tar.gz > $src/cmake-${version}.tar.gz
	echo "$md5 cmake-${version}.tar.gz" > $src/cmake-${version}.tar.gz.md5
	( cd $src && md5sum -c $src/cmake-${version}.tar.gz.md5 )
	tar xfz $src/cmake-${version}.tar.gz -C $src
	( cd $src/cmake-${version} && ./configure && make && make install )
}

download_llvm() {
	echo "Downloading llvm..."
	version=release_39
	src=/tmp/llvm/src/llvm
	url=https://github.com/llvm-mirror
	mkdir -p $src

	args="--depth 1 --branch $version --single-branch"
	git clone $args $url/llvm.git $src

	( cd $src/tools && git clone $args $url/clang.git )
	( cd $src/projects && git clone $args $url/compiler-rt )
	( cd $src/projects && git clone $args $url/libcxx )
	( cd $src/projects && git clone $args $url/libcxxabi )
	( cd $src/projects && git clone $args $url/libunwind )
}

build_and_install_llvm() {
	echo "Building llvm..."
	src=/tmp/llvm
	mkdir $src/build
	( cd $src/build && cmake .. -DCMAKE_BUILD_TYPE=Release && make && make install )
}

clean_up() {
	echo "Cleaning up..."
	rm -rf /tmp/cmake /tmp/llvm
	yum autoremove -y
	yum clean all
}

# install_tools
# build_and_install_cmake
download_llvm
# build_and_install_llvm
# clean_up


# stage 0: build clang with system compiler
src=/tmp/llvm/src/llvm
mkdir -p $src/stage_0
( cd $src/stage_0 && \
	cmake .. \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/tmp/llvm/stage_0 \
		-DLLVM_TARGETS_TO_BUILD=host \
		-DLLVM_BUILD_TOOLS=0 && \
	make -j12 clang
)
( cd $src/stage_0/tools/clang && make install )

# stage 1: build clang, compiler-rt, libc++, libc++abi, libunwind with clang from stage 0
prefix=/tmp/llvm
src=$prefix/src/llvm
mkdir -p $src/stage_1
( cd $src/stage_1 && \
	CC=$prefix/stage_0/bin/clang \
	CXX=$prefix/stage_0/bin/clang++ \
	cmake .. \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=$prefix/stage_1 \
		-DLLVM_TARGETS_TO_BUILD=host \
		-DLLVM_BUILD_TOOLS=0 \
		-DC_INCLUDE_DIRS=/usr/include && \
	make -j12 clang compiler-rt cxx cxxabi unwind
)
( cd $src/stage_1/tools/clang && make install )
( cd $src/stage_1/projects/libcxx && make install )
( cd $src/stage_1/projects/libcxxabi && make install )
( cd $src/stage_1/projects/compiler-rt && make install )
( cd $src/stage_1/projects/libunwind && make install )

# At this point we still have the following dependencies on gcc:
#   clang:  	librt, libstdc++, libgcc_s
#   libc++: 	librt, libgcc_s
#   libc++abi: 	libgcc_s
#   libunwind:	none

# stage 2: build clang, compiler-rt, libc++, libc++abi, libunwind with clang and libs from stage 1
prefix=/tmp/llvm
src=$prefix/src/llvm
include_sys=`find /usr/include | grep sys/cdefs.h | xargs dirname | xargs dirname`
mkdir -p $src/stage_2
( cd $src/stage_2 && \
	CC=$prefix/stage_1/bin/clang \
	CXX=$prefix/stage_1/bin/clang++ \
	CFLAGS="-I${include_sys}" \
	CXXFLAGS="-stdlib=libc++ -I${include_sys}" \
	LDFLAGS="-lc++abi -lunwind -rtlib=compiler-rt" \
	cmake .. \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=$prefix/stage_2 \
		-DLLVM_TARGETS_TO_BUILD=host \
		-DLLVM_BUILD_TOOLS=0 \
		-DLLVM_NO_OLD_LIBSTDCXX=1 \
		-DLIBCXXABI_USE_COMPILER_RT=YES \
		-DLIBCXXABI_USE_LLVM_UNWINDER=YES \
		-DCLANG_DEFAULT_CXX_STDLIB="libc++" \
		-DC_INCLUDE_DIRS="${include_sys}:/usr/include" \
		&& \
	make -j12 clang compiler-rt cxx cxxabi unwind
)
( cd $src/stage_2/tools/clang && make install )
( cd $src/stage_2/projects/libcxx && make install )
( cd $src/stage_2/projects/libcxxabi && make install )
( cd $src/stage_2/projects/compiler-rt && make install )
( cd $src/stage_2/projects/libunwind && make install )

# At this point we still have the following dependencies on gcc:
#   clang:  	librt, libgcc_s
#   libc++: 	librt, libgcc_s
#   libc++abi: 	none
#   libunwind:	none

prefix=/tmp/llvm
src=$prefix/src/llvm
include_sys=`find /usr/include | grep sys/cdefs.h | xargs dirname | xargs dirname`
mkdir -p $src/stage_3
( cd $src/stage_3 && \
	CC=$prefix/stage_2/bin/clang \
	CXX=$prefix/stage_2/bin/clang++ \
	CFLAGS="-I${include_sys}" \
	CXXFLAGS="-stdlib=libc++ -I${include_sys}" \
	LDFLAGS="-lc++abi -lunwind -rtlib=compiler-rt" \
	cmake .. \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=$prefix/stage_3 \
		-DLLVM_TARGETS_TO_BUILD=host \
		-DLLVM_BUILD_TOOLS=0 \
		-DLLVM_NO_OLD_LIBSTDCXX=1 \
		-DLIBCXXABI_USE_COMPILER_RT=YES \
		-DLIBCXXABI_USE_LLVM_UNWINDER=YES \
		-DCLANG_DEFAULT_CXX_STDLIB="libc++" \
		-DC_INCLUDE_DIRS="${include_sys}:/usr/include" \
		&& \
	make -j12 clang compiler-rt cxx cxxabi unwind
)
( cd $src/stage_3/tools/clang && make install )
( cd $src/stage_3/projects/libcxx && make install )
( cd $src/stage_3/projects/libcxxabi && make install )
( cd $src/stage_3/projects/compiler-rt && make install )
( cd $src/stage_3/projects/libunwind && make install )
