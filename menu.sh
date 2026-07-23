#!/bin/bash

# ============================================================
# SVXLinkJP Main Menu
# Dialog TUI Version
# Version 2.0.0
#
# 対応:
#   Raspberry Pi OS / Debian 13
#
# 使用:
#   dialog
# ============================================================

set -u

# ------------------------------------------------------------
# プログラムの場所
# ------------------------------------------------------------

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

MODULE_DIR="${SCRIPT_DIR}/modules"

SYSTEM_SCRIPT="${MODULE_DIR}/system.sh"
ECHOLINK_SCRIPT="${MODULE_DIR}/echolink.sh"
RADIO_SCRIPT="${MODULE_DIR}/radio.sh"
NETWORK_SCRIPT="${MODULE_DIR}/network.sh"
BACKUP_SCRIPT="${MODULE_DIR}/backup.sh"
SETTINGS_SCRIPT="${MODULE_DIR}/settings.sh"

VERSION_FILE="${SCRIPT_DIR}/version"

SVXLINK_SERVICE="svxlink.service"
SVXLINK_INIT="/etc/init.d/svxlink"

# ------------------------------------------------------------
# 一時ファイル
# ------------------------------------------------------------

TEMP_DIR="/tmp/svxlinkjp"

mkdir -p "$TEMP_DIR"

MENU_RESULT="${TEMP_DIR}/menu_result.$$"

cleanup() {
    rm -f "$MENU_RESULT"
    clear
}

trap cleanup EXIT
trap cleanup INT TERM

# ------------------------------------------------------------
# dialog確認
# ------------------------------------------------------------

check_dialog() {
    if command -v dialog >/dev/null 2>&1; then
        return 0
    fi

    clear

    echo "dialogがインストールされていません。"
    echo
    echo "次のコマンドを実行してください。"
    echo
    echo "  sudo apt update"
    echo "  sudo apt install -y dialog"
    echo

    exit 1
}

# ------------------------------------------------------------
# バージョン取得
# ------------------------------------------------------------

get_version() {
    if [ -f "$VERSION_FILE" ]; then
        tr -d '\r\n' <"$VERSION_FILE"
    else
        echo "2.0.0"
    fi
}

# ------------------------------------------------------------
# IPアドレス取得
# ------------------------------------------------------------

get_interface_ipv4() {
    local interface_name="$1"
    local address="未接続"

    if command -v ip >/dev/null 2>&1; then
        address="$(
            ip -4 \
                -o \
                address \
                show \
                dev "$interface_name" \
                scope global 2>/dev/null |
            awk 'NR == 1 {print $4}'
        )"
    fi

    if [ -z "$address" ]; then
        address="未接続"
    fi

    echo "$address"
}

get_hostname_text() {
    hostname 2>/dev/null || echo "raspberrypi"
}

# ------------------------------------------------------------
# 権限付きコマンド実行
# ------------------------------------------------------------

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ------------------------------------------------------------
# メッセージ表示
# ------------------------------------------------------------

show_message() {
    local title="$1"
    local message="$2"

    dialog \
        --clear \
        --no-shadow \
        --title "$title" \
        --msgbox "$message" \
        12 66
}

show_error() {
    local message="$1"

    dialog \
        --clear \
        --no-shadow \
        --title "エラー" \
        --msgbox "$message" \
        12 70
}

show_information() {
    local message="$1"

    dialog \
        --clear \
        --no-shadow \
        --title "情報" \
        --msgbox "$message" \
        12 70
}

show_text_file() {
    local title="$1"
    local file="$2"

    if [ ! -f "$file" ]; then
        show_error "表示するファイルがありません。\n\n$file"
        return
    fi

    dialog \
        --clear \
        --no-shadow \
        --title "$title" \
        --textbox "$file" \
        22 78
}

# ------------------------------------------------------------
# モジュール実行
# ------------------------------------------------------------

run_module() {
    local module_file="$1"
    local module_name="$2"

    clear

    if [ ! -f "$module_file" ]; then
        show_error \
"${module_name}が見つかりません。

確認先:
${module_file}"
        return
    fi

    if [ ! -x "$module_file" ]; then
        chmod +x "$module_file" 2>/dev/null || true
    fi

    "$module_file"

    clear
}

# ------------------------------------------------------------
# SVXLinkサービス判定
# ------------------------------------------------------------

systemd_service_exists() {
    systemctl list-unit-files \
        --type=service \
        --no-legend 2>/dev/null |
    awk '{print $1}' |
    grep -qx "$SVXLINK_SERVICE"
}

init_service_exists() {
    [ -x "$SVXLINK_INIT" ]
}

svxlink_is_active() {
    if systemd_service_exists; then
        systemctl is-active \
            --quiet \
            "$SVXLINK_SERVICE"

        return $?
    fi

    if init_service_exists; then
        "$SVXLINK_INIT" status \
            >/dev/null 2>&1

        return $?
    fi

    pgrep -x svxlink \
        >/dev/null 2>&1
}

# ------------------------------------------------------------
# SVXLink起動
# ------------------------------------------------------------

