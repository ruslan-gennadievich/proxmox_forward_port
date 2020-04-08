# Proxmox forward port
Bash script to auto port forward when create new CT in Proxmox

## Install
 apt install inotify-tools
 cp monitor_pve_conf.sh /usr/sbin
 
## Use
Just run script in background
bash /usr/sbin/monitor_pve_conf.sh &

and create/remove CT in Proxmox interface

you can see new rules:
iptables -n -L -v -t nat --line-numbers
