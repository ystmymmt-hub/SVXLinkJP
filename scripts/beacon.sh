#!/bin/bash

#############################################
# SVXLink JP Edition
# JP Smart Beacon Ver4.1
#############################################

CONFIG="$HOME/SVXLinkJP/config/beacon.conf"

source "$CONFIG"

if [ "$BEACON_ENABLE" != "ON" ]; then
    exit
fi

NOW=$(date +%H:%M)

if [[ "$NOW" < "$START_TIME" ]] || [[ "$NOW" > "$END_TIME" ]]; then
    exit
fi

HOUR24=$(date +%H)
MIN=$(date +%M)

# 午前午後判定
if [ "$HOUR24" -lt 12 ]; then
    AMPM="gozen.wav"
    HOUR=$HOUR24
    [ "$HOUR" -eq 0 ] && HOUR=12
else
    AMPM="gogo.wav"
    HOUR=$((10#$HOUR24-12))
    [ "$HOUR" -eq 0 ] && HOUR=12
fi

PLAYER=$PLAYER

DIR=$AUDIO_DIR

play(){

if [ -f "$DIR/$1" ]; then

$PLAYER "$DIR/$1"

sleep 0.3

fi

}

play chime.wav

play beacon.wav

play current_time.wav

play "$AMPM"

play hour/$HOUR.wav

play ji.wav

play minute/$MIN.wav

play fun.wav

play thanks.wav
