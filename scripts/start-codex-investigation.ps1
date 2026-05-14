#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory, Position = 0)][string]$Name,
  [Parameter(Mandatory)][string]$Prompt,
  [Parameter(Mandatory)][string]$Cwd,
  [string]$Output,
  [string]$Workspace,
  [string]$CallerCwd,
  [string]$Model,
  [string]$Sandbox = 'workspace-write',
  [string]$Approval = 'on-request',
  [switch]$DangerousBypass,
  [int]$Peek
)

$TargetScript = Join-Path $PSScriptRoot 'adapters\codex\windows\start-investigation.ps1'
& $TargetScript @PSBoundParameters
