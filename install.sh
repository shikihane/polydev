#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="worktree-orchestrator"

echo "==========================================="
echo "  Worktree Orchestrator 安装脚本"
echo "==========================================="
echo

# Step 1: Check dependencies
print_info "检查系统依赖..."

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 已安装 ($(command -v $1))"
        return 0
    else
        print_error "$1 未安装"
        return 1
    fi
}

# Required dependencies
MISSING_DEPS=0
check_command "git" || MISSING_DEPS=1
check_command "bash" || MISSING_DEPS=1

# Platform-specific terminal multiplexer
if [[ "$OSTYPE" == "darwin"* ]] || [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if ! check_command "tmux"; then
        print_warning "tmux 未安装，建议安装以获得最佳体验"
        echo "  安装方式:"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "    brew install tmux"
        else
            echo "    sudo apt install tmux  # Ubuntu/Debian"
            echo "    sudo dnf install tmux  # Fedora/RHEL"
        fi
        MISSING_DEPS=1
    fi
fi

if [ $MISSING_DEPS -eq 1 ]; then
    echo
    print_error "请先安装缺失的依赖，然后重新运行此脚本"
    exit 1
fi

echo

# Step 2: Ask installation location
print_info "选择安装位置:"
echo "  1) 个人技能 (~/.claude/skills/) - 推荐，所有项目可用"
echo "  2) 项目技能 (./.claude/skills/) - 仅当前项目可用，可通过 git 共享"
echo

read -p "请选择 (1/2) [默认: 1]: " INSTALL_CHOICE
INSTALL_CHOICE=${INSTALL_CHOICE:-1}

if [ "$INSTALL_CHOICE" = "1" ]; then
    INSTALL_DIR="$HOME/.claude/skills/$SKILL_NAME"
    print_info "安装到: $INSTALL_DIR (个人技能)"
elif [ "$INSTALL_CHOICE" = "2" ]; then
    INSTALL_DIR="$(pwd)/.claude/skills/$SKILL_NAME"
    print_info "安装到: $INSTALL_DIR (项目技能)"
else
    print_error "无效的选择"
    exit 1
fi

echo

# Step 3: Check if already installed
if [ -d "$INSTALL_DIR" ]; then
    print_warning "检测到已存在的安装: $INSTALL_DIR"
    read -p "是否覆盖? (y/N): " OVERWRITE
    if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
        print_info "安装已取消"
        exit 0
    fi
    print_info "删除旧版本..."
    rm -rf "$INSTALL_DIR"
fi

# Step 4: Install files
print_info "正在安装文件..."

mkdir -p "$(dirname "$INSTALL_DIR")"
cp -r "$SCRIPT_DIR" "$INSTALL_DIR"
print_success "文件已复制到 $INSTALL_DIR"

# Step 5: Set permissions
print_info "设置执行权限..."

find "$INSTALL_DIR/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "$INSTALL_DIR/hooks" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
print_success "脚本权限已设置"

# Step 6: Verify installation
echo
print_info "验证安装..."

if [ -f "$INSTALL_DIR/SKILL.md" ]; then
    print_success "SKILL.md 存在"
else
    print_error "SKILL.md 未找到"
    exit 1
fi

if [ -f "$INSTALL_DIR/scripts/terminal-backend.sh" ]; then
    print_success "terminal-backend.sh 存在"
else
    print_error "terminal-backend.sh 未找到"
    exit 1
fi

# Test terminal backend
print_info "测试终端后端..."
if source "$INSTALL_DIR/scripts/terminal-backend.sh" 2>/dev/null; then
    BACKEND=$(tb_get_backend)
    print_success "终端后端: $BACKEND"
else
    print_error "terminal-backend.sh 加载失败"
    exit 1
fi

echo
echo "==========================================="
print_success "安装完成!"
echo "==========================================="
echo
echo "接下来的步骤:"
echo
echo "1. 确保已安装 Claude Code:"
echo "   npm install -g @anthropic-ai/claude-code"
echo
echo "2. 安装 superpowers 插件:"
echo "   在 Claude Code 中执行:"
echo "   /plugin marketplace add obra/superpowers-marketplace"
echo "   /plugin install superpowers@superpowers-marketplace"
echo
echo "3. 重启 Claude Code 使技能生效"
echo
echo "4. 使用方式:"
echo "   在项目中启动 Claude，然后描述并行任务"
echo
echo "查看 README.md 了解更多信息:"
echo "   cat $INSTALL_DIR/README.md"
echo

exit 0
