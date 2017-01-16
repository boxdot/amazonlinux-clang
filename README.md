# Clang toolchain based on amazonlinux

Contains
* git (amazonlinux version)
* cmake (3.7.2)
* llvm (3.9)
* clang
* compiler-rt
* libc++
* libc++abi
* libunwind

Compile with:
```(bash)
$ clang++ --stdlib=libc++ main.cpp -o main -lc++abi -lunwind -rtlib=compiler-rt
```

TODO:
* Remove dependency on GCC (staging needed)
