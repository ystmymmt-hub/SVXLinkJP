#!/bin/bash
#
#=========================================
# SVXLink JP Edition
# Radio Controller Menu
# Version 4.0
#=========================================

while true
do

CHOICE=$(whiptail \
--title "SVXLink JP Edition Ver4.0" \
--menu "JQ1YOF Radio Controller" \
20 70 10 \
"1" "Radio Power ON" \
"2" "Radio Power OFF" \
"3" "GPIO Status" \
"4" "GPIO Test" \
"5" "SVXLink Start" \
"6" "SVXLink Stop" \
"7" "SVXLink Restart" \
"8" "System Status" \
"9" "Back" \
3>&1 1>&2 2>&3)

RET=$?

if [ $RET -ne 0 ]; then
    exit
fi

case $CHOICE in

1)

~/SVXLinkJP/scripts/gpio.sh on

sleep 1

;;

2)

~/SVXLinkJP/scripts/gpio.sh off

sleep 1

;;

3)

~/SVXLinkJP/scripts/gpio.sh status

read -p "Enter..."

;;

4)

~/SVXLinkJP/scripts/gpio.sh test

read -p "Enter..."

;;

5)

sudo systemctl start svxlink

read -p "Enter..."

;;

6)

sudo systemctl stop svxlink

read -p "Enter..."

;;

7)

sudo systemctl restart svxlink

read -p "Enter..."

;;

8)

systemctl status svxlink --no-pager

read -p "Enter..."

;;

9)

exit

;;

esac

done
