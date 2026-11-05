# Add an "Agent sandbox" submenu to the Explorer right-click menu for folders (current user
# only). On Windows 11 it appears under "Show more options". Asks which entries to put in the
# submenu; entries not picked are removed, so re-run it to change the menu.
#
#   .\context-menu\install.ps1                        # pick from a list
#   .\context-menu\install.ps1 -Agent bash,codex      # no prompt
# Re-run after moving the agent-sandbox folder. Remove everything with .\context-menu\uninstall.ps1
param(
    [ValidateSet('bash', 'claude', 'codex', 'pi')]
    [string[]]$Agent
)

$ErrorActionPreference = 'Stop'

# Submenu key name -> (menu label, -Agent value). Explorer sorts submenu items by key name.
$entries = [ordered]@{
    '1Bash'   = 'Bash shell', 'bash'
    '2Claude' = 'Claude Code', 'claude'
    '3Codex'  = 'Codex', 'codex'
    '4Pi'     = 'pi', 'pi'
}
$menuName = 'AgentSandbox'
$menuLabel = 'Agent sandbox'
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
# Each entry uses icons\<agent>.ico if present, otherwise the Docker Desktop icon
$defaultIcon = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'

function Set-Icon($key, $icon) {
    if (Test-Path $icon) { Set-ItemProperty -Path $key -Name 'Icon' -Value $icon }
}

foreach ($root in $roots) {
    # Start clean: drops the old flat entries (AgentSandbox, AgentSandboxClaude, ...) and
    # submenu items that weren't picked
    if (Test-Path $root) { Get-ChildItem $root | Where-Object PSChildName -like 'AgentSandbox*' | Remove-Item -Recurse }

    # Parent entry: an empty SubCommands value makes Explorer read the items from its shell subkey
    $menu = "$root\$menuName"
    New-Item -Path "$menu\shell" -Force | Out-Null
    Set-ItemProperty -Path $menu -Name 'MUIVerb' -Value $menuLabel
    Set-ItemProperty -Path $menu -Name 'SubCommands' -Value ''
    Set-Icon $menu (Join-Path $PSScriptRoot 'icons\menu.ico')

    foreach ($name in $selected) {
        $label, $agentName = $entries[$name]
        $key = "$menu\shell\$name"
        New-Item -Path "$key\command" -Force | Out-Null
        Set-ItemProperty -Path $key -Name 'MUIVerb' -Value $label
        $icon = Join-Path $PSScriptRoot "icons\$agentName.ico"
        if (-not (Test-Path $icon)) { $icon = $defaultIcon }
        Set-Icon $key $icon
        $command = "`"$pwsh`" -NoProfile -ExecutionPolicy Bypass -File `"$script`" -PauseOnError -Agent $agentName `"%V`""
        Set-ItemProperty -Path "$key\command" -Name '(default)' -Value $command
    }
}
Write-Host "$menuLabel submenu now has: $(($selected | ForEach-Object { $entries[$_][0] }) -join ', ')"
