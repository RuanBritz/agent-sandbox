# Remove every agent sandbox entry that install.ps1 added to the Explorer
# right-click menu (current user only), including ones since commented out of it.
#
#   .\context-menu\uninstall.ps1

$ErrorActionPreference = 'Stop'

$roots = 'HKCU:\Software\Classes\Directory\shell', 'HKCU:\Software\Classes\Directory\Background\shell'
foreach ($root in $roots) {
    if (Test-Path $root) { Get-ChildItem $root | Where-Object PSChildName -like 'AgentSandbox*' | Remove-Item -Recurse }
}
Write-Host 'Removed the agent sandbox entries from the context menu.'
