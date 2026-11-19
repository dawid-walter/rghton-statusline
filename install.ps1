<#
.SYNOPSIS
  Install the rghtON statusline for Claude Code on Windows (runs in Git Bash).

.EXAMPLE
  .\install.ps1                          # breach look, cool text, refresh every 3 s
  .\install.ps1 -Theme replicant
  .\install.ps1 -Icons netrunner         # needs a Nerd Font in your terminal
  .\install.ps1 -DryRun                  # show what would change, change nothing
  .\install.ps1 -Uninstall               # put back what was there before

.NOTES
  Touches only: <ClaudeDir>\rghton-statusline\ (script, backups, state), the
  statusLine entry of <ClaudeDir>\settings.json, and the one-word option files
  <ClaudeDir>\statusline_theme / _icons / _text / _motion.
  Needs Git for Windows (Git Bash) and jq: winget install Git.Git jqlang.jq
#>
[CmdletBinding()]
param(
  [ValidateSet('breach', 'replicant', 'herdr', 'rghton')] [string]$Theme = 'breach',
  [ValidateSet('slash', 'chip', 'bus', 'pixel', 'tag', 'gauge', 'typo', 'arrow', 'netrunner', 'terminal')] [string]$Icons = 'slash',
  [ValidateSet('gray', 'cool', 'cyan')] [string]$Text = 'cool',
  [ValidateSet('full', 'min')] [string]$Motion = 'full',
  [ValidateRange(0, 3600)] [int]$Refresh = 3,
  [string]$ClaudeDir = (Join-Path $HOME '.claude'),
  [string]$BashPath = '',
  [string]$JqPath = '',
  [switch]$DryRun,
  [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$Name = 'rghton-statusline'
$Dest = Join-Path $ClaudeDir $Name
$Settings = Join-Path $ClaudeDir 'settings.json'
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Opts = @('theme', 'icons', 'text', 'motion')
$Utf8 = New-Object System.Text.UTF8Encoding($false)   # no BOM

function Fail($msg) { Write-Host "error: $msg" -ForegroundColor Red; exit 1 }
function Say($msg) { Write-Host $msg }
function Do-Step($what, [scriptblock]$action) { if ($DryRun) { Write-Host "would: $what" } else { & $action } }
function Write-Text($path, $text) { [System.IO.File]::WriteAllText($path, $text, $Utf8) }
function To-Posix($p) {   # C:\Users\x -> /c/Users/x (Git Bash form)
  $full = [System.IO.Path]::GetFullPath($p)
  if ($full -match '^([A-Za-z]):\\(.*)$') { return '/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/') }
  return ($full -replace '\\', '/')
}

# ---- tools -----------------------------------------------------------------
if (-not $BashPath) {
  $git = Get-Command git -ErrorAction SilentlyContinue
  $candidates = @()
  if ($git) { $candidates += (Join-Path (Split-Path (Split-Path $git.Source)) 'bin\bash.exe') }
  $candidates += "$env:ProgramFiles\Git\bin\bash.exe", "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
  $BashPath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $BashPath -or -not (Test-Path $BashPath)) { Fail 'Git Bash not found. Install Git for Windows (winget install Git.Git) or pass -BashPath.' }
if (-not $JqPath) {
  $jq = Get-Command jq -ErrorAction SilentlyContinue
  if ($jq) { $JqPath = $jq.Source }
  elseif (Test-Path "$HOME\bin\jq.exe") { $JqPath = "$HOME\bin\jq.exe" }
}
if (-not $JqPath -or -not (Test-Path $JqPath)) { Fail 'jq not found. Install it (winget install jqlang.jq) or pass -JqPath.' }

# settings.json goes through jq; filter and values come from files so that no
# quoting survives PowerShell's handling of native arguments.
$Work = Join-Path ([System.IO.Path]::GetTempPath()) "$Name-$PID"
New-Item -ItemType Directory -Force -Path $Work | Out-Null
function Update-Settings($filter, [hashtable]$rawArgs) {
  $ff = Join-Path $Work 'filter.jq'; Write-Text $ff $filter
  $jqArgs = @()
  foreach ($k in $rawArgs.Keys) { $vf = Join-Path $Work "$k.txt"; Write-Text $vf $rawArgs[$k]; $jqArgs += '--rawfile', $k, $vf }
  $src = $Settings
  if (-not (Test-Path $Settings)) { $src = Join-Path $Work 'empty.json'; Write-Text $src '{}' }
  if ($DryRun) {
    Write-Host "would set in ${Settings}:"
    $ff2 = Join-Path $Work 'filter-show.jq'; Write-Text $ff2 "$filter | {statusLine}"
    & $JqPath @jqArgs -f $ff2 $src
    return
  }
  $out = & $JqPath @jqArgs -f $ff $src
  if ($LASTEXITCODE -ne 0) { Fail "jq could not update $Settings" }
  Write-Text $Settings (($out -join "`n") + "`n")
}

try {
  if ($Uninstall) {
    if (-not (Test-Path $Dest)) { Fail "nothing to uninstall: $Dest does not exist" }
    if (Test-Path $Settings) {
      Do-Step "back up settings.json" { Copy-Item $Settings (Join-Path $Dest "backup\settings.$Stamp.before-uninstall.json") }
      $prevFile = Join-Path $Dest 'previous-statusLine.json'
      $prev = if (Test-Path $prevFile) { (Get-Content -Raw $prevFile).Trim() } else { 'null' }
      if ($prev -ne 'null') { Update-Settings '.statusLine = ($prev | fromjson)' @{ prev = $prev }; Say 'statusLine: restored the one you had before' }
      else { Update-Settings 'del(.statusLine)' @{}; Say 'statusLine: removed (there was none before)' }
    }
    foreach ($o in $Opts) {
      $f = Join-Path $ClaudeDir "statusline_$o"; $p = Join-Path $Dest "previous-$o"
      if (Test-Path $p) { Do-Step "restore $f" { Copy-Item $p $f -Force } }
      elseif (Test-Path (Join-Path $Dest "had-no-$o")) { Do-Step "remove $f" { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
    }
    Do-Step "remove the script and state from $Dest" {
      Get-ChildItem $Dest -File | Remove-Item -Force
    }
    if ($DryRun) { Say 'dry run: nothing was changed'; exit 0 }
    Say "uninstalled. Backups stay in $Dest\backup (delete the folder when you no longer need them)."
    exit 0
  }

  # ---- install -------------------------------------------------------------
  Do-Step "create $Dest" { New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'backup') | Out-Null }
  Do-Step "copy statusline.sh to $Dest (LF line endings)" {
    $sh = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'statusline.sh')) -replace "`r`n", "`n"
    Write-Text (Join-Path $Dest 'statusline.sh') $sh
  }
  if (Test-Path $Settings) {
    Do-Step "back up settings.json" { Copy-Item $Settings (Join-Path $Dest "backup\settings.$Stamp.json") }
  }
  $prevFile = Join-Path $Dest 'previous-statusLine.json'
  if (-not (Test-Path $prevFile)) {
    Do-Step "remember the current statusLine in $prevFile" {
      $cur = 'null'
      if (Test-Path $Settings) { $cur = (& $JqPath -c '.statusLine // null' $Settings) -join '' }
      Write-Text $prevFile $cur
    }
  }
  foreach ($o in $Opts) {
    $f = Join-Path $ClaudeDir "statusline_$o"
    if ((Test-Path (Join-Path $Dest "previous-$o")) -or (Test-Path (Join-Path $Dest "had-no-$o"))) { continue }
    if (Test-Path $f) { Do-Step "remember $f" { Copy-Item $f (Join-Path $Dest "previous-$o") } }
    else { Do-Step "remember that $f did not exist" { Write-Text (Join-Path $Dest "had-no-$o") '' } }
  }

  $values = @{ theme = $Theme; icons = $Icons; text = $Text; motion = $Motion }
  foreach ($o in $Opts) {
    $f = Join-Path $ClaudeDir "statusline_$o"; $v = $values[$o]
    if ($o -eq 'theme' -and $v -eq 'rghton') { Do-Step "remove $f (rghtON is the default)" { Remove-Item $f -Force -ErrorAction SilentlyContinue } }
    else { Do-Step "write '$v' to $f" { Write-Text $f "$v`n" } }
  }

  $bashFwd = ($BashPath -replace '\\', '/')
  $jqDir = To-Posix (Split-Path $JqPath)
  $script = (To-Posix $Dest) + '/statusline.sh'
  $cmd = '"' + $bashFwd + '" -c ''export PATH="' + $jqDir + ':$PATH"; bash "' + $script + '"'''
  $filter = '.statusLine = ({type: "command", command: $cmd, padding: 0}' + $(if ($Refresh -gt 0) { " + {refreshInterval: $Refresh}" } else { '' }) + ')'
  Update-Settings $filter @{ cmd = $cmd }

  if ($DryRun) { Say 'dry run: nothing was changed'; exit 0 }
  Say "installed: theme $Theme, icons $Icons, text $Text, motion $Motion, refresh ${Refresh}s"
  Say 'Claude Code picks it up on the next refresh; restart open sessions if it does not.'
}
finally {
  Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}
