#!/usr/bin/env sh
set -eu

info() { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; }

need_root() {
  if [ "$(id -u)" != "0" ]; then
    err "请使用 root 运行此脚本"
    exit 1
  fi
}

confirm_uninstall() {
  if [ "${1:-}" = "--yes" ] || [ "${FORCE_YES:-0}" = "1" ]; then
    return 0
  fi

  warn "即将彻底卸载 sing-box 及本脚本相关残留（不备份）"
  warn "将删除：/etc/sing-box、sb、安装脚本副本、service 文件、sing-box 程序本体等"
  printf "确认继续吗？输入 YES 继续: "
  read ans
  [ "$ans" = "YES" ] || {
    warn "已取消卸载"
    exit 0
  }
}

stop_services() {
  info "停止服务中..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed sing-box 2>/dev/null || true
  fi

  if command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box stop 2>/dev/null || true
  fi

  if command -v rc-update >/dev/null 2>&1; then
    rc-update del sing-box default 2>/dev/null || true
  fi

  pkill -x sing-box 2>/dev/null || true
  pkill -f '/sing-box' 2>/dev/null || true
}

remove_files() {
  info "删除配置和脚本残留..."

  rm -rf /etc/sing-box
  rm -f /usr/local/bin/sb
  rm -f /usr/local/bin/install-singbox-yyds.sh
  rm -f /usr/local/bin/run.sh

  rm -f /etc/systemd/system/sing-box.service
  rm -f /usr/lib/systemd/system/sing-box.service
  rm -f /lib/systemd/system/sing-box.service

  rm -f /etc/init.d/sing-box

  rm -f /root/sing-box-uris.txt
  rm -f /root/node_names.txt
}

remove_binary() {
  info "删除 sing-box 程序本体..."

  if command -v sing-box >/dev/null 2>&1; then
    BIN_PATH=$(command -v sing-box || true)
    [ -n "$BIN_PATH" ] && rm -f "$BIN_PATH"
  fi

  rm -f /usr/local/bin/sing-box
  rm -f /usr/bin/sing-box
}

remove_packages() {
  info "尝试通过包管理器卸载 sing-box..."

  if command -v apk >/dev/null 2>&1; then
    apk del sing-box 2>/dev/null || true
  fi

  if command -v apt >/dev/null 2>&1; then
    apt remove -y sing-box 2>/dev/null || true
    apt purge -y sing-box 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
  fi

  if command -v apt-get >/dev/null 2>&1; then
    apt-get remove -y sing-box 2>/dev/null || true
    apt-get purge -y sing-box 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
  fi

  if command -v dnf >/dev/null 2>&1; then
    dnf remove -y sing-box 2>/dev/null || true
  fi

  if command -v yum >/dev/null 2>&1; then
    yum remove -y sing-box 2>/dev/null || true
  fi
}

final_check() {
  info "执行卸载后检查..."

  if [ -e /etc/sing-box ]; then
    warn "/etc/sing-box 仍然存在"
  else
    info "/etc/sing-box 已删除"
  fi

  if command -v sb >/dev/null 2>&1; then
    warn "命令 sb 仍然存在: $(command -v sb)"
  else
    info "sb 已移除"
  fi

  if command -v sing-box >/dev/null 2>&1; then
    warn "命令 sing-box 仍然存在: $(command -v sing-box)"
  else
    info "sing-box 程序已移除"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload 2>/dev/null || true
  fi
}

main() {
  need_root
  confirm_uninstall "${1:-}"
  stop_services
  remove_files
  remove_binary
  remove_packages
  final_check
  info "卸载完成。现在可以重新执行最新版安装脚本。"
}

main "$@"
