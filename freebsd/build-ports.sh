#! /bin/sh

test -n "$JAIL_PATH" || ( echo "JAIL_PATH is unset" && exit 1 )
test -n "$JAIL_NAME" || ( echo "JAIL_NAME is unset" && exit 1 )
test -n "$JAIL_VERSION" || ( echo "JAIL_VERSION is unset" && exit 1 )
test -n "$PORTS" || ( echo "PORTS is unset" && exit 1 )
test -n "$POUDRIERE_NAME" || ( echo "POUDRIERE_NAME is unset" && exit 1 )
test -n "$POUDRIERE_VERSION" || ( echo "POUDRIERE_VERSION is unset" && exit 1 )

mkdir -p "$JAIL_PATH"

BASE_TAR="$JAIL_PATH/base.txz"
FETCH_ARGS=$( test ! -f "$BASE_TAR" || echo "-i $BASE_TAR" )
ARTIFACT_URL="https://artifact.ci.freebsd.org/snapshot/${JAIL_VERSION}/latest/$(uname -m)/$(uname -p)/base.txz"
if test "${JAIL_VERSION#*-}" = "RELEASE"; then
    SNAPSHOT_URL="https://download.freebsd.org/releases/$(uname -m)/${JAIL_VERSION}/base.txz"
else
    SNAPSHOT_URL="${ARTIFACT_URL}"
    # "https://download.freebsd.org/snapshots/$(uname -m)/${JAIL_VERSION}/base.txz"
fi
fetch -o "$BASE_TAR" ${FETCH_ARGS} "$SNAPSHOT_URL"
if test ! "$JAIL_PATH/COPYRIGHT" -nt "$BASE_TAR"; then
    tar xm -C "$JAIL_PATH" -f "$BASE_TAR"
#    find . \( -path ./dev -o -path ./usr/ports -o -path ./usr/src -o -path ./usr/obj \) -prune -o ! -newer base.txz -ls
    find "$JAIL_PATH" \( -path ./dev -o -path ./usr/ports -o -path ./usr/local -o -path ./usr/src -o -path ./usr/obj \) -prune -o \( -type f -a ! -newer "$BASE_TAR" \) -ls
fi
mkdir -p "${JAIL_PATH}/usr/ports"
mkdir -p "${JAIL_PATH}/usr/local/poudriere"
jail -vc "name=${JAIL_NAME}" persist "path=${JAIL_PATH}" mount.devfs devfs_ruleset=0 \
    ip4=inherit children.max=99 \
    enforce_statfs=1 \
    allow.mlock \
    allow.mount \
    allow.mount.devfs \
    allow.mount.procfs \
    allow.mount.nullfs \
    allow.mount.tmpfs \
    allow.mount.zfs \
    "mount=/usr/ports	${JAIL_PATH}/usr/ports	nullfs	ro,nocache	0	0" \
    "mount=/usr/local/poudriere	${JAIL_PATH}/usr/local/poudriere	nullfs	rw,nocache	0	0"
trap 'jail -vr ${JAIL_NAME}; umount ${JAIL_PATH}/usr/local/poudriere ${JAIL_PATH}/usr/ports ${JAIL_PATH}/dev' EXIT

zfs create "zrpi4/poudriere/${JAIL_NAME}"
#zfs set jailed=on "zrpi4/poudriere/${JAIL_NAME}"
zfs jail "${JAIL_NAME}" "zrpi4/poudriere/${JAIL_NAME}"

#jexec ${JAIL_NAME} truncate -s 0 /etc/src.conf
#jexec ${JAIL_NAME} echo "NO_INSTALLEXTRAKERNELS=no" >> /etc/src.conf
#jexec ${JAIL_NAME} echo "KERNCONF=GENERIC-NODEBUG GENERIC" >> /etc/src.conf
#jexec ${JAIL_NAME} /usr/bin/make -C /usr/src -j4 -DWITHOUT_CLEAN buildworld buildkernel
cp -p /etc/resolv.conf ${JAIL_PATH}/etc/
if test "$POUDRIERE_NAME" != "freebsd12"; then
	sed -i .sed.bak s/quarterly/latest/ ${JAIL_PATH}/etc/pkg/FreeBSD.conf
fi
jexec ${JAIL_NAME} pkg install -y poudriere
echo "
WITH_TESTING_PORTS="${PORTS%@*}"
.if \${MACHINE_CPUARCH} == "aarch64"
MAKE_JOBS_NUMBER=3
.endif
OPTIONS_UNSET+=LTO
.if \${.CURDIR:M*/databases/mongodb4*}
MAKE_JOBS_NUMBER=4
#LDFLAGS+= -Wl,--no-threads
.endif
.if \${.CURDIR:M*/databases/mongodb5*}
MAKE_JOBS_NUMBER=4
#LDFLAGS+= --threads=1
.endif
.if \${.CURDIR:M*/databases/mongodb6*}
MAKE_JOBS_NUMBER=4
#LDFLAGS+= -Wl,--no-threads
.endif
.if \${.CURDIR:M*/databases/mongodb7*}
#FLAVOR=armv80a
MAKE_JOBS_NUMBER=3
LDFLAGS+= -Wl,--threads=1
.endif
.if \${.CURDIR:M*/databases/mongodb8*}
#FLAVOR=armv80a
MAKE_JOBS_NUMBER=3
LDFLAGS+= -Wl,--threads=1
.endif
.if \${.CURDIR:M*/devel/llvm*}
. if \${MACHINE_CPUARCH} == "aarch64"
MAKE_JOBS_NUMBER=4
. endif
.endif
.if \${.CURDIR:M*/java/openjdk*}
MAKE_JOBS_NUMBER=3
.endif
#JAVA_VERSION=11
#JAVA_VERSION=17+
" > ${JAIL_PATH}/usr/local/etc/poudriere.d/make.conf
echo "${PORTS}" > ${JAIL_PATH}/usr/local/etc/poudriere.d/port-list
cp freebsd/poudriere.conf ${JAIL_PATH}/usr/local/etc/

if test -n "$REMOVE_POUDRIERE"; then
	jexec ${JAIL_NAME} poudriere jail -d -j "$POUDRIERE_NAME"
fi
if ! jexec ${JAIL_NAME} poudriere jail -i -j "$POUDRIERE_NAME"; then
    jexec ${JAIL_NAME} poudriere jail -c -j "$POUDRIERE_NAME" -v "$POUDRIERE_VERSION" ${POUDRIERE_ARCH}
    jexec ${JAIL_NAME} poudriere ports -c -f none -M /usr/ports -m null -p custom
fi
LASTUPDATE=${JAIL_PATH}/poudriere_jail_lastupdate
if test "X$(find ${LASTUPDATE} -mtime -10d)" != "X${LASTUPDATE}"
then
    jexec ${JAIL_NAME} poudriere jail -u -j "$POUDRIERE_NAME"
    touch ${LASTUPDATE}
fi

jexec ${JAIL_NAME} nice -n 15 poudriere bulk -j "$POUDRIERE_NAME" -p custom -f /usr/local/etc/poudriere.d/port-list -b latest -t
#for p in ${PORTS}; do
#    jexec ${JAIL_NAME} nice -n 20 poudriere testport -j "$POUDRIERE_NAME" -p custom -b latest -o $p
#done
