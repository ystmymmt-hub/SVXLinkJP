#!/bin/bash

PROJECT_DIR="$HOME/SVXLinkJP"
BACKUP_ROOT="$PROJECT_DIR/backup/network"
WORK_ROOT="/tmp/svxlinkjp_network_restore"

error_box()
{
    whiptail \
        --title "Network Restore Error" \
        --msgbox "$1" \
        14 74
}

backup_current()
{
    local stamp
    local work
    local archive

    stamp=$(date '+%Y%m%d_%H%M%S')
    work="$BACKUP_ROOT/pre_restore_$stamp"
    archive="$BACKUP_ROOT/SVXLinkJP_network_pre_restore_$stamp.tar.gz"

    mkdir -p "$work"

    sudo cp -a /etc/netplan \
        "$work/" 2>/dev/null || true

    sudo cp -a /etc/NetworkManager/system-connections \
        "$work/" 2>/dev/null || true

    sudo cp -a /run/NetworkManager/system-connections \
        "$work/run-system-connections" 2>/dev/null || true

    {
        echo "Backup type: pre-restore safety backup"
        echo "Backup date: $(date)"
        echo "Hostname: $(hostname)"
        echo
        nmcli connection show
        echo
        ip -4 address
        echo
        ip route
    } > "$work/MANIFEST.txt" 2>&1

    sudo chown -R "$(id -u):$(id -g)" \
        "$work" 2>/dev/null || true

    tar -czf "$archive" \
        -C "$BACKUP_ROOT" \
        "$(basename "$work")" || return 1

    rm -rf "$work"

    echo "$archive"
}

mkdir -p "$BACKUP_ROOT"

mapfile -t FILES < <(
    find "$BACKUP_ROOT" \
        -maxdepth 1 \
        -type f \
        -name 'SVXLinkJP_network_*.tar.gz' \
        ! -name '*pre_restore*' \
        -printf '%T@|%p\n' |
    sort -rn |
    cut -d'|' -f2-
)

if [ "${#FILES[@]}" -eq 0 ]; then
    error_box \
"復元できるネットワークバックアップがありません。

先にネットワーク設定バックアップを作成してください。"
    exit 1
fi

MENU_ITEMS=()

for i in "${!FILES[@]}"; do
    FILE="${FILES[$i]}"
    BASENAME=$(basename "$FILE")
    SIZE=$(du -h "$FILE" 2>/dev/null | awk '{print $1}')

    MENU_ITEMS+=(
        "$((i + 1))"
        "$BASENAME  [$SIZE]"
    )
done

CHOICE=$(whiptail \
    --title "Network Restore" \
    --menu \
"復元するバックアップを選択してください。

注意:
復元後にIPアドレスが変わる可能性があります。" \
    24 88 12 \
    "${MENU_ITEMS[@]}" \
    3>&1 1>&2 2>&3)

[ $? -ne 0 ] && exit 0

INDEX=$((CHOICE - 1))
ARCHIVE="${FILES[$INDEX]}"

if ! tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
    error_box \
"バックアップファイルが壊れている可能性があります。

$ARCHIVE"
    exit 1
fi

CONTENTS=$(tar -tzf "$ARCHIVE" 2>/dev/null |
    grep -E \
'MANIFEST|netplan|system-connections' |
    head -40)

whiptail \
    --title "復元内容確認" \
    --scrolltext \
    --yesno \
"次のバックアップを復元します。

$ARCHIVE

主な内容:
$CONTENTS

復元前に現在設定を自動バックアップします。

復元後はネットワークが一時切断され、
SSH接続も切れる可能性があります。

続行しますか？" \
    27 88

[ $? -ne 0 ] && exit 0

SAFETY_BACKUP=$(backup_current)

if [ $? -ne 0 ] || [ -z "$SAFETY_BACKUP" ]; then
    error_box \
"復元前の安全バックアップに失敗しました。

復元を中止します。"
    exit 1
fi

sudo rm -rf "$WORK_ROOT"
mkdir -p "$WORK_ROOT"

if ! tar -xzf "$ARCHIVE" \
    -C "$WORK_ROOT"; then

    error_box "バックアップ展開に失敗しました。"
    exit 1
fi

RESTORE_DIR=$(find "$WORK_ROOT" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d |
    head -1)

if [ -z "$RESTORE_DIR" ]; then
    error_box "展開先フォルダーを確認できません。"
    exit 1
fi

FOUND=0

if [ -d "$RESTORE_DIR/netplan" ]; then
    FOUND=1

    sudo rm -rf /etc/netplan
    sudo cp -a "$RESTORE_DIR/netplan" /etc/
fi

if [ -d "$RESTORE_DIR/system-connections" ]; then
    FOUND=1

    sudo mkdir -p /etc/NetworkManager

    if [ -d /etc/NetworkManager/system-connections ]; then
        sudo cp -a \
            /etc/NetworkManager/system-connections \
            "/etc/NetworkManager/system-connections.before_restore.$(date '+%Y%m%d_%H%M%S')"
    fi

    sudo rm -rf /etc/NetworkManager/system-connections

    sudo cp -a \
        "$RESTORE_DIR/system-connections" \
        /etc/NetworkManager/
fi

if [ "$FOUND" -eq 0 ]; then
    error_box \
"復元対象のネットワーク設定が見つかりません。

安全バックアップ:
$SAFETY_BACKUP"
    exit 1
fi

if [ -d /etc/NetworkManager/system-connections ]; then
    sudo chown -R root:root \
        /etc/NetworkManager/system-connections

    sudo find \
        /etc/NetworkManager/system-connections \
        -type f \
        -exec chmod 600 {} \;
fi

sudo netplan generate 2>/dev/null || true
sudo nmcli connection reload 2>/dev/null || true

whiptail \
    --title "復元準備完了" \
    --yesno \
"ネットワーク設定ファイルを復元しました。

安全バックアップ:
$SAFETY_BACKUP

このあとNetworkManagerを再起動します。

SSH接続中の場合、接続が切れる可能性があります。

今すぐ反映しますか？" \
    22 82

if [ $? -eq 0 ]; then
    sudo systemctl restart NetworkManager

    sleep 4

    CURRENT=$(
        {
            echo "=== Device ==="
            nmcli device status
            echo
            echo "=== IPv4 ==="
            ip -4 address
            echo
            echo "=== Route ==="
            ip route
        } 2>&1
    )

    whiptail \
        --title "Network Restore Complete" \
        --scrolltext \
        --msgbox \
"ネットワーク設定を復元しました。

$CURRENT

SSHが切れた場合は、
復元後のIPアドレスで接続してください。" \
        27 82
else
    whiptail \
        --title "再起動保留" \
        --msgbox \
"設定ファイルの復元は完了しています。

NetworkManagerはまだ再起動していません。

本体画面から次を実行してください。

sudo systemctl restart NetworkManager

安全バックアップ:
$SAFETY_BACKUP" \
        21 78
fi

sudo rm -rf "$WORK_ROOT"
