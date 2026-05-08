#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory, Position = 0)][string]$Workspace,
  [Parameter(Mandatory, Position = 1)][string]$BranchName,
  [Parameter(Mandatory, Position = 2)][string]$WorktreePath,
  [Parameter(Mandatory, Position = 3)][string]$PlanFile,
  [string]$VerifyLevel = 'L2',
  [string]$VerifyFallback = 'L1',
  [string]$VerifyCommands = '',
  [string]$Model,
  [string]$Sandbox = 'workspace-write',
  [string]$Approval = 'on-request',
  [switch]$DangerousBypass,
  [int]$Peek
)

$TargetScript = Join-Path $PSScriptRoot 'adapters\codex\windows\start-worktree.ps1'
& $TargetScript @PSBoundParameters
