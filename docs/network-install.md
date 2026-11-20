# Network install: F12 → iPXE → Debian

How to reinstall a PC with Debian over the network, without a USB stick. The files are in [`pxe/`](../pxe).

```
PC: F12 → "UEFI IPv4 network boot"
 │
 ├─ company DHCP server ─────── gives the IP address (not changed)
 ├─ PXE server, dnsmasq ─────── proxy DHCP: "boot ipxeboot/x86_64-sb/ipxe-shim.efi" + TFTP
 │
 ▼
iPXE shim (signed by Microsoft)  →  ipxe.efi (signed by iPXE)  →  autoexec.ipxe = menu
 │                                                                 default: boot from local disk
 ▼ person chooses "Install Debian 13"
HTTP from PXE server, nginx: Debian installer kernel + initrd, Debian shim (signed)
 │
 ▼
Debian installer reads preseed.cfg → erases disk → installs Debian 13 → reboots
 │
 ▼
User "ansible" with our SSH key and sudo → `ansible-playbook site.yml` takes over (PowerShell, tools, checks)
```

The "lightweight Linux core" is the Debian installer itself: a small Linux kernel plus a 40 MB initrd
that runs in memory, then downloads and installs the full system.

## Set up the PXE server

On a Debian 13 machine (a VM is fine) in the same network (VLAN) as the PCs:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ansible -C ansible       # once, on the Ansible control machine
sudo ./pxe/setup-pxe-server.sh ~/.ssh/ansible.pub
```

The script:

- installs `dnsmasq`, `nginx` and `debian-installer-13-netboot-amd64` (the installer kernel and initrd,
  checked by apt and updated with normal system updates),
- downloads the signed iPXE 2.0.0 release and checks its SHA-256 checksum,
- writes the configuration from the templates in `pxe/` with this server's IP address,
- starts the services. Running it again is safe.

It takes the server address, subnet and network interface from the first directly connected network.
On a server with more than one network card, set them yourself:
`sudo SERVER_IP=10.1.2.3 SUBNET=10.1.2.0 IFACE=eth1 ./pxe/setup-pxe-server.sh key.pub`

| File in `pxe/` | Goes to | Purpose |
|---|---|---|
| `dnsmasq-pxe.conf` | `/etc/dnsmasq.d/pxe.conf` | Proxy DHCP + TFTP. Answers only PXE clients. |
| `autoexec.ipxe` | `/srv/tftp/ipxeboot/x86_64-sb/` | The iPXE menu. |
| `nginx-pxe.conf` | `/etc/nginx/sites-available/pxe` | HTTP for installer files, preseed and SSH key. |
| `preseed.cfg` | `/srv/pxe/preseed.cfg` | Answers for the installer: language, disk, accounts, software. |

## Install a PC

1. Connect the PC to the network with a cable.
2. Start it and press **F12** (Dell, Lenovo; HP uses F9 or F12) and choose **UEFI IPv4 network boot**.
   On some models network boot must first be turned on in the firmware setup.
3. In the menu, choose **Install Debian 13 automatically**. If nobody chooses within 30 seconds, the PC
   boots from its local disk. This protects PCs that have network boot first in the boot order.
4. Wait. The installer asks no questions. The PC reboots into Debian when it is done.
5. Add the new PC to `orchestration/inventory.ini` with `ansible_user=ansible` and run
   `ansible-playbook site.yml`. The hostname is `deb-` plus the MAC address, for example
   `deb-525400123456`.

## Change what gets installed

Edit `pxe/preseed.cfg`, then run the setup script again:

| What | Line |
|---|---|
| Keyboard, language, time zone | `xkb-keymap`, `debian-installer/locale`, `time/zone` |
| Desktop | `tasksel tasksel/first`: add `gnome-desktop` (or `kde-desktop`, `xfce-desktop`) |
| Disk encryption | Comment out `partman-auto/method string lvm` and use the `crypto` block below it |
| Local mirror or proxy | `mirror/http/hostname`, `mirror/http/proxy` |

## Secure Boot

The whole chain works **with Secure Boot on**. We tested this (see below).

| Step | Signed by | Checked by |
|---|---|---|
| `ipxe-shim.efi` (iPXE 2.0.0) | Microsoft UEFI CA **2011** | Firmware (db) |
| `ipxe.efi` | iPXE Secure Boot CA | iPXE shim |
| `bootnetx64.efi` (Debian shim) | Microsoft UEFI CA 2011 **and** 2023 | Firmware (db) |
| Installer kernel `linux` | Debian Secure Boot Signer 2022 | Debian shim |

**Watch out:** the iPXE 2.0.0 shim is signed only with the Microsoft UEFI CA **2011**. It boots on
every PC that still has that CA in db, which is the normal case, because the 2026 update *adds* the
2023 CA and does not remove the 2011 one. iPXE's newer rolling build has a shim with both signatures, but
its `ipxe.efi` is only test-signed, so Secure Boot blocks it. If a PC no longer trusts the 2011 CA,
use the Debian-only fallback in `dnsmasq-pxe.conf`: firmware → Debian shim → GRUB → installer. That path
shows Debian's own GRUB menu and does not read our preseed by itself. Check for a newer signed iPXE
release before then: <https://github.com/ipxe/ipxe/releases>.

Do **not** turn Secure Boot off to make network boot work. If a PC refuses to boot iPXE, check its db
with `mokutil --db` on a working Debian PC of the same model, or update its firmware.

## Security notes

- **Wrong-button risk:** choosing "Install" erases the disk without any further question. The menu
  default (local disk) and the 30-second timeout are the only protection. Keep the PXE server on a
  separate install VLAN if possible.
- **No encryption on the wire:** TFTP and HTTP are plain text. Anyone on the network could serve their own
  boot menu or preseed. Packages are still checked: the installer verifies everything it downloads from
  the Debian mirror against Debian's signing keys.
- **The preseed is readable by anyone on the network.** It has no passwords by default: the `ansible`
  user logs in with an SSH key only, and root is locked. If you turn on disk encryption, the
  passphrase is in this file. Change it after install.
- **Updates:** keep the PXE server updated (`unattended-upgrades`). The installer kernel must match the
  kernel modules on the Debian mirror. After a Debian point release, an old installer kernel can fail
  with "no kernel modules were found". `apt` updates the `debian-installer-13-netboot-amd64` package
  together with the point release.

## Not supported

- **Legacy BIOS PCs** (no UEFI). Windows 11 needs UEFI anyway. Could be added with iPXE's `undionly.kpxe`.
- **UEFI HTTP boot** (without PXE/TFTP) and **IPv6 network boot**.
- **ARM PCs.** iPXE and Debian both have arm64 files; the dnsmasq line for them is not written yet.

## Sources

- iPXE: [UEFI Secure Boot](https://ipxe.org/secboot), [`shim` command](https://ipxe.org/cmd/shim), [releases](https://github.com/ipxe/ipxe/releases)
- Debian: [Installation guide, preseeding](https://www.debian.org/releases/trixie/amd64/apb.en.html), [example preseed](https://www.debian.org/releases/trixie/example-preseed.txt)
- dnsmasq: [manual page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html) (`--dhcp-range ... proxy`, `--pxe-service`)
