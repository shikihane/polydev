# Worktree Orchestrator 安装脚本 (Windows)
# 需要以普通用户权限运行（不需要管理员权限）

# 设置错误处理
$ErrorActionPreference = "Stop"

# 颜色函数
function Print-Info { param([string]$Message) Write-Host "ℹ $Message" -ForegroundColor Blue }
function Print-Success { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Print-Warning { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Print-Error { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }

# 获取脚本目录
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillName = "worktree-orchestrator"

Write-Host "==========================================="
Write-Host "  Worktree Orchestrator 安装脚本 (Windows)"
Write-Host "==========================================="
Write-Host

# Step 1: 检查依赖
Print-Info "检查系统依赖..."

function Test-Command {
    param([string]$Command)
    try {
        if (Get-Command $Command -ErrorAction SilentlyContinue) {
            $Path = (Get-Command $Command).Source
            Print-Success "$Command 已安装 ($Path)"
            return $true
        } else {
            Print-Error "$Command 未安装"
            return $false
        }
    } catch {
        Print-Error "$Command 未安装"
        return $false
    }
}

# 检查必需依赖
$MissingDeps = $false

# 检查 Git
if (-not (Test-Command "git")) {
    $MissingDeps = $true
    Print-Info "  下载: https://git-scm.com/download/win"
}

# 检查 Bash (通常随 Git for Windows 安装)
if (-not (Test-Command "bash")) {
    $MissingDeps = $true
    Print-Info "  安装 Git for Windows 会自动安装 Git Bash"
}

# 检查 WezTerm
if (-not (Test-Command "wezterm")) {
    Print-Warning "wezterm 未安装，建议安装以获得最佳体验"
    Print-Info "  下载: https://wezfurlong.org/wezterm/installation.html"
    $MissingDeps = $true
}

# 检查 Python
if (-not (Test-Command "python")) {
    Print-Warning "python 未安装，WezTerm CLI 需要 Python"
    Print-Info "  下载: https://www.python.org/downloads/"
    Print-Info "  安装时勾选 'Add Python to PATH'"
    $MissingDeps = $true
}

if ($MissingDeps) {
    Write-Host
    Print-Error "请先安装缺失的依赖，然后重新运行此脚本"
    exit 1
}

Write-Host

# Step 2: 询问安装位置
Print-Info "选择安装位置:"
Write-Host "  1) 个人技能 (~/.claude/skills/) - 推荐，所有项目可用"
Write-Host "  2) 项目技能 (./.claude/skills/) - 仅当前项目可用，可通过 git 共享"
Write-Host

$InstallChoice = Read-Host "请选择 (1/2) [默认: 1]"
if ([string]::IsNullOrWhiteSpace($InstallChoice)) {
    $InstallChoice = "1"
}

if ($InstallChoice -eq "1") {
    $InstallDir = Join-Path $env:USERPROFILE ".claude\skills\$SkillName"
    Print-Info "安装到: $InstallDir (个人技能)"
} elseif ($InstallChoice -eq "2") {
    $InstallDir = Join-Path (Get-Location) ".claude\skills\$SkillName"
    Print-Info "安装到: $InstallDir (项目技能)"
} else {
    Print-Error "无效的选择"
    exit 1
}

Write-Host

# Step 3: 检查是否已安装
if (Test-Path $InstallDir) {
    Print-Warning "检测到已存在的安装: $InstallDir"
    $Overwrite = Read-Host "是否覆盖? (y/N)"
    if ($Overwrite -notmatch "^[Yy]$") {
        Print-Info "安装已取消"
        exit 0
    }
    Print-Info "删除旧版本..."
    Remove-Item -Recurse -Force $InstallDir
}

# Step 4: 安装文件
Print-Info "正在安装文件..."

$ParentDir = Split-Path -Parent $InstallDir
if (-not (Test-Path $ParentDir)) {
    New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
}

Copy-Item -Recurse -Path $ScriptDir -Destination $InstallDir
Print-Success "文件已复制到 $InstallDir"

# Step 5: 验证安装
Write-Host
Print-Info "验证安装..."

$SkillFile = Join-Path $InstallDir "SKILL.md"
if (Test-Path $SkillFile) {
    Print-Success "SKILL.md 存在"
} else {
    Print-Error "SKILL.md 未找到"
    exit 1
}

$BackendScript = Join-Path $InstallDir "scripts\terminal-backend.sh"
if (Test-Path $BackendScript) {
    Print-Success "terminal-backend.sh 存在"
} else {
    Print-Error "terminal-backend.sh 未找到"
    exit 1
}

# 测试终端后端（通过 Git Bash）
Print-Info "测试终端后端..."
try {
    $TestCmd = "source '$BackendScript' && tb_get_backend"
    $Backend = bash -c $TestCmd 2>$null
    if ($Backend) {
        Print-Success "终端后端: $Backend"
    } else {
        Print-Warning "无法检测终端后端，但文件已安装"
    }
} catch {
    Print-Warning "无法测试终端后端，请确保 Git Bash 已正确安装"
}

Write-Host
Write-Host "==========================================="
Print-Success "安装完成!"
Write-Host "==========================================="
Write-Host
Write-Host "接下来的步骤:"
Write-Host
Write-Host "1. 确保已安装 Claude Code:"
Write-Host "   npm install -g @anthropic-ai/claude-code"
Write-Host
Write-Host "2. 安装 superpowers 插件:"
Write-Host "   在 Claude Code 中执行:"
Write-Host "   /plugin marketplace add obra/superpowers-marketplace"
Write-Host "   /plugin install superpowers@superpowers-marketplace"
Write-Host
Write-Host "3. 重启 Claude Code 使技能生效"
Write-Host
Write-Host "4. 使用方式:"
Write-Host "   在项目中启动 Claude，然后描述并行任务"
Write-Host
Write-Host "查看 README.md 了解更多信息:"
Write-Host "   Get-Content $InstallDir\README.md"
Write-Host

exit 0
