<#
.SYNOPSIS
  Dev tool: render ANSI (truecolor) text from statusline.sh to a PNG, the way a
  terminal grid would, for the README pictures. Windows only (System.Drawing).

.EXAMPLE
  .\tools\render.ps1 -AnsiFile frame.ans -Out docs\breach.png -Background '#050508' `
    -PlexDir C:\fonts\plex -NerdFont C:\fonts\MesloLGSNerdFont-Regular.ttf
#>
param(
  [Parameter(Mandatory)] [string]$AnsiFile,
  [Parameter(Mandatory)] [string]$Out,
  [string]$Background = '#050508',
  [Parameter(Mandatory)] [string]$PlexDir,      # IBMPlexMono-Regular.ttf + IBMPlexMono-Bold.ttf
  [Parameter(Mandatory)] [string]$NerdFont,     # any Nerd Font .ttf, for icon glyphs
  [int]$FontPx = 30,
  [int]$Columns = 0                              # fixed width in cells (0 = longest line)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile((Join-Path $PlexDir 'IBMPlexMono-Regular.ttf'))
$pfc.AddFontFile((Join-Path $PlexDir 'IBMPlexMono-Bold.ttf'))
$pfc.AddFontFile($NerdFont)
$fam = @{}; foreach ($f in $pfc.Families) { $fam[$f.Name] = $f }
$plexFam = $pfc.Families | Where-Object { $_.Name -like 'IBM Plex Mono*' } | Select-Object -First 1
$nerdFam = $pfc.Families | Where-Object { $_.Name -notlike 'IBM Plex Mono*' } | Select-Object -First 1
$unit = [System.Drawing.GraphicsUnit]::Pixel
$fReg = New-Object System.Drawing.Font($plexFam, $FontPx, [System.Drawing.FontStyle]::Regular, $unit)
$fBold = New-Object System.Drawing.Font($plexFam, $FontPx, [System.Drawing.FontStyle]::Bold, $unit)
$fNerd = New-Object System.Drawing.Font($nerdFam, $FontPx, [System.Drawing.FontStyle]::Regular, $unit)
$fCjk = New-Object System.Drawing.Font('Yu Gothic', ($FontPx * 0.9), [System.Drawing.FontStyle]::Regular, $unit)
$fEmoji = New-Object System.Drawing.Font('Segoe UI Emoji', ($FontPx * 0.85), [System.Drawing.FontStyle]::Regular, $unit)

function Get-Color($hex) { $h = $hex.TrimStart('#'); [System.Drawing.Color]::FromArgb([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16)) }
$bgColor = Get-Color $Background
$defFg = [System.Drawing.Color]::FromArgb(218, 219, 224)

# parse: list of lines, each a list of cells @{ ch; fg; bg; bold; wide; kind }
$raw = [System.IO.File]::ReadAllText($AnsiFile) -replace "`r", ''
$lines = @()
foreach ($ln in ($raw.TrimEnd("`n") -split "`n")) {
  $cells = New-Object System.Collections.ArrayList
  $fg = $defFg; $bg = $null; $bold = $false
  foreach ($part in [regex]::Split($ln, "(\x1b\[[0-9;]*m)")) {
    if ($part -match "^\x1b\[([0-9;]*)m$") {
      $codes = @($Matches[1].Split(';') | ForEach-Object { if ($_ -eq '') { 0 } else { [int]$_ } })
      for ($i = 0; $i -lt $codes.Count; $i++) {
        $c = $codes[$i]
        if ($c -eq 0) { $fg = $defFg; $bg = $null; $bold = $false }
        elseif ($c -eq 1) { $bold = $true }
        elseif ($c -eq 49) { $bg = $null }
        elseif (($c -eq 38 -or $c -eq 48) -and $codes[$i + 1] -eq 2) {
          $col = [System.Drawing.Color]::FromArgb($codes[$i + 2], $codes[$i + 3], $codes[$i + 4])
          if ($c -eq 38) { $fg = $col } else { $bg = $col }
          $i += 4
        }
      }
      continue
    }
    $j = 0
    while ($j -lt $part.Length) {
      if ([char]::IsHighSurrogate($part[$j])) { $s = $part.Substring($j, 2); $j += 2 } else { $s = [string]$part[$j]; $j += 1 }
      $cp = [char]::ConvertToUtf32($s, 0)
      $kind = 'plex'; $wide = $false
      if (($cp -ge 0xE000 -and $cp -le 0xF8FF) -or $cp -ge 0xF0000) { $kind = 'nerd' }
      elseif (($cp -ge 0x2E80 -and $cp -le 0x9FFF) -or ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or ($cp -ge 0xFF00 -and $cp -le 0xFF60)) { $kind = 'cjk'; $wide = $true }
      elseif ($cp -ge 0x1F300 -and $cp -le 0x1FAFF) { $kind = 'emoji'; $wide = $true }
      elseif ($cp -ge 0x231A -and $cp -le 0x23FF) { $kind = 'emoji'; $wide = $true }
      [void]$cells.Add(@{ ch = $s; fg = $fg; bg = $bg; bold = $bold; wide = $wide; kind = $kind })
    }
  }
  $lines += , $cells
}

# cell size from Plex
$tmp = New-Object System.Drawing.Bitmap 10, 10
$g0 = [System.Drawing.Graphics]::FromImage($tmp)
$sf = [System.Drawing.StringFormat]::GenericTypographic
$sf.FormatFlags = $sf.FormatFlags -bor [System.Drawing.StringFormatFlags]::MeasureTrailingSpaces
$cw = $g0.MeasureString(('M' * 20), $fReg, 10000, $sf).Width / 20
$ch = [math]::Ceiling($FontPx * 1.45)
$g0.Dispose(); $tmp.Dispose()

$maxCols = 0
foreach ($cells in $lines) { $n = 0; foreach ($c in $cells) { $n += $(if ($c.wide) { 2 } else { 1 }) }; if ($n -gt $maxCols) { $maxCols = $n } }
if ($Columns -gt 0) { $maxCols = $Columns }
$padX = [math]::Round($cw * 1.5); $padY = [math]::Round($ch * 0.6)
$W = [int]([math]::Ceiling($maxCols * $cw) + 2 * $padX); $H = [int]($lines.Count * $ch + 2 * $padY)
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear($bgColor)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

for ($r = 0; $r -lt $lines.Count; $r++) {
  $col = 0; $y = $padY + $r * $ch
  foreach ($c in $lines[$r]) {
    $x = $padX + $col * $cw; $span = $(if ($c.wide) { 2 } else { 1 })
    if ($c.bg) { $b = New-Object System.Drawing.SolidBrush $c.bg; $g.FillRectangle($b, [float]$x, [float]$y, [float]($cw * $span + 0.5), [float]$ch); $b.Dispose() }
    if ($c.ch -ne ' ') {
      $font = switch ($c.kind) { 'nerd' { $fNerd } 'cjk' { $fCjk } 'emoji' { $fEmoji } default { if ($c.bold) { $fBold } else { $fReg } } }
      $dy = switch ($c.kind) { 'cjk' { $FontPx * 0.12 } 'emoji' { $FontPx * 0.15 } default { $FontPx * 0.12 } }
      $br = New-Object System.Drawing.SolidBrush $c.fg
      $g.DrawString($c.ch, $font, $br, [float]$x, [float]($y + $dy), $sf)
      $br.Dispose()
    }
    $col += $span
  }
}
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host $Out
