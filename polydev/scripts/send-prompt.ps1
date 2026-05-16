#requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)][string]$PaneId,
  [string]$Text,
  [string]$File,
  [int]$Peek
)

Set-StrictMode -Version Latest

$ScriptsRoot = $PSScriptRoot
. (Join-Path $ScriptsRoot 'backends\windows\wezterm.ps1')

if ([string]::IsNullOrWhiteSpace($Text) -and [string]::IsNullOrWhiteSpace($File)) {
  throw 'Missing prompt source: pass -Text or -File.'
}
if (-not [string]::IsNullOrWhiteSpace($Text) -and -not [string]::IsNullOrWhiteSpace($File)) {
  throw 'Use either -Text or -File, not both.'
}

if (-not [string]::IsNullOrWhiteSpace($File)) {
  $resolvedFile = (Resolve-Path -LiteralPath $File).Path
  $command = "Read $resolvedFile and follow all instructions in it."
  $sourceInfo = "path=$resolvedFile"
} else {
  $command = $Text
  $sourceInfo = "length=$($Text.Length)"
}

Send-PolydevText -PaneId $PaneId -Text $command -EnterDelay 1
Write-PolydevInfo -Event 'prompt_sent' -Pairs "pane_id=$PaneId,$sourceInfo"

if ($PSBoundParameters.ContainsKey('Peek')) {
  if ($Peek -gt 0) {
    Start-Sleep -Seconds $Peek
  }
  Write-Output '---PEEK---'
  Get-PolydevPaneText -PaneId $PaneId -Lines 50
}
