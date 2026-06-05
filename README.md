# singbox-deploy

一个用于 **Sing-box 服务端安装、管理、卸载** 的一键脚本仓库。  
支持 **SS / HY2 / TUIC / VLESS Reality / AnyTLS** 协议部署，支持 **VLESS Reality 多实例管理**，并支持 **指定哪些 VLESS Reality 走上游 Shadowsocks 中转**。

---

## 功能特点

- 支持 Alpine / Debian / Ubuntu 等常见 Linux 系统
- 支持安装 Sing-box 最新服务端
- 支持生成客户端连接 URI
- 支持 `sb` 管理面板
- 支持 VLESS Reality 多实例新增 / 删除 / 改端口 / 列表查看
- 支持 SS / HY2 / TUIC / AnyTLS 的新增 / 删除 / 改端口
- 支持中转模式
- 支持指定哪些 `vless-in-*` 走上游 Shadowsocks 中转
- 支持重新应用中转配置
- 支持一键彻底卸载
- 支持基础 IPv6 链接生成与 IPv6 地址格式兼容

---

## 仓库文件说明

- `run.sh`：一键安装入口脚本
- `install-singbox-yyds.sh`：主安装 / 管理脚本
- `uninstall-singbox-yyds.sh`：一键卸载脚本
- `README.md`：常规说明文档
- `README-BEGINNER.md`：小白版使用说明

---

## 一键安装

### 方式 1：直接运行 `run.sh`

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/run.sh)"
```

### 方式 2：直接运行主安装脚本

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/install-singbox-yyds.sh)"
```

---

## 安装后如何管理

安装完成后，输入：

```bash
sb
```

进入管理面板。

---

## 管理面板结构

主菜单：

```text
1) 链接与配置
2) 协议管理
3) VLESS Reality 管理
4) 中转管理
5) 服务管理
0) 退出
```

---

## 协议管理

在 `协议管理` 中可管理：

- SS
- HY2
- TUIC
- AnyTLS

每类协议都支持：

- 新增
- 删除
- 修改端口

---

## VLESS Reality 管理

在 `VLESS Reality 管理` 中支持：

- 查看 Reality 列表
- 新增一个 Reality
- 删除一个 Reality
- 修改指定 Reality 的端口
- 重新生成 URI

VLESS Reality 使用类似以下 tag：

```text
vless-in-1
vless-in-2
vless-in-3
```

旧版单节点 `vless-in` 会自动迁移到：

```text
vless-in-1
```

---

## 中转模式

脚本支持两种部署模式：

```text
1) 直连落地（默认）
2) 通过上游 Shadowsocks 中转指定 VLESS
```

如果启用中转模式，可以在 `中转管理` 中：

- 查看当前中转状态
- 修改上游 Shadowsocks 参数
- 选择哪些 `vless-in-*` 走中转
- 关闭中转模式
- 重新应用中转配置

说明：

- 不会默认让所有协议都走中转
- 只会让你指定的 `vless-in-*` 走上游 SS
- 其他 VLESS / 其他协议仍然保持直连

---

## 链接与配置

在 `链接与配置` 中可以：

- 查看客户端 URI
- 查看配置文件位置
- 手动编辑配置
- 重新生成链接

---

## 服务管理

在 `服务管理` 中可以：

- 启动服务
- 停止服务
- 重启服务
- 查看服务状态
- 查看运行日志
- 更新 sing-box

---

## IPv6 说明

当前脚本已支持基础 IPv6 使用场景：

- 自动探测公网地址时可识别 IPv6
- 生成 URI 时可正确处理 IPv6 字面量地址格式
- 手动输入 IPv6 地址时，会按 URI 规范自动兼容

注意：

- 请自行确认服务器具备公网 IPv6
- 请自行确认云平台安全组 / 防火墙已放行 IPv6 入站
- 若使用域名，建议优先使用域名而不是直接暴露裸 IPv6 地址

---

## 一键卸载

### 交互确认版

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh)"
```

运行后会要求输入：

```text
YES
```

确认后才会继续卸载。

### 无确认直接卸载版

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh)" --yes
```

如果上面这种 shell 传参方式在你的环境不方便，也可以这样：

```bash
curl -fsSL -o uninstall-singbox-yyds.sh https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh && chmod +x uninstall-singbox-yyds.sh && ./uninstall-singbox-yyds.sh --yes
```

---

## 卸载会删除什么

卸载脚本会尝试移除：

- `/etc/sing-box`
- `/usr/local/bin/sb`
- `/usr/local/bin/install-singbox-yyds.sh`
- `/usr/local/bin/run.sh`
- `sing-box` service 文件
- `sing-box` 二进制程序
- 相关残留进程

适用于：

- 想彻底清理旧配置重新安装
- 想从零开始重新部署
- 想移除旧版脚本残留

---

## 适用场景

适合以下用途：

- 新服务器快速部署 sing-box
- 一台机器部署多个 VLESS Reality
- 使用部分 VLESS Reality 走上游 Shadowsocks 中转
- 需要通过菜单管理协议和端口
- 需要彻底卸载后重新安装

---

## 常用命令

安装：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/run.sh)"
```

进入面板：

```bash
sb
```

卸载：

```bash
curl -fsSL -o uninstall-singbox-yyds.sh https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh && chmod +x uninstall-singbox-yyds.sh && ./uninstall-singbox-yyds.sh --yes
```

---

## 给新手用户

如果你希望给完全不会操作的新手看，请直接阅读：

- [`README-BEGINNER.md`](./README-BEGINNER.md)

---

## 说明

如果你是从旧版脚本升级：

- 旧版 `vless-in` 会自动迁移到 `vless-in-1`
- 旧配置缓存会在运行时自动检查并兼容迁移
- 如果历史配置过于混乱，建议先执行卸载脚本后再全新安装
