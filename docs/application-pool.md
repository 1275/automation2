# Application pool

The apps for our Debian desktops, installed by Ansible. One list for all machines; each machine picks
groups from it.

| File | Purpose |
|---|---|
| [`orchestration/apps.yml`](../orchestration/apps.yml) | The pool: groups of apps, vendor repositories, disk budget. **Edit this file.** |
| [`orchestration/install-apps.yml`](../orchestration/install-apps.yml) | The playbook that installs them. |
| [`orchestration/scripts/Test-AppBudget.ps1`](../orchestration/scripts/Test-AppBudget.ps1) | Disk budget check, before anything is installed. |

## Use

```bash
cd orchestration
ansible-playbook install-apps.yml            # all machines in inventory.ini
ansible-playbook install-apps.yml -l pc1     # one machine
```

Choose the groups per machine in `inventory.ini` (without `app_groups`, a machine gets `base`):

```ini
deb-001122aabbcc ansible_user=ansible app_groups='["base","office"]'
```

Running the playbook again is safe: it installs only what is missing. It does **not** remove apps that
you take out of the list (see "Remove an app").

## The pool

| Group | Apps | For |
|---|---|---|
| `base` | Firefox ESR, Microsoft Edge, 7-Zip, VLC | Every desktop |
| `office` | LibreOffice (+ GNOME integration), Evolution with Exchange support, KeePassXC | Office users |
| `admin` | Remmina (+ RDP plugin), Wireshark, Nmap, FileZilla | IT staff |
| `dev` | Visual Studio Code, .NET 8 SDK | Developers |

Notes for a Windows shop:

- **Microsoft Teams** has no native Linux client any more. Use Teams in Edge (it can be installed as an
  app from the Edge menu). The same goes for Outlook on the web and the other Microsoft 365 web apps.
- **Outlook:** Evolution with `evolution-ews` connects to Exchange and Microsoft 365 for mail, calendar
  and contacts.
- **Microsoft Office desktop apps** do not exist for Linux. LibreOffice opens and saves Office files;
  complex Excel macros and some layouts do not convert well. Test your important templates.
- **Windows-only apps:** run them on a Windows server or VDI and connect with Remmina (RDP).

## Disk budget (256 GB disks)

`apps.yml` sets `app_disk_budget_gb: 100` and `app_min_free_gb: 20`. Before installing, the playbook runs
`Test-AppBudget.ps1`. It asks apt how much space the missing apps **and their dependencies** need
(apt knows this exactly before it downloads anything). The install stops if:

- the apps already installed from the pool + the new ones would use more than 100 GB, or
- less than 20 GB would stay free on the disk.

Example output:

```
NeededMB: 5798      new apps with dependencies
PoolUsedMB: 0       pool apps already installed
FreeGB: 54.1        free now
FreeAfterGB: 48.5   free after install
WithinBudget: true
EnoughFree: true
```

All four groups together need about **5.8 GB** on Debian 13, so the 100 GB budget leaves a lot of room.
"PoolUsedMB" counts only the pool's own packages, not shared dependencies, so it is lower than the real
total (2.5 GB vs 5.8 GB in our test). It is a safety net, not exact accounting.

## Add an app

1. Find the Debian package name: `apt-cache search <word>`, or <https://packages.debian.org>.
2. Add it to a group in `apps.yml`, or add a new group.
3. If Debian does not have it but the vendor has an apt repository, add the repository under `app_repos`
   with the package name in its `packages:` list. The repository is then added only on machines that
   need it, and apt checks every package against the vendor's signing key.
4. Run the playbook.

Prefer, in this order: Debian package → vendor apt repository → nothing else. We do not use pip, snap,
curl-to-shell installers or loose `.deb` files: they skip apt's signature checks, or they do not update
themselves.

## Remove an app

Taking an app out of `apps.yml` only stops future installs. To remove it from machines:

```bash
ansible linux -b -m ansible.builtin.apt -a "name=wireshark state=absent autoremove=true"
```

## Known traps (already handled)

- **Edge and VS Code add their own repository** during install, and Edge again from a daily job. Two
  copies of the same repository with different key settings can break `apt update`. Our repository files
  use the vendors' own names (`microsoft-edge.sources`, `vscode.sources`), so the packages find them and
  add nothing. As a second guard, the playbook also turns the vendors' repository adding off
  (`/etc/default/microsoft-edge`, and the debconf question `code/add-microsoft-repo`). This guard is
  needed: in our test, with Edge's setting turned back on, a reinstall of Edge **rewrote our repository
  file**. The next playbook run changed it back. With the guard on, install, reinstall and Edge's daily
  job left everything alone, and `apt update` stayed clean.
  **Do not rename the keys `microsoft-edge` and `vscode` in `apps.yml`.**
- **The repository module needs `python3-debian`** on the machine. The playbook installs it.
- **Debian 13 rejects SHA-1 repository keys** (since February 2026). The Edge and VS Code repositories pass
  this check (tested).

## What was tested

On Debian 13.7, all four groups: install (5.8 GB), second run changes nothing, `apt update` clean, and
the budget check stops the install when the budget is set too low (`-e app_disk_budget_gb=1`).
Not tested: starting the apps on a real desktop (the test system had no screen).
