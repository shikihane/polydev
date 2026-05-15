#requires -Version 7.0
[CmdletBinding()]
param(
  [switch]$SelfTest
)

Set-StrictMode -Version Latest

function Write-PolydevInfo {
  param(
    [Parameter(Mandatory)][string]$Event,
    [string]$Pairs = ''
  )
  if ([string]::IsNullOrWhiteSpace($Pairs)) {
    Write-Output "[I] event=$Event"
  } else {
    Write-Output "[I] event=$Event,$Pairs"
  }
}

function Write-PolydevError {
  param([Parameter(Mandatory)][string]$Message)
  Write-Error "[E] error=$Message" -ErrorAction Continue
}

function Assert-PolydevCommand {
  param([Parameter(Mandatory)][string[]]$Name)

  foreach ($commandName in $Name) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
      throw "Required command not found: $commandName"
    }
  }
}

function Resolve-PolydevFullPath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$BasePath = (Get-Location).Path
  )

  $normalizedPath = ConvertFrom-PolydevGitBashPath -Path $Path
  $normalizedBasePath = ConvertFrom-PolydevGitBashPath -Path $BasePath

  if ([System.IO.Path]::IsPathFullyQualified($normalizedPath)) {
    $candidate = $normalizedPath
  } else {
    $candidate = [System.IO.Path]::Combine($normalizedBasePath, $normalizedPath)
  }

  try {
    return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
  } catch {
    return [System.IO.Path]::GetFullPath($candidate)
  }
}

function ConvertFrom-PolydevGitBashPath {
  param([Parameter(Mandatory)][string]$Path)

  if ($Path -match '^/([A-Za-z])(?:/|$)') {
    $drive = $matches[1].ToUpperInvariant()
    $suffix = $Path.Substring(2).Replace('/', '\')
    return "${drive}:$suffix"
  }

  return $Path
}

function Get-PolydevCallerCwd {
  param([string]$CallerCwd)

  if (-not [string]::IsNullOrWhiteSpace($CallerCwd)) {
    return (Resolve-PolydevFullPath -Path $CallerCwd)
  }

  if (-not [string]::IsNullOrWhiteSpace($env:PWD)) {
    return (Resolve-PolydevFullPath -Path $env:PWD)
  }

  return (Get-Location).Path
}

function ConvertTo-PolydevWindowsPath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [string]$BasePath = (Get-Location).Path
  )

  return (Resolve-PolydevFullPath -Path $Path -BasePath $BasePath)
}

function Get-PolydevWezTermPanes {
  try {
    $raw = & wezterm cli list --format json 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
      return @()
    }
    $panes = $raw | ConvertFrom-Json
    if ($null -eq $panes) {
      return @()
    }
    return @($panes)
  } catch {
    return @()
  }
}

function New-PolydevPane {
  param(
    [Parameter(Mandatory)][string]$Workspace,
    [Parameter(Mandatory)][string]$TabTitle,
    [Parameter(Mandatory)][string]$Cwd
  )

  Assert-PolydevCommand -Name wezterm

  $resolvedCwd = ConvertTo-PolydevWindowsPath -Path $Cwd
  $existingPane = Get-PolydevWezTermPanes |
    Where-Object { $_.workspace -eq $Workspace -and $_.window_id -ne $null } |
    Select-Object -First 1

  if ($existingPane) {
    $paneId = (& wezterm cli spawn --window-id ([string]$existingPane.window_id) --cwd $resolvedCwd).Trim()
  } else {
    $paneId = (& wezterm cli spawn --new-window --workspace $Workspace --cwd $resolvedCwd).Trim()
  }

  if ([string]::IsNullOrWhiteSpace($paneId)) {
    throw "WezTerm did not return a pane id"
  }

  & wezterm cli set-tab-title --pane-id $paneId "$TabTitle [$paneId]" | Out-Null
  return $paneId
}

function Send-PolydevText {
  param(
    [Parameter(Mandatory)][string]$PaneId,
    [Parameter(Mandatory)][string]$Text,
    [switch]$NoEnter
  )

  Assert-PolydevCommand -Name wezterm
  & wezterm cli send-text --no-paste --pane-id $PaneId -- $Text | Out-Null
  if (-not $NoEnter) {
    Start-Sleep -Seconds 2
    & wezterm cli send-text --no-paste --pane-id $PaneId -- "`r" | Out-Null
  }
}

function Get-PolydevPaneText {
  param(
    [Parameter(Mandatory)][string]$PaneId,
    [int]$Lines = 50
  )

  Assert-PolydevCommand -Name wezterm
  if ($Lines -gt 0) {
    return (& wezterm cli get-text --pane-id $PaneId --start-line (-1 * $Lines))
  }
  return (& wezterm cli get-text --pane-id $PaneId)
}

function Test-PolydevPaneAlive {
  param([Parameter(Mandatory)][string]$PaneId)

  try {
    & wezterm cli get-text --pane-id $PaneId --start-line 0 --end-line 0 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Close-PolydevPane {
  param([Parameter(Mandatory)][string]$PaneId)

  Assert-PolydevCommand -Name wezterm
  & wezterm cli kill-pane --pane-id $PaneId | Out-Null
}

if ($SelfTest) {
  $requiredFunctions = @(
    'Get-PolydevWezTermPanes',
    'New-PolydevPane',
    'Send-PolydevText',
    'Get-PolydevPaneText',
    'Test-PolydevPaneAlive',
    'Close-PolydevPane',
    'Resolve-PolydevFullPath',
    'ConvertFrom-PolydevGitBashPath',
    'Get-PolydevCallerCwd',
    'ConvertTo-PolydevWindowsPath',
    'Write-PolydevInfo',
    'Write-PolydevError',
    'Assert-PolydevCommand'
  )

  foreach ($functionName in $requiredFunctions) {
    if (-not (Get-Command $functionName -CommandType Function -ErrorAction SilentlyContinue)) {
      throw "Missing function: $functionName"
    }
  }

  Write-Output 'self-test-ok'
}
