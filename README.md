# singbox-deploy

> 新手用户请先看：[`README-BEGINNER.md`](./README-BEGINNER.md)（以 Alpine 为主的入门说明）

一个用于 **Sing-box 服务端安装、管理、卸载** 的一键脚本仓库。

支持协议：

- SS
- HY2
- TUIC
- VLESS Reality
- AnyTLS

支持能力：

- 一键安装 Sing-box
- 生成客户端 URI
- `sb` 管理面板
- 多实例 VLESS Reality 管理
- 上游 Shadowsocks 中转
- 一键卸载
- 基础 IPv6 地址与链接兼容

---

## 文件说明

- `run.sh`：安装入口
- `install-singbox-yyds.sh`：主安装 / 管理脚本
- `uninstall-singbox-yyds.sh`：卸载脚本
- `README-BEGINNER.md`：小白版说明（Alpine 优先）

---

## 安装

### 方式 1

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/run.sh)"
```

### 方式 2

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/install-singbox-yyds.sh)"
```

---

## 管理

安装完成后执行：

```bash
sb
```

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

## 主要功能

### 链接与配置

- 查看客户端 URI
- 重新生成链接
- 查看配置文件位置
- 手动编辑配置

### 协议管理

可管理：

- SS
- HY2
- TUIC
- AnyTLS

支持：新增 / 删除 / 改端口。

### VLESS Reality 管理

支持：

- 查看列表
- 新增
- 删除
- 改端口
- 重新生成 URI

实例 tag 形如：

```text
vless-in-1
vless-in-2
```

### 中转模式

支持两种模式：

```text
1) 直连落地
2) 上游 Shadowsocks 中转指定 VLESS
```

仅指定的 `vless-in-*` 会走中转，其余协议保持直连。

### 服务管理

支持：

- 启动 / 停止 / 重启
- 查看状态
- 查看日志
- 更新 sing-box

---

## IPv6 说明

当前脚本已做基础 IPv6 支持：

- 自动探测可返回 IPv6
- 生成 URI 时可兼容 IPv6 字面量地址
- 可手动输入 IPv6 作为连接地址

请自行确认：

- 服务器具备公网 IPv6
- 云安全组 / 防火墙已放行 IPv6 入站

---

## 卸载

### 交互卸载

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh)"
```

### 直接卸载

```bash
curl -fsSL -o uninstall-singbox-yyds.sh https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh && chmod +x uninstall-singbox-yyds.sh && ./uninstall-singbox-yyds.sh --yes
```

---

## 常用命令

安装：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/run.sh)"
```

管理：

```bash
sb
```

卸载：

```bash
curl -fsSL -o uninstall-singbox-yyds.sh https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh && chmod +x uninstall-singbox-yyds.sh && ./uninstall-singbox-yyds.sh --yes
```
