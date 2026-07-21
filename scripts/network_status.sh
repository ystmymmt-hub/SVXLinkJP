#!/bin/bash

clear

GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;36m"
NC="\033[0m"

WIFI_IP=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
LAN_IP=$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)

SSID=$(nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}')

GW=$(ip route | awk '/default/ {print $3}')

echo -e "${BLUE}"
echo "==============================================="
echo "      SVXLink JP Edition Ver5.1"
echo "        Network Status"
echo "==============================================="
echo -e "${NC}"

echo

echo "Wi-Fi"

if [ -n "$WIFI_IP" ]; then
    echo -e "  SSID : $SSID"
    echo -e "  IP   : ${GREEN}$WIFI_IP${NC}"
else
    echo -e "  ${RED}Not Connected${NC}"
fi

echo

echo "Ethernet"

if [ -n "$LAN_IP" ]; then
    echo -e "  IP   : ${GREEN}$LAN_IP${NC}"
else
    echo -e "  ${RED}Cable Not Connected${NC}"
fi

echo

echo "Gateway"

echo "  $GW"

echo

echo "Internet"

if ping -c1 -W1 8.8.8.8 >/dev/null
then
    echo -e "  ${GREEN}ONLINE${NC}"
else
    echo -e "  ${RED}OFFLINE${NC}"
fi

echo

read -p "ENTERで戻ります..."
