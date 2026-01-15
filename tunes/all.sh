#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]}")"
source ../fn.sh
set -o errexit -o nounset -o pipefail

cd ..

for ip in $(cat "$hosts_file");do
  $orgalorg_cmd -o "$ip:$ssh_port" -e -r /tmp -U tunes
  $orgalorg_cmd  -o "$ip:$ssh_port" -x -C \
    'bash /tmp/tunes/one.sh && rm -rf /tmp/tunes'
done