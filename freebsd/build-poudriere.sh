#! /bin/sh

test -n "$PORTS" || ( echo "PORTS is unset" && exit 1 )
test -n "$POUDRIERE_NAME" || ( echo "POUDRIERE_NAME is unset" && exit 1 )
test -n "$POUDRIERE_VERSION" || ( echo "POUDRIERE_VERSION is unset" && exit 1 )

pkg install -y poudriere-devel

echo "
WITH_TESTING_PORTS="${PORTS%@*}"
POUDRIERE_TEST="-t"
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
" > /usr/local/etc/poudriere.d/make.conf

echo "${PORTS}" > /tmp/port-list

pw groupadd -n frits -g 65532
pw useradd -n frits -u 65532 -g frits
cp freebsd/poudriere-zfs.conf /usr/local/etc/poudriere.conf

if test -n "$REMOVE_POUDRIERE"; then
	poudriere jail -d -j "$POUDRIERE_NAME"
fi
if ! poudriere jail -i -j "$POUDRIERE_NAME"; then
    poudriere jail -c -j "$POUDRIERE_NAME" -v "$POUDRIERE_VERSION" ${POUDRIERE_ARCH}
    poudriere ports -c -f none -M /usr/ports -m null -p custom
fi
LASTUPDATE=poudriere_jail_lastupdate
if test "X$(find ${LASTUPDATE} -mtime -10d)" != "X${LASTUPDATE}"
then
    poudriere jail -u -j "$POUDRIERE_NAME"
    touch ${LASTUPDATE}
fi

nice -n 15 poudriere bulk -j "$POUDRIERE_NAME" -p custom -f /tmp/port-list -b latest $POUDRIERE_TEST
#for p in ${PORTS}; do
#    jexec ${JAIL_NAME} nice -n 20 poudriere testport -j "$POUDRIERE_NAME" -p custom -b latest -o $p
#done
