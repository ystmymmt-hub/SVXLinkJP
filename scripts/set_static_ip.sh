#!/bin/bash

CONNECTION="netplan-eth0"
DEVICE="eth0"
BACKUP_DIR="$HOME/SVXLinkJP/backup/network"

mkdir -p "$BACKUP_DIR"

error_box()
{
    whiptail --title "Network Error" \
        --msgbox "$1" 12 68
}

valid_ipv4()
{
    local ip="$1"
    local IFS=.
    local parts
    local p

    read -r -a parts <<< "$ip"

    [ "${#parts[@]}" -eq 4 ] || return 1

    for p in "${parts[@]}"; do
        [[ "$p" =~ ^[0-9]+$ ]] || return 1
        [ "$p" -ge 0 ] && [ "$p" -le 255 ] || return 1
    done

    return 0
}

if ! systemctl is-active --quiet NetworkManager; then
    error_box "NetworkManagerが動作していません。"
    exit 1
fi

if ! nmcli -t -f NAME connection show |
    grep -Fxq "$CONNECTION"; then
    error_box \
"接続プロファイルが見つかりません。

$CONNECTION"
    exit 1
fi

CURRENT_IP=$(nmcli -g ipv4.addresses \
    connection show "$CONNECTION" 2>/dev/null |
    head -1 |
    cut -d/ -f1)

CURRENT_PREFIX=$(nmcli -g ipv4.addresses \
    connection show "$CONNECTION" 2>/dev/null |
    head -1 |
    awk -F/ '{print $2}')

CURRENT_GATEWAY=$(nmcli -g ipv4.gateway \
    connection show "$CONNECTION" 2>/dev/null |
    head -1)

CURRENT_DNS=$(nmcli -g ipv4.dns \
    connection show "$CONNECTION" 2>/dev/null |
    paste -sd ' ' -)

[ -z "$CURRENT_IP" ] && \
    CURRENT_IP=$(ip -4 -o addr show dev "$DEVICE" |
    awk '{print $4}' | head -1 | cut -d/ -f1)

[ -z "$CURRENT_PREFIX" ] && CURRENT_PREFIX="24"

[ -z "$CURRENT_GATEWAY" ] && \
    CURRENT_GATEWAY=$(ip route show default |
    awk -v dev="$DEVICE" '$0 ~ dev {print $3; exit}')

[ -z "$CURRENT_DNS" ] && CURRENT_DNS="8.8.8.8 1.1.1.1"

NEW_IP=$(whiptail \
    --title "固定IP設定" \
    --inputbox \
"有線LAN eth0 の固定IPアドレスを入力してください。

例: 192.168.1.150" \
    13 64 \
    "$CURRENT_IP" \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] && exit 0

if ! valid_ipv4 "$NEW_IP"; then
    error_box "IPアドレスの形式が正しくありません。"
    exit 1
fi

PREFIX=$(whiptail \
    --title "サブネット設定" \
    --inputbox \
"プレフィックス長を入力してください。

一般的な家庭内LANは 24 です。" \
    12 60 \
    "$CURRENT_PREFIX" \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] && exit 0

if ! [[ "$PREFIX" =~ ^[0-9]+$ ]] ||
   [ "$PREFIX" -lt 1 ] ||
   [ "$PREFIX" -gt 32 ]; then
    error_box "プレフィックス長は1～32で入力してください。"
    exit 1
fi

GATEWAY=$(whiptail \
    --title "ゲートウェイ設定" \
    --inputbox \
"ルーターのIPアドレスを入力してください。

例: 192.168.1.1" \
    12 64 \
    "$CURRENT_GATEWAY" \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] && exit 0

if ! valid_ipv4 "$GATEWAY"; then
    error_box "ゲートウェイの形式が正しくありません。"
    exit 1
fi

DNS=$(whiptail \
    --title "DNS設定" \
    --inputbox \
"DNSサーバーを空白区切りで入力してください。

例:
192.168.1.1 8.8.8.8" \
    14 66 \
    "$CURRENT_DNS" \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] && exit 0

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="$BACKUP_DIR/${CONNECTION}_${TIMESTAMP}.nmconnection"

sudo nmcli connection export "$CONNECTION" \
    "$BACKUP_FILE" >/dev/null 2>&1

sudo chown "$(id -u):$(id -g)" \
    "$BACKUP_FILE" 2>/dev/null || true

whiptail \
    --title "最終確認" \
    --yesno \
"次の内容で固定IPを設定します。

接続:
$CONNECTION

IP:
$NEW_IP/$PREFIX

ゲートウェイ:
$GATEWAY

DNS:
$DNS

現在SSH接続中の場合、一時的に通信が切れます。
新しいIPアドレスで再接続してください。

実行しますか？" \
    22 72

[ $? -ne 0 ] && exit 0

if ! sudo nmcli connection modify "$CONNECTION" \
    ipv4.method manual \
    ipv4.addresses "$NEW_IP/$PREFIX" \
    ipv4.gateway "$GATEWAY" \
    ipv4.dns "$DNS" \
    ipv4.ignore-auto-dns yes \
    connection.autoconnect yes; then

    error_box "固定IP設定の保存に失敗しました。"
    exit 1
fi

if sudo nmcli connection up "$CONNECTION" \
    ifname "$DEVICE"; then

    whiptail \
        --title "固定IP設定完了" \
        --msgbox \
"固定IPを設定しました。

新しいIP:
$NEW_IP

SSHで接続し直す場合:
ssh $(whoami)@$NEW_IP

設定バックアップ:
$BACKUP_FILE" \
        18 70
else
    error_box \
"設定は保存されましたが、
ネットワークの再接続に失敗しました。

本体画面または新しいIPから確認してください。"
    exit 1
fi
