# Docker 一键安装/卸载脚本

适用于国内 / 海外 VPS 的 Docker 交互式管理脚本，支持自动检测系统环境、配置国内镜像加速、彻底卸载等功能。

## 支持系统

| 发行版         | 包管理器 | 支持 |
| -------------- | -------- | ---- |
| Ubuntu 18.04+  | apt-get  | ✅   |
| Debian 9+      | apt-get  | ✅   |
| CentOS 7/8     | yum      | ✅   |
| RHEL 7/8       | yum      | ✅   |
| Rocky Linux    | dnf      | ✅   |
| AlmaLinux      | dnf      | ✅   |
| Fedora         | dnf      | ✅   |
| TencentOS      | yum      | ✅   |
| 华为云 EulerOS | yum/dnf  | ✅   |

## 功能特性

- 交互式选择操作（安装 / 卸载）
- 自动识别国内 / 海外 VPS，使用对应安装源
- 国内 VPS 直接走阿里云软件源，不依赖 get.docker.com
- 国内 VPS 自动配置 11 个 Docker Hub 镜像加速源
- 自动检测并安装依赖（curl、xargs、getent、usermod、systemd）
- 安装完成后自动启动服务并设置开机自启
- 彻底卸载：清理容器、镜像、数据卷、网络、软件包、残留文件
- 彩色输出：绿色成功 / 黄色警告 / 红色错误

## 快速开始

### 国内 VPS（raw.githubusercontent.com 可能被墙，推荐用镜像）

```bash
# 方式一：staticdn 镜像（推荐）
wget https://raw.staticdn.net/yuzhouxiaogegit/install_docker_cn/main/install_docker_cn.sh
bash install_docker_cn.sh
```

```bash
# 方式二：ghproxy 镜像
bash <(curl -fsSL https://ghproxy.com/https://raw.githubusercontent.com/yuzhouxiaogegit/install_docker_cn/main/install_docker_cn.sh)
```

```bash
# 方式三：直连（如果能访问）
wget https://raw.githubusercontent.com/yuzhouxiaogegit/install_docker_cn/main/install_docker_cn.sh
bash install_docker_cn.sh
```

### 海外 VPS

```bash
# 方式一：wget
wget https://raw.githubusercontent.com/yuzhouxiaogegit/install_docker_cn/main/install_docker_cn.sh
bash install_docker_cn.sh
```

```bash
# 方式二：curl 直接执行
bash <(curl -fsSL https://raw.githubusercontent.com/yuzhouxiaogegit/install_docker_cn/main/install_docker_cn.sh)
```

> 必须使用 `bash` 执行，不支持 `sh`

## 使用说明

运行脚本后会出现交互菜单：

```
=========================================
  Docker 交互式管理脚本
=========================================

请选择操作：
  1) 安装 Docker
  2) 卸载 Docker
```

### 安装 Docker

选择 `1` 后，继续选择服务器类型：

```
请选择服务器类型：
  1) 国内 VPS（阿里云、腾讯云、华为云等）
  2) 海外 VPS（AWS、GCP、Vultr、搬瓦工等）
```

- 选 `1` 国内 VPS：使用阿里云镜像源安装，并自动配置 Docker Hub 镜像加速
- 选 `2` 海外 VPS：使用 Docker 官方源安装，不配置镜像加速

安装完成后脚本会自动：

1. 启动 Docker 服务并设置开机自启
2. 配置国内镜像加速（仅国内 VPS）
3. 拉取 hello-world 验证安装
4. 显示 Docker 运行状态

### 卸载 Docker

选择 `2` 后，脚本会二次确认后彻底清理：

- 所有运行中的容器
- 所有镜像
- 所有数据卷
- 所有自定义网络
- Docker 相关软件包
- 配置文件、数据目录、软件源等残留文件

> ⚠️ 卸载操作不可恢复，请提前备份重要数据

## 国内镜像加速源

脚本为国内 VPS 配置以下镜像加速源（按优先级排列）：

| 镜像源                    | 维护方            |
| ------------------------- | ----------------- |
| docker.m.daocloud.io      | DaoCloud 道客网络 |
| docker.1panel.live        | 1Panel 社区       |
| hub.rat.dev               | 第三方社区        |
| docker.1ms.run            | 毫秒镜像          |
| docker.mybacc.com         | 第三方社区        |
| docker.zhai.cm            | 第三方社区        |
| hub.littlediary.cn        | 第三方社区        |
| dockerhub.icu             | 第三方社区        |
| docker.linkedbus.com      | 链氪网公益        |
| docker.kejilion.pro       | 第三方社区        |
| registry.dockermirror.com | 第三方社区        |

## 注意事项

- 需要 `root` 或 `sudo` 权限运行
- 海外 VPS 直连 Docker Hub，无需镜像加速
- 容器 / WSL1 环境中 systemd 不可用，Docker 服务需手动启动：`dockerd &`
- 普通用户通过 `sudo` 执行时，脚本会自动将其加入 `docker` 组，重新登录后无需 `sudo` 即可使用 docker

## License

MIT
