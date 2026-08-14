#!/usr/bin/env bash
set -euo pipefail

source_dir=${1:-/src}
packaging_dir=${2:-/packaging}
output_dir=${3:-/out}

version=$(awk '/^#define KEYDB_REAL_VERSION/ {gsub(/"/, "", $3); print $3}' \
    "$source_dir/src/version.h")
if [[ "$version" != "6.3.6" ]]; then
    echo "Expected KeyDB 6.3.6, found: $version" >&2
    exit 1
fi

dnf -y install \
    rpm-build \
    gcc \
    gcc-c++ \
    libatomic \
    make \
    pkgconf-pkg-config \
    openssl-devel \
    systemd-devel \
    systemd-rpm-macros \
    zlib-devel \
    bzip2-devel \
    lz4-devel \
    libzstd-devel \
    libuuid-devel \
    libcurl-devel \
    logrotate \
    shadow-utils \
    python3 \
    procps-ng \
    findutils \
    diffutils \
    tar \
    gzip \
    which \
    util-linux

rpm_top=$(mktemp -d /tmp/keydb-rpmbuild.XXXXXX)
source_stage=$(mktemp -d /tmp/keydb-source.XXXXXX)
server_pid=
listener_pid=

cleanup() {
    if [[ -n "$server_pid" ]]; then
        /usr/bin/keydb-cli -h 127.0.0.1 -p 6399 SHUTDOWN NOSAVE \
            >/dev/null 2>&1 || true
        kill "$server_pid" >/dev/null 2>&1 || true
    fi
    if [[ -n "$listener_pid" ]]; then
        kill "$listener_pid" >/dev/null 2>&1 || true
    fi
    rm -rf "$rpm_top" "$source_stage"
}
trap cleanup EXIT

install -d \
    "$rpm_top/BUILD" \
    "$rpm_top/BUILDROOT" \
    "$rpm_top/RPMS" \
    "$rpm_top/SOURCES" \
    "$rpm_top/SPECS" \
    "$rpm_top/SRPMS" \
    "$output_dir"

install -m 0644 "$packaging_dir/keydb.spec" "$rpm_top/SPECS/keydb.spec"
install -m 0644 "$packaging_dir/keydb.service" "$rpm_top/SOURCES/keydb.service"
install -m 0644 "$packaging_dir/keydb-sentinel.service" \
    "$rpm_top/SOURCES/keydb-sentinel.service"
install -m 0644 "$packaging_dir/keydb.logrotate" \
    "$rpm_top/SOURCES/keydb.logrotate"

install -d "$source_stage/keydb-$version"
tar -C "$source_dir" --exclude-vcs --exclude='./rpm-output' -cf - . | \
    tar -C "$source_stage/keydb-$version" -xf -

source_date_epoch=${SOURCE_DATE_EPOCH:-$(date +%s)}
tar --sort=name \
    --mtime="@$source_date_epoch" \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -C "$source_stage" \
    -cf - "keydb-$version" | \
    gzip -n > "$rpm_top/SOURCES/keydb-$version.tar.gz"

rpmbuild -ba \
    --define "_topdir $rpm_top" \
    "$rpm_top/SPECS/keydb.spec"

find "$rpm_top/RPMS" "$rpm_top/SRPMS" -type f -name '*.rpm' \
    -exec cp -v {} "$output_dir/" \;

main_rpm=$(find "$output_dir" -maxdepth 1 -type f \
    -name "keydb-$version-*.x86_64.rpm" \
    ! -name '*debuginfo*' \
    ! -name '*debugsource*' \
    -print -quit)
if [[ -z "$main_rpm" ]]; then
    echo "Main KeyDB RPM was not produced" >&2
    exit 1
fi

rpm -K --nosignature "$output_dir"/*.rpm
{
    echo '## Package information'
    rpm -qpi "$main_rpm"
    echo
    echo '## Package files'
    rpm -qpl "$main_rpm"
    echo
    echo '## Package requirements'
    rpm -qpR "$main_rpm"
} | tee "$output_dir/rpm-manifest.txt"

dnf -y install "$main_rpm"

/usr/bin/keydb-server --version 2>&1 | grep -Eq 'v=6\.3\.6([[:space:]]|$)'
ldd /usr/bin/keydb-server | grep -q 'libsystemd\.so\.0'
ldd /usr/bin/keydb-server | grep -q 'libatomic\.so\.1'
systemd-analyze verify \
    /usr/lib/systemd/system/keydb.service \
    /usr/lib/systemd/system/keydb-sentinel.service
rpm -q --configfiles keydb | grep -qx '/etc/keydb/keydb.conf'
rpm -q --configfiles keydb | grep -qx '/etc/keydb/sentinel.conf'
test "$(stat -c '%U:%G:%a' /etc/keydb)" = 'keydb:keydb:750'
test "$(stat -c '%U:%G:%a' /var/lib/keydb)" = 'keydb:keydb:750'
test "$(stat -c '%U:%G:%a' /var/log/keydb)" = 'keydb:keydb:750'

cat > /tmp/keydb-notify-listener.py <<'PY'
import os
import socket

path = "/tmp/keydb-notify.sock"
try:
    os.unlink(path)
except FileNotFoundError:
    pass

sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
sock.bind(path)
os.chmod(path, 0o777)
sock.settimeout(30)

while True:
    message = sock.recv(65535).decode("utf-8", "replace")
    print(message, flush=True)
    if "READY=1" in message:
        break
PY

rm -f \
    /tmp/keydb-notify.sock \
    /tmp/keydb-notify.log \
    /tmp/keydb-rpm-smoke.log \
    /tmp/keydb-rpm-smoke.pid
python3 /tmp/keydb-notify-listener.py >/tmp/keydb-notify.log 2>&1 &
listener_pid=$!

for _ in $(seq 1 100); do
    [[ -S /tmp/keydb-notify.sock ]] && break
    sleep 0.05
done
test -S /tmp/keydb-notify.sock

runuser -u keydb -- env NOTIFY_SOCKET=/tmp/keydb-notify.sock \
    /usr/bin/keydb-server /etc/keydb/keydb.conf \
        --bind 127.0.0.1 \
        --port 6399 \
        --save '' \
        --appendonly no \
        --daemonize no \
        --supervised systemd \
        --dir /tmp \
        --pidfile /tmp/keydb-rpm-smoke.pid \
        --logfile /tmp/keydb-rpm-smoke.log &
server_pid=$!

if ! wait "$listener_pid"; then
    cat /tmp/keydb-notify.log || true
    cat /tmp/keydb-rpm-smoke.log || true
    exit 1
fi
listener_pid=
grep -q 'READY=1' /tmp/keydb-notify.log
/usr/bin/keydb-cli -h 127.0.0.1 -p 6399 PING | grep -qx PONG
/usr/bin/keydb-cli -h 127.0.0.1 -p 6399 SHUTDOWN NOSAVE
wait "$server_pid" || true
server_pid=

(
    cd "$output_dir"
    sha256sum ./*.rpm | sort -k2 > SHA256SUMS
    cat SHA256SUMS
)

