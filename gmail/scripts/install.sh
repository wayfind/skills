#!/usr/bin/env bash
# install.sh — Gmail Agent 完整安装脚本
# 由 Claude 在首次使用 gmail skill 时自动调用，也可手动运行

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[ OK ]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET} $*"; }
prompt()  { echo -ne "${BOLD}$* ${RESET}"; }

REPO_URL="https://github.com/wayfind/gmail-agent"
DEFAULT_DIR="$HOME/gmail-agent"

echo ""
echo -e "${BOLD}Gmail Agent — 安装向导${RESET}"
echo ""

# ── 安装目录 ────────────────────────────────────────────
prompt "安装路径 [${DEFAULT_DIR}]:"
read -r INPUT_DIR
INSTALL_DIR="${INPUT_DIR:-$DEFAULT_DIR}"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"   # 展开 ~

if [[ -f "$INSTALL_DIR/run.sh" ]]; then
  success "gmail-agent 已安装于 $INSTALL_DIR，跳过克隆。"
else
  info "克隆 gmail-agent 到 $INSTALL_DIR ..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  success "克隆完成。"
fi

cd "$INSTALL_DIR"

# ── Google OAuth 凭证 ───────────────────────────────────
echo ""
if [[ -f "credentials.json" ]]; then
  success "credentials.json 已存在，跳过 GCP 配置。"
else
  info "启动 Google Cloud 凭证配置向导..."
  bash setup-gcp.sh
fi

# ── Anthropic API Key ───────────────────────────────────
echo ""
if [[ -f "config.json" ]]; then
  success "config.json 已存在，跳过配置。"
else
  info "创建 config.json..."
  cp config.example.json config.json

  prompt "请输入 Anthropic API Key（留空跳过，之后可手动填写）:"
  read -r API_KEY

  if [[ -n "$API_KEY" ]]; then
    # 用 Python 更新 JSON（避免 sed 跨平台问题）
    python3 - <<EOF
import json
with open('config.json') as f:
    cfg = json.load(f)
cfg['anthropic_key'] = '${API_KEY}'
with open('config.json', 'w') as f:
    json.dump(cfg, f, indent=2)
EOF
    success "API Key 已写入 config.json。"
  else
    warn "已跳过。请之后手动编辑 config.json 填入 anthropic_key。"
  fi
fi

# ── 编译 ────────────────────────────────────────────────
echo ""
info "编译 gmail-agent..."
go build -o gmail-agent ./cmd/gmail-agent/
success "编译完成。"

# ── Gmail OAuth 授权 ────────────────────────────────────
echo ""
info "启动 Gmail OAuth 授权（浏览器将打开，登录并点 Allow）..."
./run.sh init

# ── 完成 ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  安装完成！${RESET}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo ""
echo "  gmail-agent 安装于：$INSTALL_DIR"
echo ""
echo "  常用命令："
echo "    cd $INSTALL_DIR"
echo "    ./run.sh list           # 查看未读邮件"
echo "    ./run.sh classify       # 预览分类"
echo ""

# 写入环境变量提示（供 SKILL.md 引用）
EXPORT_LINE="export GMAIL_AGENT_DIR=\"$INSTALL_DIR\""
SHELL_RC=""
if [[ -f "$HOME/.zshrc" ]]; then SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then SHELL_RC="$HOME/.bashrc"; fi

if [[ -n "$SHELL_RC" ]] && ! grep -q "GMAIL_AGENT_DIR" "$SHELL_RC" 2>/dev/null; then
  echo "$EXPORT_LINE" >> "$SHELL_RC"
  success "已添加 GMAIL_AGENT_DIR 到 $SHELL_RC"
  echo "  重新打开终端或运行 source $SHELL_RC 使其生效。"
fi
