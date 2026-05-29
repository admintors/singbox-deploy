# singbox-deploy
一个跨平台、自动化、全兼容的 Sing-box 一键部署脚本
## 功能说明

本脚本用于安装和管理 sing-box，支持以下协议：

- Shadowsocks
- Hysteria2
- TUIC
- VLESS Reality
- AnyTLS Reality

支持以下管理能力：

- 查看 URI
- 重新生成 URI
- 查看配置文件路径
- 编辑配置文件
- 查看服务状态
- 更新 sing-box
- 卸载 sing-box

---

## 协议管理

支持对以下协议进行管理：

- SS：新增 / 删除 / 修改端口
- HY2：新增 / 删除 / 修改端口
- TUIC：新增 / 删除 / 修改端口
- AnyTLS：新增 / 删除 / 修改端口

---

## VLESS Reality 管理

支持对 VLESS Reality 节点进行管理：

- 查看 Reality 列表
- 新增一个 Reality
- 删除一个 Reality
- 修改指定 Reality 的端口

首次安装时默认创建 1 个 VLESS Reality 节点。  
后续可通过管理面板继续新增多个 Reality 节点。

---

## 中转功能

脚本支持将指定的 VLESS Reality 节点通过上游 Shadowsocks 进行中转。

### 支持的部署方式

- 直连落地
- 通过上游 Shadowsocks 中转指定 VLESS

### 中转模式说明

当启用中转模式后，可以为当前服务器配置一个上游 Shadowsocks 节点，并指定哪些 VLESS Reality 节点走该上游中转。

例如：

- `vless-in-1` 走上游 SS 中转
- `vless-in-2` 保持本机直连
- `vless-in-3` 也走上游 SS 中转

也就是说：

- 中转规则支持精确绑定到指定 `vless-in-*`
- 不会默认把所有 VLESS 节点都强制中转
- 未被选中的 VLESS 节点仍然保持本机直连
- SS / HY2 / TUIC / AnyTLS 默认不受该中转规则影响

### 中转管理功能

管理面板中支持：

- 查看当前中转状态
- 配置上游 SS 参数
- 选择哪些 VLESS 走中转
- 关闭中转模式
- 重新应用中转配置

### 中转参数包括

- 上游 SS 服务器地址
- 上游 SS 端口
- 上游 SS 加密方式
- 上游 SS 密码

---

## 安装

使用以下命令一键运行安装脚本：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/run.sh)"
```

如果已经将仓库下载到本地，也可以直接运行：

```bash
chmod +x run.sh
bash run.sh
```

---

## 运行要求

请使用 `root` 权限执行脚本。

支持系统：

- Alpine
- Debian
- Ubuntu

---

## 安装完成后

安装完成后，可使用以下命令打开管理面板：

```bash
sb
```

---

## 管理面板结构

### 1) 链接与配置
- 查看 URI
- 重新生成 URI
- 查看配置文件路径
- 编辑配置文件

### 2) 协议管理
- SS 管理
- HY2 管理
- TUIC 管理
- AnyTLS 管理

### 3) VLESS Reality 管理
- 查看 Reality 列表
- 新增一个 Reality
- 删除一个 Reality
- 修改 Reality 端口

### 4) 中转管理
- 查看当前中转状态
- 配置上游 SS 参数
- 选择哪些 VLESS 走中转
- 关闭中转模式
- 重新应用中转配置

### 5) 服务管理
- 查看服务状态
- 更新 sing-box
- 卸载 sing-box

---

## 常用命令

### 打开管理面板
```bash
sb
```

### 查看生成的链接
```bash
cat /etc/sing-box/uris.txt
```

### 查看配置文件
```bash
cat /etc/sing-box/config.json
```

### 检查配置文件
```bash
sing-box check -c /etc/sing-box/config.json
```

---

## 服务管理

### Debian / Ubuntu

重启服务：

```bash
systemctl restart sing-box
```

查看状态：

```bash
systemctl status sing-box
```

### Alpine

重启服务：

```bash
rc-service sing-box restart
```

查看状态：

```bash
rc-service sing-box status
```

---

## 文件路径

主配置文件：

```bash
/etc/sing-box/config.json
```

URI 文件：

```bash
/etc/sing-box/uris.txt
```

管理命令：

```bash
/usr/local/bin/sb
```

