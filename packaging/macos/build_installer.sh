#!/usr/bin/env bash
# SPDX-License-Identifier: (see LICENSE)
#
# build_installer.sh — Builds a macOS .pkg installer inside a .dmg disc image
# for the Mayam PACS server.
#
# Usage:
#   ./build_installer.sh [version]
#
# Arguments:
#   version   Semantic version string (default: 1.0.0)

set -euo pipefail

# ---------------------------------------------------------------------------
# MARK: - Configuration
# ---------------------------------------------------------------------------

readonly VERSION="${1:-1.0.0}"
readonly IDENTIFIER="com.raster-lab.mayam"
readonly PRODUCT_NAME="Mayam"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly BUILD_DIR="${PROJECT_ROOT}/build"
readonly PKG_NAME="${PRODUCT_NAME}-${VERSION}.pkg"
readonly DMG_NAME="${PRODUCT_NAME}-${VERSION}.dmg"

# Temporary working directories (cleaned up on exit)
PAYLOAD_DIR=""
PKG_STAGE_DIR=""
DMG_STAGE_DIR=""

# ---------------------------------------------------------------------------
# MARK: - Cleanup
# ---------------------------------------------------------------------------

cleanup() {
    local dirs=("${PAYLOAD_DIR}" "${PKG_STAGE_DIR}" "${DMG_STAGE_DIR}")
    for dir in "${dirs[@]}"; do
        if [[ -n "${dir}" && -d "${dir}" ]]; then
            rm -rf "${dir}"
        fi
    done
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

for cmd in swift pkgbuild productbuild hdiutil; do
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
# MARK: - Create Payload Directory
# ---------------------------------------------------------------------------

log "Preparing installer payload…"

PAYLOAD_DIR="$(mktemp -d)"
PKG_STAGE_DIR="$(mktemp -d)"
DMG_STAGE_DIR="$(mktemp -d)"

# Binary
install -d "${PAYLOAD_DIR}/usr/local/bin"
install -m 0755 "${BINARY_PATH}" "${PAYLOAD_DIR}/usr/local/bin/mayam"

# Configuration
install -d "${PAYLOAD_DIR}/etc/mayam"
install -m 0644 "${PROJECT_ROOT}/Config/mayam.yaml" "${PAYLOAD_DIR}/etc/mayam/mayam.yaml"

# Launch daemon plist
install -d "${PAYLOAD_DIR}/Library/LaunchDaemons"
install -m 0644 "${PROJECT_ROOT}/Config/com.raster-lab.mayam.plist" \
    "${PAYLOAD_DIR}/Library/LaunchDaemons/com.raster-lab.mayam.plist"

# Data and log directories
install -d "${PAYLOAD_DIR}/var/lib/mayam/archive"
install -d "${PAYLOAD_DIR}/var/log/mayam"

# ---------------------------------------------------------------------------
# MARK: - Build Component Package
# ---------------------------------------------------------------------------

log "Building component package…"

readonly COMPONENT_PKG="${PKG_STAGE_DIR}/mayam-component.pkg"

pkgbuild \
    --root "${PAYLOAD_DIR}" \
    --identifier "${IDENTIFIER}" \
    --version "${VERSION}" \
    --scripts "${SCRIPT_DIR}/scripts" \
    --install-location "/" \
    "${COMPONENT_PKG}"

# ---------------------------------------------------------------------------
# MARK: - Build Product Archive
# ---------------------------------------------------------------------------

log "Building product archive…"

mkdir -p "${BUILD_DIR}"
readonly FINAL_PKG="${BUILD_DIR}/${PKG_NAME}"

productbuild \
    --distribution "${SCRIPT_DIR}/Distribution.xml" \
    --package-path "${PKG_STAGE_DIR}" \
    --version "${VERSION}" \
    "${FINAL_PKG}"

# ---------------------------------------------------------------------------
# MARK: - Create DMG Disc Image
# ---------------------------------------------------------------------------

log "Creating DMG disc image…"

cp "${FINAL_PKG}" "${DMG_STAGE_DIR}/"

readonly FINAL_DMG="${BUILD_DIR}/${DMG_NAME}"

hdiutil create \
    -volname "${PRODUCT_NAME} ${VERSION}" \
    -srcfolder "${DMG_STAGE_DIR}" \
    -ov \
    -format UDZO \
    "${FINAL_DMG}"

# ---------------------------------------------------------------------------
# MARK: - Summary
# ---------------------------------------------------------------------------

log "Build complete."
log "  Package : ${FINAL_PKG}"
log "  DMG     : ${FINAL_DMG}"
