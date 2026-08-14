Name:           keydb
Version:        6.3.6
Release:        1%{?dist}
Summary:        Multithreaded in-memory key-value database
License:        BSD-3-Clause
URL:            https://docs.keydb.dev/
Source0:        %{name}-%{version}.tar.gz
Source1:        keydb.service
Source2:        keydb-sentinel.service
Source3:        keydb.logrotate

BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  pkgconf-pkg-config
BuildRequires:  openssl-devel
BuildRequires:  systemd-devel
BuildRequires:  systemd-rpm-macros
BuildRequires:  zlib-devel
BuildRequires:  bzip2-devel
BuildRequires:  lz4-devel
BuildRequires:  libzstd-devel
BuildRequires:  libuuid-devel
BuildRequires:  libcurl-devel
BuildRequires:  libatomic
Requires:       logrotate
Requires(pre):  shadow-utils
%{?systemd_requires}

%description
KeyDB is a multithreaded, Redis-compatible in-memory database. This package
contains the server, Sentinel, command-line client, benchmark, diagnostic,
and data-repair tools, with native TLS and systemd notification support.

%prep
%autosetup -n %{name}-%{version}

%build
make distclean || :
%make_build BUILD_TLS=yes USE_SYSTEMD=yes

%check
src/keydb-server --version 2>&1 | grep -Eq 'v=6\.3\.6([[:space:]]|$)'
ldd src/keydb-server | grep -q 'libsystemd\.so\.0'
ldd src/keydb-server | grep -q 'libatomic\.so\.1'

%install
rm -rf %{buildroot}

install -d -m 0755 %{buildroot}%{_bindir}
install -p -m 0755 src/keydb-server %{buildroot}%{_bindir}/keydb-server
install -p -m 0755 src/keydb-cli %{buildroot}%{_bindir}/keydb-cli
install -p -m 0755 src/keydb-benchmark %{buildroot}%{_bindir}/keydb-benchmark
install -p -m 0755 src/keydb-diagnostic-tool %{buildroot}%{_bindir}/keydb-diagnostic-tool
ln -s keydb-server %{buildroot}%{_bindir}/keydb-sentinel
ln -s keydb-server %{buildroot}%{_bindir}/keydb-check-aof
ln -s keydb-server %{buildroot}%{_bindir}/keydb-check-rdb

install -d -m 0750 %{buildroot}%{_sysconfdir}/keydb
install -p -m 0640 keydb.conf %{buildroot}%{_sysconfdir}/keydb/keydb.conf
install -p -m 0640 sentinel.conf %{buildroot}%{_sysconfdir}/keydb/sentinel.conf
sed -ri \
    -e 's|^daemonize[[:space:]]+.*$|daemonize no|' \
    -e 's|^supervised[[:space:]]+.*$|supervised systemd|' \
    -e 's|^pidfile[[:space:]]+.*$|pidfile /run/keydb/keydb-server.pid|' \
    -e 's|^logfile[[:space:]]+.*$|logfile /var/log/keydb/keydb-server.log|' \
    -e 's|^dir[[:space:]]+\./$|dir /var/lib/keydb|' \
    %{buildroot}%{_sysconfdir}/keydb/keydb.conf
sed -ri \
    -e 's|^daemonize[[:space:]]+.*$|daemonize no|' \
    -e 's|^pidfile[[:space:]]+.*$|pidfile /run/keydb-sentinel/keydb-sentinel.pid|' \
    -e 's|^logfile[[:space:]]+.*$|logfile /var/log/keydb/keydb-sentinel.log|' \
    -e 's|^dir[[:space:]]+.*$|dir /var/lib/keydb|' \
    %{buildroot}%{_sysconfdir}/keydb/sentinel.conf

install -d -m 0755 %{buildroot}%{_unitdir}
install -p -m 0644 %{SOURCE1} %{buildroot}%{_unitdir}/keydb.service
install -p -m 0644 %{SOURCE2} %{buildroot}%{_unitdir}/keydb-sentinel.service

install -d -m 0755 %{buildroot}%{_sysconfdir}/logrotate.d
install -p -m 0644 %{SOURCE3} %{buildroot}%{_sysconfdir}/logrotate.d/keydb

install -d -m 0750 %{buildroot}%{_sharedstatedir}/keydb
install -d -m 0750 %{buildroot}%{_localstatedir}/log/keydb

install -d -m 0755 %{buildroot}%{_licensedir}/%{name}
install -p -m 0644 COPYING %{buildroot}%{_licensedir}/%{name}/COPYING

install -d -m 0755 %{buildroot}%{_mandir}/man1 %{buildroot}%{_mandir}/man5
install -p -m 0644 pkg/rpm/keydb_build/keydb_rpm/usr/share/man/man1/*.gz \
    %{buildroot}%{_mandir}/man1/
install -p -m 0644 pkg/rpm/keydb_build/keydb_rpm/usr/share/man/man5/*.gz \
    %{buildroot}%{_mandir}/man5/

%pre
getent group keydb >/dev/null 2>&1 || groupadd -r keydb
getent passwd keydb >/dev/null 2>&1 || \
    useradd -r -g keydb -d /var/lib/keydb -s /sbin/nologin \
        -c 'KeyDB Database Server' keydb
exit 0

%post
%systemd_post keydb.service keydb-sentinel.service

%preun
%systemd_preun keydb.service keydb-sentinel.service

%postun
%systemd_postun_with_restart keydb.service keydb-sentinel.service

%files
%license %{_licensedir}/%{name}/COPYING
%{_bindir}/keydb-server
%{_bindir}/keydb-sentinel
%{_bindir}/keydb-cli
%{_bindir}/keydb-benchmark
%{_bindir}/keydb-check-aof
%{_bindir}/keydb-check-rdb
%{_bindir}/keydb-diagnostic-tool
%{_unitdir}/keydb.service
%{_unitdir}/keydb-sentinel.service
%config(noreplace) %{_sysconfdir}/logrotate.d/keydb
%dir %attr(0750,keydb,keydb) %{_sysconfdir}/keydb
%config(noreplace) %attr(0640,keydb,keydb) %{_sysconfdir}/keydb/keydb.conf
%config(noreplace) %attr(0640,keydb,keydb) %{_sysconfdir}/keydb/sentinel.conf
%dir %attr(0750,keydb,keydb) %{_sharedstatedir}/keydb
%dir %attr(0750,keydb,keydb) %{_localstatedir}/log/keydb
%{_mandir}/man1/keydb-*.1*
%{_mandir}/man5/keydb*.5*

%changelog
* Fri Aug 14 2026 KeyDB maintainers - 6.3.6-1
- Add a native Oracle Linux 9 package with standard filesystem layout.
