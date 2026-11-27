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
readonly release_tag="$(tr -d '[:space:]' < .moonbit-version)"
readonly moonc_floor="$(tr -d '[:space:]' < .moonc-minimum)"
readonly moon_home="${MOON_HOME:-$HOME/.moon}"
readonly moon_bin="${moon_home}/bin"

if [[ -z "${release_tag}" ]]; then
  echo "::error file=.moonbit-version::release tag is empty"
  exit 1
fi

if [[ ! -x "${moon_bin}/moon" ]]; then
  echo "Installing MoonBit ${release_tag}"
  curl -fsSL "${CLI_BASE}/install/unix.sh" | bash -s -- "${release_tag}"
fi

# GITHUB_PATH only affects later steps, so put the toolchain on PATH for the
# version assertion below as well.
export PATH="${moon_bin}:${PATH}"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${moon_bin}" >> "${GITHUB_PATH}"
fi

# `moon version --all` prints e.g. "moonc v1.0.0-rc1+3c0520448 (2026-11-26) ...".
moonc_version="$(moon version --all | sed -n 's/^moonc v\{0,1\}\([^ +]*\).*/\1/p' | head -n 1)"

if [[ -z "${moonc_version}" ]]; then
  echo "::error::could not read the moonc version from 'moon version --all'"
  moon version --all
  exit 1
fi

printf 'toolchain: moonc %s (floor %s, release %s)\n' \
  "${moonc_version}" "${moonc_floor}" "${release_tag}"

# `sort -V -C` exits non-zero exactly when the two lines are out of version
# order, i.e. when the installed moonc is older than the floor.
if ! printf '%s\n%s\n' "${moonc_floor}" "${moonc_version}" | sort -V -C; then
  echo "::error::moonc ${moonc_version} is older than the required ${moonc_floor}"
  exit 1
fi
