# Security: Windows → Debian

The security side of the Windows → Debian translation. The general table (services, registry,
networking, ...) is in [windows-to-linux.md](windows-to-linux.md).

Read this first: **the firmware is the same.** Secure Boot, the TPM and the UEFI key databases
(PK, KEK, db, dbx) belong to the PC, not to the operating system. Debian boots through a small loader
called **shim**, which Microsoft signs. So Microsoft's Secure Boot keys, the 2026 certificate change and
the revocation lists (dbx) matter for our Debian machines too.

## Quick check on every node

[`orchestration/scripts/Get-SecurityPosture.ps1`](../orchestration/scripts/Get-SecurityPosture.ps1)
reports the most important values as JSON. `ansible-playbook site.yml` runs it on all nodes.

| Field | Good value | Meaning |
|---|---|---|
| `Uefi` | `true` | The machine booted in UEFI mode. If `false`, nothing below applies. |
| `SecureBoot` | `true` | Secure Boot is on. |
| `KernelLockdown` | `integrity` | The kernel blocks unsigned modules and other ways to change the running kernel. |
| `Db_MicrosoftUefiCA2023` | `true` | The new CA that signs shim (and other third-party boot loaders) is in the firmware db. |
| `Db_WindowsUefiCA2023` | `true` | The new CA that signs the Windows boot manager is in db. Only needed for dual boot. |
| `Kek_2023` | `true` | The new Microsoft KEK is present. Without it, the machine cannot get future db/dbx updates. |
| `SbatRevocations` | not empty | Linux boot loader revocations (SBAT) that shim enforces. |
| `Tpm` | `TPM 2` | A TPM 2.0 chip is present and enabled. |
| `LuksVolumes` | `1` or more | Disk encryption (LUKS) is in use. |
| `AppArmor` | `true` | AppArmor (the Debian application confinement system) is on. |
| `RebootNeeded` | `false` | A newer kernel is installed but not running yet. |
| `OpenSecurityFixes` | `0` | Packages with a Debian security fix that is not installed. `null` = could not ask the Debian security tracker. |

`null` means "not available" (no UEFI, no TPM, tool missing, or no network). It never means "OK".
Tested on a Debian 13 virtual machine with UEFI firmware and Secure Boot on (installed through the
network install, see [network-install.md](network-install.md)). Result:

```
SecureBoot: true            KernelLockdown: integrity      AppArmor: true
Db_MicrosoftUefiCA2023: true   Db_WindowsUefiCA2023: true  Kek_2023: true
SbatRevocations: sbat,1,2025021800;shim,4;grub,5           RebootNeeded: false
Tpm: null (the VM had no TPM)
```

**Not yet tested on a physical PC.** Do that first on the POC desktop: real firmware can differ, for
example a missing 2023 certificate or KEK.

## Secure Boot

How the boot chain differs:

| | Windows | Debian |
|---|---|---|
| First loader the firmware checks | Windows boot manager (`bootmgfw.efi`) | `shim` (package `shim-signed`) |
| Signed by | "Windows Production PCA 2011", now moving to "Windows UEFI CA 2023" | Microsoft "UEFI CA 2011" (third-party CA), now moving to "Microsoft UEFI CA 2023" |
| Next steps | Windows loader → kernel → drivers | shim → GRUB → Linux kernel → kernel modules. Debian signs these with its own key, which shim trusts. |
| Revocation | dbx entries, Secure Version Number (SVN) | dbx entries, and **SBAT** (revocation by version "generation" number, enforced by shim) |

