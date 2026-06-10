#!/usr/bin/env bash
set -euo pipefail

# -----------------------
# 彩色输出函数
info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }

# -----------------------
# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID:-}"
        OS_ID_LIKE="${ID_LIKE:-}"
    else
        OS_ID=""
        OS_ID_LIKE=""
    fi

    if echo "$OS_ID $OS_ID_LIKE" | grep -qi "alpine"; then
        OS="alpine"
    elif echo "$OS_ID $OS_ID_LIKE" | grep -Ei "debian|ubuntu" >/dev/null; then
        OS="debian"
    elif echo "$OS_ID $OS_ID_LIKE" | grep -Ei "centos|rhel|fedora" >/dev/null; then
        OS="redhat"
    else
        OS="unknown"
    fi
}

detect_os
info "检测到系统: $OS (${OS_ID:-unknown})"

# -----------------------
# 检查 root 权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        err "此脚本需要 root 权限"
        err "请使用: sudo bash -c \"\$(curl -fsSL ...)\" 或切换到 root 用户"
        exit 1
    fi
}

check_root

# -----------------------
# 安装依赖
install_deps() {
    info "安装系统依赖..."
    
    case "$OS" in
        alpine)
            apk update || { err "apk update 失败"; exit 1; }
            apk add --no-cache bash curl ca-certificates openssl openrc jq || {
                err "依赖安装失败"
                exit 1
            }
            ;;
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y || { err "apt update 失败"; exit 1; }
            apt-get install -y curl ca-certificates openssl jq || {
                err "依赖安装失败"
                exit 1
            }
            ;;
        redhat)
            yum install -y curl ca-certificates openssl jq || {
                err "依赖安装失败"
                exit 1
            }
            ;;
        *)
            warn "未识别的系统类型,尝试继续..."
            ;;
    esac
    
    info "依赖安装完成"
}

install_deps

# -----------------------
# 工具函数
# 生成随机端口
rand_port() {
    local port
    port=$(shuf -i 10000-60000 -n 1 2>/dev/null) || port=$((RANDOM % 50001 + 10000))
    echo "$port"
}

# 生成随机密码
rand_pass() {
    local pass
    pass=$(openssl rand -base64 16 2>/dev/null | tr -d '\n\r') || pass=$(head -c 16 /dev/urandom | base64 2>/dev/null | tr -d '\n\r')
    echo "$pass"
}

# 生成UUID
rand_uuid() {
    local uuid
    if [ -f /proc/sys/kernel/random/uuid ]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
    else
        uuid=$(openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/')
    fi
    echo "$uuid"
}

# -----------------------
# 配置节点名称后缀
echo "请输入节点名称(留空则默认议名):"
read -r user_name
if [[ -n "$user_name" ]]; then
    suffix="-${user_name}"
    echo "$suffix" > /root/node_names.txt
else
    suffix=""
fi

# -----------------------
# 选择要部署的协议
select_protocols() {
    info "=== 选择要部署的协议 ==="
    echo "1) Shadowsocks (SS)"
    echo "2) Hysteria2 (HY2)"
    echo "3) TUIC"
    echo "4) VLESS Reality"
    echo "5) AnyTLS Reality"
    echo "6) SOCKS5"
    echo ""
    echo "请输入要部署的协议编号(多个用空格分隔,如: 1 2 4 6):"
    read -r protocol_input
    
    # 使用全局变量
    ENABLE_SS=false
    ENABLE_HY2=false
    ENABLE_TUIC=false
    ENABLE_REALITY=false
    ENABLE_ANYTLS=false
    ENABLE_SOCKS=false
    
    for num in $protocol_input; do
        case "$num" in
            1) ENABLE_SS=true ;;
            2) ENABLE_HY2=true ;;
            3) ENABLE_TUIC=true ;;
            4) ENABLE_REALITY=true ;;
            5) ENABLE_ANYTLS=true ;;
            6) ENABLE_SOCKS=true ;;
            *) warn "无效选项: $num" ;;
        esac
    done
    
    if ! $ENABLE_SS && ! $ENABLE_HY2 && ! $ENABLE_TUIC && ! $ENABLE_REALITY && ! $ENABLE_ANYTLS && ! $ENABLE_SOCKS; then
        err "未选择任何协议,退出安装"
        exit 1
    fi
    
    # 保存协议选择到文件（确保持久化）
    mkdir -p /etc/sing-box
    cat > /etc/sing-box/.protocols <<EOF
ENABLE_SS=$ENABLE_SS
ENABLE_HY2=$ENABLE_HY2
ENABLE_TUIC=$ENABLE_TUIC
ENABLE_REALITY=$ENABLE_REALITY
ENABLE_ANYTLS=$ENABLE_ANYTLS
ENABLE_SOCKS=$ENABLE_SOCKS
EOF
    
    info "已选择协议:"
    $ENABLE_SS && echo "  - Shadowsocks"
    $ENABLE_HY2 && echo "  - Hysteria2"
    $ENABLE_TUIC && echo "  - TUIC"
    $ENABLE_REALITY && echo "  - VLESS Reality"
    $ENABLE_ANYTLS && echo "  - AnyTLS Reality"
    $ENABLE_SOCKS && echo "  - SOCKS5"
    
    # 导出为全局变量（确保后续脚本可以访问）
    export ENABLE_SS
    export ENABLE_HY2
    export ENABLE_TUIC
    export ENABLE_REALITY
    export ENABLE_ANYTLS
    export ENABLE_SOCKS
}

# 创建配置目录
mkdir -p /etc/sing-box
select_protocols

# -----------------------
# 选择SS加密方式（新增）
select_ss_method() {
    if ! $ENABLE_SS; then
        SS_METHOD="2022-blake3-aes-128-gcm"
        return 0
    fi
    
    info "=== 选择 Shadowsocks 加密方式 ==="
    echo "1) 2022-blake3-aes-128-gcm (推荐)"
    echo "2) aes-128-gcm"
    echo ""
    echo "请输入选择(默认为 1):"
    read -r ss_method_choice
    
    case "${ss_method_choice:-1}" in
        1) SS_METHOD="2022-blake3-aes-128-gcm" ;;
        2) SS_METHOD="aes-128-gcm" ;;
        *) 
            warn "无效选择，使用默认方式: 2022-blake3-aes-128-gcm"
            SS_METHOD="2022-blake3-aes-128-gcm"
            ;;
    esac
    
    info "已选择加密方式: $SS_METHOD"
    export SS_METHOD
}

select_ss_method

# -----------------------
# 选择部署模式与中转设置
select_install_mode() {
    INSTALL_MODE="direct"
    UPSTREAM_SS_SERVER=""
    UPSTREAM_SS_PORT=""
    UPSTREAM_SS_METHOD=""
    UPSTREAM_SS_PASSWORD=""
    RELAY_VLESS_TAGS=""

    echo ""
    echo "请选择部署模式:"
    echo "1) 直连落地（默认）"
    echo "2) 通过上游 Shadowsocks 中转指定 VLESS"
    read -r install_mode_choice

    case "${install_mode_choice:-1}" in
        2)
            INSTALL_MODE="relay_ss"
            echo ""
            echo "请输入上游 SS 服务器地址:"
            read -r UPSTREAM_SS_SERVER
            UPSTREAM_SS_SERVER="$(echo "$UPSTREAM_SS_SERVER" | tr -d '[:space:]')"

            while [ -z "$UPSTREAM_SS_SERVER" ]; do
                warn "上游 SS 服务器地址不能为空"
                read -r UPSTREAM_SS_SERVER
                UPSTREAM_SS_SERVER="$(echo "$UPSTREAM_SS_SERVER" | tr -d '[:space:]')"
            done

            echo "请输入上游 SS 端口:"
            read -r UPSTREAM_SS_PORT
            UPSTREAM_SS_PORT="$(echo "$UPSTREAM_SS_PORT" | tr -d '[:space:]')"
            while ! echo "$UPSTREAM_SS_PORT" | grep -Eq '^[0-9]+$'; do
                warn "上游 SS 端口必须是数字"
                read -r UPSTREAM_SS_PORT
                UPSTREAM_SS_PORT="$(echo "$UPSTREAM_SS_PORT" | tr -d '[:space:]')"
            done

            if $ENABLE_SS; then
                echo "请输入上游 SS 加密方式(留空默认使用本机 SS 加密方式: $SS_METHOD):"
                read -r UPSTREAM_SS_METHOD
                UPSTREAM_SS_METHOD="$(echo "${UPSTREAM_SS_METHOD:-$SS_METHOD}" | tr -d '[:space:]')"
            else
                echo "请输入上游 SS 加密方式(默认 2022-blake3-aes-128-gcm):"
                read -r UPSTREAM_SS_METHOD
                UPSTREAM_SS_METHOD="$(echo "${UPSTREAM_SS_METHOD:-2022-blake3-aes-128-gcm}" | tr -d '[:space:]')"
            fi

            echo "请输入上游 SS 密码:"
            read -r UPSTREAM_SS_PASSWORD
            while [ -z "$UPSTREAM_SS_PASSWORD" ]; do
                warn "上游 SS 密码不能为空"
                read -r UPSTREAM_SS_PASSWORD
            done

            if $ENABLE_REALITY; then
                RELAY_VLESS_TAGS="vless-in-1"
                info "首次安装默认将 vless-in-1 设置为走上游 SS 中转"
            else
                warn "当前未启用 VLESS Reality，暂不绑定任何中转节点"
            fi
            ;;
        *)
            INSTALL_MODE="direct"
            ;;
    esac

    export INSTALL_MODE UPSTREAM_SS_SERVER UPSTREAM_SS_PORT UPSTREAM_SS_METHOD UPSTREAM_SS_PASSWORD RELAY_VLESS_TAGS
}

select_install_mode

# -----------------------
# 在获取公网 IP 之前，询问连接ip和sni配置
echo ""
echo "请输入节点连接 IP 或 DDNS域名(留空默认出口IP):"
read -r CUSTOM_IP
CUSTOM_IP="$(echo "$CUSTOM_IP" | tr -d '[:space:]')"

# 如果用户选择了 Reality 协议，询问 server_name(SNI)
REALITY_SNI=""
if $ENABLE_REALITY || $ENABLE_ANYTLS; then
    echo ""
    echo "请输入 Reality 的 SNI(留空默认 addons.mozilla.org):"
    read -r REALITY_SNI
    REALITY_SNI="$(echo "${REALITY_SNI:-addons.mozilla.org}" | tr -d '[:space:]')"
else
    # 也设默认，方便后续统一处理（若未选 reality，也写入缓存以便 sb 读取）
    REALITY_SNI="addons.mozilla.org"
fi

# 将用户选择写入缓存
mkdir -p /etc/sing-box
# preserve existing cache if any (append/overwrite relevant keys)
# 最简单直接：在后面 create_config 也会写入 .config_cache，先写初始值以便中间步骤可读取
echo "CUSTOM_IP=$CUSTOM_IP" > /etc/sing-box/.config_cache.tmp || true
echo "REALITY_SNI=$REALITY_SNI" >> /etc/sing-box/.config_cache.tmp || true
# 保留其他可能已有的缓存条目（若存在老的 .config_cache），把新临时与旧文件合并（保新值覆盖旧值）
if [ -f /etc/sing-box/.config_cache ]; then
    # 将旧文件中不在新文件内的行追加
    awk 'FNR==NR{a[$1]=1;next} {split($0,k,"="); if(!(k[1] in a)) print $0}' /etc/sing-box/.config_cache.tmp /etc/sing-box/.config_cache >> /etc/sing-box/.config_cache.tmp2 || true
    mv /etc/sing-box/.config_cache.tmp2 /etc/sing-box/.config_cache.tmp || true
fi
mv /etc/sing-box/.config_cache.tmp /etc/sing-box/.config_cache || true

# -----------------------
# 生成随机端口
rand_port() {
    shuf -i 10000-60000 -n 1 2>/dev/null || echo $((RANDOM % 50001 + 10000))
}

# 生成随机密码
rand_pass() {
    openssl rand -base64 16 | tr -d '\n\r' || head -c 16 /dev/urandom | base64 | tr -d '\n\r'
}

