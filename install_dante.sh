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

# 检测系统类型
if [[ -f /etc/debian_version ]]; then
  # Debian/Ubuntu 系统
  PKG_MANAGER="apt"
  SYSTEMCTL="/bin/systemctl"
elif [[ -f /etc/redhat-release ]]; then
  # CentOS/RHEL 系统
  PKG_MANAGER="yum"
  SYSTEMCTL="/usr/bin/systemctl"
else
  echo "Unsupported operating system"
  exit 1
fi

# 更新系统
$PKG_MANAGER update -y

# 安装依赖包
if [[ $PKG_MANAGER == "apt" ]]; then
  $PKG_MANAGER install dante-server -y
elif [[ $PKG_MANAGER == "yum" ]]; then
  $PKG_MANAGER install dante-server -y
fi

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
$SYSTEMCTL daemon-reload

# 启动服务
$SYSTEMCTL start danted
$SYSTEMCTL enable danted

# 配置防火墙
if command -v firewalld > /dev/null; then
  # CentOS 7+ firewalld
  firewall-cmd --permanent --add-port=1080/tcp
  firewall-cmd --reload
elif command -v iptables > /dev/null; then
  # iptables
  iptables -A INPUT -p tcp --dport 1080 -j ACCEPT
  service iptables save
else
  echo "Warning: Firewall not configured. Please configure your firewall manually."
fi

# 输出配置信息
echo "Dante SOCKS5 proxy has been installed and configured."
echo "Server: $(curl -s ifconfig.me)"
echo "Port: 1080"
echo "Username: sockd"
echo "Password: $PASSWORD"
