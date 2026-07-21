#!/bin/bash

CONN="netplan-wlan0-TP-Link_5B10"

sudo nmcli connection modify "$CONN" ipv4.method auto

sudo nmcli connection up "$CONN"

whiptail --msgbox "DHCPへ戻しました" 10 50
