#!/bin/bash

PROJECT_DIR="$HOME/SVXLinkJP"

while true
do
    CHOICE=$(whiptail \
        --title "SVXLinkJP Network Settings" \
        --menu "ネットワーク操作を選択してください" \
        19 72 9 \
        1 "Show IP       現在のIPアドレスを表示" \
        2 "Static IP     有線LANを固定IPに設定" \
        3 "DHCP          有線LANを自動取得に設定" \
        4 "Status        NetworkManager詳細表示" \
        0 "Back          戻る" \
        3>&1 1>&2 2>&3)

    RET=$?

    [ "$RET" -ne 0 ] && exit 0

    case "$CHOICE" in
        1)
            "$PROJECT_DIR/scripts/show_ip.sh"
            ;;
        2)
            "$PROJECT_DIR/scripts/set_static_ip.sh"
            ;;
        3)
            "$PROJECT_DIR/scripts/set_dhcp.sh"
            ;;
        4)
            STATUS=$(
                {
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
                } 2>&1
            )

            whiptail \
                --title "Network Status" \
                --scrolltext \
                --msgbox "$STATUS" \
                24 78
            ;;
        0)
            exit 0
            ;;
    esac
done