| Windows | Debian | Note |
|---|---|---|
| `Confirm-SecureBootUEFI` | `mokutil --sb-state` | Prints `SecureBoot enabled`. |
| `Get-SecureBootUEFI -Name db` / `KEK` / `dbx` / `PK` | `mokutil --db` / `--kek` / `--dbx` / `--pk` | Package `mokutil`. Also `efi-readvar` (package `efitools`). |
| Check for the 2023 CA: `[Text.Encoding]::ASCII.GetString((Get-SecureBootUEFI db).bytes) -match 'Windows UEFI CA 2023'` | `mokutil --db \| Select-String 'UEFI CA 2023'` and `mokutil --kek \| Select-String 'KEK 2K CA 2023'` | |
| Driver signature enforcement | Kernel module signing + kernel lockdown (see below) | |
| "Device security" page, `msinfo32` | `fwupdmgr security` | Shows the fwupd "Host Security ID" (HSI) level and each firmware security check. |
| BIOS settings tools from the vendor | `fwupdmgr get-bios-settings` | Only on models whose firmware exposes settings to Linux. |

## The 2026 Secure Boot certificate change

Microsoft's 2011 Secure Boot certificates expire in 2026. Today (November 2026) the KEK and UEFI CA
have already expired (late June 2026), and the Windows Production PCA expired in October 2026.

| Old certificate | Expired | Replaced by | What it signs |
|---|---|---|---|
| Microsoft Corporation KEK CA 2011 | June 2026 | Microsoft Corporation KEK 2K CA 2023 | Updates to db and dbx |
| Microsoft UEFI CA 2011 ("third-party CA") | June 2026 | Microsoft UEFI CA 2023 **and** Microsoft Option ROM UEFI CA 2023 | **Linux shim**, other third-party loaders, and firmware on graphics/network cards (option ROMs) |
| Microsoft Windows Production PCA 2011 | October 2026 | Windows UEFI CA 2023 | Windows boot manager |

What this means for us:

- **Machines do not stop booting on the expiry date.** The firmware does not check expiry dates. A shim
  signed with the 2011 CA keeps booting as long as that certificate is still in db and not revoked.
- **New shim versions are signed only with the 2023 CA.** A machine without "Microsoft UEFI CA 2023" in
  db will not boot those. So the db update must be done **before** a 2023-only shim arrives.
- **Without the 2023 KEK, a machine can get no more dbx updates.** Every new revocation is signed with
  the new KEK. Such a machine stays open to the next bootkit.
- **Do not remove the 2011 CA from db** while shim versions signed only with it are still in use.

| Windows | Debian |
|---|---|
| Set `HKLM\SYSTEM\CurrentControlSet\Control\SecureBoot\AvailableUpdates` = `0x5944`, then start the scheduled task `\Microsoft\Windows\PI\Secure-Boot-Update` | `fwupdmgr refresh`, `fwupdmgr get-updates`, `fwupdmgr update`, then reboot. Debian 13 has fwupd 2.0.20; db/KEK updates need 2.0.8 or later. The update shows as several firmware updates (KEK, db entries, dbx). |
| Status: `UEFICA2023Status` = `Updated` under `...\SecureBoot\Servicing`, and event **1808** in the System log. Event **1801** = not applied yet. Event **1802** = blocked by a known firmware problem. | Status: `mokutil --kek` and `mokutil --db` show the 2023 names. `fwupdmgr get-history` shows what was applied. `Get-SecurityPosture.ps1` fields `Kek_2023` and `Db_MicrosoftUefiCA2023`. |
| Firmware refuses the update | Same problem on Linux. Typical cause: a test Platform Key from the board maker ("DO NOT TRUST - AMI Test PK"). Fix: a firmware (BIOS) update from the PC vendor. |

Warnings that apply to both systems:

- **Dual boot:** Windows and Debian share the same firmware db/KEK/dbx. Updating from one OS changes it
  for both.
- **TPM-bound disk encryption:** a db/KEK/dbx change changes TPM PCR 7. BitLocker (Windows) and a
  TPM-bound LUKS key (Debian, see below) will then ask for the recovery key or passphrase once. Have
  the recovery keys ready **before** you update.
- **Virtual machines:** in some clouds (for example Azure Trusted Launch) the guest cannot write these
  variables. The cloud provider must do the update.

## BlackLotus (CVE-2023-24932)

