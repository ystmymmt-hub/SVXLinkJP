#!/bin/bash

CONN="netplan-wlan0-TP-Link_5B10"

IP=$(whiptail --inputbox "固定IPアドレス" 10 60 "192.168.0.150" 3>&1 1>&2 2>&3)

GW="192.168.0.1"

DNS="8.8.8.8 1.1.1.1"

sudo nmcli connection modify "$CONN" \
ipv4.addresses ${IP}/24 \
ipv4.gateway $GW \
ipv4.dns "$DNS" \
ipv4.method manual

sudo nmcli connection up "$CONN"

whiptail --msgbox "固定IPへ変更しました\n\nIP=$IP" 12 60
