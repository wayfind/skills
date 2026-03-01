#!/usr/bin/env bash
# install.sh — Gmail Agent 完整安装脚本
# 优先下载预编译二进制，无 Go 环境也能用

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[ OK ]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET} $*"; }
prompt()  { echo -ne "${BOLD}$* ${RESET}"; }
die()     { echo -e "${RED}${BOLD}[ERR]${RESET} $*"; exit 1; }

REPO="wayfind/gmail-agent"
DEFAULT_DIR="$HOME/gmail-agent"

echo ""
echo -e "${BOLD}Gmail Agent — 安装向导${RESET}"
echo ""

# ── 安装目录 ────────────────────────────────────────────
prompt "安装路径 [${DEFAULT_DIR}]:"
read -r INPUT_DIR
INSTALL_DIR="${INPUT_DIR:-$DEFAULT_DIR}"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

mkdir -p "$INSTALL_DIR"

# ── 检测平台 ────────────────────────────────────────────
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)          ARCH="amd64" ;;
  arm64|aarch64)   ARCH="arm64" ;;
  *)               die "不支持的架构: $ARCH" ;;
esac
BINARY_NAME="gmail-agent_${OS}_${ARCH}"
[[ "$OS" == "windows" ]] && BINARY_NAME="${BINARY_NAME}.exe"

# ── 克隆源码（获取 config.example.json 等配置模板）──────
if [[ ! -f "$INSTALL_DIR/config.example.json" ]]; then
  info "克隆 gmail-agent 到 $INSTALL_DIR ..."
  git clone "https://github.com/${REPO}.git" "$INSTALL_DIR"
  success "克隆完成。"
else
  success "源码已存在，跳过克隆。"
fi

cd "$INSTALL_DIR"

# ── 下载或编译二进制 ────────────────────────────────────
BINARY_PATH="$INSTALL_DIR/gmail-agent"

install_binary() {
  info "检查最新 Release..."
  LATEST=$(curl -sf "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' | cut -d'"' -f4)

  if [[ -z "$LATEST" ]]; then
    warn "未找到 Release，将从源码编译。"
    return 1
  fi

  DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST}/${BINARY_NAME}"
  CHECKSUM_URL="https://github.com/${REPO}/releases/download/${LATEST}/checksums.txt"
  info "下载 $LATEST / $BINARY_NAME ..."

  # 检测 sha256sum 工具（macOS 叫 shasum -a 256）
  if command -v sha256sum &>/dev/null; then
    SHA256_CMD=(sha256sum)
  elif command -v shasum &>/dev/null; then
    SHA256_CMD=(shasum -a 256)
  else
    warn "未找到 sha256sum 或 shasum，跳过完整性校验（不推荐）。"
    SHA256_CMD=()
  fi

  if ! curl -sfL "$DOWNLOAD_URL" -o "$BINARY_PATH.tmp"; then
    rm -f "$BINARY_PATH.tmp"
    warn "下载失败（URL: $DOWNLOAD_URL），将从源码编译。"
    return 1
  fi

  # SHA256 校验
  if [[ ${#SHA256_CMD[@]} -gt 0 ]]; then
    if ! curl -sfL "$CHECKSUM_URL" -o "$BINARY_PATH.checksums"; then
      rm -f "$BINARY_PATH.tmp" "$BINARY_PATH.checksums"
      warn "无法下载 checksums.txt，跳过校验并从源码编译。"
      return 1
    fi

    EXPECTED=$(grep " ${BINARY_NAME}$" "$BINARY_PATH.checksums" | awk '{print $1}')
    rm -f "$BINARY_PATH.checksums"

    if [[ -z "$EXPECTED" ]]; then
      rm -f "$BINARY_PATH.tmp"
      warn "checksums.txt 中未找到 ${BINARY_NAME} 条目，将从源码编译。"
      return 1
    fi

    ACTUAL=("${SHA256_CMD[@]}" "$BINARY_PATH.tmp")
    ACTUAL=$("${SHA256_CMD[@]}" "$BINARY_PATH.tmp" | awk '{print $1}')
    if [[ "$ACTUAL" != "$EXPECTED" ]]; then
      rm -f "$BINARY_PATH.tmp"
      die "SHA256 校验失败！文件可能已被篡改。\n  期望: $EXPECTED\n  实际: $ACTUAL"
    fi
    success "SHA256 校验通过。"
  fi

  mv "$BINARY_PATH.tmp" "$BINARY_PATH"
  chmod +x "$BINARY_PATH"
  success "二进制下载完成（$LATEST）。"
  return 0
}

build_from_source() {
  if ! command -v go &>/dev/null; then
    die "未找到 Go 编译器，且无法下载预编译二进制。\n请先安装 Go: https://go.dev/dl/"
  fi
  info "检测到 Go $(go version | awk '{print $3}')，从源码编译..."
  go build -ldflags="-s -w" -o "$BINARY_PATH" ./cmd/gmail-agent/
  success "编译完成。"
}

if [[ ! -x "$BINARY_PATH" ]]; then
  install_binary || build_from_source
else
  success "二进制已存在，跳过。"
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
    ANTHROPIC_KEY_VAL="$API_KEY" python3 - <<'EOF'
import json, os
with open('config.json') as f:
    cfg = json.load(f)
cfg['anthropic_key'] = os.environ['ANTHROPIC_KEY_VAL']
with open('config.json', 'w') as f:
    json.dump(cfg, f, indent=2)
EOF
    chmod 600 config.json
    success "API Key 已写入 config.json。"
  else
    warn "已跳过，请之后手动编辑 $INSTALL_DIR/config.json。"
  fi
fi

# ── 初始化（GCP 引导 + Gmail OAuth 授权）───────────────
echo ""
info "启动初始化向导（将引导 GCP 配置和 Gmail 授权）..."
"$BINARY_PATH" --config "$INSTALL_DIR/config.json" init

# ── 写入环境变量 ────────────────────────────────────────
EXPORT_LINE="export GMAIL_AGENT_DIR=\"$INSTALL_DIR\""
for RC in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [[ -f "$RC" ]] && ! grep -q "GMAIL_AGENT_DIR" "$RC" 2>/dev/null; then
    echo "$EXPORT_LINE" >> "$RC"
    success "已添加 GMAIL_AGENT_DIR 到 $RC"
  fi
done

# ── 完成 ────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  安装完成！${RESET}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo ""
echo "  安装路径：$INSTALL_DIR"
echo ""
echo "  常用命令（重新打开终端后 GMAIL_AGENT_DIR 生效）："
echo "    gmail-agent list           # 查看未读邮件"
echo "    gmail-agent classify       # 预览分类"
echo ""
echo "  或指定完整路径："
echo "    $INSTALL_DIR/gmail-agent list"
echo ""
