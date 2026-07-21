#!/bin/bash

CONFIG="$HOME/SVXLinkJP/config/config.ini"

[ -f "$CONFIG" ] && source "$CONFIG"

CALL=${CALLSIGN:-JQ1YOF-R}

while true
do

clear

IP_WIFI=$(ip -4 addr show wlan0 | awk '/inet /{print $2}'|cut -d/ -f1)
IP_LAN=$(ip -4 addr show eth0 | awk '/inet /{print $2}'|cut -d/ -f1)

SSID=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')

TEMP=$(($(cat /sys/class/thermal/thermal_zone0/temp)/1000))

MEM=$(free | awk '/Mem:/ {printf "%.0f",$3/$2*100}')

DISK=$(df -h / | awk 'NR==2{print $5}')

UP=$(uptime -p)

systemctl is-active --quiet svxlink
[ $? = 0 ] && SVX="RUNNING" || SVX="STOP"

echo "========================================================"
echo
echo "              SVXLink JP Edition Ver5.1"
echo
echo "              JQ1YOF Radio Controller"
echo
echo "========================================================"

printf "%-15s %s\n" "Callsign :" "$CALL"

printf "%-15s %s\n" "WiFi :" "$IP_WIFI"

printf "%-15s %s\n" "LAN :" "$IP_LAN"

printf "%-15s %s\n" "SSID :" "$SSID"

echo

printf "%-15s %s\n" "SVXLink :" "$SVX"

printf "%-15s READY\n" "GPIO :"

printf "%-15s READY\n" "Audio :"

printf "%-15s READY\n" "Beacon :"

echo

printf "%-15s %s°C\n" "CPU Temp :" "$TEMP"

printf "%-15s %s%%\n" "Memory :" "$MEM"

printf "%-15s %s\n" "Disk :" "$DISK"

printf "%-15s %s\n" "Uptime :" "$UP"

echo
echo "========================================================"
echo
echo "ENTER : Main Menu"

read -t 5 -n1 KEY

[ "$KEY" = "" ] && continue

break

done
