#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory, Position = 0)][string]$WorktreePath,
  [switch]$Force,
  [string]$Model,
  [string]$Sandbox = 'workspace-write',
  [string]$Approval = 'on-request',
  [switch]$DangerousBypass
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

function Read-TaskMetadata {
  param([Parameter(Mandatory)][string]$TaskFile)

  $content = Get-Content -LiteralPath $TaskFile -Raw
  $match = [regex]::Match($content, '(?m)^meta\{[^}]+\}:\s*\r?\n\s*(.+)$')
  if (-not $match.Success) {
    throw "Could not read meta row from task.toon"
  }
  $parts = $match.Groups[1].Value.Split(',').ForEach({ $_.Trim() })
  if ($parts.Count -lt 3) {
    throw "Malformed meta row in task.toon"
  }
  return [pscustomobject]@{
    Worktree = $parts[0]
    Branch = $parts[1]
    PaneId = $parts[2]
    Created = if ($parts.Count -gt 3) { $parts[3] } else { '' }
  }
}

function Update-RestoredPane {
  param(
    [Parameter(Mandatory)][string]$TaskFile,
    [Parameter(Mandatory)][string]$OldPaneId,
    [Parameter(Mandatory)][string]$NewPaneId
  )

  $content = Get-Content -LiteralPath $TaskFile -Raw
  if (-not [string]::IsNullOrWhiteSpace($OldPaneId)) {
    $content = $content.Replace($OldPaneId, $NewPaneId)
  }
  $content = [regex]::Replace($content, '(?m)^agent_status:.*$', 'agent_status: active')
  $content = [regex]::Replace($content, '(?m)^last_update:.*$', 'last_update: ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
  Set-Content -LiteralPath $TaskFile -Value $content -Encoding utf8NoBOM
}

function Get-WorkspaceName {
  param(
    [Parameter(Mandatory)][string]$Worktree,
    [Parameter(Mandatory)][string]$OldPaneId
  )

  $panes = Get-PolydevWezTermPanes
  $match = $panes | Where-Object {
    ([string]$_.pane_id) -eq $OldPaneId
  } | Select-Object -First 1
  if ($match -and -not [string]::IsNullOrWhiteSpace($match.workspace)) {
    return [string]$match.workspace
  }

  $parent = Split-Path -Parent (Split-Path -Parent $Worktree)
  return (Split-Path -Leaf $parent)
}

Assert-PolydevCommand -Name @('wezterm', 'codex')

$ResolvedWorktree = Resolve-PolydevFullPath -Path $WorktreePath
if (-not (Test-Path -LiteralPath $ResolvedWorktree -PathType Container)) {
  throw "Worktree not found: $ResolvedWorktree"
}

$taskFile = Join-Path $ResolvedWorktree 'task.toon'
if (-not (Test-Path -LiteralPath $taskFile -PathType Leaf)) {
  throw "task.toon not found: $taskFile"
}

$meta = Read-TaskMetadata -TaskFile $taskFile
$oldPaneId = $meta.PaneId
if (-not [string]::IsNullOrWhiteSpace($oldPaneId) -and $oldPaneId -ne 'PENDING_PANE_ID' -and (Test-PolydevPaneAlive -PaneId $oldPaneId)) {
  if (-not $Force) {
    throw "Existing pane is still alive: $oldPaneId. Use -Force to replace it."
  }
  if ($PSCmdlet.ShouldProcess("pane $oldPaneId", 'close old pane')) {
    Close-PolydevPane -PaneId $oldPaneId
  }
}

$workspace = Get-WorkspaceName -Worktree $ResolvedWorktree -OldPaneId $oldPaneId
$promptDir = Join-Path $env:TEMP 'polydev-prompts'
$promptFile = Join-Path $promptDir ("codex-restore-{0}.md" -f (Get-Date -Format 'yyyyMMddHHmmss'))
$codexCommand = New-CodexCommand `
  -CwdPath $ResolvedWorktree `
  -PromptPath $promptFile `
  -ModelName $Model `
  -SandboxName $Sandbox `
  -ApprovalMode $Approval `
  -Bypass:$DangerousBypass

Write-PolydevInfo -Event 'restore_starting' -Pairs "workspace=$workspace,branch=$($meta.Branch),worktree=$ResolvedWorktree"

if ($PSCmdlet.ShouldProcess($ResolvedWorktree, 'restore Codex worktree session')) {
  New-Item -ItemType Directory -Path $promptDir -Force | Out-Null
  Get-Content -LiteralPath (Join-Path $RepoRoot 'templates/codex-worktree-prompt.md') -Raw |
    Set-Content -LiteralPath $promptFile -Encoding utf8NoBOM

  $paneId = New-PolydevPane -Workspace $workspace -TabTitle $meta.Branch -Cwd $ResolvedWorktree
  Write-PolydevInfo -Event 'terminal_session_created' -Pairs "pane_id=$paneId,backend=wezterm"
  Update-RestoredPane -TaskFile $taskFile -OldPaneId $oldPaneId -NewPaneId $paneId
  Send-PolydevText -PaneId $paneId -Text $codexCommand
  Write-PolydevInfo -Event 'codex_started' -Pairs "pane_id=$paneId"
  Write-PolydevInfo -Event 'session_restored' -Pairs "pane_id=$paneId,old_pane_id=$oldPaneId"
  Write-Output $paneId
} else {
  Write-PolydevInfo -Event 'whatif_prompt_file' -Pairs "path=$promptFile"
  Write-PolydevInfo -Event 'whatif_codex_command' -Pairs "command=$codexCommand"
  Write-PolydevInfo -Event 'whatif_no_pane_created'
}
