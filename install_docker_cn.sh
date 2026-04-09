#!/bin/bash
# Docker 交互式管理脚本 - 支持国内 / 海外 VPS
# 必须使用 bash 执行：bash install_docker_cn.sh

set -e

# ─── 基础工具 ─────────────────────────────────────────────

log()  { echo ">>> $*"; }
warn() { echo -e "\033[33m警告：$*\033[0m"; }
die()  { echo -e "\033[31m错误：$*\033[0m"; exit 1; }
ok()   { echo -e "\033[32m>>> $*\033[0m"; }

banner() { echo "========================================="; echo "  $*"; echo "========================================="; }

# ─── 环境检测 ─────────────────────────────────────────────

detect_pkg_manager() {
    for mgr in apt-get apt dnf yum; do
        if command -v "$mgr" &>/dev/null; then
            PKG_MANAGER="$mgr"
            case "$mgr" in
                apt-get|apt) PKG_FAMILY="debian" ;;
                *)           PKG_FAMILY="rhel"   ;;
            esac
            log "检测到包管理器: $PKG_MANAGER"
            return 0
        fi
    done
    die "未找到支持的包管理器（apt-get / apt / dnf / yum），请手动安装依赖。"
}

# 预检并安装所有依赖命令
ensure_deps() {
    log "检测依赖..."
    # curl：下载安装脚本
    ensure_cmd curl curl
    # xargs：批量处理容器/镜像（findutils 包含 xargs）
    ensure_cmd xargs findutils
    # getent：查询用户组（libc-bin / glibc-common）
    if ! command -v getent &>/dev/null; then
        log "未检测到 getent，正在安装..."
        if [ "$PKG_FAMILY" = "debian" ]; then
            pkg_install libc-bin
        else
            pkg_install glibc-common
        fi
    else
        log "getent 已安装，跳过。"
    fi
    # usermod：用户加组（shadow-utils / passwd）
    if ! command -v usermod &>/dev/null; then
        log "未检测到 usermod，正在安装..."
        if [ "$PKG_FAMILY" = "debian" ]; then
            pkg_install passwd
        else
            pkg_install shadow-utils
        fi
    else
        log "usermod 已安装，跳过。"
    fi
}

detect_systemctl() {
    HAS_SYSTEMCTL=false

    # 没有 systemctl 先尝试安装
    if ! command -v systemctl &>/dev/null; then
        log "未检测到 systemctl，尝试安装 systemd..."
        pkg_install systemd || true
    fi

    # 安装后再检测
    if ! command -v systemctl &>/dev/null; then
        warn "systemctl 安装失败，将跳过服务管理步骤。"
        return 0
    fi

    # 用 is-system-running 判断 systemd 是否真正在运行
    local state
    state=$(systemctl is-system-running 2>/dev/null || echo "offline")
    case "$state" in
        running|degraded|starting)
            HAS_SYSTEMCTL=true
            log "systemctl 可用（状态: $state）。"
            ;;
        *)
            warn "systemctl 存在但 systemd 未运行（状态: $state），将跳过服务管理步骤。"
            ;;
    esac
}

# 查找 docker 可执行路径并刷新 PATH
detect_docker_bin() {
    DOCKER_BIN=""
    for p in /usr/bin/docker /usr/local/bin/docker; do
        if [ -x "$p" ]; then
            DOCKER_BIN="$p"
            export PATH="$(dirname "$p"):$PATH"
            hash -r 2>/dev/null || true
            return 0
        fi
    done
    warn "未找到 docker 可执行文件，请手动检查安装结果。"
}

# ─── 包管理封装 ───────────────────────────────────────────

pkg_install() {
    log "使用 $PKG_MANAGER 安装 $*..."
    if [ "$PKG_FAMILY" = "debian" ]; then
        $PKG_MANAGER update -y -qq || warn "update 失败，尝试继续安装..."
    fi
    $PKG_MANAGER install -y "$@"
}

pkg_remove() {
    log "使用 $PKG_MANAGER 卸载 $*..."
    if [ "$PKG_FAMILY" = "debian" ]; then
        $PKG_MANAGER remove -y --purge "$@" 2>/dev/null || true
    else
        $PKG_MANAGER remove -y "$@" 2>/dev/null || true
    fi
    $PKG_MANAGER autoremove -y 2>/dev/null || true
}

