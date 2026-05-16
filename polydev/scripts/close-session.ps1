#requires -Version 7.0
[CmdletBinding()]
param(
  [Parameter(Mandatory)][Alias('pane-id')][string]$PaneId
)

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'backends\windows\wezterm.ps1')

if (-not (Test-PolydevPaneAlive -PaneId $PaneId)) {
  Write-PolydevWarn "Pane already closed or not found: $PaneId"
  exit 0
}

Close-PolydevPane -PaneId $PaneId
Write-PolydevInfo -Event 'session_closed' -Pairs "pane_id=$PaneId"
