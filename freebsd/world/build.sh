#! /bin/sh

JAIL_PATH=${WORKSPACE}
JAIL_NAME=world14
LLVM_VER=15

CROSS_TOOLCHAIN=llvm${LLVM_VER}
FETCH_ARGS=$( test ! -f base.txz || echo "-i base.txz" )
JAIL_VERSION=14.0-CURRENT
ARCH=$(uname -m)
NUM_CPUS=$(sysctl -n kern.smp.cpus)
if test "${JAIL_VERSION#*-}" = "RELEASE"; then
    SNAPSHOT_URL="https://download.freebsd.org/releases/${ARCH}/${JAIL_VERSION}/base.txz"
else
    SNAPSHOT_URL="https://download.freebsd.org/snapshots/${ARCH}/${JAIL_VERSION}/base.txz"
fi
fetch -v ${FETCH_ARGS} "${SNAPSHOT_URL}"
if test ! COPYRIGHT -nt base.txz; then
    tar xmf base.txz
    find . \( -path ./dev -o -path ./usr/src -o -path ./usr/obj \) -prune -o ! -newer base.txz -ls
fi
mkdir -p dev

trap 'jail -vr ${JAIL_NAME}' EXIT

jail -vcmr name=${JAIL_NAME} persist path=${JAIL_PATH} mount.devfs devfs_ruleset=0 ip4=inherit
#echo "
#COMPILER_TYPE=clang
#CC=/usr/local/bin/clang${LLVM_VER}
#CXX=/usr/local/bin/clang++${LLVM_VER}
#CPP=/usr/local/bin/clang-cpp${LLVM_VER}
#LD=/usr/local/bin/ld.lld${LLVM_VER}
#" > ${JAIL_PATH}/etc/make.conf
echo "
NO_INSTALLEXTRAKERNELS=no
KERNCONF=GENERIC-NODEBUG GENERIC
CROSS_TOOLCHAIN=${CROSS_TOOLCHAIN}
WITHOUT_TOOLCHAIN=yes
WITHOUT_CROSS_COMPILER=yes
WITHOUT_TESTS=yes
" > ${JAIL_PATH}/etc/src.conf
# jexec ${JAIL_NAME} rm -f /usr/bin/cc /usr/bin/c++
cp -p /etc/resolv.conf ${JAIL_PATH}/etc/
pkg -j ${JAIL_NAME} install -y ${CROSS_TOOLCHAIN}
#jexec ${JAIL_NAME} sh -c "yes | /usr/bin/make -C /usr/src delete-old"
jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j${NUM_CPUS} buildworld buildkernel
cp -p /etc/resolv.conf ${JAIL_PATH}/etc/
sed -i .sed.bak s/quarterly/latest/ ${JAIL_PATH}/etc/pkg/FreeBSD.conf
# clean up old builds
test -d ${JAIL_PATH}/usr/obj/usr/src/repo && rm -r ${JAIL_PATH}/usr/obj/usr/src/repo
jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j${NUM_CPUS} packages
jail -vr ${JAIL_NAME}
