#!/bin/bash

IP=$(hostname -I | awk '{print $1}')

GW=$(ip route | awk '/default/ {print $3}')

SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2)

whiptail --msgbox \
"SSID : $SSID

IP : $IP

Gateway : $GW" 15 60
