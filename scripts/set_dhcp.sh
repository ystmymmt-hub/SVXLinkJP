#!/bin/bash

CONNECTION="netplan-eth0"
DEVICE="eth0"
BACKUP_DIR="$HOME/SVXLinkJP/backup/network"

mkdir -p "$BACKUP_DIR"

if ! systemctl is-active --quiet NetworkManager; then
    whiptail --title "Network Error" \
        --msgbox "NetworkManagerが動作していません。" \
        10 60
    exit 1
fi

if ! nmcli -t -f NAME connection show |
    grep -Fxq "$CONNECTION"; then
    whiptail --title "Network Error" \
        --msgbox \
"接続プロファイルが見つかりません。

$CONNECTION" \
        12 64
    exit 1
fi

CURRENT=$(nmcli -g ipv4.method \
    connection show "$CONNECTION" 2>/dev/null)

if [ "$CURRENT" = "auto" ]; then
    whiptail --title "DHCP設定" \
        --msgbox \
"有線LANは既にDHCP設定です。

接続:
$CONNECTION" \
        12 58
    exit 0
fi

whiptail \
    --title "DHCP設定" \
    --yesno \
"有線LAN eth0 をDHCPへ戻します。

IPアドレスはルーターから自動取得されます。

SSH接続中の場合、一時的に通信が切れます。

実行しますか？" \
    17 68

[ $? -ne 0 ] && exit 0

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="$BACKUP_DIR/${CONNECTION}_${TIMESTAMP}.nmconnection"

sudo nmcli connection export "$CONNECTION" \
    "$BACKUP_FILE" >/dev/null 2>&1

sudo chown "$(id -u):$(id -g)" \
    "$BACKUP_FILE" 2>/dev/null || true

if ! sudo nmcli connection modify "$CONNECTION" \
    ipv4.method auto \
    ipv4.addresses "" \
    ipv4.gateway "" \
    ipv4.dns "" \
    ipv4.ignore-auto-dns no \
    connection.autoconnect yes; then

    whiptail --title "Network Error" \
        --msgbox "DHCP設定の保存に失敗しました。" \
        11 60
    exit 1
fi

if sudo nmcli connection up "$CONNECTION" \
    ifname "$DEVICE"; then

    NEW_IP=$(ip -4 -o addr show dev "$DEVICE" 2>/dev/null |
        awk '{print $4}' | head -1)

    [ -z "$NEW_IP" ] && NEW_IP="取得確認中"

    whiptail \
        --title "DHCP設定完了" \
        --msgbox \
"DHCPへ変更しました。

現在のIP:
$NEW_IP

設定バックアップ:
$BACKUP_FILE" \
        16 68
else
    whiptail --title "Network Error" \
        --msgbox \
"DHCP設定は保存されましたが、
ネットワークの再接続に失敗しました。" \
        13 64
    exit 1
fi