BlackLotus is a UEFI bootkit. It starts an **old, vulnerable Windows boot manager** that is still signed
and trusted, and uses its flaw to get around Secure Boot. Red Hat says it knows of no Linux bootkit that
uses these CVEs. But the attack works on any PC whose firmware still trusts the old Windows boot managers.
That includes most Linux-only PCs, because "Windows Production PCA 2011" is in db by default.

**On Windows** (KB5025885), the mitigation has several steps. Microsoft has changed the registry values
over time, so always follow the current Microsoft article:

| Step | Windows event when done |
|---|---|
| Add "Windows UEFI CA 2023" to db | 1036 |
| Install the boot manager signed by the 2023 CA | 1799 |
| Revoke "Windows Production PCA 2011" in dbx | 1037 |
| Apply the Secure Version Number (SVN) update | 1042 |

The dbx and SVN steps **cannot be undone** while Secure Boot is on. Old recovery and boot media stop
working, and BitLocker may ask for the recovery key.

**On Debian:**

| Windows | Debian | Note |
|---|---|---|
| dbx update through Windows Update | `fwupdmgr update` (the "UEFI dbx" device) | Revokes known vulnerable boot loaders, Windows and Linux. Needs the 2023 KEK for new updates (see above). |
| SVN | SBAT: `mokutil --list-sbat-revocations` | shim keeps a minimum "generation" for shim, GRUB and others, and refuses older ones. New Debian `shim-signed` packages raise it. `mokutil --set-sbat-policy latest` applies the newest revocations. |
| Revoke "Windows Production PCA 2011" | Linux-only PCs: the NSA BlackLotus guide suggests **removing** "Windows Production PCA 2011" from db instead of adding many dbx hashes | Debian does not need that certificate. **Keep "Microsoft UEFI CA 2011/2023"**: shim and option ROMs (graphics, network cards) need them, and a PC without working graphics firmware may not show a picture. Advanced step: needs custom key management in the firmware; test on one PC first. Must be undone before installing Windows on the PC. |
| Keep boot components updated | `apt-get full-upgrade` updates `shim-signed`, `grub-efi-amd64-signed` and the kernel | |

**Dual-boot lesson from August 2024:** a Windows update applied an SBAT revocation for an old GRUB flaw
(CVE-2022-2601). The dual-boot detection failed on many PCs, and Linux stopped booting with
*"Verifying shim SBAT data failed: Security Policy Violation"*. The fix was a newer shim and GRUB from the
Linux distribution. Lesson: on dual-boot PCs, update the Linux boot packages **before** Windows applies
Secure Boot revocations. Old Linux install USB sticks may not boot after such an update.

## Kernel lockdown and driver signing

| Windows | Debian | Note |
|---|---|---|
| Driver signature enforcement | Kernel lockdown, `integrity` mode | Turns on by itself when Debian boots with Secure Boot. Check: `cat /sys/kernel/security/lockdown` (the active mode is in `[ ]`). It blocks unsigned kernel modules, `/dev/mem` writes, and hibernation. |
| HVCI / Memory integrity, Credential Guard | No direct equivalent | Lockdown `confidentiality` mode (kernel parameter `lockdown=confidentiality`) also blocks reading kernel memory. Test before use. |
| Third-party driver with its own signature (NVIDIA, VirtualBox) | DKMS module signed with a Machine Owner Key (MOK) | DKMS signs with `/var/lib/dkms/mok.key`. Enroll the public key once: `mokutil --import /var/lib/dkms/mok.pub`, set a one-time password, reboot, and confirm in the blue "MOK manager" screen. Without this, the module does not load. |
| Test signing mode | `mokutil --disable-validation` | Turns off shim checks. **Do not use** on managed machines. |

## TPM

| Windows | Debian |
|---|---|
| `Get-Tpm` | `ls /sys/class/tpm/`, `cat /sys/class/tpm/tpm0/tpm_version_major`, `systemd-analyze has-tpm2` |
| `tpm.msc`, TPM details | `tpm2_getcap properties-fixed` (package `tpm2-tools`) |
| `Clear-Tpm` | Do it in the firmware setup. `tpm2_clear` exists but removes all TPM-bound keys. |

