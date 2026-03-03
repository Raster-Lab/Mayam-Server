# SPDX-License-Identifier: (see LICENSE)
#
# RPM spec file for the Mayam PACS server.

Name:           mayam
Version:        1.0.0
Release:        1%{?dist}
Summary:        Departmental PACS built in Swift

License:        see LICENSE
URL:            https://github.com/Raster-Lab/Mayam
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  swift-lang >= 6.2

# PostgreSQL is recommended but not strictly required; SQLite may be used
# for lightweight deployments.
Recommends:     postgresql-server >= 18

%description
Mayam is a departmental-level Picture Archiving and Communication System
(PACS) built entirely in Swift 6.2 with strict concurrency.  It supports
DICOM, DICOMweb, HL7, and FHIR and targets both macOS (Apple Silicon) and
Linux (x86_64, aarch64).  The server follows the DICOM Standard 2026a (XML
edition).

# =========================================================================
# Preparation
# =========================================================================

%prep
%setup -q

# =========================================================================
# Build
# =========================================================================

%build
swift build -c release

# =========================================================================
# Install
# =========================================================================

%install
rm -rf %{buildroot}

# Binary
install -D -m 0755 .build/release/MayamServer %{buildroot}/usr/local/bin/mayam

# Configuration
install -D -m 0644 Config/mayam.yaml %{buildroot}/etc/mayam/mayam.yaml

# systemd service unit
install -D -m 0644 Config/mayam.service %{buildroot}/lib/systemd/system/mayam.service

# Data and log directories
install -d -m 0750 %{buildroot}/var/lib/mayam/archive
install -d -m 0750 %{buildroot}/var/log/mayam

# =========================================================================
# Files
# =========================================================================

%files
%attr(0755, root, root) /usr/local/bin/mayam
%config(noreplace)      /etc/mayam/mayam.yaml
%dir                    /etc/mayam
/lib/systemd/system/mayam.service
%dir %attr(0750, mayam, mayam) /var/lib/mayam
%dir %attr(0750, mayam, mayam) /var/lib/mayam/archive
%dir %attr(0750, mayam, mayam) /var/log/mayam

# =========================================================================
# Scriptlets
# =========================================================================

%pre
# Create dedicated service group and user if they do not already exist.
getent group mayam >/dev/null 2>&1 || groupadd --system mayam
getent passwd mayam >/dev/null 2>&1 || \
    useradd --system --gid mayam --home-dir /var/lib/mayam \
            --shell /sbin/nologin --no-create-home mayam

%post
# Reload systemd and enable the service.
systemctl daemon-reload
systemctl enable mayam.service

%preun
# Stop and disable the service before removal.
if [ "$1" -eq 0 ]; then
    systemctl stop mayam.service 2>/dev/null || true
    systemctl disable mayam.service 2>/dev/null || true
fi

%postun
systemctl daemon-reload

%changelog
* %(date "+%a %b %d %Y") Raster Lab <info@raster-lab.com> - 1.0.0-1
- Initial RPM package for Mayam PACS server.
