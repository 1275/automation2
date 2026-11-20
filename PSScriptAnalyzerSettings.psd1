# Checks a script for things that will not work in PowerShell 7 on Linux.
# Usage: Invoke-ScriptAnalyzer -Path ./MyScript.ps1 -Settings ./PSScriptAnalyzerSettings.psd1
# The Linux profile is the newest one PSScriptAnalyzer ships. The Windows-only commands it flags are still Windows-only.
@{
    IncludeRules = @(
        'PSUseCompatibleCommands'   # cmdlet does not exist on Linux (Get-Service, Get-WinEvent, ...)
        'PSUseCompatibleTypes'      # .NET type does not exist on Linux (Microsoft.Win32.Registry, ...)
        'PSAvoidUsingWMICmdlet'     # Get-WmiObject and friends
        'PSAvoidUsingCmdletAliases' # ls, cat, sort, ps ... run the Linux program instead of the cmdlet
    )
    Rules = @{
        PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @('ubuntu_x64_18.04_7.0.0_x64_3.1.2_core') }
        PSUseCompatibleTypes    = @{ Enable = $true; TargetProfiles = @('ubuntu_x64_18.04_7.0.0_x64_3.1.2_core') }
    }
}
