# Windows PowerShell 5.1 → PowerShell 7 on Debian

A lookup table for moving our PowerShell scripts from Windows to Debian.
Windows PowerShell 5.1 gets a lot from Windows itself (WMI, the registry, services, event logs).
On Linux those parts do not exist. This page lists what to use instead.

There is no complete community table for this. Microsoft documents the differences, but not the
Linux replacements. So this page combines Microsoft's documentation with our own tests on PowerShell 7.7.

## Step 1: let a tool find the problems

Do not read scripts line by line. PSScriptAnalyzer (from Microsoft) checks each command and .NET type
against a Linux profile and lists everything that will not work. The settings are in
[`PSScriptAnalyzerSettings.psd1`](../PSScriptAnalyzerSettings.psd1).

```powershell
# One time, on the Debian desktop:
Install-PSResource PSScriptAnalyzer -Repository PSGallery -TrustRepository

# For each script you want to move:
Invoke-ScriptAnalyzer -Path ./MyScript.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
```

Example output from our test:

```
  3 PSUseCompatibleCommands    The command 'Get-Service' is not available ... on platform 'Ubuntu 18.04.4 LTS'
  6 PSUseCompatibleCommands    The command 'Get-EventLog' is not available ...
 18 PSUseCompatibleCommands    The command 'sort' is not available ...
```

Notes:

- Use `-Repository PSGallery`. Without it, `Install-PSResource` in PowerShell 7.7 failed in our test.
  It searches the Microsoft Artifact Registry first.
- "Ubuntu 18.04 / 7.0.0" is the newest Linux profile in PSScriptAnalyzer. It is old, but the
  Windows-only commands it reports are still Windows-only on Debian 13 with PowerShell 7.7.
