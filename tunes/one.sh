#!/bin/bash
set -o errexit -o nounset -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ "$(getenforce)" != 'Disabled' ]]; then
    setenforce 0
fi
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

function disable_service() {
    local s="$(systemctl list-unit-files -t service)"
    if echo "$s" | grep -Fq "$1"; then
        systemctl disable "$1"
        systemctl stop "$1"
    fi

    if systemctl is-active "$1"; then
        systemctl disable "$1"
        systemctl stop "$1"
    fi
}

disable_service firewalld

while read i; do
    if [[ -z "$i" ]]; then
        continue
    fi
    if ! lsmod | fgrep -q "$i"; then
        modprobe "$i"
    fi
done <<< "$(cat modtune.conf)"
cp -f modtune.conf /etc/modules-load.d

f=/etc/rc.d/rc.local
sed -i '/^# operator start$/,/^# operator end$/d' "$f"
cat >> "$f" <<EOF
# operator start
bash /etc/rc.d/rc.dice
# operator end
EOF
chmod 755 "$f"

f=/etc/rc.d/rc.dice
cp -f rc.dice "$f"
chmod 755 "$f"
bash "$f"

swapoff -a
sed -r -i 's/^([^#]*\s+swap\s+)/#\1/' /etc/fstab

cp -f 99-limits.conf /etc/security/limits.d
sed -i -e '/^DefaultLimitNOFILE=/d' -e '/^\[Manager\]/a DefaultLimitNOFILE=100000' /etc/systemd/system.conf

f=/etc/logrotate.d/syslog
if [[ -f "$f" ]]; then
    if ! fgrep -q daily "$f"; then
        sed -i '/{/a\    daily' "$f"
    fi
    if ! fgrep -q size "$f"; then
        sed -i '/{/a\    size=50M' "$f"
    fi
fi

f=/usr/lib/systemd/system/sysstat-collect.timer
if [[ -f "$f" ]]; then
    sed -i 's#^OnCalendar=.*$#OnCalendar=*-*-* *:*:00#' "$f"
    systemctl daemon-reload
    systemctl restart sysstat-collect.timer
fi