## Disk encryption: BitLocker → LUKS2

| Windows | Debian | Note |
|---|---|---|
| `Get-BitLockerVolume` | `lsblk -o NAME,FSTYPE,MOUNTPOINT` (type `crypto_LUKS`), `cryptsetup status <name>`, `cryptsetup luksDump /dev/<disk>` | |
| `Enable-BitLocker` on an existing PC | Choose **"Guided - use entire disk and set up encrypted LVM"** in the Debian installer | Encrypting an existing disk later (`cryptsetup reencrypt --encrypt`) is possible but risky. For the POC, encrypt at install time. |
| TPM protector (unlock without password) | `clevis` with packages `clevis-luks`, `clevis-tpm2`, `clevis-initramfs`: `clevis luks bind -d /dev/<disk> tpm2 '{"pcr_ids":"7"}'` | Debian's default boot image (initramfs-tools) does not use `systemd-cryptenroll --tpm2-device` at boot. Use clevis, or change to `dracut`. Binding to PCR 7 = Secure Boot state; see the 2026 warning above. |
| Recovery password | `systemd-cryptenroll --recovery-key /dev/<disk>` | Adds a generated recovery key as an extra key slot. |
| Recovery key backup to AD / Entra ID | No built-in escrow | Store recovery keys in our password vault. Also back up the LUKS header: `cryptsetup luksHeaderBackup /dev/<disk> --header-backup-file <file>`. |

## Antivirus and EDR

| Windows | Debian | Note |
|---|---|---|
| Microsoft Defender (`Get-MpComputerStatus`) | Microsoft Defender for Endpoint on Linux: `mdatp health` | Package `mdatp`, from the **same** packages.microsoft.com repository as PowerShell. Needs a Defender for Endpoint licence and onboarding. Same console as our Windows machines. |
| `Update-MpSignature` | `mdatp definitions update` | |
| `Start-MpScan -ScanType QuickScan` | `mdatp scan quick` | |
| Free scanner | ClamAV: `clamscan`, signatures with `freshclam`, service `clamav-daemon` | |

## Application control: AppLocker / WDAC

| Windows | Debian | Note |
|---|---|---|
| AppLocker / WDAC | **AppArmor** (on by default since Debian 10): `aa-status` | Limits what each confined program can read, write and run. Profiles in `/etc/apparmor.d/`. |
| Allow-list of programs (WDAC policy) | **fapolicyd** (package in Debian 13) | Allows or blocks running files by path, owner or hash. Test carefully; a wrong rule can stop the system. |
| Script rules, `AllSigned` | No equivalent for PowerShell | Keep scripts root-owned and not writable by users. Optionally mount `/tmp` and `/home` with `noexec`. |

## Auditing and logs

| Windows | Debian |
|---|---|
| `auditpol` | `auditd`: rules in `/etc/audit/rules.d/`, list with `auditctl -l` |
| Security event log search | `ausearch -k <rule-key>`, `aureport --summary` |
| Logon events 4624 / 4625 | `journalctl _COMM=sshd`, `last`, `lastb`, `aureport --login` |
| `sudo` / Run as administrator events | `journalctl _COMM=sudo` |
| Windows Event Forwarding (WEF) | `systemd-journal-upload` / `systemd-journal-remote`, rsyslog forwarding, or our SIEM agent |
| File integrity monitoring | AIDE (package `aide`) |

## Hardening baselines

| Windows | Debian |
|---|---|
| Microsoft Security Baselines / CIS benchmark GPOs | **OpenSCAP** (`openscap-scanner`) with Debian content (`ssg-debian`, `ssg-debderived`). Run `oscap info` on the data stream in `/usr/share/xml/scap/ssg/content/` to see which profiles it has. CIS also publishes a Debian benchmark. |
| Microsoft Security Compliance Toolkit "Policy Analyzer" | `lynis audit system` (package `lynis`): quick score with hardening hints |
| Apply the baseline with GPO | Apply with Ansible (our `orchestration/`). Check again with OpenSCAP or Lynis. |

