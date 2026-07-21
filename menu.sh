#!/bin/bash

###############################################################################
# SVXLink JP Edition
# JQ1YOF Radio Controller
# 青色管理メニュー
###############################################################################

TITLE="SVXLink JP Edition"
BACKTITLE="JQ1YOF Radio Controller"

SVXLINK_SERVICE="svxlink"
SVXLINK_CONF="/etc/svxlink/svxlink.conf"
ECHOLINK_CONF="/etc/svxlink/svxlink.d/ModuleEchoLink.conf"
SVXLINK_LOG="/var/log/svxlink"


###############################################################################
# サービス状態取得
###############################################################################

get_svxlink_status()
{
    if systemctl is-active --quiet "$SVXLINK_SERVICE"; then
        echo "動作中"
    else
        echo "停止中"
    fi
}


###############################################################################
# EchoLink状態取得
###############################################################################

get_echolink_status()
{
    if ! systemctl is-active --quiet "$SVXLINK_SERVICE"; then
        echo "SVXLink停止中"
        return
    fi

    if sudo grep -qiE \
        "EchoLink directory status changed to ON|EchoLink Server" \
        "$SVXLINK_LOG" 2>/dev/null; then
        echo "接続中"
    elif sudo grep -qi \
        "INCORRECT PASSWORD" \
        "$SVXLINK_LOG" 2>/dev/null; then
        echo "パスワードエラー"
    else
        echo "確認中"
    fi
}


###############################################################################
# IPアドレス取得
###############################################################################

get_ip_address()
{
    hostname -I 2>/dev/null | awk '{print $1}'
}


###############################################################################
# メッセージ表示
###############################################################################

show_message()
{
    local message="$1"

    whiptail \
        --title "$TITLE" \
        --backtitle "$BACKTITLE" \
        --msgbox "$message" \
        12 64
}


###############################################################################
# SVXLink開始
###############################################################################

start_svxlink()
{
    sudo systemctl start "$SVXLINK_SERVICE"
    sleep 2

    if systemctl is-active --quiet "$SVXLINK_SERVICE"; then
        show_message "SVXLinkを開始しました。\n\n状態：動作中"
    else
        show_message "SVXLinkを開始できませんでした。\n\nログを確認してください。"
    fi
}


###############################################################################
# SVXLink停止
###############################################################################

stop_svxlink()
{
    if whiptail \
        --title "SVXLink停止" \
        --backtitle "$BACKTITLE" \
        --yesno "SVXLinkとEchoLinkを停止しますか？" \
        10 60
    then
        sudo systemctl stop "$SVXLINK_SERVICE"
        sleep 1
        show_message "SVXLinkを停止しました。"
    fi
}


###############################################################################
# SVXLink再起動
###############################################################################

restart_svxlink()
{
    sudo systemctl restart "$SVXLINK_SERVICE"
    sleep 3

    if systemctl is-active --quiet "$SVXLINK_SERVICE"; then
        show_message "SVXLinkを再起動しました。\n\n状態：動作中"
    else
        show_message "SVXLinkの再起動に失敗しました。\n\nログを確認してください。"
    fi
}


###############################################################################
# SVXLink・EchoLink状態表示
###############################################################################

show_status()
{
    local svx_status
    local echo_status
    local ip_address
    local boot_status

    svx_status="$(get_svxlink_status)"
    echo_status="$(get_echolink_status)"
    ip_address="$(get_ip_address)"

    if systemctl is-enabled --quiet "$SVXLINK_SERVICE" 2>/dev/null; then
        boot_status="有効"
    else
        boot_status="無効"
    fi

    whiptail \
        --title "システム状態" \
        --backtitle "$BACKTITLE" \
        --msgbox \
"SVXLink JP Edition

コールサイン       ：JQ1YOF-R
SVXLink            ：${svx_status}
EchoLink           ：${echo_status}
自動起動           ：${boot_status}
IPアドレス         ：${ip_address:-取得できません}

設定ファイル
${SVXLINK_CONF}

EchoLink設定
${ECHOLINK_CONF}" \
        20 72
}


###############################################################################
# EchoLinkログ表示
###############################################################################

