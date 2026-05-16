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

Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $PSCommandPath
$ScriptsRoot = (Resolve-Path -LiteralPath (Join-Path $ScriptDir '..\..\..')).Path
. (Join-Path $ScriptsRoot 'backends\windows\wezterm.ps1')

function Quote-CodexArgument {
  param([Parameter(Mandatory)][string]$Value)
  return "'" + ($Value -replace "'", "''") + "'"
}

function New-CodexCommand {
  param(
    [Parameter(Mandatory)][string]$CwdPath,
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
  $parts += @('--no-alt-screen', '--disable', 'plugins')
  return ($parts -join ' ')
}

function Test-CodexReadyText {
  param([string]$Text)
  return $Text -match 'OpenAI Codex|Use /skills|context left|Ask Codex|What can I help|gpt-[^\s]+\s.*·|^\s*›|^\s*>'
}

Assert-PolydevCommand -Name @('wezterm', 'codex')

$ResolvedCallerCwd = Get-PolydevCallerCwd -CallerCwd $CallerCwd
$ResolvedCwd = Resolve-PolydevFullPath -Path $Cwd -BasePath $ResolvedCallerCwd
if (-not (Test-Path -LiteralPath $ResolvedCwd -PathType Container)) {
  throw "Directory not found: $ResolvedCwd"
}

if ([string]::IsNullOrWhiteSpace($Workspace)) {
  $Workspace = Split-Path -Leaf $ResolvedCwd
}

$command = New-CodexCommand `
  -CwdPath $ResolvedCwd `
  -ModelName $Model `
  -SandboxName $Sandbox `
  -ApprovalMode $Approval `
  -Bypass:$DangerousBypass

Write-PolydevInfo -Event 'agent_starting' -Pairs "name=$Name,workspace=$Workspace,cwd=$ResolvedCwd,timeout=$ReadyTimeout"

if ($PSCmdlet.ShouldProcess("Codex investigation '$Name'", 'create WezTerm pane and start Codex')) {
  $paneId = New-PolydevPane -Workspace "ag-$Workspace" -TabTitle $Name -Cwd $ResolvedCwd
  Write-PolydevInfo -Event 'terminal_session_created' -Pairs "pane_id=$paneId,backend=wezterm"

  Send-PolydevText -PaneId $paneId -Text $command
  Write-PolydevInfo -Event 'codex_started' -Pairs "pane_id=$paneId"

  $start = Get-Date
  while ($true) {
    if (((Get-Date) - $start).TotalSeconds -ge $ReadyTimeout) {
      Write-Error "Codex did not become ready after startup timeout"
      Write-Error "diagnostic=$ScriptsRoot\capture-screen.ps1 -PaneId $paneId -Lines 80"
      Write-Error "cleanup=$ScriptsRoot\close-session.ps1 -PaneId $paneId"
      exit 1
    }
    $text = Get-PolydevPaneText -PaneId $paneId -Lines 80
    if (Test-CodexReadyText -Text $text) {
      break
    }
    Start-Sleep -Milliseconds 250
  }

  Write-PolydevInfo -Event 'agent_ready' -Pairs "pane_id=$paneId"
  Write-Output $paneId

  if ($PSBoundParameters.ContainsKey('Peek')) {
    if ($Peek -gt 0) {
      Start-Sleep -Seconds $Peek
    }
    Write-Output '---PEEK---'
    Get-PolydevPaneText -PaneId $paneId -Lines 50
  }
} else {
  Write-PolydevInfo -Event 'whatif_codex_command' -Pairs "command=$command"
  Write-PolydevInfo -Event 'whatif_no_pane_created'
}
