#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory, Position = 0)][string]$Name,
  [Parameter(Mandatory)][string]$Prompt,
  [Parameter(Mandatory)][string]$Cwd,
  [string]$Output,
  [string]$Workspace,
  [string]$Model,
  [string]$Sandbox = 'workspace-write',
  [string]$Approval = 'on-request',
  [switch]$DangerousBypass,
  [int]$Peek
)

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$RepoRoot = Split-Path -Parent $ScriptDir
. (Join-Path $ScriptDir 'terminal-backend.ps1')

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

function New-InvestigationPrompt {
  param(
    [Parameter(Mandatory)][string]$Task,
    [string]$ReportPath
  )

  $templatePath = Join-Path $RepoRoot 'templates/codex-investigator-prompt.md'
  $template = Get-Content -LiteralPath $templatePath -Raw
  $reportValue = if ([string]::IsNullOrWhiteSpace($ReportPath)) { '(not enforced)' } else { $ReportPath }
  return $template.Replace('{{TASK}}', $Task).Replace('{{REPORT_PATH}}', $reportValue)
}

Assert-PolydevCommand -Name @('wezterm', 'codex')

$ResolvedCwd = Resolve-PolydevFullPath -Path $Cwd
if (-not (Test-Path -LiteralPath $ResolvedCwd -PathType Container)) {
  throw "Directory not found: $ResolvedCwd"
}

if ([string]::IsNullOrWhiteSpace($Workspace)) {
  $Workspace = Split-Path -Leaf $ResolvedCwd
}

$ResolvedOutput = ''
if (-not [string]::IsNullOrWhiteSpace($Output)) {
  $ResolvedOutput = Resolve-PolydevFullPath -Path $Output -BasePath $ResolvedCwd
  $outputDir = Split-Path -Parent $ResolvedOutput
  if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not $WhatIfPreference) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
  }
}

$promptDir = Join-Path $env:TEMP 'polydev-prompts'
$promptFile = Join-Path $promptDir ("codex-investigation-{0}-{1}.md" -f $Name, (Get-Date -Format 'yyyyMMddHHmmss'))
$command = New-CodexCommand `
  -CwdPath $ResolvedCwd `
  -PromptPath $promptFile `
  -ModelName $Model `
  -SandboxName $Sandbox `
  -ApprovalMode $Approval `
  -Bypass:$DangerousBypass

Write-PolydevInfo -Event 'agent_starting' -Pairs "name=$Name,workspace=$Workspace,cwd=$ResolvedCwd"

if ($PSCmdlet.ShouldProcess("Codex investigation '$Name'", 'create WezTerm pane and start Codex')) {
  New-Item -ItemType Directory -Path $promptDir -Force | Out-Null
  New-InvestigationPrompt -Task $Prompt -ReportPath $ResolvedOutput |
    Set-Content -LiteralPath $promptFile -Encoding utf8NoBOM

  $paneId = New-PolydevPane -Workspace "ag-$Workspace" -TabTitle $Name -Cwd $ResolvedCwd
  Write-PolydevInfo -Event 'terminal_session_created' -Pairs "pane_id=$paneId,backend=wezterm"

  Send-PolydevText -PaneId $paneId -Text $command
  Write-PolydevInfo -Event 'codex_started' -Pairs "pane_id=$paneId"
  Write-PolydevInfo -Event 'prompt_sent' -Pairs "path=$promptFile"

  if ($PSBoundParameters.ContainsKey('Peek')) {
    if ($Peek -gt 0) {
      Start-Sleep -Seconds $Peek
    }
    Write-Output '---PEEK---'
    Get-PolydevPaneText -PaneId $paneId -Lines 50
  }

  $outputInfo = if ([string]::IsNullOrWhiteSpace($ResolvedOutput)) { '' } else { ",output=$ResolvedOutput" }
  Write-PolydevInfo -Event 'agent_ready' -Pairs "pane_id=$paneId$outputInfo"
  Write-Output $paneId
} else {
  Write-PolydevInfo -Event 'whatif_prompt_file' -Pairs "path=$promptFile"
  Write-PolydevInfo -Event 'whatif_codex_command' -Pairs "command=$command"
  Write-PolydevInfo -Event 'whatif_no_pane_created'
}
