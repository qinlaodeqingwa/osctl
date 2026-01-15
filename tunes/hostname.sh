s="node-$(echo "$1" | awk -F. '{printf("%03d%03d%03d%03d",$1,$2,$3,$4)}')"
hostnamectl set-hostname "$s"
s="$1 $s"

if ! fgrep -q "$s" /etc/hosts; then
    echo "$s" >> /etc/hosts
fi