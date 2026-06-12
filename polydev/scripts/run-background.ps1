#requires -Version 7.0
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory, Position = 0)][string]$Name,
  [Parameter(Mandatory, Position = 1)][string]$Command,
  [string]$Cwd = (Get-Location).Path,
  [string]$Workspace,
  [string]$CallerCwd,
  [int]$Peek
)

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'backends\windows\wezterm.ps1')

if ($Command -match "[`r`n]") {
  throw 'Command must be a single line; newline characters usually mean the caller shell expanded part of the command before Polydev received it.'
}

$ResolvedCallerCwd = Get-PolydevCallerCwd -CallerCwd $CallerCwd
$ResolvedCwd = Resolve-PolydevFullPath -Path $Cwd -BasePath $ResolvedCallerCwd
if (-not (Test-Path -LiteralPath $ResolvedCwd -PathType Container)) {
  throw "Directory not found: $ResolvedCwd"
}

if ([string]::IsNullOrWhiteSpace($Workspace)) {
  $Workspace = Split-Path -Leaf $ResolvedCwd
}

Write-PolydevInfo -Event 'bg_starting' -Pairs "name=$Name,workspace=$Workspace,cwd=$ResolvedCwd"

if ($PSCmdlet.ShouldProcess("background task '$Name'", 'create WezTerm pane and send command')) {
  $paneId = New-PolydevPane -Workspace "bg-$Workspace" -TabTitle $Name -Cwd $ResolvedCwd
  Write-PolydevInfo -Event 'terminal_session_created' -Pairs "pane_id=$paneId,backend=wezterm"

  Send-PolydevText -PaneId $paneId -Text $Command -EnterDelay 0.5
  Write-PolydevInfo -Event 'command_sent' -Pairs "length=$($Command.Length)"

  Write-PolydevInfo -Event 'bg_ready' -Pairs "pane_id=$paneId"
  Write-Output $paneId

  if ($PSBoundParameters.ContainsKey('Peek')) {
    if ($Peek -gt 0) {
      Start-Sleep -Seconds $Peek
    }
    Write-Output '---PEEK---'
    Get-PolydevPaneText -PaneId $paneId -Lines 50
  }
} else {
  Write-PolydevInfo -Event 'whatif_background_command' -Pairs "command=$Command"
  Write-PolydevInfo -Event 'whatif_no_pane_created'
}
