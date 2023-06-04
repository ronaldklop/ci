#! /bin/sh

JAIL_PATH=${WORKSPACE}
JAIL_NAME=world14
LLVM_VER=15

CROSS_TOOLCHAIN=llvm${LLVM_VER}
FETCH_ARGS=$( test ! -f base.txz || echo "-i base.txz" )
fetch -v ${FETCH_ARGS} "https://download.freebsd.org/ftp/releases/arm64/13.2-RELEASE/base.txz"
if test ! COPYRIGHT -nt base.txz; then
    tar xmf base.txz
    find . \( -path ./dev -o -path ./usr/src -o -path ./usr/obj \) -prune -o ! -newer base.txz -ls
fi
mkdir -p dev
jail -cmr name=${JAIL_NAME} persist path=${JAIL_PATH} mount.devfs devfs_ruleset=0 ip4=inherit
echo "
COMPILER_TYPE=clang
CC=/usr/local/bin/clang${LLVM_VER}
CXX=/usr/local/bin/clang++${LLVM_VER}
CPP=/usr/local/bin/clang-cpp${LLVM_VER}
LD=/usr/local/bin/ld.lld${LLVM_VER}
" > ${JAIL_PATH}/etc/make.conf
echo "
NO_INSTALLEXTRAKERNELS=no
KERNCONF=GENERIC-NODEBUG GENERIC
#CROSS_TOOLCHAIN=${CROSS_TOOLCHAIN}
WITHOUT_CLANG=yes
WITHOUT_TOOLCHAIN=yes
WITHOUT_CROSS_COMPILER=yes
" > ${JAIL_PATH}/etc/src.conf
# jexec ${JAIL_NAME} rm -f /usr/bin/cc /usr/bin/c++
cp -p /etc/resolv.conf ${JAIL_PATH}/etc/
pkg -j ${JAIL_NAME} install -y ${CROSS_TOOLCHAIN}
#jexec ${JAIL_NAME} sh -c "yes | /usr/bin/make -C /usr/src delete-old"
jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j4 buildworld buildkernel
cp -p /etc/resolv.conf ${JAIL_PATH}/etc/
sed -i .sed.bak s/quarterly/latest/ ${JAIL_PATH}/etc/pkg/FreeBSD.conf
# clean up old builds
rm -r ${JAIL_PATH}/usr/obj/usr/src/repo
jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j4 packages
