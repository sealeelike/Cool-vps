很好 👍
我给你整理一份 **“新买 Debian VPS 首次 SSH 安全加固 SOP”**，按顺序执行即可。

结构是：

1️⃣ 启用公钥
2️⃣ 导入公钥
3️⃣ Windows 测试
4️⃣ 禁用密码（允许 root 公钥）
5️⃣ 安装并配置 fail2ban（含 recidive）

全部使用 **Debian 11/12 推荐的 .d 目录方式**，不修改系统自带主配置。

---

# ✅ Debian VPS 首次安全加固 SOP

---

# 第一阶段：启用 SSH 公钥登录

## 1️⃣ 确认 sshd 支持 include 目录

```bash
grep Include /etc/ssh/sshd_config
```

应看到：

```
Include /etc/ssh/sshd_config.d/*.conf
```

---

## 2️⃣ 在 sshd_config.d 下新建文件

```bash
sudo nano /etc/ssh/sshd_config.d/10-pubkey.conf
```

写入：

```conf
PubkeyAuthentication yes
```

保存退出。

检查配置：

```bash
sudo sshd -t
```

重启 SSH：

```bash
sudo systemctl restart ssh
```

---

# 第二阶段：导入公钥

## 1️⃣ 创建 .ssh 目录（如果是 root）

```bash
mkdir -p /root/.ssh
chmod 700 /root/.ssh
```

如果是普通用户：

```bash
mkdir -p /home/用户名/.ssh
chmod 700 /home/用户名/.ssh
```

---

## 2️⃣ 写入 authorized_keys

```bash
nano /root/.ssh/authorized_keys
```

粘贴你的公钥（ssh-ed25519 或 ssh-rsa 开头那一整行）。

保存后：

```bash
chmod 600 /root/.ssh/authorized_keys
```

---

# 第三阶段：Windows 测试公钥登录

Windows PowerShell 测试：

```powershell
ssh root@你的服务器IP
```

如果使用指定私钥：

```powershell
ssh -i C:\Users\你的用户名\.ssh\id_ed25519 root@服务器IP
```

确认：

✅ 不需要密码
✅ 可以成功登录

⚠️ 成功前不要禁用密码登录。

---

# 第四阶段：禁用密码登录（允许 root 公钥）

## 新建安全配置文件

```bash
sudo nano /etc/ssh/sshd_config.d/20-security.conf
```

写入：

```conf
# 只允许公钥认证
PubkeyAuthentication yes
AuthenticationMethods publickey

# 禁止密码认证
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no

# 允许 root 但仅公钥
PermitRootLogin prohibit-password
```

检查：

```bash
sudo sshd -t
```

重启：

```bash
sudo systemctl restart ssh
```

再次用新终端测试登录。

---

# 第五阶段：安装 Fail2Ban

```bash
sudo apt update
sudo apt install fail2ban -y
```

开机自启：

```bash
sudo systemctl enable fail2ban
```

---

# 第六阶段：单文件 jail 配置（sshd + recidive）

编辑：

```bash
sudo nano /etc/fail2ban/jail.local
```

完整内容如下（可直接复制）：

```ini
[DEFAULT]

backend = systemd
bantime = 30m
findtime = 10m
maxretry = 5
banaction = iptables-multiport
logtarget = /var/log/fail2ban.log


[sshd]
enabled = true
port = ssh
filter = sshd


[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
findtime = 24h
maxretry = 5
bantime = 7d
```

---

# 第七阶段：启动并验证

测试配置：

```bash
sudo fail2ban-client -t
```

重启：

```bash
sudo systemctl restart fail2ban
```

查看状态：

```bash
sudo fail2ban-client status
```

应看到：

```
Jail list: sshd, recidive
```

查看 sshd：

```bash
sudo fail2ban-client status sshd
```

---

# 可选：限制 journald 日志大小（防止占满磁盘）

编辑：

```bash
sudo nano /etc/systemd/journald.conf
```

设置：

```
SystemMaxUse=200M
SystemKeepFree=500M
```

然后：

```bash
sudo systemctl restart systemd-journald
```

---

# 最终完成状态应为

✔ 只允许公钥登录
✔ root 允许公钥
✔ 密码彻底禁用
✔ SSH 爆破自动封禁
✔ 累犯封 7 天
✔ 日志不会爆盘

---

# 以后新 VPS 上线流程

1. apt update
2. 配公钥
3. 禁密码
4. 装 fail2ban
5. 配 recidive
6. （可选）改端口

10 分钟完成一台安全基线。

---

如果你愿意，我可以再给你一版：

* 🔒 极限安全版（带 MaxAuthTries、LoginGraceTime、AllowUsers）
* 🧱 或加 nftables 白名单版本（只允许你 IP 访问 22）

你现在这套已经是“生产可用安全基线”了。
