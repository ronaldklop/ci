#! /bin/sh

JAIL_PATH=${WORKSPACE}
JAIL_NAME=world14
LLVM_VER=16

cd ${JAIL_PATH} || exit 1

CROSS_TOOLCHAIN=llvm${LLVM_VER}
FETCH_ARGS=$( test ! -f base.txz || echo "-i base.txz" )
JAIL_VERSION=14.0-CURRENT
ARCH=$(uname -m)
NUM_CPUS=${NUM_CPUS:-$(sysctl -n kern.smp.cpus)}

if test "${JAIL_VERSION#*-}" = "RELEASE"; then
    SNAPSHOT_URL="https://download.freebsd.org/releases/${ARCH}/${JAIL_VERSION}/base.txz"
else
    SNAPSHOT_URL="https://download.freebsd.org/snapshots/${ARCH}/${JAIL_VERSION}/base.txz"
fi
fetch -v ${FETCH_ARGS} "${SNAPSHOT_URL}"
if test ! COPYRIGHT -nt base.txz; then
    chflags -R noschg .
    tar xmf base.txz
    find . \( -path ./dev -o -path ./usr/src -o -path ./usr/obj \) -prune -o ! -newer base.txz -ls
fi

trap 'jail -vr ${JAIL_NAME}' EXIT

mkdir -p dev
jail -vcmr name=${JAIL_NAME} persist path=${JAIL_PATH} mount.devfs devfs_ruleset=0 ip4=inherit

LLVM_DIR=/usr/local/${CROSS_TOOLCHAIN}

echo "" > ${JAIL_PATH}/etc/make.conf
echo "" > ${JAIL_PATH}/etc/src.conf

echo "
CROSS_TOOLCHAIN=${CROSS_TOOLCHAIN}

WITHOUT_TOOLCHAIN=yes
#LD=${LLVM_DIR}/bin/ld.lld
#CC=${LLVM_DIR}/bin/clang
#CXX=${LLVM_DIR}/bin/clang++
#CPP=${LLVM_DIR}/bin/clang-cpp
#OBJCOPY=/usr/local/bin/objcopy

#CFLAGS+=-target x86_64-unknown-freebsd14.0
#CFLAGS+=--sysroot=/data/jails/builder/usr/obj/usr/src/amd64.amd64/tmp
#CFLAGS+=-B/data/jails/builder/usr/obj/usr/src/amd64.amd64/tmp/usr/bin
#WITHOUT_CROSS_COMPILER=yes
#WITHOUT_SYSTEM_COMPILER=yes
#WITHOUT_SYSTEM_LINKER=yes

#WITHOUT_TESTS=yes
#WITHOUT_CLEAN=yes
" > ${JAIL_PATH}/etc/make.conf

# jexec ${JAIL_NAME} rm -f /usr/bin/cc /usr/bin/c++
cp -p /etc/resolv.conf ${JAIL_PATH}/etc/

pkg -j ${JAIL_NAME} delete -a -y
pkg -j ${JAIL_NAME} install -y ${CROSS_TOOLCHAIN} byacc

jexec ${JAIL_NAME} sh -c "yes | /usr/bin/make CC=${LLVM_DIR}/bin/clang LD=${LLVM_DIR}/bin/ld.lld -C /usr/src delete-old delete-old-libs"

cd ${JAIL_PATH}/usr/bin && ln -fs ../local/llvm16/bin/clang cc
cd ${JAIL_PATH}/usr/bin && ln -fs ../local/llvm16/bin/clang CC
cd ${JAIL_PATH}/usr/bin && ln -fs ../local/llvm16/bin/clang++ c++
cd ${JAIL_PATH}/usr/bin && ln -fs ../local/llvm16/bin/clang-cpp cpp
cd ${JAIL_PATH}/usr/bin && ln -fs ../local/llvm16/bin/llvm-objcopy objcopy
cd ${JAIL_PATH}/usr/bin && ln -fs ../local/llvm16/bin/ld
cd ${JAIL_PATH}/usr/bin && ln -fs ../local/bin/yacc

jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j${NUM_CPUS} buildworld buildkernel

sed -i .sed.bak s/quarterly/latest/ ${JAIL_PATH}/etc/pkg/FreeBSD.conf

# clean up old builds
test -d ${JAIL_PATH}/usr/obj/usr/src/repo && rm -r ${JAIL_PATH}/usr/obj/usr/src/repo
#jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j${NUM_CPUS} packages

trap - EXIT
jail -vr ${JAIL_NAME}
