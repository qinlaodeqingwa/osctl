#!/bin/bash

set -o errexit -o nounset -o pipefail

echo '---------- OS ----------'
PRETTY_NAME='Unknown'

f=/etc/os-release
if [[ -f "$f" ]]; then
    source "$f"
fi

kernel=$(uname -r | egrep -m 1 -o '[0-9]+(\.[0-9]+)+' | head -n 1)
cpu=$(nproc --all)
memory=$(free -h -w | awk '{if($1=="Mem:")print $2}')
system=$(lsblk -n -o SIZE,MOUNTPOINT | awk '{if(NF==2&&$2=="/")print $1}')
disk=$(lsblk -n -o NAME,SIZE,MOUNTPOINT)

echo "            Name: $PRETTY_NAME"
echo "          Kernel: $kernel"
echo "             CPU: $cpu"
echo "          Memory: $memory"
echo "     System Disk: $system"
echo -e "       Data Disk: \n$disk"

v1=$(echo "$kernel" | cut -d. -f1)
v2=$(echo "$kernel" | cut -d. -f2)
if [[ "$v1" -lt 4 ]] || [[ "$v1" -eq 4 && "$v2" -lt 18 ]]; then
    echo 'ERROR: kernel must be 4.18+' >&2
    exit 1
fi

echo '---------- MTU ----------'
for i in /sys/class/net/*/mtu; do
    j=${i#/sys/class/net/}
    j=${j%/mtu}
    printf '%16s: %s\n' "$j" $(head -n 1 "$i")
done