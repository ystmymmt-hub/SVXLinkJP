#!/bin/bash

PROJECT_DIR="$HOME/SVXLinkJP"
VERSION_FILE="$PROJECT_DIR/version"

show_system_information()
{
    local version
    local cpu_temp
    local uptime_text
    local disk_text
    local memory_text
    local svx_status
    local eth_ip
    local wlan_ip
    local gateway
    local hostname_now
    local os_name
    local kernel

    version=$(cat "$VERSION_FILE" 2>/dev/null)
    [ -z "$version" ] && version="不明"

    hostname_now=$(hostname 2>/dev/null)
    os_name=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null |
        cut -d= -f2- |
        tr -d '"')
    kernel=$(uname -r 2>/dev/null)

    uptime_text=$(uptime -p 2>/dev/null)
    memory_text=$(free -h 2>/dev/null |
        awk '/^Mem:/ {
            print "使用 " $3 " / 合計 " $2
        }')
    disk_text=$(df -h / 2>/dev/null |
        awk 'NR == 2 {
            print "使用 " $3 " / 合計 " $2 "  使用率 " $5
        }')

    if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
        cpu_temp=$(awk '{
            printf "%.1f °C", $1 / 1000
        }' /sys/class/thermal/thermal_zone0/temp)
    else
        cpu_temp="取得できません"
    fi

    svx_status=$(systemctl is-active svxlink 2>/dev/null)
    case "$svx_status" in
        active)
            svx_status="動作中"
            ;;
        inactive)
            svx_status="停止中"
            ;;
        failed)
            svx_status="異常停止"
            ;;
        *)
            svx_status="不明"
            ;;
    esac

    eth_ip=$(ip -4 -o address show dev eth0 2>/dev/null |
        awk 'NR == 1 {print $4}')
    wlan_ip=$(ip -4 -o address show dev wlan0 2>/dev/null |
        awk 'NR == 1 {print $4}')
    gateway=$(ip route show default 2>/dev/null |
        awk 'NR == 1 {print $3 " (" $5 ")"}')

    [ -z "$eth_ip" ] && eth_ip="未接続"
    [ -z "$wlan_ip" ] && wlan_ip="未接続"
    [ -z "$gateway" ] && gateway="不明"

    whiptail \
        --title "SVXLinkJP System Information" \
        --msgbox \
"SVXLinkJP Version:
$version

ホスト名:
$hostname_now

OS:
${os_name:-不明}

Kernel:
${kernel:-不明}

SVXLink:
$svx_status

有線LAN eth0:
$eth_ip

Wi-Fi wlan0:
$wlan_ip

標準ゲートウェイ:
$gateway

稼働時間:
${uptime_text:-不明}

メモリー:
${memory_text:-不明}

ディスク:
${disk_text:-不明}

CPU温度:
$cpu_temp" \
        30 76
}

show_service_log()
{
    local log_data

    log_data=$(sudo journalctl \
        -u svxlink \
        -n 100 \
        --no-pager 2>&1)

    whiptail \
        --title "SVXLink Service Log" \
        --scrolltext \
        --msgbox "$log_data" \
        28 88
}

restart_svxlink_service()
{
    whiptail \
        --title "SVXLink Restart" \
        --yesno \
"SVXLinkサービスを再起動します。

実行しますか？" \
        12 58

    [ $? -ne 0 ] && return

    if sudo systemctl restart svxlink; then
        sleep 2

        local state
        state=$(systemctl is-active svxlink 2>/dev/null)

        whiptail \
            --title "SVXLink Restart" \
            --msgbox \
"SVXLinkを再起動しました。

現在の状態:
$state" \
            13 60
    else
        whiptail \
            --title "SVXLink Error" \
            --msgbox \
"SVXLinkの再起動に失敗しました。

ログを確認してください。" \
            13 62
    fi
}

while true
do
    CHOICE=$(whiptail \
        --title "System Menu" \
        --menu "システム操作を選択してください" \
        19 70 9 \
        1 "システム情報を表示" \
        2 "SVXLinkサービスを再起動" \
        3 "SVXLinkログを表示" \
        4 "システムを再起動" \
        5 "システムをシャットダウン" \
        0 "前の画面に戻る" \
        3>&1 1>&2 2>&3)

    RET=$?
    [ "$RET" -ne 0 ] && exit 0

    case "$CHOICE" in
        1)
            show_system_information
            ;;
        2)
            restart_svxlink_service
            ;;
        3)
            show_service_log
            ;;
        4)
            whiptail \
                --title "System Reboot" \
                --yesno \
"本体を再起動します。

SSH接続は切断されます。

実行しますか？" \
                14 60

            if [ $? -eq 0 ]; then
                sudo systemctl reboot
                exit 0
            fi
            ;;
        5)
            whiptail \
                --title "System Shutdown" \
                --yesno \
"本体をシャットダウンします。

電源を切れる状態になるまでお待ちください。

実行しますか？" \
                15 64

            if [ $? -eq 0 ]; then
                sudo systemctl poweroff
                exit 0
            fi
            ;;
        0)
            exit 0
            ;;
    esac
done
