#!/bin/bash

set -o errexit -o nounset -o pipefail

if [[ $# -ne 2 || -z "$1" || -z "$2" ]]; then
    echo "Usage: disks/one.sh <disk-device> <mount-point>"
    exit 1
fi

disk="$1"
mp="$2"
df="/dev/$disk"
d1="${df}1"

if [[ "$mp" != /* ]]; then
    echo "$mp is not absolute path"
    exit 1
fi
if [[ -e "$mp" ]]; then
    if [[ ! -d "$mp" ]]; then
        echo "$mp is not directory"
        exit 1
    fi
    if mountpoint -q "$mp"; then
        d=$(lsblk -l -n -o NAME,MOUNTPOINT | awk -v mp="$mp" '{if($2==mp)print $1}')
        if [[ "$d" == "$disk" ]]; then
            echo "$disk already mounted on $mp"
            exit 0
        else
            echo "$d already mounted on $mp, but not $disk"
            exit 1
        fi
    fi
fi

if [[ ! -e "$df" ]]; then
    echo "$df not exist"
    exit 1
fi
d=$(lsblk -l -n -o NAME,MOUNTPOINT | awk -v d="$disk" '{if($1==d)print $1}')
if [[ "$d" != "$disk" ]]; then
    echo "$disk not exist"
    exit 1
fi

d=$(lsblk -l -n -o NAME,MOUNTPOINT | awk -v d="$disk" '{if($1==d)print $2}')
if [[ -n "$d" ]]; then
    if [[ "$d" == "$mp" ]]; then
        echo "$disk already mounted on $mp"
        exit 0
    else
        echo "$disk already mounted on $d, but not $mp"
        exit 1
    fi
fi

d=$(lsblk -l -n -o NAME,MOUNTPOINT | awk -v mp="$mp" '{if($2==mp)print $1}')
if [[ -n "$d" ]]; then
    if [[ "$d" == "$disk" ]]; then
        echo "$disk already mounted on $mp"
        exit 0
    else
        echo "$d already mounted on $mp, but not $disk"
        exit 1
    fi
fi

if grep -q "$df" /etc/fstab; then
    echo "find $df in /etc/fstab"
    exit 1
fi
if grep -q "$mp" /etc/fstab; then
    echo "find $mp in /etc/fstab"
    exit 1
fi

set +e
id=$(blkid -s UUID -o value "$df")
set -e
if [[ -n "$id" ]]; then
    if grep -q "$id" /etc/fstab; then
        echo "find $disk uuid in /etc/fstab"
        exit 1
    fi
fi

fstype=ext4
if [[ "$disk" == *xvd* ]]; then
    fstype=xfs # aws
fi

n="$(lsblk -l -n -o NAME,MOUNTPOINT | grep "^$disk" | wc -l)"
if [[ "$n" -eq 0 ]]; then
    echo "$disk not exist"
    exit 1
fi
if [[ "$n" -eq 1 ]]; then
    if [[ -e "$d1" ]]; then
        echo "$d1 exist, $disk already partitioned"
    else
      echo "partition $df"

      if [[ "$(lsblk -o SIZE -b -n "$df" | head -n 1)" -lt 2199023255552 ]]; then
fdisk "$df" <<EOF
o
n
p




w
q
EOF
        else
parted "$df" <<EOF
mklabel gpt
mkpart primary 0% 100%
quit
EOF
        fi

        sleep 3
        echo "format $d1"
        mkfs -t "$fstype" "$d1"
    fi
else
    echo "lsblk returns $n rows, $disk already partitioned"
fi

if grep -q "$d1" /etc/fstab; then
    echo "find $d1 in /etc/fstab"
    exit 1
fi

set +e
id=$(blkid -s UUID -o value "$d1")
set -e
if [[ -n "$id" ]]; then
    if grep -q "$id" /etc/fstab; then
        echo "find $d1 uuid in /etc/fstab"
        exit 1
    fi
fi

mkdir -p "$mp"
if [[ -n "$(ls -A "$mp")" ]]; then
    echo "$mp not empty"
fi

echo "UUID=$(blkid -s UUID -o value "$d1") $mp $fstype defaults 0 2" >> /etc/fstab
mount "$mp"
sleep 3

if mountpoint -q "$mp"; then
    echo "mount $d1 on $mp succeed"
    exit 0
else
    echo "mount $d1 on $mp failed"
    exit 1
fi