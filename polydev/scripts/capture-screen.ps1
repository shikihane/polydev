#requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('pane-id')][string]$PaneId,
  [int]$Lines = 80
)

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'backends\windows\wezterm.ps1')

if (-not (Test-PolydevPaneAlive -PaneId $PaneId)) {
  throw "Pane is not alive: $PaneId"
}

Get-PolydevPaneText -PaneId $PaneId -Lines $Lines
