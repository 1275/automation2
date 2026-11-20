# Example PowerShell task. Any existing .ps1 that runs on pwsh 7 can be dropped in here.
$os = Get-Content /etc/os-release | ConvertFrom-StringData
[pscustomobject]@{
    Host       = [Environment]::MachineName
    OS         = $os.PRETTY_NAME.Trim('"')
    PowerShell = "$($PSVersionTable.PSVersion)"
    UptimeDays = [math]::Round((Get-Uptime).TotalDays, 1)
    RootFreeGB = [math]::Round((Get-PSDrive /).Free / 1GB, 1)
} | ConvertTo-Json -Compress