ensure_cmd() {
    local cmd
    cmd=$1; shift
    if ! command -v "$cmd" &>/dev/null; then
        log "未检测到 $cmd，正在安装..."
        pkg_install "$@"
    else
        log "$cmd 已安装，跳过。"
    fi
}

# systemctl 安全封装
svc() { [ "$HAS_SYSTEMCTL" = true ] && systemctl "$@" || true; }

# ─── 安装流程 ─────────────────────────────────────────────

install_docker() {
    if [ "$IS_CN" = true ]; then
        install_docker_cn
    else
        install_docker_intl
    fi
}

# 国内安装：直接用阿里云软件源
install_docker_cn() {
    log "使用阿里云软件源安装 Docker..."
    if [ "$PKG_FAMILY" = "debian" ]; then
        pkg_install ca-certificates gnupg lsb-release
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$(. /etc/os-release && echo "$ID")/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || die "获取 Docker GPG 密钥失败。"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.aliyun.com/docker-ce/linux/$(. /etc/os-release && echo "$ID") \
$(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y -qq
        pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif [ "$PKG_FAMILY" = "rhel" ]; then
        ensure_cmd yum-config-manager yum-utils
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        die "不支持的系统，无法安装 Docker。"
    fi
    log "Docker 安装完成。"
}

# 海外安装：使用官方脚本
install_docker_intl() {
    local tmp_script
    tmp_script=$(mktemp /tmp/install_docker_XXXXXX.sh)
    log "使用官方脚本安装 Docker..."
    if ! curl -fsSL --connect-timeout 15 https://get.docker.com -o "$tmp_script"; then
        rm -f "$tmp_script"
        die "下载 Docker 安装脚本失败，请检查网络连接。"
    fi
    bash "$tmp_script" || { rm -f "$tmp_script"; die "Docker 安装失败。"; }
    rm -f "$tmp_script"
}

configure_mirrors() {
    [ "$IS_CN" = true ] || { log "海外 VPS 无需配置镜像加速，跳过。"; return 0; }
    log "配置国内镜像加速..."
    mkdir -p /etc/docker
    [ -f /etc/docker/daemon.json ] && cp /etc/docker/daemon.json /etc/docker/daemon.json.bak \
        && log "已备份原有配置到 /etc/docker/daemon.json.bak"
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1panel.live",
    "https://hub.rat.dev",
    "https://docker.1ms.run",
    "https://docker.mybacc.com",
    "https://docker.zhai.cm",
    "https://hub.littlediary.cn",
    "https://dockerhub.icu",
    "https://docker.linkedbus.com",
    "https://docker.kejilion.pro",
    "https://registry.dockermirror.com"
  ]
}
EOF
    log "镜像加速配置完成。"
}

verify_install() {
    log "验证安装..."
    detect_docker_bin
    if [ -z "$DOCKER_BIN" ]; then
        die "Docker 安装失败，未找到 docker 可执行文件，请检查安装日志。"
    fi
    set +e
    "$DOCKER_BIN" --version
    if "$DOCKER_BIN" run --rm hello-world; then
        ok "验证成功！"
    else
        warn "hello-world 拉取失败，但 Docker 已安装成功，请检查网络或镜像源。"
    fi
    set -e
}

add_user_to_docker_group() {
    local target_user
    target_user="${SUDO_USER:-}"
    [ -z "$target_user" ] && [ -n "$USER" ] && [ "$USER" != "root" ] && target_user="$USER"
    if [ -z "$target_user" ] || [ "$target_user" = "root" ]; then
        log "当前为 root 用户，无需加入 docker 组，可直接使用 docker 命令。"
        return 0
    fi
    usermod -aG docker "$target_user"
    log "已将用户 $target_user 加入 docker 组，重新登录后生效。"
}

show_docker_status() {
    echo ""
    log "Docker 当前状态："
    if [ "$HAS_SYSTEMCTL" = true ]; then
        systemctl status docker --no-pager -l || true
    elif [ -n "$DOCKER_BIN" ]; then
        "$DOCKER_BIN" info 2>/dev/null || true
    fi
    echo ""
    ok "Docker 安装成功，已可正常使用！"
}

# ─── 卸载流程 ─────────────────────────────────────────────

