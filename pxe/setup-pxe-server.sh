#!/usr/bin/env bash
# Turn a Debian 13 machine into a network install server:
#   F12 (UEFI network boot) -> iPXE (Secure Boot signed) -> menu -> Debian installer -> preseed -> done.
# The existing DHCP server is not touched: dnsmasq runs in proxy DHCP mode and only adds boot info.
# Safe to run again. Usage: sudo ./setup-pxe-server.sh /path/to/ansible_key.pub
set -euo pipefail

IPXE_URL=https://github.com/ipxe/ipxe/releases/download/v2.0.0/ipxeboot.tar.gz
IPXE_SHA256=01a526d4cc791fc30362259c609d6c506cc64a7bdff51b9a5eb788354e17eee1
DI=/usr/lib/debian-installer/images/13/amd64/text/debian-installer   # from debian-installer-13-netboot-amd64
HERE=$(dirname "$(readlink -f "$0")")
PUBKEY=${1:?Usage: $0 /path/to/ansible_key.pub  (public SSH key Ansible uses to reach installed machines)}

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }
[[ -r $PUBKEY ]] || { echo "Cannot read $PUBKEY" >&2; exit 1; }

# Server address and subnet: taken from the first directly connected IPv4 route, unless given.
read -r ROUTE_NET _ ROUTE_DEV _ ROUTE_SRC _ < <(ip -4 route show scope link proto kernel | head -n1) || true
SERVER_IP=${SERVER_IP:-${ROUTE_SRC:-}}
SUBNET=${SUBNET:-${ROUTE_NET:+${ROUTE_NET%/*}}}
IFACE=${IFACE:-${ROUTE_DEV:-}}
[[ -n $SERVER_IP && -n $SUBNET && -n $IFACE ]] || { echo "No IPv4 network found. Set SERVER_IP, SUBNET and IFACE." >&2; exit 1; }
echo "PXE server $SERVER_IP on $IFACE, proxy DHCP for $SUBNET"

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -yq dnsmasq nginx debian-installer-13-netboot-amd64 curl ca-certificates

# Signed iPXE, pinned version and checksum.
if [[ ! -f /srv/tftp/ipxeboot/.sha256 || $(cat /srv/tftp/ipxeboot/.sha256) != "$IPXE_SHA256" ]]; then
  tmp=$(mktemp)
  curl -fsSL -o "$tmp" "$IPXE_URL"
  echo "$IPXE_SHA256  $tmp" | sha256sum -c -
  rm -rf /srv/tftp/ipxeboot && mkdir -p /srv/tftp
  tar -xzf "$tmp" -C /srv/tftp
  echo "$IPXE_SHA256" > /srv/tftp/ipxeboot/.sha256
  rm -f "$tmp"
fi

render() { sed -e "s|@SERVER_IP@|$SERVER_IP|g" -e "s|@SUBNET@|$SUBNET|g" -e "s|@IFACE@|$IFACE|g" "$1"; }

# TFTP: iPXE runs autoexec.ipxe from the folder it was loaded from.
render "$HERE/autoexec.ipxe" > /srv/tftp/ipxeboot/x86_64-sb/autoexec.ipxe

# HTTP: installer kernel/initrd (kept up to date by apt), preseed, SSH key.
mkdir -p /srv/pxe
ln -sfn "$DI" /srv/pxe/debian-installer
ln -sfn "$DI" /srv/tftp/debian-installer   # only used by the Debian-shim fallback in dnsmasq-pxe.conf
render "$HERE/preseed.cfg" > /srv/pxe/preseed.cfg
install -m 0644 "$PUBKEY" /srv/pxe/authorized_keys

render "$HERE/dnsmasq-pxe.conf" > /etc/dnsmasq.d/pxe.conf
install -m 0644 "$HERE/nginx-pxe.conf" /etc/nginx/sites-available/pxe
ln -sfn /etc/nginx/sites-available/pxe /etc/nginx/sites-enabled/pxe
rm -f /etc/nginx/sites-enabled/default

dnsmasq --test
nginx -t
systemctl restart dnsmasq nginx
echo "Ready. On a client: F12 -> network boot (UEFI IPv4) -> choose 'Install Debian 13'."
