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

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$ScriptsRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir '..\..\..')).Path
$RepoRoot = Split-Path -Parent $ScriptsRoot
. (Join-Path $ScriptsRoot 'backends\windows\wezterm.ps1')

function Quote-CodexArgument {
  param([Parameter(Mandatory)][string]$Value)
  return "'" + ($Value -replace "'", "''") + "'"
}

function New-CodexCommand {
  param(
    [Parameter(Mandatory)][string]$CwdPath,
    [Parameter(Mandatory)][string]$PromptPath,
    [string]$ModelName,
    [string]$SandboxName,
    [string]$ApprovalMode,
    [switch]$Bypass
  )

  $parts = @('codex', '--cd', (Quote-CodexArgument $CwdPath))
  if ($Bypass) {
    $parts += '--dangerously-bypass-approvals-and-sandbox'
  } else {
    $parts += @('--sandbox', $SandboxName, '--ask-for-approval', $ApprovalMode)
  }
  if (-not [string]::IsNullOrWhiteSpace($ModelName)) {
    $parts += @('--model', (Quote-CodexArgument $ModelName))
  }
  $parts += '--no-alt-screen'
  $parts += (Quote-CodexArgument "Read $PromptPath and follow all instructions in it.")
  return ($parts -join ' ')
}

function Initialize-TaskToon {
  param(
    [Parameter(Mandatory)][string]$TaskFile,
    [Parameter(Mandatory)][string]$Worktree,
    [Parameter(Mandatory)][string]$Branch,
    [Parameter(Mandatory)][string]$Level,
    [Parameter(Mandatory)][string]$Fallback,
    [string]$Commands
  )

  $template = Get-Content -LiteralPath (Join-Path $RepoRoot 'templates/task.toon.template') -Raw
  $created = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $content = $template.
    Replace('{{WORKTREE_PATH}}', $Worktree).
    Replace('{{BRANCH_NAME}}', $Branch).
    Replace('{{CREATED}}', $created).
    Replace('{{VERIFY_LEVEL}}', $Level).
    Replace('{{VERIFY_FALLBACK}}', $Fallback).
    Replace('{{VERIFY_COMMANDS}}', $Commands)
  Set-Content -LiteralPath $TaskFile -Value $content -Encoding utf8NoBOM
}

function Backup-TaskToon {
  param([Parameter(Mandatory)][string]$TaskFile)
  if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    return
  }
  $backupDir = Join-Path (Split-Path -Parent $TaskFile) '.task_backups'
  New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
  $backupFile = Join-Path $backupDir ("task.toon.{0}.bak" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
  Copy-Item -LiteralPath $TaskFile -Destination $backupFile -Force
}

function Get-TaskPaneId {
  param([Parameter(Mandatory)][string]$TaskFile)
  if (-not (Test-Path -LiteralPath $TaskFile -PathType Leaf)) {
    return ''
  }
  $content = Get-Content -LiteralPath $TaskFile -Raw
  $match = [regex]::Match($content, '(?m)^meta\{[^}]+\}:\s*\r?\n\s*(.+)$')
  if (-not $match.Success) {
    return ''
  }
  $parts = $match.Groups[1].Value.Split(',')
  if ($parts.Count -lt 3) {
    return ''
  }
  return $parts[2].Trim()
}

