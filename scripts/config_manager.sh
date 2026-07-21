#!/bin/bash
#
# SVXLink JP Edition
# Configuration Manager
#

CONFIG="$HOME/SVXLinkJP/config/config.ini"

SVXCONF="/etc/svxlink/svxlink.conf"

ECHOCONF="/etc/svxlink/svxlink.d/ModuleEchoLink.conf"

BACKUP="$HOME/SVXLinkJP/backup"

mkdir -p "$BACKUP"
backup_all(){

STAMP=$(date +%Y%m%d_%H%M%S)

sudo cp "$SVXCONF" \
"$BACKUP/svxlink_$STAMP.conf"

sudo cp "$ECHOCONF" \
"$BACKUP/echolink_$STAMP.conf"

cp "$CONFIG" \
"$BACKUP/config_$STAMP.ini"

}

update_callsign(){

source "$CONFIG"

sudo sed -i \
"s/^CALLSIGN=.*/CALLSIGN=$CALLSIGN/" \
"$SVXCONF"

}

update_echolink(){

source "$CONFIG"

sudo sed -i \
"s/^CALLSIGN=.*/CALLSIGN=$ECHOLINK_CALL/" \
"$ECHOCONF"

}
update_password(){

source "$CONFIG"

sudo sed -i \
"s/^PASSWORD=.*/PASSWORD=$ECHOLINK_PASSWORD/" \
"$ECHOCONF"

}
restart_service(){

sudo systemctl restart svxlink

}

sync_all(){

backup_all

update_callsign

update_echolink

update_password

restart_service

}

