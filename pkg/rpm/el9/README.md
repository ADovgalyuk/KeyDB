# KeyDB RPM for Enterprise Linux 9

This directory contains the native RPM packaging for KeyDB 6.3.6 on
Oracle Linux 9-compatible x86_64 systems.

The package uses the standard layout:

- configuration: `/etc/keydb`
- persistent data: `/var/lib/keydb`
- logs: `/var/log/keydb`
- systemd units: `keydb.service` and `keydb-sentinel.service`

TLS and native systemd notification support are enabled. Configuration files
are installed as `%config(noreplace)`, so package upgrades do not replace local
changes.

## Local build

From the repository root, with Docker available:

```bash
mkdir -p rpm-output
docker run --rm \
  -v "$PWD:/src:ro" \
  -v "$PWD/pkg/rpm/el9:/packaging:ro" \
  -v "$PWD/rpm-output:/out" \
  oraclelinux:9 \
  /packaging/build-el9-rpm.sh
```

The build produces the binary RPM, source RPM, `SHA256SUMS`, and a package
manifest in `rpm-output/`. It then installs the package in the build container,
validates the systemd units and standard directory ownership, and performs a
`READY=1` plus `PING/PONG` smoke test.