# 生成UUID
rand_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# -----------------------
# 配置端口和密码
get_config() {
    info "开始配置端口和密码..."
    
    if $ENABLE_SS; then
        info "=== 配置 Shadowsocks (SS) ==="
        if [ -n "${SINGBOX_PORT_SS:-}" ]; then
            PORT_SS="$SINGBOX_PORT_SS"
        else
            read -p "请输入 SS 端口(留空则随机 10000-60000): " USER_PORT_SS
            PORT_SS="${USER_PORT_SS:-$(rand_port)}"
        fi
        echo "$PORT_SS" | grep -Eq '^[0-9]+$' && [ "$PORT_SS" -ge 1 ] && [ "$PORT_SS" -le 65535 ] || { err "SS 端口必须是 1-65535 的数字"; exit 1; }
        PSK_SS=$(rand_pass)
        info "SS 端口: $PORT_SS"
        info "SS 加密方式: $SS_METHOD"
        info "SS 密码已自动生成"
    fi

    if $ENABLE_HY2; then
        info "=== 配置 Hysteria2 (HY2) ==="
        if [ -n "${SINGBOX_PORT_HY2:-}" ]; then
            PORT_HY2="$SINGBOX_PORT_HY2"
        else
            read -p "请输入 HY2 端口(留空则随机 10000-60000): " USER_PORT_HY2
            PORT_HY2="${USER_PORT_HY2:-$(rand_port)}"
        fi
        echo "$PORT_HY2" | grep -Eq '^[0-9]+$' && [ "$PORT_HY2" -ge 1 ] && [ "$PORT_HY2" -le 65535 ] || { err "HY2 端口必须是 1-65535 的数字"; exit 1; }
        PSK_HY2=$(rand_pass)
        info "HY2 端口: $PORT_HY2"
        info "HY2 密码已自动生成"
    fi

    if $ENABLE_TUIC; then
        info "=== 配置 TUIC ==="
        if [ -n "${SINGBOX_PORT_TUIC:-}" ]; then
            PORT_TUIC="$SINGBOX_PORT_TUIC"
        else
            read -p "请输入 TUIC 端口(留空则随机 10000-60000): " USER_PORT_TUIC
            PORT_TUIC="${USER_PORT_TUIC:-$(rand_port)}"
        fi
        echo "$PORT_TUIC" | grep -Eq '^[0-9]+$' && [ "$PORT_TUIC" -ge 1 ] && [ "$PORT_TUIC" -le 65535 ] || { err "TUIC 端口必须是 1-65535 的数字"; exit 1; }
        PSK_TUIC=$(rand_pass)
        UUID_TUIC=$(rand_uuid)
        info "TUIC 端口: $PORT_TUIC"
        info "TUIC UUID 和密码已自动生成"
    fi

    if $ENABLE_REALITY; then
        info "=== 配置 VLESS Reality ==="
        if [ -n "${SINGBOX_PORT_REALITY:-}" ]; then
            PORT_REALITY="$SINGBOX_PORT_REALITY"
        else
            read -p "请输入 VLESS Reality 端口(留空则随机 10000-60000): " USER_PORT_REALITY
            PORT_REALITY="${USER_PORT_REALITY:-$(rand_port)}"
        fi
        echo "$PORT_REALITY" | grep -Eq '^[0-9]+$' && [ "$PORT_REALITY" -ge 1 ] && [ "$PORT_REALITY" -le 65535 ] || { err "VLESS Reality 端口必须是 1-65535 的数字"; exit 1; }
        UUID=$(rand_uuid)
        info "VLESS Reality 端口: $PORT_REALITY"
        info "VLESS Reality UUID 已自动生成"
    fi
    
    if $ENABLE_ANYTLS; then
    info "=== 配置 AnyTLS Reality ==="
    if [ -n "${SINGBOX_PORT_ANYTLS:-}" ]; then
        PORT_ANYTLS="$SINGBOX_PORT_ANYTLS"
    else
        read -p "请输入 AnyTLS Reality 端口(留空则随机 10000-60000): " USER_PORT_ANYTLS
        PORT_ANYTLS="${USER_PORT_ANYTLS:-$(rand_port)}"
    fi
    echo "$PORT_ANYTLS" | grep -Eq '^[0-9]+$' && [ "$PORT_ANYTLS" -ge 1 ] && [ "$PORT_ANYTLS" -le 65535 ] || { err "AnyTLS Reality 端口必须是 1-65535 的数字"; exit 1; }

    ANYTLS_USER=$(openssl rand -hex 4)
    ANYTLS_PSK=$(openssl rand -base64 16)

    info "AnyTLS Reality 端口: $PORT_ANYTLS"
    info "AnyTLS Reality 用户名: $ANYTLS_USER"
    info "AnyTLS Reality 密码已自动生成"
    fi

    if $ENABLE_SOCKS; then
        info "=== 配置 SOCKS5 ==="
        if [ -n "${SINGBOX_PORT_SOCKS:-}" ]; then
            PORT_SOCKS="$SINGBOX_PORT_SOCKS"
        else
            read -p "请输入 SOCKS5 端口(留空则随机 10000-60000): " USER_PORT_SOCKS
            PORT_SOCKS="${USER_PORT_SOCKS:-$(rand_port)}"
        fi
        echo "$PORT_SOCKS" | grep -Eq '^[0-9]+$' && [ "$PORT_SOCKS" -ge 1 ] && [ "$PORT_SOCKS" -le 65535 ] || { err "SOCKS5 端口必须是 1-65535 的数字"; exit 1; }
        read -p "请输入 SOCKS5 用户名(留空自动生成): " USER_SOCKS_USERNAME
        read -p "请输入 SOCKS5 密码(留空自动生成): " USER_SOCKS_PASSWORD
        SOCKS_USERNAME="${USER_SOCKS_USERNAME:-socks$(openssl rand -hex 2)}"
        SOCKS_PASSWORD="${USER_SOCKS_PASSWORD:-$(rand_pass)}"
        info "SOCKS5 端口: $PORT_SOCKS"
        info "SOCKS5 用户名: $SOCKS_USERNAME"
        info "SOCKS5 密码已设置"
    fi

    info "配置完成，继续安装..."
}

get_config

# -----------------------
# 安装 sing-box
install_singbox() {
    info "开始安装 sing-box..."

    if command -v sing-box >/dev/null 2>&1; then
        CURRENT_VERSION=$(sing-box version 2>/dev/null | head -1 || echo "unknown")
        warn "检测到已安装 sing-box: $CURRENT_VERSION"
        read -p "是否重新安装?(y/N): " REINSTALL
        if [[ ! "$REINSTALL" =~ ^[Yy]$ ]]; then
            info "跳过 sing-box 安装"
            return 0
        fi
    fi

    case "$OS" in
        alpine)
            info "使用 Edge 仓库安装 sing-box"
            apk update || { err "apk update 失败"; exit 1; }
            apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community sing-box || {
                err "sing-box 安装失败"
                exit 1
            }
            ;;
        debian|redhat)
            bash <(curl -fsSL https://sing-box.app/install.sh) || {
                err "sing-box 安装失败"
                exit 1
            }
            ;;
        *)
            err "未支持的系统,无法安装 sing-box"
            exit 1
            ;;
    esac

    if ! command -v sing-box >/dev/null 2>&1; then
        err "sing-box 安装后未找到可执行文件"
        exit 1
    fi

    INSTALLED_VERSION=$(sing-box version 2>/dev/null | head -1 || echo "unknown")
    info "sing-box 安装成功: $INSTALLED_VERSION"
}

install_singbox

# -----------------------
# 生成 Reality 密钥对（必须在 sing-box 安装之后）
generate_reality_keys() {
    if ! $ENABLE_REALITY && ! $ENABLE_ANYTLS; then
        info "跳过 Reality 密钥生成（未选择 Reality 协议）"
        return 0
    fi
    
    info "生成 Reality 密钥对..."
    
    if ! command -v sing-box >/dev/null 2>&1; then
        err "sing-box 未安装，无法生成 Reality 密钥"
        exit 1
    fi
    
    REALITY_KEYS=$(sing-box generate reality-keypair 2>&1) || {
        err "生成 Reality 密钥失败"
        exit 1
    }
    
    REALITY_PK=$(echo "$REALITY_KEYS" | grep "PrivateKey" | awk '{print $NF}' | tr -d '\r')
    REALITY_PUB=$(echo "$REALITY_KEYS" | grep "PublicKey" | awk '{print $NF}' | tr -d '\r')
    REALITY_SID=$(sing-box generate rand 8 --hex 2>&1) || {
        err "生成 Reality ShortID 失败"
        exit 1
    }
    
    if [ -z "$REALITY_PK" ] || [ -z "$REALITY_PUB" ] || [ -z "$REALITY_SID" ]; then
        err "Reality 密钥生成结果为空"
        exit 1
    fi
    
    mkdir -p /etc/sing-box
    echo -n "$REALITY_PUB" > /etc/sing-box/.reality_pub
    echo -n "$REALITY_SID" > /etc/sing-box/.reality_sid
    
    info "Reality 密钥已生成"
}

generate_reality_keys

# -----------------------
# 生成 HY2/TUIC 自签证书(仅在需要时)
generate_cert() {
    if ! $ENABLE_HY2 && ! $ENABLE_TUIC; then
        info "跳过证书生成(未选择 HY2 或 TUIC)"
        return 0
    fi
    
    info "生成 HY2/TUIC 自签证书..."
    mkdir -p /etc/sing-box/certs
    
    if [ ! -f /etc/sing-box/certs/fullchain.pem ] || [ ! -f /etc/sing-box/certs/privkey.pem ]; then
        openssl req -x509 -newkey rsa:2048 -nodes \
          -keyout /etc/sing-box/certs/privkey.pem \
          -out /etc/sing-box/certs/fullchain.pem \
          -days 3650 \
          -subj "/CN=www.bing.com" || {
            err "证书生成失败"
            exit 1
        }
        info "证书已生成"
    else
        info "证书已存在"
    fi
}

generate_cert

# -----------------------
# 生成配置文件
CONFIG_PATH="/etc/sing-box/config.json"

create_config() {
    info "生成配置文件: $CONFIG_PATH"

    mkdir -p "$(dirname "$CONFIG_PATH")"

    # 构建 inbounds 内容（使用临时文件避免字符串处理问题）
    local TEMP_INBOUNDS="/tmp/singbox_inbounds_$.json"
    > "$TEMP_INBOUNDS"
    
    local need_comma=false
    
    if $ENABLE_SS; then
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_SS'
    {
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": PORT_SS_PLACEHOLDER,
      "method": "METHOD_SS_PLACEHOLDER",
      "password": "PSK_SS_PLACEHOLDER",
      "tag": "ss-in"
    }
INBOUND_SS
        sed -i "s|PORT_SS_PLACEHOLDER|$PORT_SS|g" "$TEMP_INBOUNDS"
        sed -i "s|METHOD_SS_PLACEHOLDER|$SS_METHOD|g" "$TEMP_INBOUNDS"
        sed -i "s|PSK_SS_PLACEHOLDER|$PSK_SS|g" "$TEMP_INBOUNDS"
        need_comma=true
    fi
    
    if $ENABLE_HY2; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_HY2'
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": PORT_HY2_PLACEHOLDER,
      "users": [
        {
          "password": "PSK_HY2_PLACEHOLDER"
        }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/sing-box/certs/fullchain.pem",
        "key_path": "/etc/sing-box/certs/privkey.pem"
      }
    }
INBOUND_HY2
        sed -i "s|PORT_HY2_PLACEHOLDER|$PORT_HY2|g" "$TEMP_INBOUNDS"
        sed -i "s|PSK_HY2_PLACEHOLDER|$PSK_HY2|g" "$TEMP_INBOUNDS"
        need_comma=true
    fi
    
    if $ENABLE_TUIC; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_TUIC'
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": PORT_TUIC_PLACEHOLDER,
      "users": [
        {
          "uuid": "UUID_TUIC_PLACEHOLDER",
          "password": "PSK_TUIC_PLACEHOLDER"
        }
      ],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "/etc/sing-box/certs/fullchain.pem",
        "key_path": "/etc/sing-box/certs/privkey.pem"
      }
    }
INBOUND_TUIC
        sed -i "s|PORT_TUIC_PLACEHOLDER|$PORT_TUIC|g" "$TEMP_INBOUNDS"
        sed -i "s|UUID_TUIC_PLACEHOLDER|$UUID_TUIC|g" "$TEMP_INBOUNDS"
        sed -i "s|PSK_TUIC_PLACEHOLDER|$PSK_TUIC|g" "$TEMP_INBOUNDS"
        need_comma=true
    fi
    
    if $ENABLE_REALITY; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_REALITY'
    {
      "type": "vless",
      "tag": "vless-in-1",
      "listen": "::",
      "listen_port": PORT_REALITY_PLACEHOLDER,
      "users": [
        {
          "uuid": "UUID_REALITY_PLACEHOLDER",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "REALITY_SNI_PLACEHOLDER",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "REALITY_SNI_PLACEHOLDER",
            "server_port": 443
          },
          "private_key": "REALITY_PK_PLACEHOLDER",
          "short_id": ["REALITY_SID_PLACEHOLDER"]
        }
      }
    }