start_svxlink() {
    local result_file="${TEMP_DIR}/start_result.$$"

    if ! command -v svxlink >/dev/null 2>&1; then
        show_error \
"SVXLink本体がインストールされていません。

Systemメニューから
SVXLink本体インストールを実行してください。"
        return
    fi

    if svxlink_is_active; then
        show_information "SVXLinkはすでに動作中です。"
        return
    fi

    dialog \
        --clear \
        --no-shadow \
        --title "SVXLink開始" \
        --yesno \
"SVXLinkサービスを開始します。

実行してよろしいですか？" \
        10 56

    if [ "$?" -ne 0 ]; then
        return
    fi

    if systemd_service_exists; then
        if run_as_root systemctl start \
            "$SVXLINK_SERVICE" \
            >"$result_file" 2>&1; then

            sleep 2

            if svxlink_is_active; then
                show_message \
                    "SVXLink開始" \
                    "SVXLinkを開始しました。"
            else
                run_as_root journalctl \
                    -u "$SVXLINK_SERVICE" \
                    -n 40 \
                    --no-pager \
                    >"$result_file" 2>&1 || true

                show_text_file \
                    "SVXLink起動エラー" \
                    "$result_file"
            fi
        else
            run_as_root journalctl \
                -u "$SVXLINK_SERVICE" \
                -n 40 \
                --no-pager \
                >"$result_file" 2>&1 || true

            show_text_file \
                "SVXLink起動エラー" \
                "$result_file"
        fi

    elif init_service_exists; then
        if run_as_root "$SVXLINK_INIT" start \
            >"$result_file" 2>&1; then

            show_message \
                "SVXLink開始" \
                "SVXLinkを開始しました。"
        else
            show_text_file \
                "SVXLink起動エラー" \
                "$result_file"
        fi

    else
        show_error \
"SVXLinkサービスが見つかりません。

確認対象:
${SVXLINK_SERVICE}
${SVXLINK_INIT}"
    fi

    rm -f "$result_file"
}

# ------------------------------------------------------------
# SVXLink停止
# ------------------------------------------------------------

stop_svxlink() {
    local result_file="${TEMP_DIR}/stop_result.$$"

    if ! svxlink_is_active; then
        show_information "SVXLinkはすでに停止しています。"
        return
    fi

    dialog \
        --clear \
        --no-shadow \
        --title "SVXLink停止" \
        --yesno \
"SVXLinkサービスを停止します。

実行してよろしいですか？" \
        10 56

    if [ "$?" -ne 0 ]; then
        return
    fi

    if systemd_service_exists; then
        if run_as_root systemctl stop \
            "$SVXLINK_SERVICE" \
            >"$result_file" 2>&1; then

            show_message \
                "SVXLink停止" \
                "SVXLinkを停止しました。"
        else
            show_text_file \
                "SVXLink停止エラー" \
                "$result_file"
        fi

    elif init_service_exists; then
        if run_as_root "$SVXLINK_INIT" stop \
            >"$result_file" 2>&1; then

            show_message \
                "SVXLink停止" \
                "SVXLinkを停止しました。"
        else
            show_text_file \
                "SVXLink停止エラー" \
                "$result_file"
        fi
    else
        show_error "SVXLinkサービスが見つかりません。"
    fi

    rm -f "$result_file"
}

# ------------------------------------------------------------
# SVXLink再起動
# ------------------------------------------------------------

restart_svxlink() {
    local result_file="${TEMP_DIR}/restart_result.$$"

    dialog \
        --clear \
        --no-shadow \
        --title "SVXLink再起動" \
        --yesno \
"SVXLinkサービスを再起動します。

実行してよろしいですか？" \
        10 56

    if [ "$?" -ne 0 ]; then
        return
    fi

    if systemd_service_exists; then
        run_as_root systemctl reset-failed \
            "$SVXLINK_SERVICE" \
            >/dev/null 2>&1 || true

        if run_as_root systemctl restart \
            "$SVXLINK_SERVICE" \
            >"$result_file" 2>&1; then

            sleep 2

            if svxlink_is_active; then
                show_message \
                    "SVXLink再起動" \
                    "SVXLinkを再起動しました。"
            else
                run_as_root journalctl \
                    -u "$SVXLINK_SERVICE" \
                    -n 40 \
                    --no-pager \
                    >"$result_file" 2>&1 || true

                show_text_file \
                    "SVXLink再起動エラー" \
                    "$result_file"
            fi
        else
            run_as_root journalctl \
                -u "$SVXLINK_SERVICE" \
                -n 40 \
                --no-pager \
                >"$result_file" 2>&1 || true

            show_text_file \
                "SVXLink再起動エラー" \
                "$result_file"
        fi

    elif init_service_exists; then
        if run_as_root "$SVXLINK_INIT" restart \
            >"$result_file" 2>&1; then

            show_message \
                "SVXLink再起動" \
                "SVXLinkを再起動しました。"
        else
            show_text_file \
                "SVXLink再起動エラー" \
                "$result_file"
        fi

    else
        show_error "SVXLinkサービスが見つかりません。"
    fi

    rm -f "$result_file"
}