## Identity: AD, Kerberos, LAPS

| Windows | Debian | Note |
|---|---|---|
| `Add-Computer -DomainName` | `realm join ad.example.com` (packages `realmd`, `sssd`, `adcli`) | `realm list` shows the result. AD users can then log in. |
| `klist` | `klist` (package `krb5-user`) | |
| Local admin rights through an AD group | A sudo rule for the AD group, for example in `/etc/sudoers.d/` | |
| GPO "Allow log on locally" | sssd `ad_gpo_access_control` | sssd reads only logon rights from GPOs. Everything else: Ansible. |
| Windows LAPS | No Microsoft client for Linux | Common setup: root locked (no root password), admin rights only through AD groups and sudo. If local passwords are needed, rotate them with Ansible and store them in the vault. |

## Sources

- Microsoft: [Enterprise deployment guidance for CVE-2023-24932](https://support.microsoft.com/en-us/topic/enterprise-deployment-guidance-for-cve-2023-24932-88b8f034-20b7-4a45-80cb-c6049b0f9967)
- Microsoft: [How to manage the Windows Boot Manager revocations for CVE-2023-24932](https://support.microsoft.com/en-us/topic/how-to-manage-the-windows-boot-manager-revocations-for-secure-boot-changes-associated-with-cve-2023-24932-41a975df-beb2-40c1-99a3-b3ff139f832d)
- Microsoft: [Secure Boot DB and DBX variable update events](https://support.microsoft.com/en-us/topic/secure-boot-db-and-dbx-variable-update-events-37e47cf8-608b-4a87-8175-bdead630eb69)
- Microsoft: [Registry key updates for Secure Boot (KB5068202)](https://support.microsoft.com/en-us/help/5068202)
- Microsoft: [Secure Boot 2023 certificate transition guidance for Linux distributions](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/linux-distribution-guidance-handling-2023keys?view=windows-11)
- Red Hat: [Expiration of Secure Boot signing certificates in 2026](https://www.redhat.com/en/blog/expiration-secure-boot-signing-certificates-2026)
- Red Hat: [Is RHEL vulnerable to the BlackLotus UEFI bootkit?](https://access.redhat.com/security/blacklotus_uefi_bootkit)
- Ubuntu: [Microsoft UEFI CA rotation: what it means for Ubuntu users](https://discourse.ubuntu.com/t/microsoft-uefi-ca-rotation-what-it-means-for-ubuntu-users-and-vendors/82652)
- AlmaLinux: [Microsoft 2023 certificate transition](https://wiki.almalinux.org/documentation/secure-boot-2023-certificates.html)
- Google Cloud: [Update KEK and db certificates](https://docs.cloud.google.com/compute/docs/security/ms-secure-boot-certificates-update)
- fwupd: [issue 9191, AMI test PK](https://github.com/fwupd/fwupd/issues/9191), [issue 11251, KEK order](https://github.com/fwupd/fwupd/issues/11251)
- NSA: [BlackLotus Mitigation Guide](https://media.defense.gov/2023/Jun/22/2003245723/-1/-1/0/CSI_BlackLotus_Mitigation_Guide.PDF)
- BleepingComputer: [August Windows update breaks dual boot on Linux](https://www.bleepingcomputer.com/news/microsoft/august-windows-security-update-breaks-dual-boot-on-linux-systems/)
- Debian: [SecureBoot wiki](https://wiki.debian.org/SecureBoot), [kernel_lockdown(7)](https://manpages.debian.org/bullseye/manpages/kernel_lockdown.7.en.html)
- Our own checks on Debian 13.7: package names and versions (fwupd 2.0.20, mokutil 0.7.2, shim-signed 16.1,
  clevis 20, fapolicyd 1.3.4, mdatp in the Microsoft repo), and the `mokutil`, `fwupdmgr`, `needrestart`
  and `debsecan` options used above.