INBOUND_REALITY
        sed -i "s|PORT_REALITY_PLACEHOLDER|$PORT_REALITY|g" "$TEMP_INBOUNDS"
        sed -i "s|UUID_REALITY_PLACEHOLDER|$UUID|g" "$TEMP_INBOUNDS"
        sed -i "s|REALITY_PK_PLACEHOLDER|$REALITY_PK|g" "$TEMP_INBOUNDS"
        sed -i "s|REALITY_SID_PLACEHOLDER|$REALITY_SID|g" "$TEMP_INBOUNDS"
        sed -i "s|REALITY_SNI_PLACEHOLDER|$REALITY_SNI|g" "$TEMP_INBOUNDS"
        need_comma=true
    fi

    if $ENABLE_ANYTLS; then
    $need_comma && echo "," >> "$TEMP_INBOUNDS"
    cat >> "$TEMP_INBOUNDS" <<'INBOUND_ANYTLS'
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": PORT_ANYTLS_PLACEHOLDER,
      "users": [
        {
          "name": "ANYTLS_USER_PLACEHOLDER",
          "password": "ANYTLS_PSK_PLACEHOLDER"
        }
      ],
      "padding_scheme": [],
      "tls": {
        "enabled": true,
        "server_name": "REALITY_SNI_PLACEHOLDER",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "REALITY_SNI_PLACEHOLDER",
            "server_port": 443
          },
          "private_key": "REALITY_PK_PLACEHOLDER",
          "short_id": [
            "REALITY_SID_PLACEHOLDER"
          ]
        }
      }
    }
INBOUND_ANYTLS

    sed -i "s|PORT_ANYTLS_PLACEHOLDER|$PORT_ANYTLS|g" "$TEMP_INBOUNDS"
    sed -i "s|ANYTLS_USER_PLACEHOLDER|$ANYTLS_USER|g" "$TEMP_INBOUNDS"
    sed -i "s|ANYTLS_PSK_PLACEHOLDER|$ANYTLS_PSK|g" "$TEMP_INBOUNDS"
    sed -i "s|REALITY_PK_PLACEHOLDER|$REALITY_PK|g" "$TEMP_INBOUNDS"
    sed -i "s|REALITY_SID_PLACEHOLDER|$REALITY_SID|g" "$TEMP_INBOUNDS"
    sed -i "s|REALITY_SNI_PLACEHOLDER|$REALITY_SNI|g" "$TEMP_INBOUNDS"

    need_comma=true
    fi

    if $ENABLE_SOCKS; then
        $need_comma && echo "," >> "$TEMP_INBOUNDS"
        cat >> "$TEMP_INBOUNDS" <<'INBOUND_SOCKS'
    {
      "type": "socks",
      "tag": "socks-in-1",
      "listen": "::",
      "listen_port": PORT_SOCKS_PLACEHOLDER,
      "users": [
        {
          "username": "SOCKS_USERNAME_PLACEHOLDER",
          "password": "SOCKS_PASSWORD_PLACEHOLDER"
        }
      ]
    }
INBOUND_SOCKS
        sed -i "s|PORT_SOCKS_PLACEHOLDER|$PORT_SOCKS|g" "$TEMP_INBOUNDS"
        sed -i "s|SOCKS_USERNAME_PLACEHOLDER|$SOCKS_USERNAME|g" "$TEMP_INBOUNDS"
        sed -i "s|SOCKS_PASSWORD_PLACEHOLDER|$SOCKS_PASSWORD|g" "$TEMP_INBOUNDS"
        need_comma=true
    fi

    # 生成最终配置
    cat > "$CONFIG_PATH" <<'CONFIG_HEAD'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "ntp": {
    "enabled": true,
    "server": "time.apple.com",
    "server_port": 123,
    "interval": "30m"
  },
  "inbounds": [
CONFIG_HEAD
    
    cat "$TEMP_INBOUNDS" >> "$CONFIG_PATH"
    
    cat >> "$CONFIG_PATH" <<CONFIG_TAIL
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out"
    }$(
      if [ "${INSTALL_MODE:-direct}" = "relay_ss" ] && [ -n "${UPSTREAM_SS_SERVER:-}" ] && [ -n "${UPSTREAM_SS_PORT:-}" ] && [ -n "${UPSTREAM_SS_METHOD:-}" ] && [ -n "${UPSTREAM_SS_PASSWORD:-}" ]; then
        cat <<EOF
,
    {
      "type": "shadowsocks",
      "tag": "ss-upstream",
      "server": "${UPSTREAM_SS_SERVER}",
      "server_port": ${UPSTREAM_SS_PORT},
      "method": "${UPSTREAM_SS_METHOD}",
      "password": "${UPSTREAM_SS_PASSWORD}"
    }
EOF
      fi
    )
  ],
  "route": $(
    if [ "${INSTALL_MODE:-direct}" = "relay_ss" ] && [ -n "${RELAY_VLESS_TAGS:-}" ]; then
      RELAY_JSON=$(printf '%s' "$RELAY_VLESS_TAGS" | awk -F',' '{
        printf "[";
        for (i=1; i<=NF; i++) {
          gsub(/^ +| +$/, "", $i);
          if ($i != "") {
            if (c++) printf ", ";
            printf "\"%s\"", $i;
          }
        }
        printf "]";
      }')
      cat <<EOF
{
    "rules": [
      {
        "inbound": ${RELAY_JSON},
        "outbound": "ss-upstream"
      }
    ],
    "final": "direct-out"
  }
EOF
    else
      cat <<EOF
{
    "final": "direct-out"
  }
EOF
    fi
  )
}
CONFIG_TAIL

    rm -f "$TEMP_INBOUNDS"

    sing-box check -c "$CONFIG_PATH" >/dev/null 2>&1 \
       && info "配置文件验证通过" \
       || warn "配置文件验证失败,但继续执行"

    # 保存配置缓存（追加/覆盖）
    cat > /etc/sing-box/.config_cache <<CACHEEOF
ENABLE_SS=$ENABLE_SS
ENABLE_HY2=$ENABLE_HY2
ENABLE_TUIC=$ENABLE_TUIC
ENABLE_REALITY=$ENABLE_REALITY
ENABLE_ANYTLS=$ENABLE_ANYTLS
CACHEEOF

    $ENABLE_SS && cat >> /etc/sing-box/.config_cache <<CACHEEOF
SS_PORT=$PORT_SS
SS_PSK=$PSK_SS
SS_METHOD=$SS_METHOD
CACHEEOF

    $ENABLE_HY2 && cat >> /etc/sing-box/.config_cache <<CACHEEOF
HY2_PORT=$PORT_HY2
HY2_PSK=$PSK_HY2
CACHEEOF

    $ENABLE_TUIC && cat >> /etc/sing-box/.config_cache <<CACHEEOF
TUIC_PORT=$PORT_TUIC
TUIC_UUID=$UUID_TUIC
TUIC_PSK=$PSK_TUIC
CACHEEOF

    $ENABLE_REALITY && cat >> /etc/sing-box/.config_cache <<CACHEEOF
REALITY_PORT=$PORT_REALITY
REALITY_UUID=$UUID
REALITY_PK=$REALITY_PK
REALITY_SID=$REALITY_SID
REALITY_PUB=$REALITY_PUB
REALITY_SNI=$REALITY_SNI
CACHEEOF

    $ENABLE_ANYTLS && cat >> /etc/sing-box/.config_cache <<CACHEEOF
ANYTLS_PORT=$PORT_ANYTLS
ANYTLS_USER=$ANYTLS_USER
ANYTLS_PSK=$ANYTLS_PSK
CACHEEOF

    echo "CUSTOM_IP=$CUSTOM_IP" >> /etc/sing-box/.config_cache
    echo "INSTALL_MODE=${INSTALL_MODE:-direct}" >> /etc/sing-box/.config_cache
    echo "UPSTREAM_SS_SERVER=${UPSTREAM_SS_SERVER:-}" >> /etc/sing-box/.config_cache
    echo "UPSTREAM_SS_PORT=${UPSTREAM_SS_PORT:-}" >> /etc/sing-box/.config_cache
    echo "UPSTREAM_SS_METHOD=${UPSTREAM_SS_METHOD:-}" >> /etc/sing-box/.config_cache
    echo "UPSTREAM_SS_PASSWORD=${UPSTREAM_SS_PASSWORD:-}" >> /etc/sing-box/.config_cache
    echo "RELAY_VLESS_TAGS=${RELAY_VLESS_TAGS:-}" >> /etc/sing-box/.config_cache

    info "配置缓存已保存到 /etc/sing-box/.config_cache"
}

# 调用配置生成
create_config

info "配置生成完成，准备设置服务..."

# -----------------------
# 设置服务
setup_service() {
    info "配置系统服务..."
    
    if [ "$OS" = "alpine" ]; then
        SERVICE_PATH="/etc/init.d/sing-box"
        
        cat > "$SERVICE_PATH" <<'OPENRC'
#!/sbin/openrc-run

name="sing-box"
description="Sing-box Proxy Server"
command="/usr/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
pidfile="/run/${RC_SVCNAME}.pid"
command_background="yes"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.err"
# 自动拉起（程序崩溃、OOM、被 kill 后自动恢复）
supervisor=supervise-daemon
supervise_daemon_args="--respawn-max 0 --respawn-delay 5"

depend() {
    need net
    after firewall
}

start_pre() {
    checkpath --directory --mode 0755 /var/log
    checkpath --directory --mode 0755 /run
}
OPENRC
        
        chmod +x "$SERVICE_PATH"
        rc-update add sing-box default >/dev/null 2>&1 || warn "添加开机自启失败"
        rc-service sing-box restart || {
            err "服务启动失败"
            tail -20 /var/log/sing-box.err 2>/dev/null || tail -20 /var/log/sing-box.log 2>/dev/null || true
            exit 1
        }
        
        sleep 2
        if rc-service sing-box status >/dev/null 2>&1; then
            info "✅ OpenRC 服务已启动"
        else
            err "服务状态异常"
            exit 1
        fi
        
    else
        SERVICE_PATH="/etc/systemd/system/sing-box.service"
        
        cat > "$SERVICE_PATH" <<'SYSTEMD'
[Unit]
Description=Sing-box Proxy Server
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/sing-box
ExecStart=/usr/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SYSTEMD
        
        systemctl daemon-reload
        systemctl enable sing-box >/dev/null 2>&1
        systemctl restart sing-box || {
            err "服务启动失败"
            journalctl -u sing-box -n 30 --no-pager
            exit 1
        }
        
        sleep 2
        if systemctl is-active sing-box >/dev/null 2>&1; then
            info "✅ Systemd 服务已启动"
        else
            err "服务状态异常"
            exit 1
        fi
    fi
    
    info "服务配置完成: $SERVICE_PATH"
}

setup_service

