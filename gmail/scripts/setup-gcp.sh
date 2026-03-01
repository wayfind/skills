#!/usr/bin/env bash
# setup-gcp.sh — 引导创建 Google Cloud OAuth 凭证
# 不依赖 gcloud，只需浏览器。全程约 5 步点选操作。

set -euo pipefail

# ── 颜色 ────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}[ OK ]${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET} $*"; }
step()    { echo -e "\n${BOLD}${YELLOW}── Step $* ──────────────────────────────────────${RESET}"; }
prompt()  { echo -e "${BOLD}$*${RESET}"; }

# ── 打开浏览器 ──────────────────────────────────────────
open_url() {
  local url="$1"
  if command -v xdg-open &>/dev/null; then
    xdg-open "$url" 2>/dev/null &
  elif command -v open &>/dev/null; then
    open "$url"
  else
    warn "无法自动打开浏览器，请手动复制以下链接："
    echo "  $url"
  fi
}

# ── 等待用户确认 ────────────────────────────────────────
wait_enter() {
  echo ""
  prompt "完成后按 Enter 继续..."
  read -r
}

# ── 检查 credentials.json 是否有效 ─────────────────────
check_credentials() {
  local file="${1:-credentials.json}"
  if [[ ! -f "$file" ]]; then return 1; fi
  if ! python3 -c "import json,sys; d=json.load(open('$file')); assert 'installed' in d or 'web' in d" 2>/dev/null; then
    return 1
  fi
  return 0
}

# ════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}Gmail Agent — Google Cloud 凭证配置向导${RESET}"
echo -e "全程约 5 步浏览器操作，无需安装任何工具。"
echo ""

# ── 检查是否已有 credentials.json ──────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_FILE="$SCRIPT_DIR/credentials.json"

if check_credentials "$CRED_FILE"; then
  success "检测到已有 credentials.json，跳过配置。"
  echo ""
  info "直接运行：  ./run.sh init"
  exit 0
fi

# ════════════════════════════════════════════════════════
step "1/5  创建 Google Cloud 项目"
echo ""
echo "  将打开 Google Cloud Console 新建项目页面。"
echo ""
echo -e "  ${BOLD}操作：${RESET}"
echo "  1. 填写项目名称（如 gmail-agent）"
echo "  2. 点击「创建」"
echo "  3. 等待项目创建完成（右上角提示）"
echo "  4. 记住项目 ID（格式类似 gmail-agent-123456）"
echo ""
prompt "按 Enter 打开浏览器..."
read -r
open_url "https://console.cloud.google.com/projectcreate"
sleep 1

echo ""
prompt "请输入刚创建的项目 ID（在 Console 顶部项目选择器中可见）："
read -r PROJECT_ID
PROJECT_ID="${PROJECT_ID// /}"   # 去除空格

if [[ -z "$PROJECT_ID" ]]; then
  echo -e "${RED}错误：项目 ID 不能为空${RESET}"
  exit 1
fi
success "项目 ID：$PROJECT_ID"

# ════════════════════════════════════════════════════════
step "2/5  启用 Gmail API"
echo ""
echo "  将打开 Gmail API 启用页面（已预选你的项目）。"
echo ""
echo -e "  ${BOLD}操作：${RESET}"
echo "  1. 确认顶部项目名称正确"
echo "  2. 点击「启用」"
echo ""
prompt "按 Enter 打开浏览器..."
read -r
open_url "https://console.cloud.google.com/apis/library/gmail.googleapis.com?project=${PROJECT_ID}"
wait_enter

# ════════════════════════════════════════════════════════
step "3/5  配置 OAuth 同意屏幕"
echo ""
echo "  将打开 OAuth 同意屏幕配置页面。"
echo ""
echo -e "  ${BOLD}操作：${RESET}"
echo "  1. 用户类型选「外部」→ 点「创建」"
echo "  2. 应用名称填：Gmail Agent"
echo "  3. 用户支持电子邮件：选你的邮箱"
echo "  4. 开发者联系信息：填你的邮箱"
echo "  5. 点「保存并继续」（后续页面直接继续，权限范围暂时跳过）"
echo "  6. 一直到最后「返回信息中心」"
echo ""
prompt "按 Enter 打开浏览器..."
read -r
open_url "https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"
wait_enter

# ════════════════════════════════════════════════════════
step "4/5  创建 OAuth 客户端 ID（Desktop 应用）"
echo ""
echo "  将打开创建 OAuth 客户端页面。"
echo ""
echo -e "  ${BOLD}操作：${RESET}"
echo "  1. 应用类型选「桌面应用」"
echo "  2. 名称填：Gmail Agent（或任意）"
echo "  3. 点「创建」"
echo "  4. 弹窗中点「下载 JSON」"
echo "  5. 将下载的文件重命名为 credentials.json"
echo -e "  6. 移动到此目录：${BOLD}${SCRIPT_DIR}/${RESET}"
echo ""
prompt "按 Enter 打开浏览器..."
read -r
open_url "https://console.cloud.google.com/apis/credentials/oauthclient?project=${PROJECT_ID}"
echo ""
warn "下载 JSON 后，将文件移动到：$SCRIPT_DIR/credentials.json"

# ── 等待文件出现 ────────────────────────────────────────
echo ""
info "等待 credentials.json..."

MAX_WAIT=120
WAITED=0
while ! check_credentials "$CRED_FILE"; do
  if [[ $WAITED -ge $MAX_WAIT ]]; then
    echo ""
    warn "超时未检测到文件。请手动将下载的 JSON 复制到："
    echo "  $CRED_FILE"
    echo ""
    prompt "放好后按 Enter 继续..."
    read -r
    break
  fi
  printf "."
  sleep 2
  WAITED=$((WAITED + 2))
done
echo ""

if check_credentials "$CRED_FILE"; then
  success "credentials.json 已就位。"
else
  echo -e "${RED}仍未找到有效的 credentials.json，请手动放置后重新运行。${RESET}"
  exit 1
fi

# ════════════════════════════════════════════════════════
step "5/5  添加测试用户（仅首次需要）"
echo ""
echo "  OAuth 同意屏幕处于「测试」模式，需要手动添加授权账号。"
echo ""
echo -e "  ${BOLD}操作：${RESET}"
echo "  1. 打开 OAuth 同意屏幕 → 「测试用户」"
echo "  2. 点「Add Users」→ 填入你的 Gmail 地址 → 保存"
echo ""
prompt "按 Enter 打开浏览器..."
read -r
open_url "https://console.cloud.google.com/apis/credentials/consent?project=${PROJECT_ID}"
wait_enter

# ════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}  配置完成！${RESET}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${RESET}"
echo ""
echo "  下一步运行："
echo ""
echo -e "  ${BOLD}./run.sh init${RESET}"
echo ""
echo "  浏览器会打开 Google 授权页面，登录并点 Allow 即可。"
echo ""