function Update-TaskToonForPane {
  param(
    [Parameter(Mandatory)][string]$TaskFile,
    [Parameter(Mandatory)][string]$PaneId,
    [Parameter(Mandatory)][string]$OldPaneId
  )

  $content = Get-Content -LiteralPath $TaskFile -Raw
  if (-not [string]::IsNullOrWhiteSpace($OldPaneId) -and $OldPaneId -ne 'PENDING_PANE_ID') {
    $content = $content.Replace($OldPaneId, $PaneId)
  } else {
    $content = $content.Replace('PENDING_PANE_ID', $PaneId)
  }
  $content = [regex]::Replace($content, '(?m)^agent_status:.*$', 'agent_status: active')
  $content = [regex]::Replace($content, '(?m)^overall_status:.*$', 'overall_status: pending')
  $content = [regex]::Replace($content, '(?m)^last_update:.*$', 'last_update: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
  Set-Content -LiteralPath $TaskFile -Value $content -Encoding utf8NoBOM
}

Assert-PolydevCommand -Name @('wezterm', 'git', 'codex')

$ResolvedPlan = Resolve-PolydevFullPath -Path $PlanFile
if (-not (Test-Path -LiteralPath $ResolvedPlan -PathType Leaf)) {
  throw "Plan file not found: $ResolvedPlan"
}

$ResolvedWorktree = Resolve-PolydevFullPath -Path $WorktreePath
if (Test-Path -LiteralPath $ResolvedWorktree -PathType Leaf) {
  throw "WorktreePath is an existing file: $ResolvedWorktree"
}

if ($ResolvedWorktree -notmatch '[\\/]\.worktrees[\\/]') {
  Write-PolydevInfo -Event 'worktree_path_warning' -Pairs "expected=.worktrees/<branch>,got=$ResolvedWorktree"
}

$promptDir = Join-Path $env:TEMP 'polydev-prompts'
$promptFile = Join-Path $promptDir ("codex-worktree-{0}.md" -f (Get-Date -Format 'yyyyMMddHHmmss'))
$codexCommand = New-CodexCommand `
  -CwdPath $ResolvedWorktree `
  -PromptPath $promptFile `
  -ModelName $Model `
  -SandboxName $Sandbox `
  -ApprovalMode $Approval `
  -Bypass:$DangerousBypass

Write-PolydevInfo -Event 'session_starting' -Pairs "workspace=$Workspace,branch=$BranchName,worktree=$ResolvedWorktree,verify=$VerifyLevel,backend=wezterm"

if ($PSCmdlet.ShouldProcess($ResolvedWorktree, "create or reuse git worktree for $BranchName")) {
  if (-not (Test-Path -LiteralPath $ResolvedWorktree -PathType Container)) {
    & git worktree add $ResolvedWorktree -b $BranchName 2>$null
    if ($LASTEXITCODE -ne 0) {
      & git worktree add $ResolvedWorktree $BranchName
      if ($LASTEXITCODE -ne 0) {
        throw "Failed to create git worktree: $ResolvedWorktree"
      }
    }
    Write-PolydevInfo -Event 'git_worktree_added' -Pairs "worktree=$ResolvedWorktree,branch=$BranchName"
  }

  $planCopy = Join-Path $ResolvedWorktree 'PLAN.md'
  if (-not (Test-Path -LiteralPath $planCopy -PathType Leaf)) {
    Copy-Item -LiteralPath $ResolvedPlan -Destination $planCopy
  }

  $taskFile = Join-Path $ResolvedWorktree 'task.toon'
  if (-not (Test-Path -LiteralPath $taskFile -PathType Leaf)) {
    Initialize-TaskToon -TaskFile $taskFile -Worktree $ResolvedWorktree -Branch $BranchName -Level $VerifyLevel -Fallback $VerifyFallback -Commands $VerifyCommands
    Write-PolydevInfo -Event 'task_toon_initialized' -Pairs "path=$taskFile"
  }

  $existingPaneId = Get-TaskPaneId -TaskFile $taskFile
  if (-not [string]::IsNullOrWhiteSpace($existingPaneId) -and $existingPaneId -ne 'PENDING_PANE_ID' -and (Test-PolydevPaneAlive -PaneId $existingPaneId)) {
    Write-PolydevInfo -Event 'session_already_running' -Pairs "pane_id=$existingPaneId"
    Write-Output $existingPaneId
    exit 0
  }

  $paneId = New-PolydevPane -Workspace $Workspace -TabTitle $BranchName -Cwd $ResolvedWorktree
  Write-PolydevInfo -Event 'terminal_session_created' -Pairs "pane_id=$paneId,backend=wezterm"

  Backup-TaskToon -TaskFile $taskFile
  Update-TaskToonForPane -TaskFile $taskFile -PaneId $paneId -OldPaneId $existingPaneId

  New-Item -ItemType Directory -Path $promptDir -Force | Out-Null
  Get-Content -LiteralPath (Join-Path $RepoRoot 'templates/codex-worktree-prompt.md') -Raw |
    Set-Content -LiteralPath $promptFile -Encoding utf8NoBOM

  Send-PolydevText -PaneId $paneId -Text $codexCommand
  Write-PolydevInfo -Event 'codex_started' -Pairs "pane_id=$paneId"
  Write-PolydevInfo -Event 'prompt_sent' -Pairs "path=$promptFile"

  if ($PSBoundParameters.ContainsKey('Peek')) {
    if ($Peek -gt 0) {
      Start-Sleep -Seconds $Peek
    }
    Write-Output '---PEEK---'
    Get-PolydevPaneText -PaneId $paneId -Lines 50
  }

  Write-PolydevInfo -Event 'session_ready' -Pairs "pane_id=$paneId,worktree=$ResolvedWorktree,branch=$BranchName"
  Write-Output $paneId
} else {
  Write-PolydevInfo -Event 'whatif_git_command' -Pairs "command=git worktree add $ResolvedWorktree -b $BranchName"
  Write-PolydevInfo -Event 'whatif_prompt_file' -Pairs "path=$promptFile"
  Write-PolydevInfo -Event 'whatif_codex_command' -Pairs "command=$codexCommand"
  Write-PolydevInfo -Event 'whatif_no_worktree_or_pane_created'
}
