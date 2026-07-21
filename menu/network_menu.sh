#!/bin/bash

while true
do

MENU=$(whiptail \
--title "SVXLink JP Edition Ver5.1" \
--menu "Network Manager" \
22 75 12 \
1 "Network Status" \
2 "Wi-Fi Information" \
3 "Ethernet Information" \
4 "Static IP Setting" \
5 "DHCP Mode" \
6 "Internet Test" \
7 "Restart Network" \
8 "Return" \
3>&1 1>&2 2>&3)

case $MENU in

1)

~/SVXLinkJP/scripts/network_status.sh

;;

2)

nmcli dev wifi

read

;;

3)

ip addr show eth0

read

;;

4)

~/SVXLinkJP/scripts/set_static_ip.sh

;;

5)

~/SVXLinkJP/scripts/set_dhcp.sh

;;

6)

ping -c4 8.8.8.8

read

;;

7)

sudo systemctl restart NetworkManager

;;

8)

break

;;

esac

done
