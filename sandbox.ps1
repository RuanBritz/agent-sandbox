# Start a throwaway sandbox container and remove it on exit.
# Folders passed in are mounted at /mnt/<folder-name>; ./workspace is always at /workspace.
#
#   .\sandbox.ps1                              # bash, just ./workspace
#   .\sandbox.ps1 C:\code\foo                  # also mount foo, start in /mnt/foo
#   .\sandbox.ps1 C:\code\foo D:\data\bar:ro   # several folders; ":ro" = read-only
#   .\sandbox.ps1 -Agent claude C:\code\foo    # start Claude Code, Codex or pi instead of bash
#   .\sandbox.ps1 -Memory 8g -Cpus 4 C:\code\foo
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('bash', 'claude', 'codex', 'pi')]
    [string]$Agent = 'bash',
    [string]$Memory,
    [string]$Cpus,
    [switch]$PauseOnError,           # used by the right-click menu, so errors stay readable
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Folders = @()
)

$ErrorActionPreference = 'Stop'

# Runs a native command with its output discarded and returns its exit code. Windows PowerShell
# 5.1 turns redirected stderr into a terminating error under ErrorActionPreference=Stop.
function Invoke-Quiet([scriptblock]$command) {
    $ErrorActionPreference = 'Continue'
    & $command *> $null
    $LASTEXITCODE
}

function Invoke-Sandbox {
    if (Invoke-Quiet { docker info }) { throw 'Docker is not running. Start Docker Desktop and try again.' }

    $runArgs = @()
    $names = @{}
    foreach ($arg in $Folders) {
        $arg = $arg.Trim('"')        # Explorer passes D:\ as `D:"`
        $mode = ''
        if ($arg -match '^(.+):(ro|rw)$') { $arg = $Matches[1]; $mode = ":$($Matches[2])" }
        if ($arg -match '^[A-Za-z]:$') { $arg += '\' }   # bare "D:" means the current directory on D

        $path = (Resolve-Path -LiteralPath $arg).ProviderPath
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Not a folder: $path" }
        # Keep the backslash on drive roots, for the same reason
        $isRoot = $path -match '^[A-Za-z]:\\$'
        if (-not $isRoot) { $path = $path.TrimEnd('\') }

        $name = if ($isRoot) { $path.Substring(0, 1) } else { Split-Path -Leaf $path }   # D:\ -> d
        $name = $name.ToLower() -replace '[^\w.-]', '-'
        if ($names.ContainsKey($name)) { throw "Two folders map to /mnt/$name; mount one of them manually." }
        $names[$name] = $true

        $gitConfig = Join-Path $path '.git\config'
        if ((Test-Path -LiteralPath $gitConfig -PathType Leaf) -and (Select-String -LiteralPath $gitConfig -Pattern 'https?://[^/\s@]+@' -Quiet)) {
            Write-Host "Warning: $gitConfig has credentials in a remote URL; the agent can read them." -ForegroundColor Yellow
        }

        $runArgs += '-v', "${path}:/mnt/${name}${mode}"
    }

    if ($names.Count -eq 1) { $runArgs += '-w', "/mnt/$($names.Keys | Select-Object -First 1)" }
    if ($Memory) { $env:SANDBOX_MEMORY = $Memory }
    if ($Cpus) { $env:SANDBOX_CPUS = $Cpus }

    $command = @(switch ($Agent) {
        'claude' { 'claude', '--dangerously-skip-permissions' }
        'codex'  { 'codex', '--dangerously-bypass-approvals-and-sandbox' }
        'pi'     { 'pi' }
        default  { 'bash' }
    })

    # Build separately, so a non-zero exit from the run below is (almost always) the shell's own
    $compose = "$PSScriptRoot\docker-compose.yml"
    docker compose -f $compose build agent
    if ($LASTEXITCODE) { throw "Building the sandbox image failed (exit code $LASTEXITCODE)." }

    # --rm only fires on a clean exit; closing the window kills the docker client but leaves the
    # container running. A hidden watcher removes it once this shell process is gone.
    $container = "agent-sandbox-$PID-$(Get-Random)"
    $runArgs += '--name', $container
    $cleanup = "Wait-Process -Id $PID -ErrorAction SilentlyContinue; docker rm -f $container *> `$null"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanup))
    $watcher = Start-Process (Get-Process -Id $PID).Path -WindowStyle Hidden -PassThru `
        -ArgumentList "-NoProfile -NonInteractive -EncodedCommand $encoded"

    $started = Get-Date
    try {
        docker compose -f $compose run --rm @runArgs agent @command
        $code = $LASTEXITCODE
    } finally {
        # Covers Ctrl+C and compose errors too, where --rm may not have fired
        Invoke-Quiet { docker rm -f $container } | Out-Null
        Stop-Process -InputObject $watcher -ErrorAction SilentlyContinue
    }
    # Shells and agents often exit non-zero after normal use; only a quick failure (e.g. a bad
    # mount) is worth pausing on
    if ($code -and $PauseOnError -and ((Get-Date) - $started).TotalSeconds -lt 15) {
        Read-Host "`nExited with code $code. Press Enter to close" | Out-Null
    }
}

try {
    Invoke-Sandbox
} catch {
    Write-Host $_ -ForegroundColor Red
    if ($PauseOnError) { Read-Host "`nPress Enter to close" | Out-Null }
    exit 1
}
