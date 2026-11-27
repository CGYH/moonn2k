#!/usr/bin/env bash
# Install the MoonBit toolchain pinned by .moonbit-version, then fail unless the
# installed moonc satisfies .moonc-minimum.
#
# Two independent version numbers are involved and must not be conflated:
#   .moonbit-version  the MoonBit *release tag* the installer downloads
#   .moonc-minimum    the *compiler* version this project requires
#
# The release tag does not encode the moonc version, so pinning the release is
# not enough on its own: an unpinned `install/unix.sh` would silently track
# "latest" while this file still claimed to be pinned. Both are therefore read
# from the repository and the compiler floor is asserted on every run, cache hit
# or not.

set -euo pipefail

readonly CLI_BASE="https://cli.moonbitlang.com"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

log() { printf '[toolchain] %s\n' "$*"; }

die() {
  printf '::error::%s\n' "$*"
  exit 1
}

cd "${REPO_ROOT}"

# Read the two pins. `tr` strips the trailing newline and any stray whitespace;
# a missing or empty file is a repository bug, not a transient failure.
[[ -f .moonbit-version ]] || die ".moonbit-version is missing"
[[ -f .moonc-minimum ]] || die ".moonc-minimum is missing"
release_tag="$(tr -d '[:space:]' < .moonbit-version)"
moonc_floor="$(tr -d '[:space:]' < .moonc-minimum)"
[[ -n "${release_tag}" ]] || die ".moonbit-version is empty"
[[ -n "${moonc_floor}" ]] || die ".moonc-minimum is empty"

moon_home="${MOON_HOME:-$HOME/.moon}"
moon_bin="${moon_home}/bin"
log "release=${release_tag} floor=${moonc_floor} moon_home=${moon_home}"

if [[ -x "${moon_bin}/moon" ]]; then
  log "reusing toolchain found at ${moon_bin}"
else
  # Download the installer to a file instead of piping it into bash: with
  # `set -o pipefail` a failed download and a failed installer are otherwise
  # indistinguishable, and the error surfaces as an unexplained exit code.
  installer="$(mktemp)"
  log "downloading installer from ${CLI_BASE}/install/unix.sh"
  curl -fsSL --retry 3 --retry-delay 2 -o "${installer}" "${CLI_BASE}/install/unix.sh"
  log "installer is $(wc -c < "${installer}") bytes; installing ${release_tag}"
  MOONBIT_INSTALL_VERSION="${release_tag}" bash "${installer}"
  rm -f "${installer}"
fi

# GITHUB_PATH only affects later steps, so put the toolchain on PATH for the
# assertion below as well.
export PATH="${moon_bin}:${PATH}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${moon_bin}" >> "${GITHUB_PATH}"
fi

if ! command -v moon > /dev/null 2>&1; then
  log "contents of ${moon_bin}:"
  ls -la "${moon_bin}" || true
  die "'moon' is still not on PATH after installing ${release_tag}"
fi

# `moon version --all` prints e.g. "moonc v1.0.0-rc1+3c0520448 (2026-11-26) ...".
version_report="$(moon version --all)"
printf '%s\n' "${version_report}"
moonc_version="$(printf '%s\n' "${version_report}" | sed -n 's/^moonc v\{0,1\}\([^ +]*\).*/\1/p' | head -n 1)"
[[ -n "${moonc_version}" ]] || die "could not read the moonc version from 'moon version --all'"

log "moonc ${moonc_version} (floor ${moonc_floor})"

# `sort -V -C` exits non-zero exactly when the two lines are out of version
# order, i.e. when the installed moonc is older than the floor.
if ! printf '%s\n%s\n' "${moonc_floor}" "${moonc_version}" | sort -V -C; then
  die "moonc ${moonc_version} is older than the required ${moonc_floor}"
fi

log "toolchain OK"
