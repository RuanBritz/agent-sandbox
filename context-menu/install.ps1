# Add agent sandbox entries to the Explorer right-click menu for folders (current user only).
# On Windows 11 they appear under "Show more options". Asks which entries to add; entries
# not picked are removed, so re-run it to change the menu.
#
#   .\context-menu\install.ps1                        # pick from a list
#   .\context-menu\install.ps1 -Agent bash,codex      # no prompt
# Re-run after moving the agent-sandbox folder. Remove everything with .\context-menu\uninstall.ps1
param(
    [ValidateSet('bash', 'claude', 'codex', 'pi')]
    [string[]]$Agent
)

$ErrorActionPreference = 'Stop'

# Key name -> (menu label, -Agent value)
$entries = [ordered]@{
    'AgentSandbox'       = 'Open in agent sandbox', 'bash'
    'AgentSandboxClaude' = 'Open Claude Code here (sandbox)', 'claude'
    'AgentSandboxCodex'  = 'Open Codex here (sandbox)', 'codex'
    'AgentSandboxPi'     = 'Open pi here (sandbox)', 'pi'
}
# Right-click on a folder, and right-click on the background inside a folder
$roots = 'HKCU:\Software\Classes\Directory\shell', 'HKCU:\Software\Classes\Directory\Background\shell'

$names = @($entries.Keys)
if (-not $Agent) {
    for ($i = 0; $i -lt $names.Count; $i++) { Write-Host "  $($i + 1)) $($entries[$names[$i]][0])" }
    $answer = Read-Host 'Entries to add, e.g. 1,3 (Enter = all)'
    $picks = @($answer -split '[,\s]+' | Where-Object { $_ })
    $selected = if (-not $picks) { $names } else {
        foreach ($p in $picks) {
            if ($p -notmatch '^\d+$' -or [int]$p -lt 1 -or [int]$p -gt $names.Count) { throw "Not an option: $p" }
            $names[[int]$p - 1]
        }
    }
} else {
    $selected = $names | Where-Object { $entries[$_][1] -in $Agent }
}

$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }
$script = Join-Path (Split-Path $PSScriptRoot) 'sandbox.ps1'
$icon = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'

foreach ($root in $roots) {
    foreach ($name in $names) {
        $key = "$root\$name"
        if ($name -notin $selected) {
            if (Test-Path $key) { Remove-Item $key -Recurse }
            continue
        }
        $label, $agentName = $entries[$name]
        New-Item -Path "$key\command" -Force | Out-Null
        Set-ItemProperty -Path $key -Name '(default)' -Value $label
        if (Test-Path $icon) { Set-ItemProperty -Path $key -Name 'Icon' -Value $icon }
        $command = "`"$pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$script`" -PauseOnError -Agent $agentName `"%V`""
        Set-ItemProperty -Path "$key\command" -Name '(default)' -Value $command
    }
}
Write-Host "Context menu now has: $(($selected | ForEach-Object { $entries[$_][0] }) -join ', ')"
