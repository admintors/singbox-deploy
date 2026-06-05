# singbox-deploy 小白版说明（Alpine 优先）

这份说明主要写给：

- 第一次接触服务器的人
- 不会手动配 Sing-box 的人
- 用 **Alpine Linux** 的人

如果你不是 Alpine，也可以参考这个流程，整体思路差不多。

---

## 一、这个脚本是干嘛的

这是一个用来在服务器上快速安装和管理 Sing-box 的脚本。

它可以帮你：

- 安装 Sing-box 服务端
- 生成客户端链接
- 用菜单管理协议
- 新增 / 删除 / 改端口
- 管理多个 VLESS Reality
- 一键卸载
- 基础支持 IPv6 链接生成

支持的协议有：

- SS
- HY2
- TUIC
- VLESS Reality
- AnyTLS

---

## 二、你要准备什么

在开始之前，你要准备好下面这些东西。

### 1）一台 Alpine 服务器

最好是全新的 Alpine 系统，省得旧环境太乱。

---

### 2）root 权限

先输入：

```bash
whoami
```

如果返回：

```bash
root
```

就可以继续。

如果不是 root，可以试：

```bash
sudo -i
```

如果你的系统没装 sudo，就直接用 root 登录。

---

### 3）服务器能联网

至少要能：

- 访问 GitHub raw
- 下载脚本
- 下载 sing-box

你可以先试：

```bash
wget -O /dev/null https://raw.githubusercontent.com/admintors/singbox-deploy/main/run.sh
```

如果这里都失败了，脚本安装大概率也会失败。

---

### 4）云平台安全组 / 防火墙

这个很重要。

脚本可以帮你装服务，**但不一定会帮你把云平台安全组全部配好**。

你需要确认：

- 你要使用的端口，已经在云平台放行
- 如果有系统防火墙，也要放行
- 如果你要用 IPv6，IPv6 入站也要放行

---

## 三、Alpine 新手建议先做的事

在 Alpine 上，建议你先更新一下软件索引：

```bash
apk update
```

如果你还没有 curl，先装一下：

```bash
apk add curl bash
```

有些机器默认没有 bash，装一下更稳。

---

## 四、怎么安装

直接执行：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/run.sh)"
```

如果你想直接跑主脚本，也可以：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/install-singbox-yyds.sh)"
```

---

## 五、安装时不会选怎么办

别慌，按下面来就行。

### 1）协议怎么选

如果你完全不懂，推荐先这样：

- 先开：`VLESS Reality`
- 可选再开：`SS`
- 其他先别开

为什么这样选？

因为这样最简单，出问题也最好排查。

---

### 2）部署模式怎么选

一般会看到：

```text
1) 直连落地（默认）
2) 通过上游 Shadowsocks 中转指定 VLESS
```

### 新手怎么选？

**直接选 1。**

也就是：

```text
直连落地
```

如果你根本不知道“上游 SS 中转”是什么，那就不要选 2。

---

### 3）“节点连接 IP 或 DDNS 域名”填什么

这一步的意思是：客户端最终连接服务器时用什么地址。

你有四种常见填法：

#### 方式 A：直接回车

留空让脚本自动探测公网 IP。

这是大多数新手最省心的方式。

#### 方式 B：填域名

比如：

```text
node.example.com
```

如果你有域名，推荐优先填域名。

#### 方式 C：填 IPv4

比如：

```text
1.2.3.4
```

#### 方式 D：填 IPv6

比如：

```text
2408:xxxx:xxxx::1
```

现在脚本已经做了基础 IPv6 支持，会自动处理链接格式。

但前提是：

- 你的服务器有公网 IPv6
- 云平台已经放行 IPv6
- 你的本地网络也能访问 IPv6

如果你不确定，就先用域名或 IPv4。

---

### 4）端口怎么选

如果你不会选：

- 尽量先用默认值
- 不要和已有服务冲突
- 改端口后，旧链接通常会失效

所以建议：

**能不改就先别乱改。**

---

## 六、安装完成后怎么管理

安装完成后，输入：

```bash
sb
```

就能进入管理菜单。

一般会看到：

