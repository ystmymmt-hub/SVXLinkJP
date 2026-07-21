#!/bin/bash

HOSTNAME_NOW=$(hostname 2>/dev/null)

ETH_IP=$(ip -4 -o address show dev eth0 2>/dev/null |
    awk 'NR == 1 {print $4}')

WLAN_IP=$(ip -4 -o address show dev wlan0 2>/dev/null |
    awk 'NR == 1 {print $4}')

DEFAULT_LINE=$(ip -4 route show default 2>/dev/null |
    head -1)

GATEWAY=$(awk '{print $3}' <<< "$DEFAULT_LINE")
DEFAULT_DEV=$(awk '{print $5}' <<< "$DEFAULT_LINE")

[ -z "$ETH_IP" ] &&
    ETH_IP="未接続"

[ -z "$WLAN_IP" ] &&
    WLAN_IP="未接続"

[ -z "$GATEWAY" ] &&
    GATEWAY="不明"

[ -z "$DEFAULT_DEV" ] &&
    DEFAULT_DEV="不明"

DNS=""

if [ "$DEFAULT_DEV" != "不明" ]; then
    DNS=$(nmcli -g IP4.DNS device show "$DEFAULT_DEV" 2>/dev/null |
        sed '/^$/d' |
        paste -sd ' ' -)
fi

if [ -z "$DNS" ]; then
    DNS=$(awk '/^nameserver / {
        print $2
    }' /etc/resolv.conf 2>/dev/null |
        paste -sd ' ' -)
fi

[ -z "$DNS" ] &&
    DNS="不明"

whiptail \
    --title "SVXLinkJP Network Status" \
    --msgbox \
"ホスト名:
$HOSTNAME_NOW

有線LAN eth0:
$ETH_IP

Wi-Fi wlan0:
$WLAN_IP

標準接続:
$DEFAULT_DEV

ゲートウェイ:
$GATEWAY

DNS:
$DNS" \
    23 68
