# Build environment for ASUS HND (BCM6756 / src-rt-5.04axhnd.675x) GPL and Asuswrt-Merlin trees.
# The ARM toolchain is NOT baked in: bind-mount the GPL package's own
#   release/src-rt-5.04axhnd.675x/toolchains  ->  /opt/toolchains   (read-only)
# so the compiler used is exactly the one ASUS shipped with the package.
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
# cc1/cc1plus/lto1 load libisl/libmpc/libmpfr/libgmp from the toolchain's own lib dir
# (no RPATH); same setting the Asuswrt-Merlin build docs use for the HND toolchains.
ENV LD_LIBRARY_PATH=/opt/toolchains/crosstools-arm-gcc-9.2-linux-4.19-glibc-2.30-binutils-2.32/usr/lib:/opt/toolchains/crosstools-aarch64-gcc-9.2-linux-4.19-glibc-2.30-binutils-2.32/usr/lib
RUN dpkg --add-architecture i386 && apt-get update && apt-get install -y --no-install-recommends \
      autoconf autogen automake autopoint bash bc binutils bison build-essential bzip2 ca-certificates \
      cmake cpio cvs device-tree-compiler diffutils dos2unix file flex g++ g++-multilib gawk gcc-multilib \
      gettext git gperf groff-base gtk-doc-tools intltool kmod lib32stdc++6 lib32z1-dev libelf-dev \
      libelf1 libelf1:i386 libexpat1-dev libglib2.0-dev libltdl-dev liblzo2-dev libncurses5 \
      libncurses5-dev libproxy-dev libslang2 libssl-dev libtool libtool-bin libvorbis-dev libxml-parser-perl \
      libxml2-dev lzop m4 make mtd-utils patch perl pkg-config python2 python3 python-is-python3 rsync \
      sed shtool sudo subversion tar texinfo u-boot-tools unzip uuid-dev wget xsltproc xutils-dev xxd xz-utils openssl python3-yaml python3-pycryptodome python3-pyelftools \
      zlib1g zlib1g-dev zstd \
 && rm -rf /var/lib/apt/lists/* \
 && ln -sf bash /bin/sh
# Stock ASUS GPL trees regenerate some configure scripts (e.g. iperf3/bootstrap.sh) and
# expect autoconf 2.69; 2.71 emits broken AC_EGREP_CPP checks there. Merlin carries its own
# fix, so only the stock-build image switches: docker build --build-arg STOCK_AUTOCONF=1
ARG STOCK_AUTOCONF=0
RUN if [ "$STOCK_AUTOCONF" = 1 ]; then apt-get update && apt-get install -y --no-install-recommends autoconf2.69 \
      && rm -rf /var/lib/apt/lists/* \
      && for t in autoconf autoheader autom4te autoreconf autoscan autoupdate ifnames; do \
           ln -sf /usr/bin/${t}2.69 /usr/local/bin/$t; done; fi
ARG UID=1000
ARG GID=1000
# The ASUS HND Makefiles call sudo (e.g. roldconf: sudo mkdir /projects/bca/...); container-local only.
RUN groupadd -g ${GID} builder && useradd -m -u ${UID} -g ${GID} -s /bin/bash builder \
 && echo "builder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/builder && chmod 0440 /etc/sudoers.d/builder
USER builder
WORKDIR /work