```text
1) 链接与配置
2) 协议管理
3) VLESS Reality 管理
4) 中转管理
5) 服务管理
0) 退出
```

---

## 七、每个菜单是干嘛的

### 1）链接与配置

这是你最常用的菜单。

它可以：

- 看客户端链接
- 重新生成链接
- 看配置文件位置
- 手动改配置

如果你只是想把节点导入客户端，基本来这里就够了。

---

### 2）协议管理

这里可以管理：

- SS
- HY2
- TUIC
- AnyTLS

支持：

- 新增
- 删除
- 改端口

如果你已经能用，就别频繁乱改。

---

### 3）VLESS Reality 管理

这里专门管理 VLESS Reality。

支持：

- 查看列表
- 新增一个
- 删除一个
- 改端口
- 重新生成链接

如果你看到：

```text
vless-in-1
vless-in-2
```

可以理解成不同的 VLESS 节点入口。

---

### 4）中转管理

这是进阶功能。

如果你看不懂“上游 SS 中转”是什么，就先不要碰这里。

---

### 5）服务管理

这里很重要。

可以：

- 启动
- 停止
- 重启
- 查看状态
- 看日志
- 更新 sing-box

如果你改完设置后连不上，优先：

1. 重启服务
2. 看日志

---

## 八、Alpine 上常用检查命令

### 看服务状态

先试：

```bash
sb
```

进菜单里看状态。

如果你想手动看，也可以试：

```bash
rc-service sing-box status
```

有些环境也可能使用别的服务方式，如果这条不适用，就以脚本里的 `sb` 菜单为准。

---

### 重启服务

优先在 `sb` 菜单里操作。

如果你手动试，也可以看看：

```bash
rc-service sing-box restart
```

---

### 看日志

优先在 `sb` 菜单里看日志。

如果脚本里有输出日志文件路径，也可以按路径直接查看。

---

## 九、如果你只想最简单能用

照这个方案来：

- 只开 `VLESS Reality`
- 部署模式选 `直连落地`
- 地址留空自动探测，或者填你的域名
- 端口先用默认值
- 安装完成后复制链接到客户端

如果你想多留一个备用协议：

- 再开一个 `SS`

---

## 十、客户端链接丢了怎么办

别担心。

重新输入：

```bash
sb
```

进入：

```text
链接与配置
```

重新查看或重新生成链接就行。

---

## 十一、连不上时先查哪里

### 1）先确认服务是不是启动了

最简单的方式：

```bash
sb
```

然后进服务管理看状态。

---

### 2）检查安全组和防火墙

这是最常见原因。

请确认：

- 云平台安全组已经放行端口
- 系统防火墙没有拦
- 端口没有被别的程序占用

---

### 3）检查你复制的是不是最新链接

如果你：

- 改过端口
- 删除重建过协议
- 新增过节点

那旧链接很可能已经失效。

要重新生成再导入客户端。

---

### 4）如果你用 IPv6

要确认：

- VPS 有公网 IPv6
- 云平台 IPv6 入站已放行
- 你的本地网络能访问 IPv6

如果你不确定，就先不要优先用 IPv6。

---

## 十二、怎么卸载

### 普通卸载

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh)"
```

然后按提示输入：

```text
YES
```

### 直接卸载

```bash
curl -fsSL -o uninstall-singbox-yyds.sh https://raw.githubusercontent.com/admintors/singbox-deploy/main/uninstall-singbox-yyds.sh && chmod +x uninstall-singbox-yyds.sh && ./uninstall-singbox-yyds.sh --yes
```

---

## 十三、给 Alpine 新手的最后建议

记住下面几条就够了：

1. 先执行 `apk update`
2. 没有 `curl` 和 `bash` 就先装：`apk add curl bash`
3. 不会就先选 **直连落地**
4. 不会就先只开 **VLESS Reality**
5. 改端口后，记得重新复制链接
6. 连不上先查 **安全组 / 防火墙 / 服务状态**
7. 看不懂中转就先别碰

---

## 文档入口

- 常规版说明：[`README.md`](./README.md)
- 当前文件：`README-BEGINNER.md`
