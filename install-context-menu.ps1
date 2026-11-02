# Add agent sandbox entries to the Explorer right-click menu for folders (current user only).
# On Windows 11 they appear under "Show more options".
#
#   .\install-context-menu.ps1              # add (re-run after moving this folder)
#   .\install-context-menu.ps1 -Uninstall   # remove
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

# Key name -> (menu label, -Agent value)
$entries = [ordered]@{
    'AgentSandbox'       = 'Open in agent sandbox', 'bash'
    # 'AgentSandboxClaude' = 'Open Claude Code here (sandbox)', 'claude'
    # 'AgentSandboxCodex'  = 'Open Codex here (sandbox)', 'codex'
    # 'AgentSandboxPi'     = 'Open pi here (sandbox)', 'pi'
}
# Right-click on a folder, and right-click on the background inside a folder
$roots = 'HKCU:\Software\Classes\Directory\shell', 'HKCU:\Software\Classes\Directory\Background\shell'

if ($Uninstall) {
    foreach ($root in $roots) {
        foreach ($name in $entries.Keys) { if (Test-Path "$root\$name") { Remove-Item "$root\$name" -Recurse } }
    }
    Write-Host 'Removed the agent sandbox entries from the context menu.'
    return
}

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }
$script = Join-Path $PSScriptRoot 'sandbox.ps1'
$icon = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'

foreach ($root in $roots) {
    foreach ($name in $entries.Keys) {
        $label, $agent = $entries[$name]
        $key = "$root\$name"
        New-Item -Path "$key\command" -Force | Out-Null
        Set-ItemProperty -Path $key -Name '(default)' -Value $label
        if (Test-Path $icon) { Set-ItemProperty -Path $key -Name 'Icon' -Value $icon }
        $command = "`"$pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$script`" -PauseOnError -Agent $agent `"%V`""
        Set-ItemProperty -Path "$key\command" -Name '(default)' -Value $command
    }
}
Write-Host 'Added the agent sandbox entries to the context menu.'