- The analyzer does **not** find: Windows paths (`C:\`, `HKLM:\`), environment variables that are
  empty on Linux, and .NET Windows types that exist but fail at run time (`Microsoft.Win32.Registry`,
  `WindowsIdentity`). Check these with the "General differences" table below.

## Step 2: look up the replacement

Tip: many Linux tools can print JSON. Pipe it to `ConvertFrom-Json` and you have PowerShell objects again,
like you had with WMI. In the tables, *(json)* marks commands that can do this.

### General differences

| Windows PowerShell 5.1 | PowerShell 7 on Debian | Note |
|---|---|---|
| `C:\Temp\file.txt` | `/tmp/file.txt` | Use `Join-Path` and `/`. A `\` is not a path separator on Linux. |
| File names are not case-sensitive | File names **are** case-sensitive | `Config.json` and `config.json` are two different files. |
| `$env:TEMP` | `[IO.Path]::GetTempPath()` | Works on both systems. |
| `$env:USERPROFILE` | `$HOME` | `$HOME` works on both systems. |
| `$env:COMPUTERNAME` | `[Environment]::MachineName` | `$env:COMPUTERNAME` is empty on Linux. |
| `$env:USERNAME` | `[Environment]::UserName` | `$env:USERNAME` is empty on Linux. |
| `$env:ProgramFiles` | `/opt`, `/usr/local` | |
| Run as Administrator | `sudo` | |
| `#Requires -RunAsAdministrator` | `if (-not [Environment]::IsPrivilegedProcess) { throw 'Run with sudo' }` | **Trap:** on Linux, `#Requires -RunAsAdministrator` is ignored. Our test ran it as a normal user without an error. |
| `([Security.Principal.WindowsPrincipal] ...).IsInRole(...)` | `[Environment]::IsPrivilegedProcess` | Works on both systems (PowerShell 7.4+). |
| Aliases `ls`, `cat`, `sort`, `ps`, `cp`, `mv`, `rm`, `kill`, `sleep`, `diff`, `tee`, `man`, `mount`, `start`, `clear`, `compare` | Use the full name: `Get-ChildItem`, `Get-Content`, `Sort-Object`, `Get-Process`, ... | **Trap:** on Linux these aliases do not exist. `ls` runs the Linux `ls`, which returns text, not objects. Aliases that still exist: `cd`, `cls`, `copy`, `del`, `dir`, `echo`, `gci`, `md`, `pwd`, `select`, `type`, `where`. |
| `Set-ExecutionPolicy` | Not needed | Has no effect on Linux. Use file permissions (`chmod +x`). |
| Script started by double-click or `.ps1` file type | First line `#!/usr/bin/env pwsh`, then `chmod +x script.ps1` | After that, `./script.ps1` runs from bash. |
| Files saved as UTF-16 or with CRLF line endings | UTF-8, LF line endings | PowerShell 7 writes UTF-8 without BOM by default. Set `.gitattributes` to keep LF. |
| `$PSVersionTable.PSEdition -eq 'Desktop'` | `$IsLinux`, `$IsWindows`, `$IsMacOS` | Use these to write one script for both systems. |

### System information (WMI / CIM)

There is no WMI or CIM on Linux. `Get-WmiObject` and `Get-CimInstance` are both missing.

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| `Get-CimInstance Win32_OperatingSystem` | `Get-Content /etc/os-release \| ConvertFrom-StringData` or `$PSVersionTable.OS` |
| `Get-ComputerInfo` | `hostnamectl --json=short \| ConvertFrom-Json` *(json)* |
| `Win32_ComputerSystem` (model, maker) | `hostnamectl` (shows hardware vendor and model) or `sudo dmidecode -t system` |
| `Win32_Processor` | `lscpu -J \| ConvertFrom-Json` *(json)*, `[Environment]::ProcessorCount` |
| `Win32_PhysicalMemory`, free memory | `Get-Content /proc/meminfo`, `free -b` |
| `Win32_LogicalDisk`, `Get-Volume` | `Get-PSDrive -PSProvider FileSystem`, `df -h`, `findmnt -J` *(json)* |
| `Get-Disk`, `Get-Partition` | `lsblk -J \| ConvertFrom-Json` *(json)* |
| `Win32_BIOS` | `sudo dmidecode -t bios` |
| Uptime from `Win32_OperatingSystem.LastBootUpTime` | `Get-Uptime` (works on Linux) |
| `Get-Counter` (performance counters) | `/proc/loadavg`, `vmstat`, `sar` (package `sysstat`) |
| `Get-Process`, `Stop-Process` | Same. These work on Linux. |

### Services

Debian uses systemd instead of the Windows Service Control Manager.

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| `Get-Service` | `systemctl list-units --type=service` |
| `(Get-Service sshd).Status` | `systemctl is-active ssh` or `systemctl show ssh -p ActiveState,SubState \| ConvertFrom-StringData` |
| `Start-Service` / `Stop-Service` / `Restart-Service` | `systemctl start` / `stop` / `restart <name>` |
| `Set-Service -StartupType Automatic` / `Disabled` | `systemctl enable` / `disable <name>` (add `--now` to also start or stop it) |
| `New-Service` | Write a unit file in `/etc/systemd/system/<name>.service`, then `systemctl daemon-reload` and `systemctl enable --now <name>` |

### Scheduled tasks

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| `Register-ScheduledTask` | systemd timer: a `.service` file plus a `.timer` file in `/etc/systemd/system/`. Or a line in `/etc/cron.d/` |
| `Get-ScheduledTask` | `systemctl list-timers`, `ls /etc/cron.d` |
| `Start-ScheduledTask` | `systemctl start <name>.service` |

We suggest systemd timers. Their output goes to the journal, so you can read it with `journalctl -u <name>`.

### Event logs

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| `Get-EventLog` / `Get-WinEvent -LogName System` | `journalctl -n 50`, `journalctl -u <service>`, `journalctl -p err --since today` |
| `Get-WinEvent` with objects | `journalctl -o json -n 50 \| ForEach-Object { $_ \| ConvertFrom-Json }` *(json, one object per line)* |
| `Write-EventLog` / `New-EventLog` | `logger -t MyScript "message"`. The message goes to the journal. |
| Application log files | `/var/log/` |

### Registry

Linux has no registry. There is no `HKLM:` or `HKCU:` drive.

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| System settings in `HKLM:\SOFTWARE\...` | Text files in `/etc/` (for example `/etc/<app>/`, `/etc/default/<app>`) |
| User settings in `HKCU:\...` | Files in `~/.config/<app>/` |
| Our own script settings in the registry | A `.psd1` file (`Import-PowerShellDataFile`) or JSON (`ConvertFrom-Json`). Works on both systems. |
| Installed software (`...\Uninstall` keys) | `dpkg-query -W -f='${Package}\t${Version}\n'` |

### Networking

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| `Test-NetConnection server -Port 443` | `Test-Connection server -TcpPort 443` (built into PowerShell 7) |
| `Test-NetConnection server` (ping) | `Test-Connection server` |
| `Get-NetIPAddress` | `ip -j addr \| ConvertFrom-Json` *(json)* |
| `Get-NetAdapter` | `ip -j link \| ConvertFrom-Json` *(json)* |
| `Get-NetRoute` | `ip -j route \| ConvertFrom-Json` *(json)* |
| `Resolve-DnsName` | `[System.Net.Dns]::GetHostAddresses('name')`, `getent hosts name`, `dig` (package `bind9-dnsutils`) |
| `Get-DnsClientServerAddress` | `resolvectl status` or `/etc/resolv.conf` |
| `Get-NetFirewallRule` / `New-NetFirewallRule` | `nft list ruleset` (nftables is the Debian default). `ufw` is a simpler option. |
| `Invoke-WebRequest`, `Invoke-RestMethod` | Same. These work on Linux. `-UseBasicParsing` is not needed. |
| `New-PSDrive -Persist`, `New-SmbMapping` (map a share) | `mount -t cifs` (package `cifs-utils`), or a line in `/etc/fstab` |

### Users, groups and permissions

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| `Get-LocalUser` | `getent passwd \| ConvertFrom-Csv -Delimiter ':' -Header Name,Pw,Uid,Gid,Gecos,Home,Shell` |
| `New-LocalUser` / `Remove-LocalUser` | `useradd -m <name>` / `userdel <name>` |
| `Get-LocalGroupMember` | `getent group <group>` |
| `Add-LocalGroupMember` | `usermod -aG <group> <user>` |
| `Get-Acl` / `Set-Acl` | `Get-Item` shows `UnixMode`, `User`, `Group`. Change with `chmod`, `chown`. Extra ACLs: `getfacl` / `setfacl` (package `acl`) |
| `Start-Process -Verb RunAs` | `sudo` |

### Updates, software and system

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| `Get-HotFix` | `/var/log/apt/history.log` |
| Windows Update | `apt-get update; apt-get upgrade`. Automatic: package `unattended-upgrades` |
| `Install-WindowsFeature` / `Get-WindowsFeature` | `apt-get install <package>` / `dpkg -l` |
| `Rename-Computer` | `hostnamectl set-hostname <name>` |
| `Restart-Computer`, `Stop-Computer` | Same. These work on Linux. |
| `Get-TimeZone` | Same. Works on Linux. |
| `Set-TimeZone` | `timedatectl set-timezone Europe/Stockholm` |
| `Cert:\` drive, `Import-Certificate` (trusted root CA) | Copy the `.crt` to `/usr/local/share/ca-certificates/`, then `update-ca-certificates` |

### Credentials and secrets

| Windows PowerShell 5.1 | PowerShell 7 on Debian | Note |
|---|---|---|
| `Get-Credential \| Export-Clixml cred.xml` | Modules `Microsoft.PowerShell.SecretManagement` + `Microsoft.PowerShell.SecretStore` | **Trap:** on Linux, `Export-Clixml` does **not** encrypt credentials. It stores the password as plain hex; our test decoded it back in one line. On Windows it uses DPAPI, which Linux does not have. |
| `ConvertFrom-SecureString` (DPAPI) | Same modules as above | |

### Remoting

| Windows PowerShell 5.1 | PowerShell 7 on Debian |
|---|---|
| `Enter-PSSession -ComputerName srv` (WinRM) | `Enter-PSSession -HostName srv -UserName me` (SSH) |
| `Invoke-Command -ComputerName a,b -ScriptBlock {...}` | `Invoke-Command -HostName a,b -ScriptBlock {...}` |
| Many machines, settings that must stay the same | Ansible, see [`orchestration/`](../orchestration) |

SSH remoting needs a PowerShell subsystem line in `/etc/ssh/sshd_config` on the target:
`Subsystem powershell /usr/bin/pwsh -sshs -NoLogo`

### Windows-only modules and GUI

| Windows PowerShell 5.1 | On Debian |
|---|---|
| `ActiveDirectory` module (`Get-ADUser`, ...) | Not available on Linux. Run it on a Windows server through `Invoke-Command -HostName` (SSH) or an Ansible Windows task. For joining Debian to AD: `realmd` + `sssd`. |
| Group Policy | Ansible playbooks |
| `Out-GridView` | `Out-ConsoleGridView` from module `Microsoft.PowerShell.ConsoleGuiTools` (works in the terminal) |
| Windows Forms / WPF (`System.Windows.Forms`) | Not available. Write console scripts instead. |
| COM objects (`New-Object -ComObject Excel.Application`) | Not available. For Excel files: module `ImportExcel` (works on Linux, no Excel needed). |
| `Import-Module -UseWindowsPowerShell` | Not available. It needs Windows PowerShell 5.1 on the same machine. |

## Sources

- Microsoft: [Differences between Windows PowerShell 5.1 and PowerShell 7](https://learn.microsoft.com/powershell/scripting/whats-new/differences-from-windows-powershell)
- Microsoft: [PowerShell differences on non-Windows platforms](https://learn.microsoft.com/powershell/scripting/whats-new/unix-support)
- Microsoft: [Migrating from Windows PowerShell 5.1 to PowerShell 7](https://learn.microsoft.com/powershell/scripting/whats-new/migrating-from-windows-powershell-51-to-powershell-7)
- Microsoft: [PSScriptAnalyzer rule UseCompatibleCommands](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules/usecompatiblecommands)
- Jeff Hicks: [PowerShell 7 cross-platform scripting tips and traps](https://jdhitsolutions.com/blog/scripting/7361/powershell-7-cross-platform-scripting-tips-and-traps/)
- Our own tests on Ubuntu 24.04 with PowerShell 7.7.0: the aliases, `#Requires -RunAsAdministrator`,
  `Test-Connection -TcpPort`, `Get-Item` Unix properties, `Export-Clixml` credentials, and the cmdlets marked "works on Linux".