# ------------------------------------------------------------
# アップデート
# ------------------------------------------------------------

update_svxlinkjp() {
    local update_log="${TEMP_DIR}/update_result.$$"

    dialog \
        --clear \
        --no-shadow \
        --title "SVXLinkJP Update" \
        --yesno \
"SVXLinkJPとSVXLinkパッケージの
更新確認を実行します。

実行してよろしいですか？" \
        11 60

    if [ "$?" -ne 0 ]; then
        return
    fi

    (
        echo "10"
        sleep 1

        echo "XXX"
        echo "10"
        echo "APTパッケージ情報を更新しています..."
        echo "XXX"

        run_as_root apt-get update \
            >"$update_log" 2>&1

        apt_result=$?

        echo "55"
        sleep 1

        echo "XXX"
        echo "55"
        echo "SVXLinkパッケージを確認しています..."
        echo "XXX"

        if [ "$apt_result" -eq 0 ]; then
            run_as_root apt-get install \
                --only-upgrade \
                -y \
                svxlink-server \
                svxlink-gpio \
                >>"$update_log" 2>&1
        fi

        echo "90"
        sleep 1

        echo "XXX"
        echo "90"
        echo "SVXLinkJPを確認しています..."
        echo "XXX"

        if [ -d "${SCRIPT_DIR}/.git" ] &&
           command -v git >/dev/null 2>&1; then

            git -C "$SCRIPT_DIR" pull \
                >>"$update_log" 2>&1 || true
        else
            echo \
                "Git管理ディレクトリではないためgit pullは省略しました。" \
                >>"$update_log"
        fi

        echo "100"
        sleep 1

    ) |
    dialog \
        --clear \
        --no-shadow \
        --title "Update" \
        --gauge \
        "更新処理を開始しています..." \
        10 65 0

    show_text_file \
        "アップデート結果" \
        "$update_log"

    rm -f "$update_log"
}

# ------------------------------------------------------------
# SVXLink基本設定
# ------------------------------------------------------------

open_svxlink_settings() {
    if [ -f "$SETTINGS_SCRIPT" ]; then
        run_module \
            "$SETTINGS_SCRIPT" \
            "SVXLink基本設定"
    else
        run_module \
            "$SYSTEM_SCRIPT" \
            "System設定"
    fi
}

# ------------------------------------------------------------
# メインメニュー
# ------------------------------------------------------------

main_menu() {
    local selection=""
    local hostname_text=""
    local eth0_ip=""
    local wlan0_ip=""
    local service_status=""
    local version=""

    while true; do
        hostname_text="$(get_hostname_text)"
        eth0_ip="$(get_interface_ipv4 eth0)"
        wlan0_ip="$(get_interface_ipv4 wlan0)"
        version="$(get_version)"

        if svxlink_is_active; then
            service_status="動作中"
        else
            service_status="停止中"
        fi

        dialog \
            --clear \
            --no-shadow \
            --ok-label "選択" \
            --cancel-label "終了" \
            --backtitle \
"SVXLinkJP Ver.${version}  Host:${hostname_text}
eth0: ${eth0_ip}    wlan0: ${wlan0_ip}
SVXLink: ${service_status}" \
            --title "SVXLinkJP Main Menu" \
            --menu \
"操作を選択してください。" \
            22 78 13 \
            1  "SVXLink Settings   基本設定" \
            2  "EchoLink Settings  EchoLink設定" \
            3  "Radio Settings     無線機・音声設定" \
            4  "Network Settings   IP・Wi-Fi・バックアップ" \
            5  "System Backup      システムバックアップ・復元" \
            6  "Update             更新機能" \
            7  "System             状態・ログ・再起動" \
            8  "Restart SVXLink    SVXLinkサービス再起動" \
            9  "Stop SVXLink       SVXLinkサービス停止" \
            10 "Start SVXLink      SVXLinkサービス開始" \
            0  "Exit               終了" \
            2>"$MENU_RESULT"

        dialog_result=$?

        if [ "$dialog_result" -ne 0 ]; then
            break
        fi

        selection="$(cat "$MENU_RESULT")"

        case "$selection" in
            1)
                open_svxlink_settings
                ;;

            2)
                run_module \
                    "$ECHOLINK_SCRIPT" \
                    "EchoLink設定"
                ;;

            3)
                run_module \
                    "$RADIO_SCRIPT" \
                    "Radio設定"
                ;;

            4)
                run_module \
                    "$NETWORK_SCRIPT" \
                    "Network設定"
                ;;

            5)
                run_module \
                    "$BACKUP_SCRIPT" \
                    "System Backup"
                ;;

            6)
                update_svxlinkjp
                ;;

            7)
                run_module \
                    "$SYSTEM_SCRIPT" \
                    "System設定"
                ;;

            8)
                restart_svxlink
                ;;

            9)
                stop_svxlink
                ;;

            10)
                start_svxlink
                ;;

            0)
                break
                ;;

            *)
                show_error \
                    "正しい項目を選択してください。"
                ;;
        esac
    done
}

# ------------------------------------------------------------
# 起動
# ------------------------------------------------------------

check_dialog
main_menu

exit 0
