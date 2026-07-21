#!/bin/bash

PROJECT_DIR="$HOME/SVXLinkJP"
SCRIPT_DIR="$PROJECT_DIR/scripts"

while true
do
    CHOICE=$(whiptail \
        --title "SVXLinkJP Network Settings" \
        --menu "ネットワーク操作を選択してください" \
        22 76 12 \
        1 "現在のIPアドレスを表示" \
        2 "有線LAN eth0 を固定IPに設定" \
        3 "有線LAN eth0 をDHCPに設定" \
        4 "Wi-Fi wlan0 を固定IPに設定" \
        5 "Wi-Fi wlan0 をDHCPに設定" \
        6 "ネットワーク設定をバックアップ" \
        7 "NetworkManager詳細表示" \
        8 "ネットワーク設定を復元"
        0 "前の画面に戻る" \
        3>&1 1>&2 2>&3)

    RET=$?

    [ "$RET" -ne 0 ] && exit 0

    case "$CHOICE" in
        1)
            "$SCRIPT_DIR/show_ip.sh"
            ;;

        2)
            "$SCRIPT_DIR/set_network_ip.sh" eth0 static
            ;;

        3)
            "$SCRIPT_DIR/set_network_ip.sh" eth0 dhcp
            ;;

        4)
            "$SCRIPT_DIR/set_network_ip.sh" wlan0 static
            ;;

        5)
            "$SCRIPT_DIR/set_network_ip.sh" wlan0 dhcp
            ;;

        6)
            "$SCRIPT_DIR/backup_network.sh"
            ;;

        7)
            STATUS=$(
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
                --msgbox "$STATUS" \
                26 82
           ;;
      8)
               "$SCRIPT_DIR/restore_network.sh"
    ;;

        0)
            exit 0
            ;;
    esac
done
