#!/usr/bin/env bash
# Install the MoonBit toolchain and refuse to continue unless the resulting
# moonc satisfies .moonc-minimum.
#
# Why this asserts instead of pinning the download:
#
#   The MoonBit CDN serves only the `latest` alias. Every versioned path was
#   probed and answers 403 Forbidden:
#     binaries/0.1.20261126/moonbit-linux-x86_64.tar.gz   -> 403
#     binaries/0.1.20261104/moonbit-linux-x86_64.tar.gz   -> 403
#     cores/core-0.1.20261126.tar.gz                      -> 403
#     binaries/latest/...                                 -> 200
#   So `install/unix.sh <version>` cannot work, and the previous workflow's
#   claim to install the toolchain "pinned by .moonbit-version" was never true.
#
#   The guarantee therefore comes from the assertion, not from the URL: we
#   install whatever `latest` is and fail loudly if that is older than the
#   floor this project requires. `.moonbit-version` records the release the
#   code was verified against; a mismatch is reported as a warning, because it
#   is information, not a reason to redo the release.

set -Eeuo pipefail

# Without this, any unguarded command aborts the job with a bare "exit code 1"
# and no clue which line died. `set -E` propagates the trap into functions and
# substitutions; BASH_COMMAND names the exact failing command.
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

[[ -f .moonbit-version ]] || die ".moonbit-version is missing in ${repo_root}"
[[ -f .moonc-minimum ]] || die ".moonc-minimum is missing in ${repo_root}"
verified_release="$(tr -d '[:space:]' < .moonbit-version)"
moonc_floor="$(tr -d '[:space:]' < .moonc-minimum)"
[[ -n "${verified_release}" ]] || die ".moonbit-version is empty"
[[ -n "${moonc_floor}" ]] || die ".moonc-minimum is empty"

moon_home="${MOON_HOME:-$HOME/.moon}"
moon_bin="${moon_home}/bin"
log "verified_release=${verified_release} floor=${moonc_floor} moon_home=${moon_home}"

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
  log "installer is $(wc -c < "${installer}") bytes; installing latest"
  install_rc=0
  bash "${installer}" || install_rc=$?
  if [[ ${install_rc} -ne 0 ]]; then
    die "the installer failed with ${install_rc}"
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
  die "'moon' is still not on PATH after installing"
fi

# `moon version --all` prints, in order:
#   moon 0.1.20261126 (ccd306a 2026-11-26) /home/runner/.moon/bin/moon
#   moonc v1.0.0-rc1+3c0520448 (2026-11-26) /home/runner/.moon/bin/moonc
#   moonrun 0.1.20261126 (ccd306a 2026-11-26) /home/runner/.moon/bin/moonrun
version_report="$(moon version --all)"
echo "${version_report}"

moonc_version="$(echo "${version_report}" | sed -n 's/^moonc v\{0,1\}\([^ +]*\).*/\1/p' | head -n 1)"
[[ -n "${moonc_version}" ]] || die "cannot parse the moonc version from the output above"
installed_release="$(echo "${version_report}" | sed -n 's/^moon \([^ ]*\).*/\1/p' | head -n 1)"

log "moonc ${moonc_version} (floor ${moonc_floor}), release ${installed_release}"

# `sort -V -C` exits non-zero exactly when the two lines are out of version
# order, i.e. when the installed moonc is older than the floor.
if ! printf '%s\n%s\n' "${moonc_floor}" "${moonc_version}" | sort -V -C; then
  die "moonc ${moonc_version} is older than the required ${moonc_floor}"
fi

if [[ -n "${installed_release}" && "${installed_release}" != "${verified_release}" ]]; then
  echo "::warning title=install-toolchain::CI installed release ${installed_release}, but .moonbit-version records ${verified_release} as the verified one. The compiler is still within the required floor."
fi

log "toolchain OK"
