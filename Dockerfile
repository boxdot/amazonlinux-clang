FROM amazonlinux

ADD build-clang.sh .
RUN ./build-clang.sh