# -----------------------
# 获取公网 IP
get_public_ip() {
    local ip=""
    for url in \
        "https://api4.ipify.org" \
        "https://api64.ipify.org" \
        "https://api.ipify.org" \
        "https://ident.me" \
        "https://ipinfo.io/ip" \
        "https://ifconfig.me" \
        "https://icanhazip.com" \
        "https://ipecho.net/plain" \
        "https://api6.ipify.org" \
        "https://v6.ident.me"; do
        ip=$(curl -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)
        if [ -n "$ip" ]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

format_host_for_uri() {
    local host="$1"
    if [[ "$host" == \[*\] ]]; then
        echo "$host"
    elif [[ "$host" == *:* ]]; then
        echo "[$host]"
    else
        echo "$host"
    fi
}

# 如果用户提供了 CUSTOM_IP，则优先使用；否则自动检测出口 IP
if [ -n "${CUSTOM_IP:-}" ]; then
    PUB_IP="$CUSTOM_IP"
    info "使用用户提供的连接IP或ddns域名 : $PUB_IP"
else
    PUB_IP=$(get_public_ip || echo "YOUR_SERVER_IP")
    if [ "$PUB_IP" = "YOUR_SERVER_IP" ]; then
        warn "无法获取公网 IP,请手动替换"
    else
        info "检测到公网 IP: $PUB_IP"
    fi
fi

# -----------------------
# 生成链接(仅生成已选择的协议)
generate_uris() {
    local host="$PUB_IP"
    local uri_host
    uri_host=$(format_host_for_uri "$host")
    
    if $ENABLE_SS; then
        local ss_userinfo="${SS_METHOD}:${PSK_SS}"
        ss_encoded=$(printf "%s" "$ss_userinfo" | sed 's/:/%3A/g; s/+/%2B/g; s/\//%2F/g; s/=/%3D/g')
        ss_b64=$(printf "%s" "$ss_userinfo" | base64 -w0 2>/dev/null || printf "%s" "$ss_userinfo" | base64 | tr -d '\n')

        echo "=== Shadowsocks (SS) ==="
        echo "ss://${ss_encoded}@${uri_host}:${PORT_SS}#ss${suffix}"
        echo "ss://${ss_b64}@${uri_host}:${PORT_SS}#ss${suffix}"
        echo ""
    fi
    
    if $ENABLE_HY2; then
        hy2_encoded=$(printf "%s" "$PSK_HY2" | sed 's/:/%3A/g; s/+/%2B/g; s/\//%2F/g; s/=/%3D/g')
        echo "=== Hysteria2 (HY2) ==="
        echo "hy2://${hy2_encoded}@${uri_host}:${PORT_HY2}/?sni=www.bing.com&alpn=h3&insecure=1#hy2${suffix}"
        echo ""
    fi

    if $ENABLE_TUIC; then
        tuic_encoded=$(printf "%s" "$PSK_TUIC" | sed 's/:/%3A/g; s/+/%2B/g; s/\//%2F/g; s/=/%3D/g')
        echo "=== TUIC ==="
        echo "tuic://${UUID_TUIC}:${tuic_encoded}@${uri_host}:${PORT_TUIC}/?congestion_control=bbr&alpn=h3&sni=www.bing.com&insecure=1#tuic${suffix}"
        echo ""
    fi
    
    if $ENABLE_REALITY; then
        echo "=== VLESS Reality ==="
        echo "vless://${UUID}@${uri_host}:${PORT_REALITY}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SID}#reality${suffix}"
        echo ""
    fi

    if $ENABLE_ANYTLS; then
        anytls_user_encoded=$(printf "%s" "$ANYTLS_USER" | sed 's/:/%3A/g; s/+/%2B/g; s/\//%2F/g; s/=/%3D/g')
        anytls_pass_encoded=$(printf "%s" "$ANYTLS_PSK" | sed 's/:/%3A/g; s/+/%2B/g; s/\//%2F/g; s/=/%3D/g')
        echo "=== AnyTLS Reality ==="
        echo "anytls://${anytls_pass_encoded}@${uri_host}:${PORT_ANYTLS}/?security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SID}#anytls${suffix}"
        echo ""
    fi

    if $ENABLE_SOCKS; then
        socks_user_encoded=$(printf "%s" "$SOCKS_USERNAME" | sed 's/:/%3A/g; s/+/%2B/g; s/\//%2F/g; s/=/%3D/g')
        socks_pass_encoded=$(printf "%s" "$SOCKS_PASSWORD" | sed 's/:/%3A/g; s/+/%2B/g; s/\//%2F/g; s/=/%3D/g')
        echo "=== SOCKS5 ==="
        echo "socks5://${socks_user_encoded}:${socks_pass_encoded}@${uri_host}:${PORT_SOCKS}#socks${suffix}"
        echo "${host}:${PORT_SOCKS} 用户名=${SOCKS_USERNAME} 密码=${SOCKS_PASSWORD}"
        echo ""
    fi
}

# -----------------------
# 最终输出
echo ""
echo "=========================================="
info "🎉 Sing-box 部署完成!"
echo "=========================================="
echo ""
info "📋 配置信息:"
$ENABLE_SS && echo "   SS 端口: $PORT_SS | 密码: $PSK_SS | 加密: $SS_METHOD"
$ENABLE_HY2 && echo "   HY2 端口: $PORT_HY2 | 密码: $PSK_HY2"
$ENABLE_TUIC && echo "   TUIC 端口: $PORT_TUIC | UUID: $UUID_TUIC | 密码: $PSK_TUIC"
$ENABLE_REALITY && echo "   Reality 端口: $PORT_REALITY | UUID: $UUID"
$ENABLE_ANYTLS && echo "   AnyTLS 端口: $PORT_ANYTLS | 用户: $ANYTLS_USER | 密码: $ANYTLS_PSK"
$ENABLE_SOCKS && echo "   SOCKS5 端口: $PORT_SOCKS | 用户: $SOCKS_USERNAME | 密码: $SOCKS_PASSWORD"
echo "   服务器: $PUB_IP"
echo "   Reality server_name(SNI): ${REALITY_SNI:-addons.mozilla.org}"
echo ""
info "📂 文件位置:"
echo "   配置: $CONFIG_PATH"
($ENABLE_HY2 || $ENABLE_TUIC) && echo "   证书: /etc/sing-box/certs/"
echo "   服务: $SERVICE_PATH"
echo ""
info "📜 客户端链接:"
generate_uris | while IFS= read -r line; do
    echo "   $line"
done
echo ""
info "🔧 管理命令:"
if [ "$OS" = "alpine" ]; then
    echo "   启动: rc-service sing-box start"
    echo "   停止: rc-service sing-box stop"
    echo "   重启: rc-service sing-box restart"
    echo "   状态: rc-service sing-box status"
    echo "   日志: tail -f /var/log/sing-box.log"
else
    echo "   启动: systemctl start sing-box"
    echo "   停止: systemctl stop sing-box"
    echo "   重启: systemctl restart sing-box"
    echo "   状态: systemctl status sing-box"
    echo "   日志: journalctl -u sing-box -f"
fi
echo ""
echo "=========================================="

# -----------------------
# 创建 sb 管理脚本
SB_PATH="/usr/local/bin/sb"
info "正在创建 sb 管理面板: $SB_PATH"

cat > "$SB_PATH" <<'SB_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

info() { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }

CONFIG_PATH="/etc/sing-box/config.json"
CACHE_FILE="/etc/sing-box/.config_cache"
PROTOCOL_FILE="/etc/sing-box/.protocols"
SERVICE_NAME="sing-box"
REALITY_PUB_FILE="/etc/sing-box/.reality_pub"
URI_FILE="/etc/sing-box/uris.txt"

REALITY_TAGS=()
REALITY_PORTS=()
REALITY_UUIDS=()
REALITY_SIDS=()
REALITY_COUNT=0

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        ID="${ID:-}"
        ID_LIKE="${ID_LIKE:-}"
    else
        ID=""
        ID_LIKE=""
    fi

    if echo "$ID $ID_LIKE" | grep -qi "alpine"; then
        OS="alpine"
    elif echo "$ID $ID_LIKE" | grep -Eqi "debian|ubuntu"; then
        OS="debian"
    elif echo "$ID $ID_LIKE" | grep -Eqi "centos|rhel|fedora"; then
        OS="redhat"
    else
        OS="unknown"
    fi
}

detect_os

service_start() { [ "$OS" = "alpine" ] && rc-service "$SERVICE_NAME" start || systemctl start "$SERVICE_NAME"; }
service_stop() { [ "$OS" = "alpine" ] && rc-service "$SERVICE_NAME" stop || systemctl stop "$SERVICE_NAME"; }
service_restart() { [ "$OS" = "alpine" ] && rc-service "$SERVICE_NAME" restart || systemctl restart "$SERVICE_NAME"; }
service_status() { [ "$OS" = "alpine" ] && rc-service "$SERVICE_NAME" status || systemctl status "$SERVICE_NAME" --no-pager; }
service_status_pause() {
    service_status
    echo
    read -r -p "按回车返回菜单..." _
}

rand_port() { shuf -i 10000-60000 -n 1 2>/dev/null || echo $((RANDOM % 50001 + 10000)); }
rand_pass() { openssl rand -base64 16 2>/dev/null | tr -d '\n\r' || head -c 16 /dev/urandom | base64 2>/dev/null | tr -d '\n\r'; }
rand_uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/'; }
rand_sid() { openssl rand -hex 4 2>/dev/null || echo "01234567"; }

ensure_valid_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

url_encode() {
    printf "%s" "$1" | sed -e 's/%/%25/g' -e 's/:/%3A/g' -e 's/+/%2B/g' -e 's/\//%2F/g' -e 's/=/%3D/g'
}

need_config() {
    if [ ! -f "$CONFIG_PATH" ]; then
        err "未找到配置文件: $CONFIG_PATH"
        return 1
    fi
}

inbound_tag_exists() {
    local tag="$1"
    need_config || return 1
    [ "$(jq -r --arg tag "$tag" '[.inbounds[]? | select(.tag == $tag)] | length' "$CONFIG_PATH" 2>/dev/null || echo 0)" -gt 0 ]
}

inbound_type_exists() {
    local type="$1"
    need_config || return 1
    [ "$(jq -r --arg type "$type" '[.inbounds[]? | select(.type == $type)] | length' "$CONFIG_PATH" 2>/dev/null || echo 0)" -gt 0 ]
}

load_protocol_flags() {
    ENABLE_SS=false
    ENABLE_HY2=false
    ENABLE_TUIC=false
    ENABLE_REALITY=false
    ENABLE_ANYTLS=false
    ENABLE_SOCKS=false
    INSTALL_MODE="direct"
    UPSTREAM_SS_SERVER=""
    UPSTREAM_SS_PORT=""
    UPSTREAM_SS_METHOD=""
    UPSTREAM_SS_PASSWORD=""
    RELAY_VLESS_TAGS=""
    [ -f "$PROTOCOL_FILE" ] && . "$PROTOCOL_FILE"
}

save_protocol_flags() {
    mkdir -p /etc/sing-box
    cat > "$PROTOCOL_FILE" <<EOF
ENABLE_SS=${ENABLE_SS:-false}
ENABLE_HY2=${ENABLE_HY2:-false}
ENABLE_TUIC=${ENABLE_TUIC:-false}
ENABLE_REALITY=${ENABLE_REALITY:-false}
ENABLE_ANYTLS=${ENABLE_ANYTLS:-false}
ENABLE_SOCKS=${ENABLE_SOCKS:-false}
EOF
}

set_protocol_flag() {
    local key="$1" val="$2"
    load_protocol_flags
    case "$key" in
        ENABLE_SS) ENABLE_SS="$val" ;;
        ENABLE_HY2) ENABLE_HY2="$val" ;;
        ENABLE_TUIC) ENABLE_TUIC="$val" ;;
        ENABLE_REALITY) ENABLE_REALITY="$val" ;;
        ENABLE_ANYTLS) ENABLE_ANYTLS="$val" ;;
        ENABLE_SOCKS) ENABLE_SOCKS="$val" ;;
        *) err "未知协议标志: $key"; return 1 ;;
    esac
    save_protocol_flags

    if [ -f "$CACHE_FILE" ]; then
        awk -F= -v k="$key" -v v="$val" '
        BEGIN{done=0}
        $1==k {print k"="v; done=1; next}
        {print}
        END{if(!done) print k"="v}
        ' "$CACHE_FILE" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    else
        echo "$key=$val" > "$CACHE_FILE"
    fi
}

