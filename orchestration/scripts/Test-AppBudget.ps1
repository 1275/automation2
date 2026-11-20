# Disk budget check for the application pool, done BEFORE anything is installed.
# apt itself says how much space the missing packages (with dependencies) will use.
# Output: JSON. Exit code 1 if the pool would go over the budget or the free-space reserve.
# Usage: Test-AppBudget.ps1 -BudgetGB 100 -MinFreeGB 20 firefox-esr libreoffice ...
param(
    [int]$BudgetGB = 100,
    [int]$MinFreeGB = 20,
    [Parameter(ValueFromRemainingArguments)][string[]]$Packages
)

$env:LANG = 'C'   # apt prints the size line in English only with the C locale
$apt = apt-get install --assume-no @Packages 2>&1
if ($apt -match '^E: ') { throw ($apt -match '^E: ' -join "`n") }   # unknown package, broken repo, ...

$neededMB = 0
if ("$apt" -match 'After this operation, ([\d.,]+) ([kMG])B of additional') {
    $neededMB = [double]($Matches[1] -replace ',', '') * @{ k = 1 / 1024; M = 1; G = 1024 }[$Matches[2]]
}

# Space the pool's own packages use now (dpkg Installed-Size is in KiB; shared dependencies are not counted).
$poolUsedMB = (dpkg-query -W -f='${db:Status-Abbrev} ${Installed-Size}\n' @Packages 2>$null |
    Where-Object { $_ -like 'ii *' } | ForEach-Object { [double]($_ -split '\s+')[-1] } |
    Measure-Object -Sum).Sum / 1024

$freeGB = [IO.DriveInfo]::new('/').AvailableFreeSpace / 1GB
$result = [pscustomobject]@{
    NeededMB      = [math]::Round($neededMB)
    PoolUsedMB    = [math]::Round($poolUsedMB)
    BudgetGB      = $BudgetGB
    FreeGB        = [math]::Round($freeGB, 1)
    FreeAfterGB   = [math]::Round($freeGB - $neededMB / 1024, 1)
    WithinBudget  = ($poolUsedMB + $neededMB) -le $BudgetGB * 1024
    EnoughFree    = ($freeGB - $neededMB / 1024) -ge $MinFreeGB
}
$result | ConvertTo-Json -Compress
if (-not ($result.WithinBudget -and $result.EnoughFree)) { exit 1 }
