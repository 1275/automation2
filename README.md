# automation2 — Debian automation platform (POC)

A proof of concept for running our automation from Debian Linux desktops and servers.
It is PowerShell-first, so the scripts we already have keep working. Bash is used only where it is needed.

## What is in it

```
bootstrap/install.sh               Bash. Installs PowerShell 7 and the automation tools on one machine.
orchestration/site.yml             Ansible playbook. Bootstraps every node, then runs PowerShell tasks on them.
orchestration/inventory.ini        List of the nodes to manage.
orchestration/ansible.cfg          Ansible settings for this folder.
orchestration/scripts/*.ps1        PowerShell scripts that the playbook runs on the nodes.
```

## Quick start

On a fresh Debian 12 or 13 machine (Ubuntu also works):

```bash
git clone <this repo> && cd automation2
sudo ./bootstrap/install.sh        # PowerShell 7, git, curl, jq, rsync, ssh, ansible

cd orchestration
ansible-playbook site.yml          # runs against the nodes in inventory.ini (localhost by default)
```

Example: the output ends with a short report from each node, made by `scripts/Get-SystemReport.ps1`:

```
msg:
    Host: debian-poc-01
    OS: Debian GNU/Linux 13 (trixie)
    PowerShell: 7.x.x
    RootFreeGB: 59.1
```

To manage more machines, add them under `[linux]` in `inventory.ini`. They need SSH access and `sudo`.
The playbook bootstraps them on the first run, so you only run `install.sh` by hand on the control machine.

## How it works

1. **Bootstrap (bash).** A new Debian machine has no PowerShell, so the first step must be bash.
   `install.sh` adds the Microsoft package repository, which is the supported way to get PowerShell 7 on
   Debian. It then installs PowerShell and the tools with `apt`. The script is idempotent: running it again
   only checks that everything is present.
2. **Orchestration (Ansible).** Ansible connects to each node over SSH. It runs `install.sh` on nodes that
   do not have `pwsh` yet, and then runs the `.ps1` files in `scripts/` with `pwsh`.
3. **Work (PowerShell).** The actual automation logic lives in PowerShell scripts. To add a task, put a
   `.ps1` file in `scripts/` and add one `ansible.builtin.script` step to `site.yml` (copy the existing one).

## Why these choices

This POC follows the [Ponytail](https://flaviocopes.com/ponytail) approach: before writing code, ask
"does this need to exist?", then "does something we already have do it?", then "does a standard tool
do it?". Write new code only if all three answers are no. In practice:

- **No custom orchestrator.** Ansible is packaged in Debian, is agentless (SSH only), and is widely known.
  Writing our own would be more code for us to maintain and less capable.
- **Ansible, not PowerShell DSC.** DSC v3 is cross-platform but still young on Linux. Ansible is mature and
  the Debian `ansible` package already includes WinRM support (`python3-winrm`), so the same tool can
  manage our Windows estate later. One orchestrator for both sides.
- **PowerShell does the work.** Ansible only delivers and runs the scripts. Our team keeps writing
  PowerShell, and existing scripts move over with the usual Windows-to-Linux fixes (paths, no WMI/CIM,
  no Windows-only modules).
- **apt for everything.** No pip, no snap, no curl-pipe-to-shell. Updates come with normal system updates.
- **No wrapper scripts.** `ansible-playbook site.yml` is already one command.

## Notes and options

- **PowerShell version.** The `powershell` package follows the current release. For a fixed long-term
  version, change it to `powershell-lts` in `install.sh`.
- **CPU architecture.** Microsoft publishes the `.deb` for x64 only. That fits our Intel hardware. ARM
  machines would need the tarball install instead.
- **PowerShell-only option.** For quick ad-hoc runs without Ansible, PowerShell 7 can run commands on many
  Linux hosts over SSH by itself: `Invoke-Command -HostName host1,host2 -FilePath ./script.ps1`.
  This needs the PowerShell SSH subsystem enabled in `sshd_config` on the targets.

## Suggested next steps

1. Test on a real Debian 13 desktop VM and a second node over SSH.
2. Move one or two real PowerShell scripts from Windows into `scripts/` and note what needed changes.
3. Add a `[windows]` group to the inventory and try one task over WinRM.
4. Decide on where secrets live (Ansible Vault or our existing vault) before any real credentials are used.

Tested: `install.sh` (two runs, second one makes no changes) and `ansible-playbook site.yml` on Ubuntu 24.04.
Not yet tested on Debian itself; the Microsoft repository does publish PowerShell for Debian 12 and 13.
