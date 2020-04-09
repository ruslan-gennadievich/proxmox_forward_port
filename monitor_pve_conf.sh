#!/bin/bash
# This script monitoring proxmox conf dir (/etc/pve/lxc) and add/remove rules in iptables to forward port
# Before runing, plese do  apt-get install inotify-tools

HOSTNAME=`cat /etc/hostname`
inotifywait -m /etc/pve/lxc -e delete,move |
    while read dir action file; do
        ID_VM=$(basename -- $file .conf)
        if [[ $action == 'MOVED_TO' ]]; then
                if [ -f $dir/$file ]; then
                        IP_VM=`cat $dir/$file | grep -E -o "ip=([0-9]{1,3}[\.]){3}[0-9]{1,3}" | cut -c 4-`
                        if [[ $IP_VM != "" && ! -f /tmp/ct_$file ]]; then
                                echo "$IP_VM" > /tmp/ct_$file
                                echo "iptables -A PREROUTING -t nat -d $HOSTNAME/32 -p tcp -m tcp --dport $(echo $ID_VM)22 -j DNAT --to-destination $IP_VM:22"
                                iptables -A PREROUTING -t nat -d $HOSTNAME/32 -p tcp -m tcp --dport $(echo $ID_VM)22 -j DNAT --to-destination $IP_VM:22
                                iptables -A PREROUTING -t nat -d $HOSTNAME/32 -p tcp -m tcp --dport $(echo $ID_VM)80 -j DNAT --to-destination $IP_VM:80
                                iptables -A PREROUTING -t nat -d $HOSTNAME/32 -p tcp -m tcp --dport $(echo $ID_VM)81 -j DNAT --to-destination $IP_VM:81
                                iptables -A PREROUTING -t nat -d $HOSTNAME/32 -p tcp -m tcp --dport $(echo $ID_VM)43 -j DNAT --to-destination $IP_VM:443
                                iptables-save > /etc/iptables.up.rules
                                # Add comment to CT
                                echo "#Ports forward:" >> $dir/$file
                                echo "#$HOSTNAME:$(echo $ID_VM)22 -> $IP_VM:22" >> $dir/$file
                                echo "#$HOSTNAME:$(echo $ID_VM)80 -> $IP_VM:80" >> $dir/$file
                                echo "#$HOSTNAME:$(echo $ID_VM)81 -> $IP_VM:81" >> $dir/$file
                                echo "#$HOSTNAME:$(echo $ID_VM)43 -> $IP_VM:443" >> $dir/$file
                        fi
                fi
        fi
        if [[ $action == 'DELETE' ]]; then
                IP_VM=`cat /tmp/ct_$file`
                IP_VM_ID=$(echo $IP_VM | awk -F '.' '{print $4}')
                rm /tmp/ct_$file
                RULE_NUM='0'
                if [[ $IP_VM_ID == $ID_VM ]]; then
                        grp="$IP_VM"
                else
                        grp=":$ID_VM"
                fi
                while [[ $RULE_NUM != "" ]]; do
                        RULE_NUM=`iptables -n -L -v -t nat --line-numbers | grep $grp | awk '{print $1}' | head -n1`
                        if [[ $RULE_NUM != "" ]]; then
                                echo "iptables -t nat -D PREROUTING $RULE_NUM"
                                iptables -t nat -D PREROUTING $RULE_NUM
                        fi
                done
                iptables-save > /etc/iptables.up.rules
        fi
        sleep 2
    done
