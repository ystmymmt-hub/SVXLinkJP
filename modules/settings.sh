#!/bin/bash

source ~/SVXLinkJP/scripts/common.sh

load_config

while true
do

CHOICE=$(whiptail \
--title "Settings" \
--menu "設定項目を選択してください" \
20 70 10 \
1 "Callsign" \
2 "EchoLink" \
3 "Audio" \
4 "GPIO" \
5 "Network" \
6 "Save" \
7 "Restore" \
0 "Back" \
3>&1 1>&2 2>&3)

RET=$?

[ $RET != 0 ] && exit

case $CHOICE in
1)

NEW=$(whiptail \
--inputbox \
"Callsign" \
10 60 \
"$CALLSIGN" \
3>&1 1>&2 2>&3)

RET=$?

if [ $RET = 0 ]; then

save_value CALLSIGN "$NEW"

fi

;;
2)

NEW=$(whiptail \
--inputbox \
"EchoLink Callsign" \
10 60 \
"$ECHOLINK_CALL" \
3>&1 1>&2 2>&3)

RET=$?

if [ $RET = 0 ]; then

save_value ECHOLINK_CALL "$NEW"

fi

;;
6)

backup_config

restart_svxlink

whiptail \
--msgbox \
"保存しました" \
10 40

;;
7)

LATEST=$(ls -t ~/SVXLinkJP/backup/*.ini | head -1)

cp "$LATEST" \
~/SVXLinkJP/config/config.ini

whiptail \
--msgbox \
"復元しました" \
10 40

;;
0)

exit

;;
esac

done
