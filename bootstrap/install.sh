#!/usr/bin/env bash
# Bootstrap a Debian (or Ubuntu) node: PowerShell 7 + automation tools.
# Safe to run again. Usage: sudo ./install.sh
set -euo pipefail

TOOLS=(git curl jq rsync openssh-client ansible)

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
. /etc/os-release   # gives $ID (debian|ubuntu) and $VERSION_ID

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

apt-get install -yq powershell "${TOOLS[@]}"

pwsh -NoProfile -Command '"PowerShell $($PSVersionTable.PSVersion) ready"'
