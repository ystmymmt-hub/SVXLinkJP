#!/bin/bash

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
NC="\033[0m"

check(){

printf "%-20s" "$1"

if eval "$2" >/dev/null 2>&1
then
    echo -e "${GREEN}[ OK ]${NC}"
else
    echo -e "${RED}[ NG ]${NC}"
fi

}

clear

echo -e "${CYAN}"
echo "===================================================="
echo "          SVXLink JP Edition Ver5.1"
echo "             System Check"
echo "===================================================="
echo -e "${NC}"

check "Configuration" "[ -f ~/SVXLinkJP/config/config.ini ]"
check "WiFi" "ip addr show wlan0 | grep inet"
check "Ethernet" "ip addr show eth0 | grep inet"
check "Internet" "ping -c1 -W1 8.8.8.8"
check "GPIO" "which pinctrl"
check "USB Audio" "arecord -l"
check "SVXLink" "systemctl is-active --quiet svxlink"
check "EchoLink" "grep -q PASSWORD /etc/svxlink/svxlink.d/ModuleEchoLink.conf"
check "Disk" "[ \$(df / | awk 'NR==2{print \$5}'|tr -d '%') -lt 90 ]"

echo
echo -e "${GREEN}System READY${NC}"

sleep 3
