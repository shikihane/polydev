#requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)][Alias('pane-id')][string]$PaneId,
  [Parameter(Mandatory, Position = 1)][string]$Command,
  [switch]$NoEnter,
  [int]$Peek
)

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'backends\windows\wezterm.ps1')

if (-not (Test-PolydevPaneAlive -PaneId $PaneId)) {
  throw "Pane is not alive: $PaneId"
}

Send-PolydevText -PaneId $PaneId -Text $Command -NoEnter:$NoEnter -EnterDelay 0.5
Write-PolydevInfo -Event 'command_sent' -Pairs "pane_id=$PaneId,length=$($Command.Length)"

if ($PSBoundParameters.ContainsKey('Peek')) {
  if ($Peek -gt 0) {
    Start-Sleep -Seconds $Peek
  }
  Write-Output '---PEEK---'
  Get-PolydevPaneText -PaneId $PaneId -Lines 50
}
