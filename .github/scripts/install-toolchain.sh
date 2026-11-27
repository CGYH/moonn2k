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

set -Eeuo pipefail

# Without this, any unguarded command in this script aborts the job with a bare
# "exit code 1" and no clue which line died. `set -E` propagates the trap into
# functions and substitutions; BASH_COMMAND names the exact failing command.
trap 'rc=$?; echo "::error title=install-toolchain::exited ${rc} on: ${BASH_COMMAND}"' ERR

die() {
  echo "::error title=install-toolchain::$*"
  exit 1
}

log() {
  echo "[toolchain] $*"
}

cli_base="https://cli.moonbitlang.com"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" ||
  die "cannot resolve the script directory"
repo_root="$(cd "${script_dir}/../.." && pwd)" ||
  die "cannot resolve the repository root from ${script_dir}"
cd "${repo_root}" || die "cannot enter ${repo_root}"

# Read the two pins. `tr` strips the trailing newline and any stray whitespace;
# a missing or empty file is a repository bug, not a transient failure.
[[ -f .moonbit-version ]] || die ".moonbit-version is missing in ${repo_root}"
[[ -f .moonc-minimum ]] || die ".moonc-minimum is missing in ${repo_root}"
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
  # Download the installer to a file instead of piping it into bash: under
  # `set -o pipefail` a failed download and a failed install are otherwise
  # indistinguishable, and the real status is lost.
  installer="$(mktemp)" || die "cannot create a temporary file"
  log "downloading ${cli_base}/install/unix.sh"
  # `$?` inside `if ! cmd` is the status of the negation, i.e. always 0, so the
  # real status has to be captured with `||`.
  curl_rc=0
  curl -fsSL --retry 3 --retry-delay 2 -o "${installer}" "${cli_base}/install/unix.sh" ||
    curl_rc=$?
  if [[ ${curl_rc} -ne 0 ]]; then
    ls -l "${installer}" || true
    die "curl failed with ${curl_rc} while fetching the installer"
  fi
  log "installer is $(wc -c < "${installer}") bytes; installing ${release_tag}"
  install_rc=0
  MOONBIT_INSTALL_VERSION="${release_tag}" bash "${installer}" || install_rc=$?
  if [[ ${install_rc} -ne 0 ]]; then
    die "the installer failed with ${install_rc} for release ${release_tag}"
  fi
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
echo "${version_report}"
moonc_version="$(echo "${version_report}" | sed -n 's/^moonc v\{0,1\}\([^ +]*\).*/\1/p' | head -n 1)"
[[ -n "${moonc_version}" ]] || die "cannot parse the moonc version from the output above"

log "moonc ${moonc_version} (floor ${moonc_floor})"

# `sort -V -C` exits non-zero exactly when the two lines are out of version
# order, i.e. when the installed moonc is older than the floor.
if ! printf '%s\n%s\n' "${moonc_floor}" "${moonc_version}" | sort -V -C; then
  die "moonc ${moonc_version} is older than the required ${moonc_floor}"
fi

log "toolchain OK"
