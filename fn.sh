if [[ -z "$hosts_file" ]]; then
    hosts_file=/opt/all_hosts_file
fi
if [[ -z "$ssh_port" ]]; then
    ssh_port=22
fi

if [[ -z "$ssh_user" ]]; then
    ssh_user="$(id -u -n)"
fi
if ! which orgalorg > /dev/null 2>&1; then
    export PATH=$PATH:/opt/dice-tools/bin
fi
orgalorg_cmd="orgalorg -y -u $ssh_user"
if [[ "$ssh_user" != root ]]; then
    orgalorg_cmd="$orgalorg_cmd -x"
fi
if [[ -n "$ssh_password" ]]; then
    export ORGALORG_PASSWORD="$ssh_password"
    orgalorg_cmd="$orgalorg_cmd -p"
elif [[ -n "$ssh_key" ]]; then
    orgalorg_cmd="$orgalorg_cmd -k $ssh_key"
else
    orgalorg_cmd="$orgalorg_cmd -k $(eval echo ~$ssh_user)/.ssh/id_rsa"
fi

if [[ "$serial_mode" != no ]]; then
    orgalorg_cmd="$orgalorg_cmd -l"
fi

if [[ -z "$ssh_account" ]]; then
    ssh_account=dice
fi