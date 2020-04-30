#!/bin/bash

# Check new version of this script: https://github.com/ruslan-gennadievich/proxmox_forward_port

# This script monitoring proxmox conf dir (/etc/pve/lxc and /etc/pve/qemu-server) and add/remove iptables rules to forward port
# Before runing, plese do  apt install inotify-tools
#
# Copyright (c) 2020 ruslan-gennadievich
# MIT License

TMPDIR_SAVE_VM_FILE="/etc/pve/forwarded_vm/'"
LOG="/var/log/monitor_pve_conf.log"
ARR_PORTS_FOR_FORWARD=(22 80 81 443)
USE_VMID_FOR_PORTFORWARD=true #if false - get IP from vm.conf file
IP_PREFIX="192.168.0."
HOSTNAME=`cat /etc/hostname`

mkdir -p $TMPDIR_SAVE_CT_FILE
inotifywait -m /etc/pve/lxc /etc/pve/qemu-server -e delete,move |
    while read dir action file; do
        ID_VM=$(basename -- $file .conf)
        if [[ $action == 'MOVED_TO' ]]; then
                if [ -f $dir/$file ]; then
                        if $USE_VMID_FOR_PORTFORWARD; then
                                #Get IP from IP_PREFIX+VMID
                                IP_VM="$(echo $IP_PREFIX)$(echo $ID_VM)"
                        else
                                #Get IP from VM.conf
                                IP_VM=`cat $dir/$file | grep "^[^#;]" | grep -E -o "^[^#;] ip=([0-9]{1,3}[\.]){3}[0-9]{1,3}" | cut -c 4-`
                                if [ $IP_VM == "" ]; then
                                        # if this qemu-server conf file, make IP from PREFIX+VMID
                                        IP_VM="$(echo $IP_PREFIX)$(echo $ID_VM)"
                                fi
                        fi                        
                        if [[ $ID_VM != "" && ! -f $(echo $TMPDIR_SAVE_VM_FILE)ctvm_$file ]]; then
                                echo "$IP_VM" > $(echo $TMPDIR_SAVE_VM_FILE)ctvm_$file
                                echo "--- Run commands at `date`:"
                                echo "--- Run commands at `date`:" >> $LOG
                                for port in ${ARR_PORTS_FOR_FORWARD[*]} do
                                        CMD="iptables -A PREROUTING -t nat -d $HOSTNAME/32 -p tcp -m tcp --dport $(echo $ID_VM)$port -j DNAT --to-destination $IP_VM:$port"
                                        echo $CMD
                                        echo $CMD >> $LOG
                                        eval $CMD
                                done                                
                                CMD="iptables-save > /etc/iptables.up.rules"
                                echo $CMD >> $LOG
                                eval $CMD
                                # Add comment to CT
                                sleep 4
                                echo "#Ports forward:" >> $dir/$file
                                echo "#$HOSTNAME:$(echo $ID_VM)22 -> $IP_VM:22" >> $dir/$file
                                echo "#$HOSTNAME:$(echo $ID_VM)80 -> $IP_VM:80" >> $dir/$file
                                echo "#$HOSTNAME:$(echo $ID_VM)81 -> $IP_VM:81" >> $dir/$file
                                echo "#$HOSTNAME:$(echo $ID_VM)43 -> $IP_VM:443" >> $dir/$file
                        fi
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
