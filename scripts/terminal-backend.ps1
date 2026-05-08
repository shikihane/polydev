#requires -Version 7.0
[CmdletBinding()]
param(
  [switch]$SelfTest
)

$BackendScript = Join-Path $PSScriptRoot 'backends\windows\wezterm.ps1'
. $BackendScript -SelfTest:$SelfTest