# docker 命令批量清理封装（兼容无 xargs -r 的系统）
docker_clean() {
    local ids
    ids=$(docker "$@" 2>/dev/null) || true
    if [ -n "$ids" ]; then
        echo "$ids" | xargs docker rm -f 2>/dev/null || true
    fi
}

uninstall_docker() {
    set +e

    # 用 docker 命令清理（docker 存在时）
    if command -v docker &>/dev/null; then
        log "停止并删除所有容器..."
        ids=$(docker ps -aq 2>/dev/null) || true
        if [ -n "$ids" ]; then
            echo "$ids" | xargs docker stop 2>/dev/null || true
            echo "$ids" | xargs docker rm -f 2>/dev/null || true
        fi

        log "删除所有镜像..."
        ids=$(docker images -aq 2>/dev/null) || true
        [ -n "$ids" ] && echo "$ids" | xargs docker rmi -f 2>/dev/null || true

        log "删除所有数据卷..."
        ids=$(docker volume ls -q 2>/dev/null) || true
        [ -n "$ids" ] && echo "$ids" | xargs docker volume rm 2>/dev/null || true

        log "删除所有自定义网络..."
        ids=$(docker network ls --filter type=custom -q 2>/dev/null) || true
        [ -n "$ids" ] && echo "$ids" | xargs docker network rm 2>/dev/null || true
    else
        warn "docker 命令不存在，将直接删除数据目录。"
    fi

    log "停止 Docker 服务..."
    svc stop docker
    svc disable docker

    log "卸载 Docker 软件包..."
    pkg_remove docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin docker-compose \
        docker docker-engine docker.io

    log "删除所有残留文件及数据目录..."
    rm -rf /var/lib/docker /var/lib/containerd /etc/docker /run/docker /run/containerd
    rm -f  /usr/local/bin/docker-compose
    rm -f  /etc/apt/sources.list.d/docker.list
    rm -f  /etc/apt/keyrings/docker.gpg
    rm -f  /etc/yum.repos.d/docker-ce.repo
    rm -f  /etc/systemd/system/docker.service
    rm -f  /etc/systemd/system/docker.socket

    log "删除 docker 用户组..."
    getent group docker &>/dev/null && groupdel docker 2>/dev/null || true

    svc daemon-reload
    set -e

    banner "Docker 已彻底卸载！"
    ok "Docker 已彻底卸载！"
}

# ─── 主流程 ───────────────────────────────────────────────

banner "Docker 交互式管理脚本"

[ "$EUID" -ne 0 ] && die "请使用 sudo 或 root 用户运行此脚本"

echo ""
echo "请选择操作："
echo "  1) 安装 Docker"
echo "  2) 卸载 Docker"
echo ""
read -rp "请输入选项 [1/2]: " ACTION

case "$ACTION" in
    1)
        echo ""
        echo "请选择服务器类型："
        echo "  1) 国内 VPS（阿里云、腾讯云、华为云等）"
        echo "  2) 海外 VPS（AWS、GCP、Vultr、搬瓦工等）"
        echo ""
        read -rp "请输入选项 [1/2]: " SERVER_REGION
        case "$SERVER_REGION" in
            1) log "已选择：国内 VPS"; IS_CN=true  ;;
            2) log "已选择：海外 VPS"; IS_CN=false ;;
            *) die "无效选项，退出。" ;;
        esac

        detect_pkg_manager
        ensure_deps
        detect_systemctl
        install_docker
        configure_mirrors
        log "重载 Docker 配置并启动服务..."
        svc enable docker
        svc daemon-reload
        svc start docker
        [ "$HAS_SYSTEMCTL" = false ] && warn "请手动启动 Docker：dockerd &"
        verify_install
        add_user_to_docker_group
        show_docker_status
        banner "Docker 安装完成！"
        ok "Docker 安装完成！"
        ;;
    2)
        detect_pkg_manager
        ensure_deps
        detect_systemctl
        echo ""
        warn "此操作将彻底卸载 Docker 及所有数据，不可恢复！"
        read -rp "确认卸载？[y/N]: " CONFIRM
        case "$CONFIRM" in
            y|Y) uninstall_docker ;;
            *)   log "已取消卸载。" ;;
        esac
        ;;
    *)
        die "无效选项，退出。"
        ;;
esac
