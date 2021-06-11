#! /bin/sh

test -n "$JAIL_PATH" || ( echo "JAIL_PATH is unset" && exit 1 )
test -n "$JAIL_NAME" || ( echo "JAIL_NAME is unset" && exit 1 )
test -n "$PORTS" || ( echo "PORTS is unset" && exit 1 )

mkdir -p "$JAIL_PATH"

BASE_TAR="$JAIL_PATH/base.txz"
FETCH_ARGS=$( test ! -f "$BASE_TAR" || echo "-i $BASE_TAR" )
fetch -o "$BASE_TAR" ${FETCH_ARGS} "https://download.freebsd.org/ftp/snapshots/arm64/14.0-CURRENT/base.txz"
if test ! "$JAIL_PATH/COPYRIGHT" -nt "$BASE_TAR"; then
    tar xm -C "$JAIL_PATH" -f "$BASE_TAR"
#    find . \( -path ./dev -o -path ./usr/ports -o -path ./usr/src -o -path ./usr/obj \) -prune -o ! -newer base.txz -ls
    find "$JAIL_PATH" \( -path ./dev -o -path ./usr/ports -o -path ./usr/local -o -path ./usr/src -o -path ./usr/obj \) -prune -o \( -type f -a ! -newer "$BASE_TAR" \) -ls
fi
mkdir -p "${JAIL_PATH}/usr/ports"
jail -cmr "name=${JAIL_NAME}" persist "path=${JAIL_PATH}" mount.devfs devfs_ruleset=0 \
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
jexec ${JAIL_NAME} pkg install -y poudriere lighttpd
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
echo "${PORTS}" > ${JAIL_PATH}/usr/local/etc/poudriere.d/port-list
cp freebsd/poudriere.conf ${JAIL_PATH}/usr/local/etc/
cp freebsd/lighttpd.conf ${JAIL_PATH}/usr/local/etc/lighttpd/
cp freebsd/modules.conf ${JAIL_PATH}/usr/local/etc/lighttpd/
cp freebsd/vhosts.d-poudriere.conf ${JAIL_PATH}/usr/local/etc/lighttpd/vhosts.d/poudriere.conf
jexec ${JAIL_NAME} /usr/local/etc/rc.d/lighttpd onerestart
jexec ${JAIL_NAME} pkg fetch -y -o /usr/local/poudriere/data/packages/freebsd14-custom llvm10 rust
jexec ${JAIL_NAME} poudriere bulk -j freebsd14 -p custom -f /usr/local/etc/poudriere.d/port-list
