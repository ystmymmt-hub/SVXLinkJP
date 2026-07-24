#!/bin/bash

PROJECT_DIR="$HOME/SVXLinkJP"
SCRIPT_DIR="$PROJECT_DIR/scripts"

show_error()
{
    whiptail \
        --title "Network Error" \
        --msgbox "$1" \
        13 72
}

run_script()
{
    local script_file="$1"
    shift

    if [ ! -f "$script_file" ]; then
        show_error "スクリプトが見つかりません。

$script_file"
        return 1
    fi

    if [ ! -x "$script_file" ]; then
        chmod +x "$script_file" 2>/dev/null
    fi

    "$script_file" "$@"
}

show_networkmanager_status()
{
    local status_text

    status_text=$(
        {
            echo "=== NetworkManager ==="
            systemctl is-active NetworkManager
            echo

            echo "=== Device status ==="
            nmcli device status
            echo

            echo "=== Active connections ==="
            nmcli connection show --active
            echo

            echo "=== IPv4 addresses ==="
            ip -4 address
            echo

            echo "=== Route ==="
            ip route
            echo

            echo "=== DNS ==="
            nmcli device show |
                grep -E 'GENERAL.DEVICE|IP4.DNS'
        } 2>&1
    )

    whiptail \
        --title "NetworkManager Status" \
        --scrolltext \
        --msgbox "$status_text" \
        27 86
}

while true
do
    CHOICE=$(whiptail \
        --title "SVXLinkJP Network Settings" \
        --menu "ネットワーク操作を選択してください" \
        22 78 10 \
        1 "現在のIPアドレスを表示" \
        2 "有線LAN eth0 を固定IPに設定" \
        3 "有線LAN eth0 をDHCPに設定" \
        4 "Wi-Fi wlan0 を固定IPに設定" \
        5 "Wi-Fi wlan0 をDHCPに設定" \
        6 "ネットワーク設定をバックアップ" \
        7 "NetworkManager詳細表示" \
        8 "ネットワーク設定を復元" \
        0 "前の画面に戻る" \
        3>&1 1>&2 2>&3)

    RET=$?

    if [ "$RET" -ne 0 ]; then
        exit 0
    fi

    case "$CHOICE" in
        1)
            run_script "$SCRIPT_DIR/show_ip.sh"
            ;;

        2)
            run_script "$SCRIPT_DIR/set_network_ip.sh" eth0 static
            ;;

        3)
            run_script "$SCRIPT_DIR/set_network_ip.sh" eth0 dhcp
            ;;

        4)
            run_script "$SCRIPT_DIR/set_network_ip.sh" wlan0 static
            ;;

        5)
            run_script "$SCRIPT_DIR/set_network_ip.sh" wlan0 dhcp
            ;;

        6)
            run_script "$SCRIPT_DIR/backup_network.sh"
            ;;

        7)
            show_networkmanager_status
            ;;

        8)
            run_script "$SCRIPT_DIR/restore_network.sh"
            ;;

        0)
            exit 0
            ;;
    esac
done
