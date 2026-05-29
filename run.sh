#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="install-singbox-yyds.sh"

# 可按需修改默认仓库信息
GITHUB_USER="${GITHUB_USER:-yourname}"
GITHUB_REPO="${GITHUB_REPO:-singbox-deploy}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"

RAW_BASE_URL="${RAW_BASE_URL:-https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}}"
SCRIPT_URL="${SCRIPT_URL:-${RAW_BASE_URL}/${SCRIPT_NAME}}"

WORK_DIR="${WORK_DIR:-/root/singbox-deploy}"
TMP_SCRIPT="${WORK_DIR}/${SCRIPT_NAME}"

COLOR_INFO="\033[1;34m"
COLOR_WARN="\033[1;33m"
COLOR_ERR="\033[1;31m"
COLOR_OK="\033[1;32m"
COLOR_END="\033[0m"

info() {
  echo -e "${COLOR_INFO}[INFO]${COLOR_END} $*"
}

warn() {
  echo -e "${COLOR_WARN}[WARN]${COLOR_END} $*"
}

error() {
  echo -e "${COLOR_ERR}[ERROR]${COLOR_END} $*" >&2
}

ok() {
  echo -e "${COLOR_OK}[OK]${COLOR_END} $*"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 身份运行此脚本"
    echo
    echo "可使用以下方式执行："
    echo "  sudo bash run.sh"
    echo "或："
    echo "  sudo bash -c \"\$(curl -fsSL ${RAW_BASE_URL}/run.sh)\""
    exit 1
  fi
}

detect_os() {
  OS_ID=""
  OS_LIKE=""

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
  fi

  if echo "${OS_ID} ${OS_LIKE}" | grep -qi "alpine"; then
    OS_FAMILY="alpine"
  elif echo "${OS_ID} ${OS_LIKE}" | grep -Eqi "debian|ubuntu"; then
    OS_FAMILY="debian"
  elif echo "${OS_ID} ${OS_LIKE}" | grep -Eqi "centos|rhel|rocky|almalinux|fedora"; then
    OS_FAMILY="redhat"
  else
    OS_FAMILY="unknown"
  fi

  info "系统识别结果: ${OS_FAMILY}"
}

install_curl() {
  if command -v curl >/dev/null 2>&1; then
    return 0
  fi

  warn "未检测到 curl，开始自动安装"

  case "${OS_FAMILY}" in
    alpine)
      apk update
      apk add curl
      ;;
    debian)
      apt-get update
      apt-get install -y curl ca-certificates
      ;;
    redhat)
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y curl ca-certificates
      elif command -v yum >/dev/null 2>&1; then
        yum install -y curl ca-certificates
      else
        error "未找到 dnf 或 yum，无法自动安装 curl"
        exit 1
      fi
      ;;
    *)
      error "无法识别系统类型，不能自动安装 curl，请手动安装后重试"
      exit 1
      ;;
  esac

  if ! command -v curl >/dev/null 2>&1; then
    error "curl 安装失败，请手动安装后重试"
    exit 1
  fi

  ok "curl 安装完成"
}

prepare_workdir() {
  info "准备工作目录: ${WORK_DIR}"
  mkdir -p "${WORK_DIR}"
  cd "${WORK_DIR}"
}

download_script() {
  info "开始下载主脚本"
  info "下载地址: ${SCRIPT_URL}"

  if ! curl -fL --connect-timeout 10 --retry 3 --retry-delay 2 "${SCRIPT_URL}" -o "${TMP_SCRIPT}"; then
    error "下载 ${SCRIPT_NAME} 失败，请检查仓库地址、分支名或网络"
    exit 1
  fi

  if [ ! -s "${TMP_SCRIPT}" ]; then
    error "下载后的脚本为空，已终止"
    exit 1
  fi

  chmod +x "${TMP_SCRIPT}"
  ok "主脚本下载完成: ${TMP_SCRIPT}"
}

show_summary() {
  echo
  echo "=============================="
  echo "工作目录 : ${WORK_DIR}"
  echo "仓库用户 : ${GITHUB_USER}"
  echo "仓库名称 : ${GITHUB_REPO}"
  echo "分支名称 : ${GITHUB_BRANCH}"
  echo "脚本地址 : ${SCRIPT_URL}"
  echo "=============================="
  echo
}

run_installer() {
  info "开始执行 ${SCRIPT_NAME}"
  bash "${TMP_SCRIPT}"
}

main() {
  require_root
  detect_os
  install_curl
  prepare_workdir
  show_summary
  download_script
  run_installer
}

main "$@"