backup_config() { cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"; }
rollback_config() { [ -f "${CONFIG_PATH}.bak" ] && mv "${CONFIG_PATH}.bak" "$CONFIG_PATH"; }

validate_and_restart() {
    if command -v sing-box >/dev/null 2>&1; then
        if ! sing-box check -c "$CONFIG_PATH" >/dev/null 2>&1; then
            rollback_config
            err "配置校验失败，已回滚"
            return 1
        fi
    fi
    service_restart || warn "服务重启失败"
    sleep 1
    generate_uris || warn "生成 URI 失败"
    return 0
}

migrate_legacy_reality_config() {
    need_config || return 1

    local has_legacy has_new
    has_legacy=$(jq -r '[.inbounds[]? | select(.type=="vless" and .tag=="vless-in" and .tls.reality.enabled==true)] | length' "$CONFIG_PATH" 2>/dev/null || echo 0)
    has_new=$(jq -r '[.inbounds[]? | select(.type=="vless" and (.tag|test("^vless-in-[0-9]+$")) and .tls.reality.enabled==true)] | length' "$CONFIG_PATH" 2>/dev/null || echo 0)

    if [ "$has_legacy" -gt 0 ] && [ "$has_new" -eq 0 ]; then
        info "检测到旧版 VLESS Reality 配置，正在迁移..."
        cp "$CONFIG_PATH" "${CONFIG_PATH}.bak.migrate.$(date +%s)"
        jq '.inbounds |= map(if .type=="vless" and .tag=="vless-in" and .tls.reality.enabled==true then .tag="vless-in-1" else . end)' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
        info "旧版 Reality 配置已迁移为 vless-in-1"
    fi
}

read_config() {
    need_config || return 1
    load_protocol_flags
    [ -f "$CACHE_FILE" ] && . "$CACHE_FILE"

    INSTALL_MODE="${INSTALL_MODE:-direct}"
    UPSTREAM_SS_SERVER="${UPSTREAM_SS_SERVER:-}"
    UPSTREAM_SS_PORT="${UPSTREAM_SS_PORT:-}"
    UPSTREAM_SS_METHOD="${UPSTREAM_SS_METHOD:-}"
    UPSTREAM_SS_PASSWORD="${UPSTREAM_SS_PASSWORD:-}"
    RELAY_VLESS_TAGS="${RELAY_VLESS_TAGS:-}"
    REALITY_SNI="${REALITY_SNI:-addons.mozilla.org}"
    CUSTOM_IP="${CUSTOM_IP:-}"

    if [ "${ENABLE_SS:-false}" = "true" ]; then
        SS_PORT=$(jq -r '.inbounds[] | select(.type=="shadowsocks") | .listen_port // empty' "$CONFIG_PATH" | head -n1)
        SS_PSK=$(jq -r '.inbounds[] | select(.type=="shadowsocks") | .password // empty' "$CONFIG_PATH" | head -n1)
        SS_METHOD=$(jq -r '.inbounds[] | select(.type=="shadowsocks") | .method // empty' "$CONFIG_PATH" | head -n1)
    fi

    if [ "${ENABLE_HY2:-false}" = "true" ]; then
        HY2_PORT=$(jq -r '.inbounds[] | select(.type=="hysteria2") | .listen_port // empty' "$CONFIG_PATH" | head -n1)
        HY2_PSK=$(jq -r '.inbounds[] | select(.type=="hysteria2") | .users[0].password // empty' "$CONFIG_PATH" | head -n1)
    fi

    if [ "${ENABLE_TUIC:-false}" = "true" ]; then
        TUIC_PORT=$(jq -r '.inbounds[] | select(.type=="tuic") | .listen_port // empty' "$CONFIG_PATH" | head -n1)
        TUIC_UUID=$(jq -r '.inbounds[] | select(.type=="tuic") | .users[0].uuid // empty' "$CONFIG_PATH" | head -n1)
        TUIC_PSK=$(jq -r '.inbounds[] | select(.type=="tuic") | .users[0].password // empty' "$CONFIG_PATH" | head -n1)
    fi

    if [ "${ENABLE_REALITY:-false}" = "true" ] || [ "${ENABLE_ANYTLS:-false}" = "true" ]; then
        REALITY_SID=$(jq -r '.inbounds[] | select(.tls.reality.enabled == true) | .tls.reality.short_id[0] // empty' "$CONFIG_PATH" | head -n1)
        [ -f "$REALITY_PUB_FILE" ] && REALITY_PUB=$(cat "$REALITY_PUB_FILE")
    fi

    if [ "${ENABLE_REALITY:-false}" = "true" ]; then
        REALITY_PORT=$(jq -r '.inbounds[] | select(.type=="vless" and .tls.reality.enabled==true) | .listen_port // empty' "$CONFIG_PATH" | head -n1)
        REALITY_UUID=$(jq -r '.inbounds[] | select(.type=="vless" and .tls.reality.enabled==true) | .users[0].uuid // empty' "$CONFIG_PATH" | head -n1)
    fi

    REALITY_PK=$(jq -r '.inbounds[] | select((.type=="vless" or .type=="anytls") and .tls.reality.enabled==true) | .tls.reality.private_key // empty' "$CONFIG_PATH" | head -n1)
    REALITY_SNI=$(jq -r '.inbounds[] | select((.type=="vless" or .type=="anytls") and .tls.enabled==true) | .tls.server_name // empty' "$CONFIG_PATH" | head -n1 || true)
    REALITY_SID=$(jq -r '.inbounds[] | select((.type=="vless" or .type=="anytls") and .tls.reality.enabled==true) | .tls.reality.short_id[0] // empty' "$CONFIG_PATH" | head -n1 || true)
    REALITY_SNI="${REALITY_SNI:-addons.mozilla.org}"

    if [ "${ENABLE_ANYTLS:-false}" = "true" ]; then
        ANYTLS_PORT=$(jq -r '.inbounds[] | select(.type=="anytls") | .listen_port // empty' "$CONFIG_PATH" | head -n1)
        ANYTLS_USER=$(jq -r '.inbounds[] | select(.type=="anytls") | .users[0].name // empty' "$CONFIG_PATH" | head -n1)
        ANYTLS_PSK=$(jq -r '.inbounds[] | select(.type=="anytls") | .users[0].password // empty' "$CONFIG_PATH" | head -n1)
    fi

    if [ "${ENABLE_SOCKS:-false}" = "true" ]; then
        SOCKS_PORT=$(jq -r '.inbounds[] | select(.type=="socks") | .listen_port // empty' "$CONFIG_PATH" | head -n1)
        SOCKS_USERNAME=$(jq -r '.inbounds[] | select(.type=="socks") | .users[0].username // empty' "$CONFIG_PATH" | head -n1)
        SOCKS_PASSWORD=$(jq -r '.inbounds[] | select(.type=="socks") | .users[0].password // empty' "$CONFIG_PATH" | head -n1)
    fi
}

read_reality_list() {
    migrate_legacy_reality_config || return 1
    need_config || return 1

    REALITY_TAGS=()
    REALITY_PORTS=()
    REALITY_UUIDS=()
    REALITY_SIDS=()
    REALITY_COUNT=0

    mapfile -t REALITY_TAGS < <(jq -r '.inbounds[]? | select(.type=="vless" and .tls.reality.enabled==true) | .tag // empty' "$CONFIG_PATH")
    mapfile -t REALITY_PORTS < <(jq -r '.inbounds[]? | select(.type=="vless" and .tls.reality.enabled==true) | .listen_port // empty' "$CONFIG_PATH")
    mapfile -t REALITY_UUIDS < <(jq -r '.inbounds[]? | select(.type=="vless" and .tls.reality.enabled==true) | .users[0].uuid // empty' "$CONFIG_PATH")
    mapfile -t REALITY_SIDS < <(jq -r '.inbounds[]? | select(.type=="vless" and .tls.reality.enabled==true) | .tls.reality.short_id[0] // empty' "$CONFIG_PATH")

    REALITY_COUNT="${#REALITY_TAGS[@]}"
    REALITY_SNI=$(jq -r '.inbounds[]? | select(.type=="vless" and .tls.reality.enabled==true) | .tls.server_name // empty' "$CONFIG_PATH" | head -n1)
    REALITY_PK=$(jq -r '.inbounds[]? | select(.type=="vless" and .tls.reality.enabled==true) | .tls.reality.private_key // empty' "$CONFIG_PATH" | head -n1)
    [ -f "$REALITY_PUB_FILE" ] && REALITY_PUB=$(cat "$REALITY_PUB_FILE" 2>/dev/null || true)
    REALITY_SNI="${REALITY_SNI:-addons.mozilla.org}"
}

read_ss_list() {
    need_config || return 1
    SS_TAGS=()
    SS_PORTS=()
    SS_METHODS=()
    SS_PSKS=()
    mapfile -t SS_TAGS < <(jq -r '.inbounds[]? | select(.type=="shadowsocks") | .tag // empty' "$CONFIG_PATH")
    mapfile -t SS_PORTS < <(jq -r '.inbounds[]? | select(.type=="shadowsocks") | .listen_port // empty' "$CONFIG_PATH")
    mapfile -t SS_METHODS < <(jq -r '.inbounds[]? | select(.type=="shadowsocks") | .method // empty' "$CONFIG_PATH")
    mapfile -t SS_PSKS < <(jq -r '.inbounds[]? | select(.type=="shadowsocks") | .password // empty' "$CONFIG_PATH")
    SS_COUNT="${#SS_TAGS[@]}"
}

read_hy2_list() {
    need_config || return 1
    HY2_TAGS=()
    HY2_PORTS=()
    HY2_PSKS=()
    mapfile -t HY2_TAGS < <(jq -r '.inbounds[]? | select(.type=="hysteria2") | .tag // empty' "$CONFIG_PATH")
    mapfile -t HY2_PORTS < <(jq -r '.inbounds[]? | select(.type=="hysteria2") | .listen_port // empty' "$CONFIG_PATH")
    mapfile -t HY2_PSKS < <(jq -r '.inbounds[]? | select(.type=="hysteria2") | .users[0].password // empty' "$CONFIG_PATH")
    HY2_COUNT="${#HY2_TAGS[@]}"
}

read_tuic_list() {
    need_config || return 1
    TUIC_TAGS=()
    TUIC_PORTS=()
    TUIC_UUIDS=()
    TUIC_PSKS=()
    mapfile -t TUIC_TAGS < <(jq -r '.inbounds[]? | select(.type=="tuic") | .tag // empty' "$CONFIG_PATH")
    mapfile -t TUIC_PORTS < <(jq -r '.inbounds[]? | select(.type=="tuic") | .listen_port // empty' "$CONFIG_PATH")
    mapfile -t TUIC_UUIDS < <(jq -r '.inbounds[]? | select(.type=="tuic") | .users[0].uuid // empty' "$CONFIG_PATH")
    mapfile -t TUIC_PSKS < <(jq -r '.inbounds[]? | select(.type=="tuic") | .users[0].password // empty' "$CONFIG_PATH")
    TUIC_COUNT="${#TUIC_TAGS[@]}"
}

read_anytls_list() {
    need_config || return 1
    ANYTLS_TAGS=()
    ANYTLS_PORTS=()
    ANYTLS_USERS=()
    ANYTLS_PSKS=()
    ANYTLS_SIDS=()
    mapfile -t ANYTLS_TAGS < <(jq -r '.inbounds[]? | select(.type=="anytls") | .tag // empty' "$CONFIG_PATH")
    mapfile -t ANYTLS_PORTS < <(jq -r '.inbounds[]? | select(.type=="anytls") | .listen_port // empty' "$CONFIG_PATH")
    mapfile -t ANYTLS_USERS < <(jq -r '.inbounds[]? | select(.type=="anytls") | .users[0].name // empty' "$CONFIG_PATH")
    mapfile -t ANYTLS_PSKS < <(jq -r '.inbounds[]? | select(.type=="anytls") | .users[0].password // empty' "$CONFIG_PATH")
    mapfile -t ANYTLS_SIDS < <(jq -r '.inbounds[]? | select(.type=="anytls") | .tls.reality.short_id[0] // empty' "$CONFIG_PATH")
    ANYTLS_COUNT="${#ANYTLS_TAGS[@]}"
}

read_socks_list() {
    need_config || return 1
    SOCKS_TAGS=()
    SOCKS_PORTS=()
    SOCKS_USERS=()
    SOCKS_PASSWORDS=()
    mapfile -t SOCKS_TAGS < <(jq -r '.inbounds[]? | select(.type=="socks") | .tag // empty' "$CONFIG_PATH")
    mapfile -t SOCKS_PORTS < <(jq -r '.inbounds[]? | select(.type=="socks") | .listen_port // empty' "$CONFIG_PATH")
    mapfile -t SOCKS_USERS < <(jq -r '.inbounds[]? | select(.type=="socks") | .users[0].username // empty' "$CONFIG_PATH")
    mapfile -t SOCKS_PASSWORDS < <(jq -r '.inbounds[]? | select(.type=="socks") | .users[0].password // empty' "$CONFIG_PATH")
    SOCKS_COUNT="${#SOCKS_TAGS[@]}"
}

next_protocol_tag() {
    local prefix="$1"
    local next
    next=$(jq -r --arg prefix "$prefix" '[.inbounds[]? | .tag // empty | select(. == $prefix or test("^" + $prefix + "-[0-9]+$")) | if . == $prefix then 1 else (split("-") | last | tonumber) end] | max // 0 | . + 1' "$CONFIG_PATH" 2>/dev/null)
    if [ "$next" -le 1 ]; then
        echo "$prefix"
    else
        echo "$prefix-$next"
    fi
}

select_tag_from_list() {
    local title="$1"; shift
    local tags=("$@")
    local count="${#tags[@]}"
    [ "$count" -gt 0 ] || return 1
    echo >&2
    echo "$title" >&2
    local i
    for ((i=0; i<count; i++)); do
        echo "$((i+1))) ${tags[$i]}" >&2
    done
    while true; do
        read -r -p "请选择编号: " choice
        case "$choice" in
            ''|*[!0-9]*) warn "请输入数字编号" >&2 ;;
            *)
                if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
                    printf '%s\n' "${tags[$((choice-1))]}"
                    return 0
                fi
                warn "编号超出范围" >&2
                ;;
        esac
    done
}

