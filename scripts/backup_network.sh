#!/bin/bash

PROJECT_DIR="$HOME/SVXLinkJP"
BACKUP_ROOT="$PROJECT_DIR/backup/network"
STAMP=$(date '+%Y%m%d_%H%M%S')
WORK_DIR="$BACKUP_ROOT/network_$STAMP"
ARCHIVE="$BACKUP_ROOT/SVXLinkJP_network_$STAMP.tar.gz"

mkdir -p "$WORK_DIR"

sudo cp -a /etc/netplan \
    "$WORK_DIR/" 2>/dev/null || true

sudo cp -a /etc/NetworkManager/system-connections \
    "$WORK_DIR/" 2>/dev/null || true

sudo cp -a /run/NetworkManager/system-connections \
    "$WORK_DIR/run-system-connections" 2>/dev/null || true

{
    echo "Backup date: $(date)"
    echo "Hostname: $(hostname)"
    echo
    echo "=== NetworkManager ==="
    systemctl is-active NetworkManager
    echo
    echo "=== Connections ==="
    nmcli connection show
    echo
    echo "=== Active connections ==="
    nmcli connection show --active
    echo
    echo "=== Addresses ==="
    ip -4 address
    echo
    echo "=== Routes ==="
    ip route
} > "$WORK_DIR/MANIFEST.txt" 2>&1

sudo chown -R "$(id -u):$(id -g)" \
    "$WORK_DIR" 2>/dev/null || true

if tar -czf "$ARCHIVE" \
    -C "$BACKUP_ROOT" \
    "$(basename "$WORK_DIR")"; then

    rm -rf "$WORK_DIR"

    CONTENT=$(tar -tzf "$ARCHIVE" 2>/dev/null |
        head -30)

    whiptail \
        --title "Network Backup Complete" \
        --scrolltext \
        --msgbox \
"ネットワーク設定を保存しました。

保存先:
$ARCHIVE

内容:
$CONTENT" \
        25 78
else
    whiptail \
        --title "Network Backup Error" \
        --msgbox \
"ネットワーク設定の圧縮保存に失敗しました。

作業フォルダー:
$WORK_DIR" \
        14 72
    exit 1
fi
