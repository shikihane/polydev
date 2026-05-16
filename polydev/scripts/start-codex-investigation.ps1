#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory, Position = 0)][string]$Name,
  [Parameter(Mandatory)][string]$Cwd,
  [string]$Workspace,
  [string]$CallerCwd,
  [string]$Model,
  [string]$Sandbox = 'workspace-write',
  [string]$Approval = 'on-request',
  [switch]$DangerousBypass,
  [int]$ReadyTimeout = 15,
  [int]$Peek
)

$TargetScript = Join-Path $PSScriptRoot 'adapters\codex\windows\start-investigation.ps1'
& $TargetScript @PSBoundParameters
