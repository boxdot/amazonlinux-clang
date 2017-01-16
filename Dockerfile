FROM amazonlinux

ADD build.sh .
RUN ./build.sh
