#!/bin/bash
set -o errexit -o nounset -o pipefail

rpms=( atop bc bind-utils epel-release git iotop ipvsadm jq lsof mysql net-tools nmap-ncat socat sysstat telnet unzip vim-enhanced wget xz yum-utils )
if command -v yum; then
    yum install -y "${rpms[@]}"
elif command -v dnf; then
    dnf install -y "${rpms[@]}"
fi

debs=( atop bc dnsutils git iotop ipvsadm jq lsof default-mysql-client net-tools ncat socat sysstat telnet unzip vim wget xz-utils )
if command -v apt-get; then
    apt-get install -y "${rpms[@]}"
elif command -v apt; then
    apt install -y "${rpms[@]}"
fi

if command -v atop;then
    sed -i  's/600/30/g; s/28/1/g' /etc/sysconfig/atop
    echo "0 0 * * * root systemctl try-restart atop" > /etc/cron.d/atop
    systemctl restart  atop
fi