get_public_ip() {
    local ip=""
    for url in \
        "https://api4.ipify.org" \
        "https://api64.ipify.org" \
        "https://api.ipify.org" \
        "https://ident.me" \
        "https://ipinfo.io/ip" \
        "https://ifconfig.me" \
        "https://api6.ipify.org" \
        "https://v6.ident.me"; do
        ip=$(curl -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
        [ -n "$ip" ] && echo "$ip" && return 0
    done
    echo "YOUR_SERVER_IP"
}

format_host_for_uri() {
    local host="$1"
    if [[ "$host" == \[*\] ]]; then
        echo "$host"
    elif [[ "$host" == *:* ]]; then
        echo "[$host]"
    else
        echo "$host"
    fi
}

generate_uris() {
    read_config || return 1
    if [ -n "${CUSTOM_IP:-}" ]; then PUBLIC_IP="$CUSTOM_IP"; else PUBLIC_IP=$(get_public_ip); fi
    URI_HOST=$(format_host_for_uri "$PUBLIC_IP")
    node_suffix=$(cat /root/node_names.txt 2>/dev/null || echo "")
    : > "$URI_FILE"

    read_ss_list || return 1
    if [ "$SS_COUNT" -gt 0 ]; then
        echo "=== Shadowsocks (SS) ===" >> "$URI_FILE"
        for ((i=0; i<SS_COUNT; i++)); do
            ss_userinfo="${SS_METHODS[$i]}:${SS_PSKS[$i]}"
            ss_encoded=$(url_encode "$ss_userinfo")
            ss_b64=$(printf "%s" "$ss_userinfo" | base64 -w0 2>/dev/null || printf "%s" "$ss_userinfo" | base64 | tr -d '\n')
            echo "ss://${ss_encoded}@${URI_HOST}:${SS_PORTS[$i]}#${SS_TAGS[$i]}${node_suffix}" >> "$URI_FILE"
            echo "ss://${ss_b64}@${URI_HOST}:${SS_PORTS[$i]}#${SS_TAGS[$i]}${node_suffix}" >> "$URI_FILE"
        done
        echo >> "$URI_FILE"
    fi

    read_hy2_list || return 1
    if [ "$HY2_COUNT" -gt 0 ]; then
        echo "=== Hysteria2 (HY2) ===" >> "$URI_FILE"
        for ((i=0; i<HY2_COUNT; i++)); do
            hy2_encoded=$(url_encode "${HY2_PSKS[$i]}")
            echo "hy2://${hy2_encoded}@${URI_HOST}:${HY2_PORTS[$i]}/?sni=www.bing.com&alpn=h3&insecure=1#${HY2_TAGS[$i]}${node_suffix}" >> "$URI_FILE"
        done
        echo >> "$URI_FILE"
    fi

    read_tuic_list || return 1
    if [ "$TUIC_COUNT" -gt 0 ]; then
        echo "=== TUIC ===" >> "$URI_FILE"
        for ((i=0; i<TUIC_COUNT; i++)); do
            tuic_encoded=$(url_encode "${TUIC_PSKS[$i]}")
            echo "tuic://${TUIC_UUIDS[$i]}:${tuic_encoded}@${URI_HOST}:${TUIC_PORTS[$i]}?congestion_control=bbr&udp_relay_mode=native&sni=www.bing.com&alpn=h3&allow_insecure=1#${TUIC_TAGS[$i]}${node_suffix}" >> "$URI_FILE"
        done
        echo >> "$URI_FILE"
    fi

    if [ "${ENABLE_REALITY:-false}" = "true" ]; then
        read_reality_list || return 1
        if [ "$REALITY_COUNT" -gt 0 ]; then
            echo "=== VLESS Reality ===" >> "$URI_FILE"
            for ((i=0; i<REALITY_COUNT; i++)); do
                echo "vless://${REALITY_UUIDS[$i]}@${URI_HOST}:${REALITY_PORTS[$i]}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=chrome&pbk=${REALITY_PUB}&sid=${REALITY_SIDS[$i]}#${REALITY_TAGS[$i]}${node_suffix}" >> "$URI_FILE"
            done
            echo >> "$URI_FILE"
        fi
    fi

    read_anytls_list || return 1
    if [ "$ANYTLS_COUNT" -gt 0 ]; then
        echo "=== AnyTLS Reality ===" >> "$URI_FILE"
        for ((i=0; i<ANYTLS_COUNT; i++)); do
            anytls_encoded=$(url_encode "${ANYTLS_PSKS[$i]}")
            echo "anytls://${ANYTLS_USERS[$i]}:${anytls_encoded}@${URI_HOST}:${ANYTLS_PORTS[$i]}?sni=${REALITY_SNI}&insecure=1#${ANYTLS_TAGS[$i]}${node_suffix}" >> "$URI_FILE"
        done
        echo >> "$URI_FILE"
    fi

    read_socks_list || return 1
    if [ "$SOCKS_COUNT" -gt 0 ]; then
        echo "=== SOCKS5 ===" >> "$URI_FILE"
        for ((i=0; i<SOCKS_COUNT; i++)); do
            socks_user_encoded=$(url_encode "${SOCKS_USERS[$i]}")
            socks_pass_encoded=$(url_encode "${SOCKS_PASSWORDS[$i]}")
            echo "socks5://${socks_user_encoded}:${socks_pass_encoded}@${URI_HOST}:${SOCKS_PORTS[$i]}#${SOCKS_TAGS[$i]}${node_suffix}" >> "$URI_FILE"
            echo "${SOCKS_TAGS[$i]} => ${PUBLIC_IP}:${SOCKS_PORTS[$i]} 用户名=${SOCKS_USERS[$i]} 密码=${SOCKS_PASSWORDS[$i]}" >> "$URI_FILE"
        done
        echo >> "$URI_FILE"
    fi
}

jq_add_inbound() {
    local inbound_json="$1"
    jq --argjson inbound "$inbound_json" '.inbounds += [$inbound]' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
}

jq_remove_by_tag() {
    local tag="$1"
    jq --arg tag "$tag" '.inbounds |= map(select(.tag != $tag))' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
}

relay_tags_to_json() {
    local tags_csv="$1"
    printf '%s' "$tags_csv" | awk -F',' '{
        printf "[";
        for (i=1; i<=NF; i++) {
            gsub(/^ +| +$/, "", $i);
            if ($i != "") {
                if (c++) printf ", ";
                printf "\"%s\"", $i;
            }
        }
        printf "]";
    }'
}

apply_relay_settings() {
    read_config || return 1
    backup_config

    jq 'del(.outbounds[]? | select(.tag == "ss-upstream"))' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"

    if [ "${INSTALL_MODE:-direct}" = "relay_ss" ] && [ -n "${UPSTREAM_SS_SERVER:-}" ] && [ -n "${UPSTREAM_SS_PORT:-}" ] && [ -n "${UPSTREAM_SS_METHOD:-}" ] && [ -n "${UPSTREAM_SS_PASSWORD:-}" ]; then
        relay_outbound=$(jq -nc --arg server "$UPSTREAM_SS_SERVER" --argjson port "$UPSTREAM_SS_PORT" --arg method "$UPSTREAM_SS_METHOD" --arg password "$UPSTREAM_SS_PASSWORD" '{type:"shadowsocks",tag:"ss-upstream",server:$server,server_port:$port,method:$method,password:$password}')
        jq --argjson outbound "$relay_outbound" '.outbounds += [$outbound]' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    fi

    if [ "${INSTALL_MODE:-direct}" = "relay_ss" ] && [ -n "${RELAY_VLESS_TAGS:-}" ] && [ -n "${UPSTREAM_SS_SERVER:-}" ] && [ -n "${UPSTREAM_SS_PORT:-}" ] && [ -n "${UPSTREAM_SS_METHOD:-}" ] && [ -n "${UPSTREAM_SS_PASSWORD:-}" ]; then
        relay_json=$(relay_tags_to_json "$RELAY_VLESS_TAGS")
        jq --argjson inbound_list "$relay_json" '.route = {rules: [{inbound: $inbound_list, outbound: "ss-upstream"}], final: "direct-out"}' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    else
        jq '.route = {final: "direct-out"}' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    fi

    validate_and_restart
}

action_view_uri() {
    info "正在生成并显示 URI..."
    generate_uris || { err "生成 URI 失败"; return 1; }
    echo
    cat "$URI_FILE"
    echo
    read -r -p "按回车返回菜单..." _
}

action_regenerate_uri() {
    generate_uris || { err "生成 URI 失败"; return 1; }
    echo
    cat "$URI_FILE"
    echo
    read -r -p "按回车返回菜单..." _
}

action_view_config() {
    echo "$CONFIG_PATH"
    echo
    read -r -p "按回车返回菜单..." _
}

action_edit_config() {
    [ -f "$CONFIG_PATH" ] || { err "配置文件不存在: $CONFIG_PATH"; return 1; }
    "${EDITOR:-vi}" "$CONFIG_PATH"
    if command -v sing-box >/dev/null 2>&1; then
        if sing-box check -c "$CONFIG_PATH" >/dev/null 2>&1; then
            info "配置校验通过,已重启服务"
            service_restart || warn "重启失败"
            generate_uris || true
        else
            warn "配置校验失败,服务未重启"
            return 1
        fi
    fi
}

action_reset_ss() {
    read_ss_list || return 1
    [ "$SS_COUNT" -gt 0 ] || { err "SS 协议未启用"; return 1; }
    target_tag=$(select_tag_from_list "当前 SS 列表：" "${SS_TAGS[@]}") || return 1
    current_port=$(jq -r --arg tag "$target_tag" '.inbounds[] | select(.tag==$tag) | .listen_port // empty' "$CONFIG_PATH" | head -n1)
    read -p "输入新的 SS 端口(回车保持 ${current_port}): " new_port
    new_port="${new_port:-$current_port}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    backup_config
    jq --arg tag "$target_tag" --argjson port "$new_port" '.inbounds |= map(if .tag==$tag then .listen_port = $port else . end)' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    validate_and_restart
}

action_add_ss() {
    read_config || return 1
    read -p "输入 SS 端口(留空随机 10000-60000): " new_port
    read -p "输入 SS 加密方式(默认 2022-blake3-aes-128-gcm): " new_method
    read -p "输入 SS 密码(留空自动生成): " new_psk
    new_port="${new_port:-$(rand_port)}"
    new_method="${new_method:-2022-blake3-aes-128-gcm}"
    new_psk="${new_psk:-$(rand_pass)}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    new_tag=$(next_protocol_tag "ss-in")
    inbound=$(jq -nc --arg tag "$new_tag" --argjson port "$new_port" --arg method "$new_method" --arg psk "$new_psk" '{type:"shadowsocks",listen:"::",listen_port:$port,method:$method,password:$psk,tag:$tag}')
    backup_config
    jq_add_inbound "$inbound"
    set_protocol_flag ENABLE_SS true
    validate_and_restart
}

action_delete_ss() {
    read_ss_list || return 1
    [ "$SS_COUNT" -gt 0 ] || { warn "SS 未启用"; return 0; }
    target_tag=$(select_tag_from_list "当前 SS 列表：" "${SS_TAGS[@]}") || return 1
    read -p "确认删除 ${target_tag} ? [y/N]: " confirm
    case "$confirm" in y|Y|yes|YES) ;; *) warn "已取消删除"; return 0 ;; esac
    backup_config
    jq_remove_by_tag "$target_tag"
    read_ss_list || true
    [ "${SS_COUNT:-0}" -gt 0 ] && set_protocol_flag ENABLE_SS true || set_protocol_flag ENABLE_SS false
    validate_and_restart
}

action_reset_hy2() {
    read_hy2_list || return 1
    [ "$HY2_COUNT" -gt 0 ] || { err "HY2 协议未启用"; return 1; }
    target_tag=$(select_tag_from_list "当前 HY2 列表：" "${HY2_TAGS[@]}") || return 1
    current_port=$(jq -r --arg tag "$target_tag" '.inbounds[] | select(.tag==$tag) | .listen_port // empty' "$CONFIG_PATH" | head -n1)
    read -p "输入新的 HY2 端口(回车保持 ${current_port}): " new_port
    new_port="${new_port:-$current_port}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    backup_config
    jq --arg tag "$target_tag" --argjson port "$new_port" '.inbounds |= map(if .tag==$tag then .listen_port = $port else . end)' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    validate_and_restart
}

action_add_hy2() {
    read_config || return 1
    read -p "输入 HY2 端口(留空随机 10000-60000): " new_port
    read -p "输入 HY2 密码(留空自动生成): " new_psk
    new_port="${new_port:-$(rand_port)}"
    new_psk="${new_psk:-$(rand_pass)}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    new_tag=$(next_protocol_tag "hy2-in")
    inbound=$(jq -nc --arg tag "$new_tag" --argjson port "$new_port" --arg psk "$new_psk" '{type:"hysteria2",tag:$tag,listen:"::",listen_port:$port,users:[{password:$psk}],masquerade:"https://bing.com",tls:{enabled:true,alpn:["h3"],certificate_path:"/etc/sing-box/certs/fullchain.pem",key_path:"/etc/sing-box/certs/privkey.pem"}}')
    backup_config
    jq_add_inbound "$inbound"
    set_protocol_flag ENABLE_HY2 true
    validate_and_restart
}

action_delete_hy2() {
    read_hy2_list || return 1
    [ "$HY2_COUNT" -gt 0 ] || { warn "HY2 未启用"; return 0; }
    target_tag=$(select_tag_from_list "当前 HY2 列表：" "${HY2_TAGS[@]}") || return 1
    read -p "确认删除 ${target_tag} ? [y/N]: " confirm
    case "$confirm" in y|Y|yes|YES) ;; *) warn "已取消删除"; return 0 ;; esac
    backup_config
    jq_remove_by_tag "$target_tag"
    read_hy2_list || true
    [ "${HY2_COUNT:-0}" -gt 0 ] && set_protocol_flag ENABLE_HY2 true || set_protocol_flag ENABLE_HY2 false
    validate_and_restart
}

action_reset_tuic() {
    read_tuic_list || return 1
    [ "$TUIC_COUNT" -gt 0 ] || { err "TUIC 协议未启用"; return 1; }
    target_tag=$(select_tag_from_list "当前 TUIC 列表：" "${TUIC_TAGS[@]}") || return 1
    current_port=$(jq -r --arg tag "$target_tag" '.inbounds[] | select(.tag==$tag) | .listen_port // empty' "$CONFIG_PATH" | head -n1)
    read -p "输入新的 TUIC 端口(回车保持 ${current_port}): " new_port
    new_port="${new_port:-$current_port}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    backup_config
    jq --arg tag "$target_tag" --argjson port "$new_port" '.inbounds |= map(if .tag==$tag then .listen_port = $port else . end)' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    validate_and_restart
}

