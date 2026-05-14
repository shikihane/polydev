#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory, Position = 0)][string]$WorktreePath,
  [switch]$Force,
  [string]$CallerCwd,
  [string]$Model,
  [string]$Sandbox = 'workspace-write',
  [string]$Approval = 'on-request',
  [switch]$DangerousBypass
)

$TargetScript = Join-Path $PSScriptRoot 'adapters\codex\windows\restore-worktree.ps1'
& $TargetScript @PSBoundParameters
