# Security state of one Debian node as JSON: the Linux side of the Windows Secure Boot / BlackLotus checks.
# Run as root. A value of null means the hardware or tool is not there (for example no UEFI, no TPM).
# Needs: mokutil, needrestart, debsecan (site.yml installs them).

function Invoke-Tool { param($Name) if (Get-Command $Name -CommandType Application -ErrorAction Ignore) { & $Name @args 2>$null } }

$efi = Test-Path /sys/firmware/efi
$db  = if ($efi) { Invoke-Tool mokutil --db  | Out-String }
$kek = if ($efi) { Invoke-Tool mokutil --kek | Out-String }
$os  = Get-Content /etc/os-release | ConvertFrom-StringData
$fixes = $null   # debsecan needs to reach security-tracker.debian.org; on failure leave null, not 0
if (Get-Command debsecan -ErrorAction Ignore) {
    $out = debsecan --suite $os.VERSION_CODENAME --only-fixed --format packages 2>$null
    if ($LASTEXITCODE -eq 0) { $fixes = @($out).Count }
}
$kernel = Invoke-Tool needrestart -b | Select-String 'NEEDRESTART-KSTA: (\d)' | ForEach-Object { [int]$_.Matches.Groups[1].Value }

[pscustomobject]@{
    Host                  = [Environment]::MachineName
    Uefi                  = $efi
    SecureBoot            = if ($efi) { [bool]((Invoke-Tool mokutil --sb-state) -match 'SecureBoot enabled') } else { $null }
    KernelLockdown        = if (Test-Path /sys/kernel/security/lockdown) { (Get-Content /sys/kernel/security/lockdown) -replace '.*\[(\w+)\].*', '$1' } else { $null }
    Db_MicrosoftUefiCA2023= if ($db)  { $db  -match 'Microsoft UEFI CA 2023' } else { $null }
    Db_WindowsUefiCA2023  = if ($db)  { $db  -match 'Windows UEFI CA 2023' } else { $null }
    Kek_2023              = if ($kek) { $kek -match 'KEK 2K CA 2023' } else { $null }
    SbatRevocations       = if ($efi) { (Invoke-Tool mokutil --list-sbat-revocations) -join ';' } else { $null }
    Tpm                   = if (Test-Path /sys/class/tpm/tpm0) { "TPM $(Get-Content /sys/class/tpm/tpm0/tpm_version_major -ErrorAction Ignore)" } else { $null }
    LuksVolumes           = @(Invoke-Tool lsblk -nro FSTYPE | Where-Object { $_ -eq 'crypto_LUKS' }).Count
    AppArmor              = (Get-Content /sys/module/apparmor/parameters/enabled -ErrorAction Ignore) -eq 'Y'
    RebootNeeded          = if ($kernel) { $kernel -ge 2 } else { $null }   # 2/3 = newer kernel installed, not running
    OpenSecurityFixes     = $fixes   # packages with a Debian security fix that is not installed yet
} | ConvertTo-Json -Compress