action_add_tuic() {
    read_config || return 1
    read -p "输入 TUIC 端口(留空随机 10000-60000): " new_port
    read -p "输入 TUIC UUID(留空自动生成): " new_uuid
    read -p "输入 TUIC 密码(留空自动生成): " new_psk
    new_port="${new_port:-$(rand_port)}"
    new_uuid="${new_uuid:-$(rand_uuid)}"
    new_psk="${new_psk:-$(rand_pass)}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    new_tag=$(next_protocol_tag "tuic-in")
    inbound=$(jq -nc --arg tag "$new_tag" --argjson port "$new_port" --arg uuid "$new_uuid" --arg psk "$new_psk" '{type:"tuic",tag:$tag,listen:"::",listen_port:$port,users:[{uuid:$uuid,password:$psk}],congestion_control:"bbr",tls:{enabled:true,alpn:["h3"],certificate_path:"/etc/sing-box/certs/fullchain.pem",key_path:"/etc/sing-box/certs/privkey.pem"}}')
    backup_config
    jq_add_inbound "$inbound"
    set_protocol_flag ENABLE_TUIC true
    validate_and_restart
}

action_delete_tuic() {
    read_tuic_list || return 1
    [ "$TUIC_COUNT" -gt 0 ] || { warn "TUIC 未启用"; return 0; }
    target_tag=$(select_tag_from_list "当前 TUIC 列表：" "${TUIC_TAGS[@]}") || return 1
    read -p "确认删除 ${target_tag} ? [y/N]: " confirm
    case "$confirm" in y|Y|yes|YES) ;; *) warn "已取消删除"; return 0 ;; esac
    backup_config
    jq_remove_by_tag "$target_tag"
    read_tuic_list || true
    [ "${TUIC_COUNT:-0}" -gt 0 ] && set_protocol_flag ENABLE_TUIC true || set_protocol_flag ENABLE_TUIC false
    validate_and_restart
}

action_list_reality() {
    read_reality_list || return 1
    if [ "$REALITY_COUNT" -eq 0 ]; then warn "当前没有 VLESS Reality 节点"; return 0; fi
    echo
    echo "当前 VLESS Reality 列表："
    for ((i=0; i<REALITY_COUNT; i++)); do
        echo "$((i+1))) ${REALITY_TAGS[$i]} | port: ${REALITY_PORTS[$i]} | uuid: ${REALITY_UUIDS[$i]} | sid: ${REALITY_SIDS[$i]}"
    done
    echo
    read -r -p "按回车返回菜单..." _
}

action_add_reality() {
    read_reality_list || return 1
    [ -n "${REALITY_PK:-}" ] || { err "未读取到 Reality private_key，无法新增"; return 1; }
    read -p "输入新的 VLESS Reality 端口(留空随机 10000-60000): " new_port
    new_port="${new_port:-$(rand_port)}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    next_index=$(jq -r '[.inbounds[]? | select(.type=="vless" and .tls.reality.enabled==true and (.tag|test("^vless-in-[0-9]+$"))) | (.tag | split("-") | last | tonumber)] | max // 0' "$CONFIG_PATH")
    next_index=$((next_index + 1))
    new_tag="vless-in-$next_index"
    new_uuid="$(rand_uuid)"
    new_sid="$(rand_sid)"
    backup_config
    inbound=$(jq -nc --arg tag "$new_tag" --argjson port "$new_port" --arg uuid "$new_uuid" --arg sid "$new_sid" --arg sni "$REALITY_SNI" --arg pk "$REALITY_PK" '{type:"vless",tag:$tag,listen:"::",listen_port:$port,users:[{uuid:$uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$pk,short_id:[$sid]}}}')
    jq_add_inbound "$inbound"
    set_protocol_flag ENABLE_REALITY true
    validate_and_restart
    info "已新增 ${new_tag}"
}

action_delete_reality() {
    read_reality_list || return 1
    [ "$REALITY_COUNT" -gt 0 ] || { warn "当前没有可删除的 VLESS Reality 节点"; return 0; }
    echo
    echo "请选择要删除的 VLESS Reality："
    for ((i=0; i<REALITY_COUNT; i++)); do echo "$((i+1))) ${REALITY_TAGS[$i]} | port: ${REALITY_PORTS[$i]}"; done
    echo
    read -p "输入编号: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { err "输入无效"; return 1; }
    idx=$((choice - 1))
    [ "$idx" -ge 0 ] && [ "$idx" -lt "$REALITY_COUNT" ] || { err "编号超出范围"; return 1; }
    target_tag="${REALITY_TAGS[$idx]}"
    read -p "确认删除 ${target_tag} ? [y/N]: " confirm
    case "$confirm" in y|Y|yes|YES) ;; *) warn "已取消删除"; return 0 ;; esac
    backup_config
    jq_remove_by_tag "$target_tag"
    local remaining
    remaining=$(jq -r '[.inbounds[]? | select(.type=="vless" and .tls.reality.enabled==true)] | length' "$CONFIG_PATH")
    [ "$remaining" -gt 0 ] || set_protocol_flag ENABLE_REALITY false
    validate_and_restart
    info "已删除 ${target_tag}"
}

action_reset_reality() {
    read_reality_list || return 1
    [ "$REALITY_COUNT" -gt 0 ] || { err "当前没有 VLESS Reality 节点"; return 1; }
    echo
    echo "请选择要修改端口的 VLESS Reality："
    for ((i=0; i<REALITY_COUNT; i++)); do echo "$((i+1))) ${REALITY_TAGS[$i]} | 当前端口: ${REALITY_PORTS[$i]}"; done
    echo
    read -p "输入编号: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { err "输入无效"; return 1; }
    idx=$((choice - 1))
    [ "$idx" -ge 0 ] && [ "$idx" -lt "$REALITY_COUNT" ] || { err "编号超出范围"; return 1; }
    target_tag="${REALITY_TAGS[$idx]}"
    current_port="${REALITY_PORTS[$idx]}"
    read -p "输入新的端口(回车保持 $current_port): " new_port
    new_port="${new_port:-$current_port}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    backup_config
    jq --arg tag "$target_tag" --argjson port "$new_port" '.inbounds |= map(if .tag == $tag then .listen_port = $port else . end)' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    validate_and_restart
}

action_reset_anytls() {
    read_anytls_list || return 1
    [ "$ANYTLS_COUNT" -gt 0 ] || { err "AnyTLS Reality 协议未启用"; return 1; }
    target_tag=$(select_tag_from_list "当前 AnyTLS 列表：" "${ANYTLS_TAGS[@]}") || return 1
    current_port=$(jq -r --arg tag "$target_tag" '.inbounds[] | select(.tag==$tag) | .listen_port // empty' "$CONFIG_PATH" | head -n1)
    read -p "输入新的 AnyTLS Reality 端口(回车保持 ${current_port}): " new_port
    new_port="${new_port:-$current_port}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    backup_config
    jq --arg tag "$target_tag" --argjson port "$new_port" '.inbounds |= map(if .tag==$tag then .listen_port = $port else . end)' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    validate_and_restart
}

action_reset_socks() {
    read_socks_list || return 1
    [ "$SOCKS_COUNT" -gt 0 ] || { err "SOCKS5 协议未启用"; return 1; }
    target_tag=$(select_tag_from_list "当前 SOCKS5 列表：" "${SOCKS_TAGS[@]}") || return 1
    current_port=$(jq -r --arg tag "$target_tag" '.inbounds[] | select(.tag==$tag) | .listen_port // empty' "$CONFIG_PATH" | head -n1)
    current_user=$(jq -r --arg tag "$target_tag" '.inbounds[] | select(.tag==$tag) | .users[0].username // empty' "$CONFIG_PATH" | head -n1)
    current_pass=$(jq -r --arg tag "$target_tag" '.inbounds[] | select(.tag==$tag) | .users[0].password // empty' "$CONFIG_PATH" | head -n1)
    read -p "输入新的 SOCKS5 端口(回车保持 ${current_port}): " new_port
    read -p "输入新的 SOCKS5 用户名(回车保持 ${current_user}): " new_user
    read -p "输入新的 SOCKS5 密码(回车保持当前): " new_pass
    new_port="${new_port:-$current_port}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    new_user="${new_user:-$current_user}"
    new_pass="${new_pass:-$current_pass}"
    backup_config
    jq --arg tag "$target_tag" --argjson port "$new_port" --arg user "$new_user" --arg pass "$new_pass" '.inbounds |= map(if .tag==$tag then .listen_port = $port | .users[0].username = $user | .users[0].password = $pass else . end)' "$CONFIG_PATH" > "${CONFIG_PATH}.tmp" && mv "${CONFIG_PATH}.tmp" "$CONFIG_PATH"
    validate_and_restart
}

action_add_socks() {
    read_config || return 1
    read -p "输入 SOCKS5 端口(留空随机 10000-60000): " new_port
    read -p "输入 SOCKS5 用户名(留空自动生成): " new_user
    read -p "输入 SOCKS5 密码(留空自动生成): " new_pass
    new_port="${new_port:-$(rand_port)}"
    new_user="${new_user:-socks$(openssl rand -hex 2)}"
    new_pass="${new_pass:-$(rand_pass)}"
    ensure_valid_port "$new_port" || { err "端口必须是 1-65535 的数字"; return 1; }
    new_tag=$(next_protocol_tag "socks-in")
    inbound=$(jq -nc --arg tag "$new_tag" --argjson port "$new_port" --arg user "$new_user" --arg pass "$new_pass" '{type:"socks",tag:$tag,listen:"::",listen_port:$port,users:[{username:$user,password:$pass}]}' )
    backup_config
    jq_add_inbound "$inbound"
    set_protocol_flag ENABLE_SOCKS true
    validate_and_restart
}

action_delete_socks() {
    read_socks_list || return 1
    [ "$SOCKS_COUNT" -gt 0 ] || { warn "SOCKS5 未启用"; return 0; }
    target_tag=$(select_tag_from_list "当前 SOCKS5 列表：" "${SOCKS_TAGS[@]}") || return 1
    read -p "确认删除 ${target_tag} ? [y/N]: " confirm
    case "$confirm" in y|Y|yes|YES) ;; *) warn "已取消删除"; return 0 ;; esac
    backup_config
    jq_remove_by_tag "$target_tag"
    read_socks_list || true
    [ "${SOCKS_COUNT:-0}" -gt 0 ] && set_protocol_flag ENABLE_SOCKS true || set_protocol_flag ENABLE_SOCKS false
    validate_and_restart
}

action_add_anytls() {
    read_config || return 1
    read -p "输入 AnyTLS 端口(留空随机 10000-60000): " new_port
    read -p "输入 AnyTLS 用户名(默认 anytls): " new_user
    read -p "输入 AnyTLS 密码(留空自动生成): " new_psk
    new_port="${new_port:-$(rand_port)}"
    new_user="${new_user:-anytls}"
    new_psk="${new_psk:-$(rand_pass)}"
    REALITY_SNI="${REALITY_SNI:-addons.mozilla.org}"
    [ -n "${REALITY_PK:-}" ] || { err "未读取到 Reality private_key，无法新增 AnyTLS"; return 1; }
    new_sid="$(rand_sid)"
    new_tag=$(next_protocol_tag "anytls-in")
    backup_config
    inbound=$(jq -nc --arg tag "$new_tag" --argjson port "$new_port" --arg user "$new_user" --arg psk "$new_psk" --arg sni "$REALITY_SNI" --arg pk "$REALITY_PK" --arg sid "$new_sid" '{type:"anytls",tag:$tag,listen:"::",listen_port:$port,users:[{name:$user,password:$psk}],padding_scheme:[],tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$pk,short_id:[$sid]}}}')
    jq_add_inbound "$inbound"
    set_protocol_flag ENABLE_ANYTLS true
    validate_and_restart
}

action_delete_anytls() {
    read_anytls_list || return 1
    [ "$ANYTLS_COUNT" -gt 0 ] || { warn "AnyTLS 未启用"; return 0; }
    target_tag=$(select_tag_from_list "当前 AnyTLS 列表：" "${ANYTLS_TAGS[@]}") || return 1
    read -p "确认删除 ${target_tag} ? [y/N]: " confirm
    case "$confirm" in y|Y|yes|YES) ;; *) warn "已取消删除"; return 0 ;; esac
    backup_config
    jq_remove_by_tag "$target_tag"
    read_anytls_list || true
    [ "${ANYTLS_COUNT:-0}" -gt 0 ] && set_protocol_flag ENABLE_ANYTLS true || set_protocol_flag ENABLE_ANYTLS false
    validate_and_restart
}

