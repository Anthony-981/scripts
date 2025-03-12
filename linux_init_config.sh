#!/bin/bash

# 检查是否以root权限运行
if [ $(id -u) -ne 0 ]; then
    echo "请使用root权限运行此脚本"
    exit 1
fi

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo "无法确定操作系统类型"
    exit 1
fi

echo "检测到操作系统: $OS $VERSION_ID"

# 关闭防火墙
if [ "$OS" == "centos" ]; then
    systemctl stop firewalld
    systemctl disable firewalld
    echo "CentOS防火墙已关闭并禁用开机自启"
elif [ "$OS" == "ubuntu" ]; then
    ufw disable
    echo "Ubuntu防火墙已禁用"
fi

# 关闭SELinux（仅CentOS）
if [ "$OS" == "centos" ]; then
    setenforce 0
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    echo "SELinux已关闭并永久禁用"
fi

# 配置软件源
if [ "$OS" == "centos" ]; then
    # 备份原有yum源
    mkdir -p /etc/yum.repos.d/backup
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/
    # 下载阿里云yum源
    curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-${VERSION_ID}.repo
    
    # 安装并配置EPEL源
    if [ "${VERSION_ID}" == "7" ]; then
        yum -y install epel-release
        # 备份EPEL源
        mv /etc/yum.repos.d/epel.repo /etc/yum.repos.d/epel.repo.backup
        mv /etc/yum.repos.d/epel-testing.repo /etc/yum.repos.d/epel-testing.repo.backup
        # 下载阿里云EPEL源
        curl -o /etc/yum.repos.d/epel.repo https://mirrors.aliyun.com/repo/epel-7.repo
    elif [ "${VERSION_ID}" == "8" ]; then
        dnf -y install epel-release
        # 配置EPEL源为阿里云镜像
        sed -i 's|^#baseurl=https://download.fedoraproject.org/pub|baseurl=https://mirrors.aliyun.com|' /etc/yum.repos.d/epel*
        sed -i 's|^metalink|#metalink|' /etc/yum.repos.d/epel*
    elif [ "${VERSION_ID}" == "9" ]; then
        dnf -y install epel-release
        # 配置EPEL源为阿里云镜像
        sed -i 's|^#baseurl=https://download.fedoraproject.org/pub|baseurl=https://mirrors.aliyun.com|' /etc/yum.repos.d/epel*
        sed -i 's|^metalink|#metalink|' /etc/yum.repos.d/epel*
    fi
    
    # 清除并重建yum缓存
    yum clean all
    yum makecache
    echo "EPEL源已配置完成"
elif [ "$OS" == "ubuntu" ]; then
    # 备份原有源
    cp /etc/apt/sources.list /etc/apt/sources.list.backup
    # 配置阿里云源
    cat > /etc/apt/sources.list << EOF
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs) main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-proposed main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $(lsb_release -cs)-backports main restricted universe multiverse
EOF
    # 更新软件包列表
    apt-get update
    
    # 安装常用系统工具
    apt-get install -y vim net-tools wget curl htop iftop iotop unzip lsof tcpdump sysstat
    
    # 配置系统参数
    cat >> /etc/sysctl.conf << EOF
# 系统级别文件描述符限制
fs.file-max = 1000000
# 允许更多的PIDs
kernel.pid_max = 65535
# 增加网络连接数限制
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 65535
# TCP连接优化
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
# TCP内存优化
net.ipv4.tcp_mem = 786432 1048576 1572864
net.ipv4.tcp_rmem = 4096 87380 4194304
net.ipv4.tcp_wmem = 4096 87380 4194304
EOF
    sysctl -p
    
    # 配置系统最大打开文件数
    cat >> /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF

    # 配置SSH安全
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    cat > /etc/ssh/sshd_config << EOF
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
SyslogFacility AUTH
LogLevel INFO
PermitRootLogin yes
StrictModes yes
MaxAuthTries 3
MaxSessions 10
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
PrintMotd no
ClientAliveInterval 300
ClientAliveCountMax 2
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
    systemctl restart sshd

    # 配置系统日志
    cat > /etc/logrotate.d/syslog << EOF
/var/log/syslog
/var/log/mail.info
/var/log/mail.warn
/var/log/mail.err
/var/log/mail.log
/var/log/daemon.log
/var/log/kern.log
/var/log/auth.log
/var/log/user.log
/var/log/lpr.log
/var/log/cron.log
/var/log/debug
/var/log/messages
{
    rotate 7
    daily
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
EOF
fi

# 配置时间同步
if [ "$OS" == "centos" ]; then
    # CentOS使用chronyd
    yum -y install chrony
    # 配置chrony使用国内时间服务器
    cat > /etc/chrony.conf << EOF
server ntp.aliyun.com iburst
server ntp1.aliyun.com iburst
server ntp2.aliyun.com iburst
server ntp3.aliyun.com iburst

stratumweight 0
driftfile /var/lib/chrony/drift
rtcsync
makestep 10 3
bindcmdaddress 127.0.0.1
bindcmdaddress ::1
local stratum 10
keyfile /etc/chrony.keys
commandkey 1
generatecommandkey
noclientlog
logchange 0.5
logdir /var/log/chrony
EOF
    # 启动chronyd服务
    systemctl start chronyd
    systemctl enable chronyd
    # 验证时间同步状态
    chronyc sources
elif [ "$OS" == "ubuntu" ]; then
    # Ubuntu使用systemd-timesyncd
    apt-get install -y systemd-timesyncd
    # 配置时间同步服务器
    cat > /etc/systemd/timesyncd.conf << EOF
[Time]
NTP=ntp.aliyun.com ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com
FallbackNTP=ntp.ubuntu.com
EOF
    # 启动时间同步服务
    systemctl restart systemd-timesyncd
    systemctl enable systemd-timesyncd
    # 验证时间同步状态
    timedatectl status
fi

echo "系统初始化配置完成！"
echo "已执行的操作："
echo "1. 关闭并禁用防火墙"
if [ "$OS" == "centos" ]; then
    echo "2. 关闭并禁用SELinux"
    echo "3. 更换为阿里云yum源和EPEL源"
else
    echo "2. 更换为阿里云软件源"
    echo "3. 安装常用系统工具"
    echo "4. 优化系统内核参数"
    echo "5. 配置系统最大文件打开数"
    echo "6. 配置SSH安全设置"
    echo "7. 优化系统日志配置"
fi
echo "8. 配置时间同步服务" 