#!/usr/bin/env bash
# Bootstrap a Debian (or Ubuntu) node: PowerShell 7 + automation tools.
# Safe to run again. Usage: sudo ./install.sh
# PWSH_PACKAGE=powershell sudo -E ./install.sh   -> newest release instead of LTS
set -euo pipefail

PWSH_PACKAGE=${PWSH_PACKAGE:-powershell-lts}
TOOLS=(git curl jq rsync openssh-client ansible)

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
. /etc/os-release   # gives $ID (debian|ubuntu) and $VERSION_ID
: "${VERSION_ID:?No VERSION_ID in /etc/os-release. Use a stable release, not testing/sid.}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -yq ca-certificates curl

# Microsoft package repo: ships PowerShell 7 for Debian and Ubuntu.
if ! dpkg -s packages-microsoft-prod >/dev/null 2>&1; then
  deb=$(mktemp --suffix=.deb)
  curl -fsSL -o "$deb" "https://packages.microsoft.com/config/${ID}/${VERSION_ID}/packages-microsoft-prod.deb"
  dpkg -i "$deb"
  rm -f "$deb"
  apt-get update -q
fi

# powershell and powershell-lts both own /usr/bin/pwsh, so only one can be installed.
other=powershell; [[ $PWSH_PACKAGE == powershell ]] && other=powershell-lts
apt-get remove -yq "$other"
apt-get install -yq "$PWSH_PACKAGE" "${TOOLS[@]}"

pwsh -NoProfile -Command '"PowerShell $($PSVersionTable.PSVersion) ready"'
