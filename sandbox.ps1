# Start a throwaway sandbox container and remove it on exit.
# Folders passed in are mounted at /mnt/<folder-name>; ./workspace is always at /workspace.
# Files/folders matching .sandboxignore are hidden (replaced by empty read-only placeholders).
#
#   .\sandbox.ps1                              # bash, just ./workspace
#   .\sandbox.ps1 C:\code\foo                  # also mount foo, start in /mnt/foo
#   .\sandbox.ps1 C:\code\foo D:\data\bar:ro   # several folders; ":ro" = read-only
#   .\sandbox.ps1 -Agent claude C:\code\foo    # start Claude Code (or pi) instead of bash
#   .\sandbox.ps1 -Memory 8g -Cpus 4 C:\code\foo
[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet('bash', 'claude', 'pi')]
    [string]$Agent = 'bash',
    [string]$Memory,
    [string]$Cpus,
    [switch]$PauseOnError,           # used by the right-click menu, so errors stay readable
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Folders = @()
)

$ErrorActionPreference = 'Stop'

# Directories never scanned for ignored files (huge, and not where secrets live)
$skipDirs = @('node_modules', '.venv', 'venv', '__pycache__')

function Read-IgnorePatterns {
    $file = Join-Path $PSScriptRoot '.sandboxignore'
    if (-not (Test-Path -LiteralPath $file)) { return @() }
    Get-Content -LiteralPath $file | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
}

function Test-Ignored([string]$name, [string[]]$patterns) {
    $hit = $false
    foreach ($p in $patterns) {
        if ($p.StartsWith('!')) { if ($name -like $p.Substring(1)) { $hit = $false } }
        elseif ($name -like $p) { $hit = $true }
    }
    $hit
}

# Yields @{ Path; IsDir } for every ignored item under $root (doesn't descend into ignored dirs)
function Find-Ignored([string]$root, [string[]]$patterns) {
    $queue = [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
    $queue.Enqueue([System.IO.DirectoryInfo]::new($root))
    $scanned = 0; $nextReport = 5000
    while ($queue.Count) {
        # .NET enumeration is much faster than Get-ChildItem on big trees
        try { $items = @($queue.Dequeue().EnumerateFileSystemInfos()) } catch { continue }
        foreach ($item in $items) {
            $isDir = $item -is [System.IO.DirectoryInfo]
            if (Test-Ignored $item.Name $patterns) { @{ Path = $item.FullName; IsDir = $isDir } }
            elseif ($isDir -and $item.Name -notin $skipDirs -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $queue.Enqueue($item)
            }
        }
        $scanned += $items.Count
        if ($scanned -ge $nextReport) {
            Write-Progress -Activity "Scanning $root for secrets" -Status "$scanned items (mount a narrower folder to start faster)"
            $nextReport += 5000
        }
    }
    Write-Progress -Activity "Scanning $root for secrets" -Completed
}

# Runs a native command with its output discarded and returns its exit code. Windows PowerShell
# 5.1 turns redirected stderr into a terminating error under ErrorActionPreference=Stop.
function Invoke-Quiet([scriptblock]$command) {
    $ErrorActionPreference = 'Continue'
    & $command *> $null
    $LASTEXITCODE
}

function Invoke-Sandbox {
    if (Invoke-Quiet { docker info }) { throw 'Docker is not running. Start Docker Desktop and try again.' }

    $patterns = @(Read-IgnorePatterns)
    $runArgs = @()
    $mounts = @(@{ Host = Join-Path $PSScriptRoot 'workspace'; Container = '/workspace' })
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

        # Mounting an ignored folder (or something inside one) would expose all of it
        $ignoredPart = $path.Split('\') | Where-Object { $_ -and (Test-Ignored $_ $patterns) } | Select-Object -First 1
        if ($ignoredPart) { throw "Refusing to mount ${path}: '$ignoredPart' is hidden by .sandboxignore." }

        $name = if ($isRoot) { $path.Substring(0, 1) } else { Split-Path -Leaf $path }   # D:\ -> d
        $name = $name.ToLower() -replace '[^\w.-]', '-'
        if ($names.ContainsKey($name)) { throw "Two folders map to /mnt/$name; mount one of them manually." }
        $names[$name] = $true

        $gitConfig = Join-Path $path '.git\config'
        if ((Test-Path -LiteralPath $gitConfig -PathType Leaf) -and (Select-String -LiteralPath $gitConfig -Pattern 'https?://[^/\s@]+@' -Quiet)) {
            Write-Host "Warning: $gitConfig has credentials in a remote URL; the agent can read them." -ForegroundColor Yellow
        }

        $runArgs += '-v', "${path}:/mnt/${name}${mode}"
        $mounts += @{ Host = $path; Container = "/mnt/$name" }
    }

    # Hide secrets: mount empty read-only placeholders over anything matching .sandboxignore
    if ($patterns) {
        $empty = Join-Path $env:TEMP 'agent-sandbox-empty'
        New-Item -ItemType Directory -Force "$empty\dir" | Out-Null
        if (-not (Test-Path -LiteralPath "$empty\file")) { New-Item -ItemType File "$empty\file" | Out-Null }

        foreach ($m in $mounts) {
            foreach ($hit in Find-Ignored $m.Host $patterns) {
                $rel = $hit.Path.Substring($m.Host.Length).TrimStart('\') -replace '\\', '/'
                $src = if ($hit.IsDir) { "$empty\dir" } else { "$empty\file" }
                $runArgs += '-v', "${src}:$($m.Container)/${rel}:ro"
                Write-Host "Hidden from agent: $($m.Container)/$rel" -ForegroundColor DarkGray
            }
        }
    }

    if ($names.Count -eq 1) { $runArgs += '-w', "/mnt/$($names.Keys | Select-Object -First 1)" }
    if ($Memory) { $env:SANDBOX_MEMORY = $Memory }
    if ($Cpus) { $env:SANDBOX_CPUS = $Cpus }

    $command = @(switch ($Agent) {
        'claude' { 'claude', '--dangerously-skip-permissions' }
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
