#!/bin/bash

# Check new version of this script: https://github.com/ruslan-gennadievich/proxmox_forward_port

# This script monitoring proxmox conf dir (/etc/pve/lxc and /etc/pve/qemu-server) and add/remove iptables rules to forward port
# Before runing, plese do  apt install inotify-tools
#
# Copyright (c) 2020 ruslan-gennadievich
# MIT License

TMPDIR_SAVE_VM_FILE="/etc/pve/forwarded_vm/"
LOG="/var/log/monitor_pve_conf.log"
ARR_PORTS_FOR_FORWARD=(22 80 81 443)
USE_VMID_FOR_PORTFORWARD=true #true - make IP from VMID, false - get IP from vm.conf file
AUTOGEN_IP_FROM_VMID=true #for new VM
IP_PREFIX="192.168.0."
HOSTNAME=`cat /etc/hostname`

echo "`date` start monitor_pve_conf.sh" >> $LOG

ME="${0##*/}"
ME_COUNT=$(ps aux | grep $ME | wc -l)
if [[ "$ME_COUNT" > 3 ]]; then
        echo "Another $ME is running. Please kill him"
        exit 1
fi
mkdir -p "$TMPDIR_SAVE_VM_FILE"
inotifywait -m /etc/pve/lxc /etc/pve/qemu-server -e delete,move |
    while read dir action file; do
        if [[ -f $dir/$file && `cat $dir/$file | grep "template: 1"` == "template: 1" ]]; then
                echo "Ignore template $dir/$file"
                continue
        fi
        ID_VM=$(basename -- $file .conf)
        if [[ $action == 'MOVED_TO' ]]; then
                if [[ $ID_VM != "" && ! -f $(echo $TMPDIR_SAVE_VM_FILE)ctvm_$file ]]; then
                        echo $dir/$file
                        sleep 10
                        sed -i 's:#.*$::g' $dir/$file #clean file from old comments
                        IP_VM=`cat $dir/$file | grep "^[^#;]" | grep -E -o "ip=([0-9]{1,3}[\.]){3}[0-9]{1,3}" | cut -c 4-`
                        if [[ $IP_VM == "" ]]; then
                                # if this qemu-server conf file, make IP from PREFIX+VMID
                                IP_VM="$(echo $IP_PREFIX)$(echo $ID_VM)"
                                if $AUTOGEN_IP_FROM_VMID; then
                                        sed -i "s/type=veth/type=veth,ip=$IP_VM\/24,gw=$(echo $IP_PREFIX)1/g" $dir/$file
                                fi
                        fi
                        if $USE_VMID_FOR_PORTFORWARD; then
                                NEW_IP_VM="$(echo $IP_PREFIX)$(echo $ID_VM)" #Get IP from IP_PREFIX+VMID
                                if [[ $AUTOGEN_IP_FROM_VMID && $IP_VM != $NEW_IP_VM ]]; then
                                        sed -i "s/ip=$IP_VM/ip=$NEW_IP_VM/g" $dir/$file
                                fi                                
                                IP_VM=$NEW_IP_VM
                        fi
                        echo "$IP_VM" > $(echo $TMPDIR_SAVE_VM_FILE)ctvm_$file
                        echo "--- Run commands at `date`:"
                        echo "--- Run commands at `date`:" >> $LOG
                        echo "#Ports forward:" >> $dir/$file #Add comment to CT/VM
                        for port in ${ARR_PORTS_FOR_FORWARD[*]}; do
                                USEDPORT="1"
                                while [[ $USEDPORT != "" ]]; do
                                        PORT_FORWARD=$(( ((RANDOM<<15)|RANDOM) % 65535 + 1000))
                                        USEDPORT=`iptables -n -L -v -t nat --line-numbers | grep "dpt:$PORT_FORWARD" | head -n1`
                                done
                                CMD="iptables -A PREROUTING -t nat -d $HOSTNAME/32 -p tcp -m tcp --dport $PORT_FORWARD -j DNAT --to-destination $IP_VM:$port"
                                echo $CMD
                                echo $CMD >> $LOG
                                eval $CMD
                                echo "#$HOSTNAME:$(echo $ID_VM)$port -> $IP_VM:$port" >> $dir/$file #Add comment to CT/VM
                        done
                        CMD="iptables-save > /etc/iptables.up.rules"
                        echo $CMD >> $LOG
                        eval $CMD
                fi
        fi
        if [[ $action == 'DELETE' ]]; then
                IP_VM=`cat $(echo $TMPDIR_SAVE_VM_FILE)ctvm_$file`
                rm $(echo $TMPDIR_SAVE_VM_FILE)ctvm_$file
                RULE_NUM='0'
                echo "--- Run commands at `date`:"
                echo "--- Run commands at `date`:" >> $LOG
                while [[ $RULE_NUM != "" ]]; do
                        RULE_NUM=`iptables -n -L -v -t nat --line-numbers | grep $IP_VM | awk '{print $1}' | head -n1`
                        if [[ $RULE_NUM != "" ]]; then
                                echo "iptables -t nat -D PREROUTING $RULE_NUM"
                                iptables -t nat -D PREROUTING $RULE_NUM
                        fi
                done
                CMD="iptables-save > /etc/iptables.up.rules"
                echo $CMD >> $LOG
                eval $CMD
        fi
        sleep 2
    done