show_echolink_log()
{
    local temp_file

    temp_file="$(mktemp)"

    sudo grep -Ei \
        "EchoLink|directory|server|password|connected|disconnected|error|warning" \
        "$SVXLINK_LOG" 2>/dev/null |
        tail -n 100 > "$temp_file"

    if [ ! -s "$temp_file" ]; then
        echo "EchoLinkに関するログはまだありません。" > "$temp_file"
    fi

    whiptail \
        --title "EchoLinkログ" \
        --backtitle "$BACKTITLE" \
        --scrolltext \
        --textbox "$temp_file" \
        24 90

    rm -f "$temp_file"
}


###############################################################################
# SVXLinkログ表示
###############################################################################

show_svxlink_log()
{
    local temp_file

    temp_file="$(mktemp)"

    if [ -f "$SVXLINK_LOG" ]; then
        sudo tail -n 150 "$SVXLINK_LOG" > "$temp_file"
    else
        sudo journalctl \
            -u "$SVXLINK_SERVICE" \
            -n 150 \
            --no-pager > "$temp_file"
    fi

    whiptail \
        --title "SVXLinkログ" \
        --backtitle "$BACKTITLE" \
        --scrolltext \
        --textbox "$temp_file" \
        25 100

    rm -f "$temp_file"
}


###############################################################################
# リアルタイムログ
###############################################################################

show_live_log()
{
    clear

    echo "======================================================"
    echo " SVXLink リアルタイムログ"
    echo " 終了するときは Ctrl+C を押してください"
    echo "======================================================"
    echo

    if [ -f "$SVXLINK_LOG" ]; then
        sudo tail -f "$SVXLINK_LOG"
    else
        sudo journalctl -u "$SVXLINK_SERVICE" -f
    fi

    echo
    read -r -p "Enterキーでメニューへ戻ります..."
}


###############################################################################
# 設定ファイル編集
###############################################################################

edit_svxlink_conf()
{
    clear
    sudo nano "$SVXLINK_CONF"
}


###############################################################################
# EchoLink設定編集
###############################################################################

edit_echolink_conf()
{
    clear
    sudo nano "$ECHOLINK_CONF"
}


###############################################################################
# 音量調整
###############################################################################

audio_mixer()
{
    clear
    alsamixer -c 2
}


###############################################################################
# 自動起動有効化
###############################################################################

enable_autostart()
{
    sudo systemctl enable "$SVXLINK_SERVICE"

    if systemctl is-enabled --quiet "$SVXLINK_SERVICE"; then
        show_message "SVXLinkの電源投入時自動起動を有効にしました。"
    else
        show_message "自動起動の設定に失敗しました。"
    fi
}


###############################################################################
# メインメニュー
###############################################################################

while true
do
    SVX_STATUS="$(get_svxlink_status)"
    ECHO_STATUS="$(get_echolink_status)"
    IP_ADDRESS="$(get_ip_address)"

    CHOICE=$(whiptail \
        --title "$TITLE" \
        --backtitle "$BACKTITLE" \
        --menu \
"コールサイン：JQ1YOF-R
SVXLink：${SVX_STATUS}    EchoLink：${ECHO_STATUS}
IPアドレス：${IP_ADDRESS:-未取得}

カーソルキーで選択し、Enterキーを押してください。" \
        23 76 12 \
        "1" "SVXLink・EchoLink状態表示" \
        "2" "SVXLink開始" \
        "3" "SVXLink停止" \
        "4" "SVXLink再起動" \
        "5" "EchoLinkログ表示" \
        "6" "SVXLinkログ表示" \
        "7" "リアルタイムログ表示" \
        "8" "音量調整（USB Audio card 2）" \
        "9" "svxlink.conf編集" \
        "10" "EchoLink設定編集" \
        "11" "電源投入時の自動起動を有効化" \
        "0" "メニューを終了" \
        3>&1 1>&2 2>&3)

    EXIT_STATUS=$?

    if [ "$EXIT_STATUS" -ne 0 ]; then
        clear
        exit 0
    fi

    case "$CHOICE" in
        1)
            show_status
            ;;
        2)
            start_svxlink
            ;;
        3)
            stop_svxlink
            ;;
        4)
            restart_svxlink
            ;;
        5)
            show_echolink_log
            ;;
        6)
            show_svxlink_log
            ;;
        7)
            show_live_log
            ;;
        8)
            audio_mixer
            ;;
        9)
            edit_svxlink_conf
            ;;
        10)
            edit_echolink_conf
            ;;
        11)
            enable_autostart
            ;;
        0)
            clear
            echo "SVXLink JP Editionを終了しました。"
            exit 0
            ;;
    esac
done
