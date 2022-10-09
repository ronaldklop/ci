#! /bin/sh

JAIL_PATH=${WORKSPACE}
JAIL_NAME=world
FETCH_ARGS=$( test ! -f base.txz || echo "-i base.txz" )
fetch -v ${FETCH_ARGS} "https://download.freebsd.org/ftp/releases/arm64/13.0-RELEASE/base.txz"
if test ! COPYRIGHT -nt base.txz; then
    tar xmf base.txz
    find . \( -path ./dev -o -path ./usr/src -o -path ./usr/obj \) -prune -o ! -newer base.txz -ls
fi
jail -cmr name=${JAIL_NAME} persist path=${JAIL_PATH} mount.devfs devfs_ruleset=0 ip4=inherit
jexec ${JAIL_NAME} truncate -s 0 /etc/src.conf
jexec ${JAIL_NAME} echo "NO_INSTALLEXTRAKERNELS=no" >> /etc/src.conf
jexec ${JAIL_NAME} echo "KERNCONF=GENERIC-NODEBUG GENERIC" >> /etc/src.conf
jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j4 -DWITHOUT_CLEAN buildworld buildkernel
cp -p /etc/resolv.conf ${JAIL_PATH}/etc/
sed -i .sed.bak s/quarterly/latest/ ${JAIL_PATH}/etc/pkg/FreeBSD.conf
# clean up old builds
if test -d ${JAIL_PATH}/usr/obj/usr/src/repo; then
    rm -r ${JAIL_PATH}/usr/obj/usr/src/repo
fi
jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j4 packages
