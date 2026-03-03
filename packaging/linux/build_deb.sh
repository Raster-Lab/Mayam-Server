#!/usr/bin/env bash
# SPDX-License-Identifier: (see LICENSE)
#
# build_deb.sh — Builds a Debian (.deb) package for the Mayam PACS server.
#
# Usage:
#   ./build_deb.sh [version]
#
# Arguments:
#   version   Semantic version string (default: 1.0.0)

set -euo pipefail

# ---------------------------------------------------------------------------
# MARK: - Configuration
# ---------------------------------------------------------------------------

readonly VERSION="${1:-1.0.0}"
readonly PACKAGE_NAME="mayam"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/build"

# Detect architecture
case "$(uname -m)" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64"  ;;
    *)       echo "ERROR: Unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
readonly ARCH

readonly DEB_NAME="${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

# Temporary staging directory (cleaned up on exit)
STAGING_DIR=""

# ---------------------------------------------------------------------------
# MARK: - Cleanup
# ---------------------------------------------------------------------------

cleanup() {
    if [[ -n "${STAGING_DIR}" && -d "${STAGING_DIR}" ]]; then
        rm -rf "${STAGING_DIR}"
    fi
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# MARK: - Helper Functions
# ---------------------------------------------------------------------------

log() {
    echo "==> $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# MARK: - Preflight Checks
# ---------------------------------------------------------------------------

for cmd in swift dpkg-deb; do
    command -v "${cmd}" >/dev/null 2>&1 || error "Required command '${cmd}' not found."
done

[[ -f "${PROJECT_ROOT}/Package.swift" ]] || error "Package.swift not found in ${PROJECT_ROOT}."

# ---------------------------------------------------------------------------
# MARK: - Build Release Binary
# ---------------------------------------------------------------------------

log "Building release binary (version ${VERSION})…"
cd "${PROJECT_ROOT}"
swift build -c release

readonly BINARY_PATH="${PROJECT_ROOT}/.build/release/MayamServer"
[[ -f "${BINARY_PATH}" ]] || error "Release binary not found at ${BINARY_PATH}."

# ---------------------------------------------------------------------------
# MARK: - Create Staging Directory
# ---------------------------------------------------------------------------

log "Preparing Debian package staging directory…"

STAGING_DIR="$(mktemp -d)"
readonly PKG_ROOT="${STAGING_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCH}"

# Binary
install -D -m 0755 "${BINARY_PATH}" "${PKG_ROOT}/usr/local/bin/mayam"

# Configuration
install -D -m 0644 "${PROJECT_ROOT}/Config/mayam.yaml" "${PKG_ROOT}/etc/mayam/mayam.yaml"

# systemd service unit
install -D -m 0644 "${PROJECT_ROOT}/Config/mayam.service" \
    "${PKG_ROOT}/lib/systemd/system/mayam.service"

# Data and log directories
install -d "${PKG_ROOT}/var/lib/mayam/archive"
install -d "${PKG_ROOT}/var/log/mayam"

# ---------------------------------------------------------------------------
# MARK: - DEBIAN Control Files
# ---------------------------------------------------------------------------

install -d "${PKG_ROOT}/DEBIAN"

# control
cat > "${PKG_ROOT}/DEBIAN/control" <<EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Section: medical
Priority: optional
Architecture: ${ARCH}
Maintainer: Raster Lab <info@raster-lab.com>
Homepage: https://github.com/Raster-Lab/Mayam
Description: Departmental PACS built in Swift
 Mayam is a departmental-level Picture Archiving and Communication System
 (PACS) supporting DICOM, DICOMweb, HL7, and FHIR.  It is designed for
 macOS (Apple Silicon) and Linux (x86_64, aarch64) and follows the DICOM
 Standard 2026a.
Depends: libc6
Recommends: postgresql (>= 18)
EOF

# conffiles — prevent dpkg from overwriting user-modified configuration
cat > "${PKG_ROOT}/DEBIAN/conffiles" <<EOF
/etc/mayam/mayam.yaml
EOF

# postinst
cat > "${PKG_ROOT}/DEBIAN/postinst" <<'POSTINST'
#!/usr/bin/env bash
set -euo pipefail

# Create dedicated service user and group if they do not already exist.
if ! getent group mayam >/dev/null 2>&1; then
    groupadd --system mayam
fi

if ! getent passwd mayam >/dev/null 2>&1; then
    useradd --system --gid mayam --home-dir /var/lib/mayam \
            --shell /usr/sbin/nologin --no-create-home mayam
fi

# Ensure correct ownership on data and log directories.
chown -R mayam:mayam /var/lib/mayam
chown -R mayam:mayam /var/log/mayam
chmod 0750 /var/lib/mayam
chmod 0750 /var/log/mayam

# Reload systemd and enable the service.
systemctl daemon-reload
systemctl enable mayam.service
POSTINST
chmod 0755 "${PKG_ROOT}/DEBIAN/postinst"

# prerm
cat > "${PKG_ROOT}/DEBIAN/prerm" <<'PRERM'
#!/usr/bin/env bash
set -euo pipefail

# Stop and disable the service before removal.
if systemctl is-active --quiet mayam.service; then
    systemctl stop mayam.service
fi

systemctl disable mayam.service 2>/dev/null || true
PRERM
chmod 0755 "${PKG_ROOT}/DEBIAN/prerm"

# ---------------------------------------------------------------------------
# MARK: - Build .deb Package
# ---------------------------------------------------------------------------

log "Building Debian package…"

mkdir -p "${BUILD_DIR}"
dpkg-deb --build "${PKG_ROOT}" "${BUILD_DIR}/${DEB_NAME}"

# ---------------------------------------------------------------------------
# MARK: - Summary
# ---------------------------------------------------------------------------

log "Build complete."
log "  Package : ${BUILD_DIR}/${DEB_NAME}"
