# singbox-deploy
一个跨平台、自动化、全兼容的 Sing-box 一键部署脚本
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

## 管理功能

运行 `sb` 后，可进行以下操作：

- 查看 URI
- 查看配置文件路径
- 编辑配置文件
- 重置 SS 端口
- 重置 HY2 端口
- 重置 TUIC 端口
- 重置 VLESS Reality 端口
- 重置 AnyTLS Reality 端口
- 查看 Reality 列表
- 新增一个 Reality
- 删除一个 Reality
- 更新 sing-box
- 查看服务状态
- 重新生成 URI
- 卸载 sing-box

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
