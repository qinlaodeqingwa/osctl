#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../fn.sh
set -o errexit -o nounset -o pipefail


for ip in $(cat "$hosts_file");do
    $orgalorg_cmd -o "$ip:$ssh_port"  -i ./one.sh -C 'bash -s'
done