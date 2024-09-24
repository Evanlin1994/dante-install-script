#!/bin/bash

# 检查是否以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# 检查是否提供了密码参数
if [ -z "$1" ]; then
   echo "Usage: $0 <password>"
   exit 1
fi

PASSWORD=$1

# 更新系统
apt update && apt upgrade -y

# 安装 Dante 服务器
apt install dante-server -y

# 获取主网卡名称
INTERFACE=$(ip route | grep default | awk '{print $5}')

# 创建配置文件
cat > /etc/danted.conf <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

internal: 0.0.0.0 port=1080
external: $INTERFACE

socksmethod: username
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
EOF

# 创建用户
useradd -r -s /bin/false sockd

# 设置密码
echo "sockd:$PASSWORD" | chpasswd

# 创建 danted.service 文件
cat > /etc/systemd/system/danted.service <<EOF
[Unit]
Description=SOCKS (v4 and v5) proxy daemon (danted)
After=network.target

[Service]
ExecStart=/usr/sbin/danted -f /etc/danted.conf
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd 配置
systemctl daemon-reload

# 启动服务
systemctl start danted
systemctl enable danted

# 配置防火墙（如果使用 UFW）
if command -v ufw > /dev/null; then
    ufw allow 1080
    ufw reload
fi

# 输出配置信息
echo "Dante SOCKS5 proxy has been installed and configured."
echo "Server: $(curl -s ifconfig.me)"
echo "Port: 1080"
echo "Username: sockd"
echo "Password: $PASSWORD"

# 检查服务状态
systemctl status danted
