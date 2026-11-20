# automation2 — Debian automation platform (POC)

A proof of concept for running our automation from Debian Linux desktops and servers.
It is PowerShell-first, so the scripts we already have keep working. Bash is used only where it is needed.

## What is in it

```
bootstrap/install.sh                       Bash. Installs PowerShell 7 (LTS) and the automation tools on one machine.
orchestration/site.yml                     Ansible playbook. Bootstraps every node, then runs PowerShell scripts on them.
orchestration/inventory.ini                List of the nodes to manage.
orchestration/ansible.cfg                  Ansible settings for this folder.
orchestration/scripts/Get-SystemReport.ps1     Example task: OS, PowerShell version, uptime, free disk.
orchestration/scripts/Get-SecurityPosture.ps1  Secure Boot, 2023 certificates, SBAT, lockdown, TPM, LUKS, patches.
docs/windows-to-linux.md                   Table: Windows PowerShell 5.1 features and what to use on Debian.
docs/security-windows-to-linux.md          Table: Windows security features (Secure Boot, BlackLotus, BitLocker,
                                           Defender, AppLocker, ...) and what to use on Debian.
PSScriptAnalyzerSettings.psd1              Settings to check a script for things that will not work on Linux.
```

## Quick start

On a fresh Debian 13 machine (Debian 12 and Ubuntu should also work, but were not tested):

```bash
git clone <this repo> && cd automation2
sudo ./bootstrap/install.sh        # PowerShell 7.6 LTS, git, curl, jq, rsync, ssh, ansible

cd orchestration
ansible-playbook site.yml          # runs against the nodes in inventory.ini (localhost by default)
```

The output ends with two reports per node. Real output from our Debian 13 test (a container, so it has no
UEFI firmware or TPM, and those fields are `null`):

```
msg:
-   Host: vm
    OS: Debian GNU/Linux 13 (trixie)
    PowerShell: 7.6.10
    RootFreeGB: 56.9
    UptimeDays: 0.0
-   AppArmor: false
    Db_MicrosoftUefiCA2023: null
    Kek_2023: null
    KernelLockdown: null
    SecureBoot: null
    ...
```

To manage more machines, add them under `[linux]` in `inventory.ini`. They need SSH access, `sudo` and
`python3` (Ansible needs Python on the node). The playbook bootstraps them on the first run, so you only
run `install.sh` by hand on the control machine.

## How it works

1. **Bootstrap (bash).** A new Debian machine has no PowerShell, so the first step must be bash.
   `install.sh` adds the Microsoft package repository, which is the supported way to get PowerShell 7 on
   Debian. It then installs PowerShell and the tools with `apt`. Running it again changes nothing.
2. **Orchestration (Ansible).** Ansible connects to each node over SSH. It runs `install.sh` on nodes that
   do not have `pwsh` yet, installs the tools the scripts need, and runs the `.ps1` files with `pwsh`.
3. **Work (PowerShell).** The automation logic lives in PowerShell scripts. To add a task, put a `.ps1`
   file in `orchestration/scripts/` and add its name to the `loop:` list in `site.yml`.

## Why these choices

This POC follows the [Ponytail](https://flaviocopes.com/ponytail) approach: before writing code, ask
"does this need to exist?", then "does something we already have do it?", then "does a standard tool
do it?". Write new code only if all three answers are no. In practice:

- **No custom orchestrator.** Ansible is packaged in Debian, is agentless (SSH only), and is widely known.
- **Ansible, not PowerShell DSC.** DSC v3 is cross-platform but still young on Linux. Ansible is mature and
  the Debian `ansible` package already includes WinRM support (`python3-winrm`), so the same tool can
  manage our Windows estate later. One orchestrator for both sides.
- **PowerShell does the work.** Ansible only delivers and runs the scripts. Our team keeps writing
  PowerShell. Existing scripts need the fixes listed in [docs/windows-to-linux.md](docs/windows-to-linux.md).
- **Existing checkers, not our own.** PSScriptAnalyzer (Microsoft) finds Windows-only commands. `mokutil`,
  `fwupd`, `needrestart` and `debsecan` (Debian packages) do the security checks; our script only collects
  their answers.
- **apt for everything on the nodes.** No pip, no snap, no curl-pipe-to-shell. Updates come with normal
  system updates. (Only PSScriptAnalyzer, a developer tool, comes from the PowerShell Gallery.)
- **No wrapper scripts.** `ansible-playbook site.yml` is already one command.

## Notes and options

- **PowerShell version.** `install.sh` installs `powershell-lts` (7.6, long-term support), which suits a
  company fleet. For the newest release (7.7): `sudo PWSH_PACKAGE=powershell ./bootstrap/install.sh`.
  The two packages both own `/usr/bin/pwsh`, so the script removes the other one first.
- **CPU architecture.** The Microsoft repository has PowerShell for Debian 13 on `amd64` and `arm64`.
- **Microsoft repository key.** Since February 2026, Debian 13 rejects repository keys with SHA-1
  signatures, and some older Microsoft key packages had this problem. We tested on Debian 13.7: the current
  `packages-microsoft-prod` package (1.1-debian13) works without warnings.
- **No mail server.** `debsecan` recommends a mail server (postfix/exim). `site.yml` installs it without
  recommended packages, so nodes do not get one.
- **PowerShell-only option.** For quick ad-hoc runs without Ansible, PowerShell 7 can run commands on many
  Linux hosts over SSH by itself: `Invoke-Command -HostName host1,host2 -FilePath ./script.ps1`.
  This needs the PowerShell SSH subsystem enabled in `sshd_config` on the targets.

## Suggested next steps

1. Run `site.yml` on a real Debian 13 desktop with Secure Boot on. Check the security report against
   [docs/security-windows-to-linux.md](docs/security-windows-to-linux.md). In particular: is the
   "Microsoft UEFI CA 2023" in db and the 2023 KEK present? If not, plan the `fwupdmgr` update, and have
   recovery keys ready first.
2. Move one or two real PowerShell scripts from Windows into `scripts/`. Check them first with
   PSScriptAnalyzer and use [docs/windows-to-linux.md](docs/windows-to-linux.md) for the fixes.
3. Add a `[windows]` group to the inventory and try one task over WinRM.
4. Decide on where secrets live (Ansible Vault or our existing vault) before any real credentials are used.

## What was tested

- `install.sh` on Debian 13.7 (a clean minimal install in a chroot) and Ubuntu 24.04: install, second run,
  and switching between `powershell-lts` and `powershell`.
- `ansible-playbook site.yml` against the Debian 13.7 system: passes, second run changes nothing.
  On the Ubuntu 24.04 container the `apt` task fails because of a Python mismatch in that container
  (not a playbook problem).
- Both PowerShell scripts on Debian 13 and Ubuntu 24.04, and PSScriptAnalyzer on both scripts (no findings).
- **Not tested:** real hardware. The containers have no UEFI firmware, TPM, systemd or `ip` command, so
  the Secure Boot, TPM and some table rows are checked against documentation and package contents only.
