#! /bin/sh

JAIL_PATH=${WORKSPACE}
JAIL_NAME=ports14
FETCH_ARGS=$( test ! -f base.txz || echo "-i base.txz" )
fetch -v ${FETCH_ARGS} "https://download.freebsd.org/ftp/snapshots/arm64/14.0-CURRENT/base.txz"
if test ! COPYRIGHT -nt base.txz; then
    tar xmf base.txz
#    find . \( -path ./dev -o -path ./usr/ports -o -path ./usr/src -o -path ./usr/obj \) -prune -o ! -newer base.txz -ls
    find . \( -path ./dev -o -path ./usr/ports -o -path ./usr/local -o -path ./usr/src -o -path ./usr/obj \) -prune -o \( -type f -a ! -newer base.txz \) -ls
fi
jail -cmr name=${JAIL_NAME} persist path=${JAIL_PATH} mount.devfs devfs_ruleset=0 \
    ip4=inherit children.max=99 \
    allow.mount allow.mount.devfs allow.mount.procfs \
    enforce_statfs=1 allow.mount.nullfs allow.mount.tmpfs \
    "mount=/usr/ports	${JAIL_PATH}/usr/ports	nullfs	ro	0	0"

#jexec ${JAIL_NAME} truncate -s 0 /etc/src.conf
#jexec ${JAIL_NAME} echo "NO_INSTALLEXTRAKERNELS=no" >> /etc/src.conf
#jexec ${JAIL_NAME} echo "KERNCONF=GENERIC-NODEBUG GENERIC" >> /etc/src.conf
#jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j4 -DWITHOUT_CLEAN buildworld buildkernel
cp -p /etc/resolv.conf ${JAIL_PATH}/etc/
sed -i .sed.bak s/quarterly/latest/ ${JAIL_PATH}/etc/pkg/FreeBSD.conf
jexec ${JAIL_NAME} pkg install -y poudriere
#jexec ${JAIL_NAME} poudriere jail -d -j freebsd14
#exit 1
if ! jexec ${JAIL_NAME} poudriere jail -i -j freebsd14; then
    jexec ${JAIL_NAME} poudriere jail -c -j freebsd14 -v 14.0-CURRENT
    jexec ${JAIL_NAME} poudriere ports -c -f none -M /usr/ports -m null -p custom
fi
#jexec ${JAIL_NAME} poudriere jail -u -j freebsd14
echo "
MAKE_JOBS_NUMBER=2
.if \${.CURDIR:M*/databases/mongodb*}
MAKE_JOBS_NUMBER=4
OPTIONS_UNSET+=LTO
#LDFLAGS.lld+= -Wl,--no-threads
.endif
.if \${.CURDIR:M*/devel/llvm*}
MAKE_JOBS_NUMBER=4
.endif
.if \${.CURDIR:M*/java/openjdk*}
MAKE_JOBS_NUMBER=4
.endif
#JAVA_VERSION=11
" > ${JAIL_PATH}/usr/local/etc/poudriere.d/make.conf
echo "
#databases/mongodb36
#databases/mongodb40
#databases/mongodb40-tools
#databases/mongodb42
#databases/mongodb42-tools
#databases/mongodb44
#databases/mongodb49
databases/mongodb50
#databases/mongodb-tools
#databases/cassandra4
#devel/jenkins-lts
#devel/scons
#devel/tijmp
#java/openjdk8
#sysutils/fusefs-smbnetfs
#www/grafana7
" > ${JAIL_PATH}/usr/local/etc/poudriere.d/port-list
jexec ${JAIL_NAME} /usr/local/etc/rc.d/lighttpd restart
jexec ${JAIL_NAME} pkg fetch -y -o /usr/local/poudriere/data/packages/freebsd14-custom llvm10 rust
jexec ${JAIL_NAME} poudriere bulk -j freebsd14 -p custom -f /usr/local/etc/poudriere.d/port-list