action_update() {
    info "开始更新 sing-box..."
    if [ "$OS" = "alpine" ]; then apk update && apk upgrade sing-box || bash <(curl -fsSL https://sing-box.app/install.sh); else bash <(curl -fsSL https://sing-box.app/install.sh); fi
    info "更新完成,已重启服务..."
    if command -v sing-box >/dev/null 2>&1; then NEW_VER=$(sing-box version 2>/dev/null | head -n1); info "当前版本: $NEW_VER"; service_restart || warn "重启失败"; fi
}

action_show_relay_status() {
    read_config || return 1
    echo
    echo "当前部署模式: ${INSTALL_MODE:-direct}"
    if [ "${INSTALL_MODE:-direct}" = "relay_ss" ]; then
        echo "上游 SS 地址: ${UPSTREAM_SS_SERVER:-未设置}"
        echo "上游 SS 端口: ${UPSTREAM_SS_PORT:-未设置}"
        echo "上游 SS 加密: ${UPSTREAM_SS_METHOD:-未设置}"
        echo "中转 VLESS 标签: ${RELAY_VLESS_TAGS:-未设置}"
    else
        echo "当前为直连模式，没有启用上游 SS 中转"
    fi
    echo
    read -r -p "按回车返回菜单..." _
}

action_configure_relay_upstream() {
    read_config || return 1
    echo ""
    echo "请输入上游 SS 服务器地址(当前: ${UPSTREAM_SS_SERVER:-未设置}):"
    read -r new_server
    new_server="${new_server:-${UPSTREAM_SS_SERVER:-}}"
    new_server="$(echo "$new_server" | tr -d '[:space:]')"
    [ -n "$new_server" ] || { err "上游 SS 地址不能为空"; return 1; }

    echo "请输入上游 SS 端口(当前: ${UPSTREAM_SS_PORT:-未设置}):"
    read -r new_port
    new_port="${new_port:-${UPSTREAM_SS_PORT:-}}"
    new_port="$(echo "$new_port" | tr -d '[:space:]')"
    echo "$new_port" | grep -Eq '^[0-9]+$' || { err "上游 SS 端口必须是数字"; return 1; }

    echo "请输入上游 SS 加密方式(当前: ${UPSTREAM_SS_METHOD:-未设置}):"
    read -r new_method
    new_method="${new_method:-${UPSTREAM_SS_METHOD:-}}"
    new_method="$(echo "$new_method" | tr -d '[:space:]')"
    [ -n "$new_method" ] || { err "上游 SS 加密方式不能为空"; return 1; }

    echo "请输入上游 SS 密码(留空保持当前):"
    read -r new_password
    new_password="${new_password:-${UPSTREAM_SS_PASSWORD:-}}"
    [ -n "$new_password" ] || { err "上游 SS 密码不能为空"; return 1; }

    if [ ! -f "$CACHE_FILE" ]; then
        touch "$CACHE_FILE"
    fi
    awk -F= '!/^(INSTALL_MODE|UPSTREAM_SS_SERVER|UPSTREAM_SS_PORT|UPSTREAM_SS_METHOD|UPSTREAM_SS_PASSWORD|RELAY_VLESS_TAGS)=/' "$CACHE_FILE" > "${CACHE_FILE}.tmp" || true
    {
        cat "${CACHE_FILE}.tmp" 2>/dev/null || true
        echo "INSTALL_MODE=relay_ss"
        echo "UPSTREAM_SS_SERVER=$new_server"
        echo "UPSTREAM_SS_PORT=$new_port"
        echo "UPSTREAM_SS_METHOD=$new_method"
        echo "UPSTREAM_SS_PASSWORD=$new_password"
        echo "RELAY_VLESS_TAGS=${RELAY_VLESS_TAGS:-}"
    } > "$CACHE_FILE"
    rm -f "${CACHE_FILE}.tmp"

    INSTALL_MODE="relay_ss"
    UPSTREAM_SS_SERVER="$new_server"
    UPSTREAM_SS_PORT="$new_port"
    UPSTREAM_SS_METHOD="$new_method"
    UPSTREAM_SS_PASSWORD="$new_password"

    apply_relay_settings || return 1
    info "上游 SS 参数已更新并生效"
}

action_select_relay_vless_tags() {
    read_reality_list || return 1
    if [ "$REALITY_COUNT" -eq 0 ]; then
        warn "当前没有可用于中转的 VLESS Reality 节点"
        return 0
    fi

    echo
    echo "请选择要走上游 SS 中转的 VLESS 节点，可多选，例如: 1 3"
    for ((i=0; i<REALITY_COUNT; i++)); do
        echo "$((i+1))) ${REALITY_TAGS[$i]} | port: ${REALITY_PORTS[$i]}"
    done
    echo "0) 清空中转绑定"
    echo
    read -r relay_choice

    if [ "$relay_choice" = "0" ]; then
        new_tags=""
    else
        new_tags=""
        for n in $relay_choice; do
            echo "$n" | grep -Eq '^[0-9]+$' || { err "输入包含非法编号"; return 1; }
            idx=$((n - 1))
            [ "$idx" -ge 0 ] && [ "$idx" -lt "$REALITY_COUNT" ] || { err "编号超出范围: $n"; return 1; }
            tag="${REALITY_TAGS[$idx]}"
            if [ -z "$new_tags" ]; then
                new_tags="$tag"
            else
                case ",$new_tags," in
                    *",$tag,"*) ;;
                    *) new_tags="$new_tags,$tag" ;;
                esac
            fi
        done
    fi

    if [ ! -f "$CACHE_FILE" ]; then
        touch "$CACHE_FILE"
    fi
    awk -F= '!/^(INSTALL_MODE|RELAY_VLESS_TAGS|UPSTREAM_SS_SERVER|UPSTREAM_SS_PORT|UPSTREAM_SS_METHOD|UPSTREAM_SS_PASSWORD)=/' "$CACHE_FILE" > "${CACHE_FILE}.tmp" || true
    {
        cat "${CACHE_FILE}.tmp" 2>/dev/null || true
        echo "INSTALL_MODE=relay_ss"
        echo "RELAY_VLESS_TAGS=$new_tags"
        echo "UPSTREAM_SS_SERVER=${UPSTREAM_SS_SERVER:-}"
        echo "UPSTREAM_SS_PORT=${UPSTREAM_SS_PORT:-}"
        echo "UPSTREAM_SS_METHOD=${UPSTREAM_SS_METHOD:-}"
        echo "UPSTREAM_SS_PASSWORD=${UPSTREAM_SS_PASSWORD:-}"
    } > "$CACHE_FILE"
    rm -f "${CACHE_FILE}.tmp"

    INSTALL_MODE="relay_ss"
    RELAY_VLESS_TAGS="$new_tags"

    apply_relay_settings || return 1
    info "已更新中转 VLESS 标签并生效: ${new_tags:-<空>}"
}

action_disable_relay_mode() {
    if [ ! -f "$CACHE_FILE" ]; then
        warn "未找到缓存文件，当前无需关闭中转"
        return 0
    fi
    awk -F= '!/^(INSTALL_MODE|UPSTREAM_SS_SERVER|UPSTREAM_SS_PORT|UPSTREAM_SS_METHOD|UPSTREAM_SS_PASSWORD|RELAY_VLESS_TAGS)=/' "$CACHE_FILE" > "${CACHE_FILE}.tmp" || true
    {
        cat "${CACHE_FILE}.tmp" 2>/dev/null || true
        echo "INSTALL_MODE=direct"
        echo "UPSTREAM_SS_SERVER="
        echo "UPSTREAM_SS_PORT="
        echo "UPSTREAM_SS_METHOD="
        echo "UPSTREAM_SS_PASSWORD="
        echo "RELAY_VLESS_TAGS="
    } > "$CACHE_FILE"
    rm -f "${CACHE_FILE}.tmp"

    INSTALL_MODE="direct"
    UPSTREAM_SS_SERVER=""
    UPSTREAM_SS_PORT=""
    UPSTREAM_SS_METHOD=""
    UPSTREAM_SS_PASSWORD=""
    RELAY_VLESS_TAGS=""

    apply_relay_settings || return 1
    info "已关闭中转模式并生效"
}

action_uninstall() {
    info "正在卸载 sing-box..."
    service_stop || true
    if [ "$OS" = "alpine" ]; then apk del sing-box || true; rm -f /etc/init.d/sing-box; else systemctl disable sing-box || true; rm -f /etc/systemd/system/sing-box.service; systemctl daemon-reload || true; fi
    rm -rf /etc/sing-box
    rm -f /usr/local/bin/sb
    info "卸载完成"
    exit 0
}

show_main_menu() {
    echo
    echo "=============== sb 管理面板 ==============="
    echo "1) 链接与配置"
    echo "2) 协议管理"
    echo "3) VLESS Reality 管理"
    echo "4) 中转管理"
    echo "5) 服务管理"
    echo "0) 退出"
    echo "=========================================="
}

menu_links_and_config() {
    while true; do
        echo
        echo "----------- 链接与配置 -----------"
        echo "1) 查看 URI"
        echo "2) 重新生成 URI"
        echo "3) 查看配置文件路径"
        echo "4) 编辑配置文件"
        echo "0) 返回上一级"
        echo "----------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) action_view_uri ;;
            2) action_regenerate_uri ;;
            3) action_view_config ;;
            4) action_edit_config ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_protocols() {
    while true; do
        echo
        echo "----------- 协议管理 -----------"
        echo "1) SS 管理"
        echo "2) HY2 管理"
        echo "3) TUIC 管理"
        echo "4) AnyTLS 管理"
        echo "5) SOCKS5 管理"
        echo "0) 返回上一级"
        echo "--------------------------------"
        read -p "请输入选项: " proto_menu
        case "$proto_menu" in
            1) menu_ss ;;
            2) menu_hy2 ;;
            3) menu_tuic ;;
            4) menu_anytls ;;
            5) menu_socks ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_ss() {
    while true; do
        echo
        echo "------------- SS 管理 -------------"
        echo "1) 新增 SS"
        echo "2) 删除 SS"
        echo "3) 修改 SS 端口"
        echo "0) 返回上一级"
        echo "-----------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) action_add_ss ;;
            2) action_delete_ss ;;
            3) action_reset_ss ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_hy2() {
    while true; do
        echo
        echo "------------ HY2 管理 ------------"
        echo "1) 新增 HY2"
        echo "2) 删除 HY2"
        echo "3) 修改 HY2 端口"
        echo "0) 返回上一级"
        echo "----------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) action_add_hy2 ;;
            2) action_delete_hy2 ;;
            3) action_reset_hy2 ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_tuic() {
    while true; do
        echo
        echo "------------ TUIC 管理 -----------"
        echo "1) 新增 TUIC"
        echo "2) 删除 TUIC"
        echo "3) 修改 TUIC 端口"
        echo "0) 返回上一级"
        echo "----------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) action_add_tuic ;;
            2) action_delete_tuic ;;
            3) action_reset_tuic ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_socks() {
    while true; do
        echo
        echo "----------- SOCKS5 管理 -----------"
        echo "1) 新增 SOCKS5"
        echo "2) 删除 SOCKS5"
        echo "3) 修改 SOCKS5 端口/账号"
        echo "0) 返回上一级"
        echo "-----------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) action_add_socks ;;
            2) action_delete_socks ;;
            3) action_reset_socks ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_anytls() {
    while true; do
        echo
        echo "----------- AnyTLS 管理 -----------"
        echo "1) 新增 AnyTLS"
        echo "2) 删除 AnyTLS"
        echo "3) 修改 AnyTLS 端口"
        echo "0) 返回上一级"
        echo "-----------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) action_add_anytls ;;
            2) action_delete_anytls ;;
            3) action_reset_anytls ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_reality() {
    while true; do
        echo
        echo "-------- VLESS Reality 管理 --------"
        echo "1) 查看 Reality 列表"
        echo "2) 新增一个 Reality"
        echo "3) 删除一个 Reality"
        echo "4) 修改 Reality 端口"
        echo "0) 返回上一级"
        echo "------------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) action_list_reality ;;
            2) action_add_reality ;;
            3) action_delete_reality ;;
            4) action_reset_reality ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_relay() {
    while true; do
        echo
        echo "------------- 中转管理 -------------"
        echo "1) 查看当前中转状态"
        echo "2) 配置上游 SS 参数"
        echo "3) 选择哪些 VLESS 走中转"
        echo "4) 关闭中转模式"
        echo "5) 重新应用中转配置"
        echo "0) 返回上一级"
        echo "------------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) action_show_relay_status ;;
            2) action_configure_relay_upstream ;;
            3) action_select_relay_vless_tags ;;
            4) action_disable_relay_mode ;;
            5) apply_relay_settings ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

menu_service() {
    while true; do
        echo
        echo "------------- 服务管理 -------------"
        echo "1) 查看服务状态"
        echo "2) 更新 sing-box"
        echo "3) 卸载 sing-box"
        echo "0) 返回上一级"
        echo "------------------------------------"
        read -p "请输入选项: " subopt
        case "$subopt" in
            1) service_status_pause ;;
            2) action_update ;;
            3) action_uninstall ;;
            0) return 0 ;;
            *) warn "无效选项，请重新输入" ;;
        esac
    done
}

while true; do
    migrate_legacy_reality_config || true
    show_main_menu
    read -p "请输入选项: " opt
    case "$opt" in
        1) menu_links_and_config ;;
        2) menu_protocols ;;
        3) menu_reality ;;
        4) menu_relay ;;
        5) menu_service ;;
        0) exit 0 ;;
        *) warn "无效选项，请重新输入" ;;
    esac
done
SB_SCRIPT

chmod +x "$SB_PATH"
ln -sf /usr/local/bin/sb /usr/bin/sb
info "✅ 管理面板已创建,可输入 sb 打开管理面板"
