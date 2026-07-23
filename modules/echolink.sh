#!/bin/bash

# ============================================================
# SVXLinkJP EchoLink Configuration Module
# Version 1.2.0
#
# 設定ファイル:
#   /etc/svxlink/svxlink.d/ModuleEchoLink.conf
#
# 機能:
#   ・コールサイン設定
#   ・パスワード設定（画面非表示）
#   ・管理者名、設置場所、説明文設定
#   ・EchoLinkサーバー設定
#   ・MAX_QSOS設定
#   ・設定保存、バックアップ
#   ・ModuleEchoLink有効化
#   ・SVXLink再起動
# ============================================================

set -u

ECHOLINK_CONFIG="/etc/svxlink/svxlink.d/ModuleEchoLink.conf"
SVXLINK_CONFIG="/etc/svxlink/svxlink.conf"

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# ------------------------------------------------------------
# 初期値
# ------------------------------------------------------------

CALLSIGN=""
PASSWORD=""
SYSOPNAME=""
LOCATION=""
DESCRIPTION=""
SERVERS="servers.echolink.org"
MAX_QSOS="2"

MODULE_ID="2"
MODULE_TIMEOUT="60"

PASSWORD_CHANGED=0
CONFIG_CHANGED=0

# ------------------------------------------------------------
# 共通表示
# ------------------------------------------------------------

print_ok() {
    echo -e "${GREEN}[ OK ]${RESET} $1"
}

print_ng() {
    echo -e "${RED}[ NG ]${RESET} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${RESET} $1"
}

print_title() {
    clear
    echo "============================================================"
    echo "                $1"
    echo "============================================================"
    echo
}

pause_screen() {
    echo
    read -r -p "Enterキーを押してください..."
}

confirm_action() {
    local message="$1"
    local answer=""

    echo
    read -r -p "$message [y/N]: " answer

    case "$answer" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ------------------------------------------------------------
# 管理者権限
# ------------------------------------------------------------

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ------------------------------------------------------------
# 設定値読み取り
# ------------------------------------------------------------

read_config_value() {
    local file="$1"
    local key="$2"

    [ -f "$file" ] || {
        echo ""
        return
    }

    awk -F= -v wanted_key="$key" '
        /^[[:space:]]*[#;]/ {
            next
        }

        {
            key = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)

            if (key == wanted_key) {
                value = substr($0, index($0, "=") + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)

                if (
                    value ~ /^".*"$/ ||
                    value ~ /^\047.*\047$/
                ) {
                    value = substr(value, 2, length(value) - 2)
                }

                print value
                exit
            }
        }
    ' "$file"
}

load_configuration() {
    local value=""

    [ -f "$ECHOLINK_CONFIG" ] || return 0

    value="$(read_config_value "$ECHOLINK_CONFIG" "CALLSIGN")"
    [ -n "$value" ] && CALLSIGN="$value"

    value="$(read_config_value "$ECHOLINK_CONFIG" "PASSWORD")"
    [ -n "$value" ] && PASSWORD="$value"

    value="$(read_config_value "$ECHOLINK_CONFIG" "SYSOPNAME")"
    [ -n "$value" ] && SYSOPNAME="$value"

    value="$(read_config_value "$ECHOLINK_CONFIG" "LOCATION")"
    [ -n "$value" ] && LOCATION="$value"

    value="$(read_config_value "$ECHOLINK_CONFIG" "DESCRIPTION")"
    [ -n "$value" ] && DESCRIPTION="$value"

    value="$(read_config_value "$ECHOLINK_CONFIG" "SERVERS")"
    [ -n "$value" ] && SERVERS="$value"

    value="$(read_config_value "$ECHOLINK_CONFIG" "MAX_QSOS")"
    [ -n "$value" ] && MAX_QSOS="$value"

    value="$(read_config_value "$ECHOLINK_CONFIG" "ID")"
    [ -n "$value" ] && MODULE_ID="$value"

    value="$(read_config_value "$ECHOLINK_CONFIG" "TIMEOUT")"
    [ -n "$value" ] && MODULE_TIMEOUT="$value"
}

# ------------------------------------------------------------
# 入力文字列処理
# ------------------------------------------------------------

remove_line_breaks() {
    printf '%s' "$1" |
        tr -d '\r\n'
}

valid_callsign() {
    local callsign="$1"

    [[ "$callsign" =~ ^[A-Z0-9/]{3,10}(-[LR])?$ ]]
}

valid_positive_number() {
    [[ "$1" =~ ^[0-9]+$ ]] &&
        [ "$1" -ge 1 ] &&
        [ "$1" -le 99 ]
}

# ------------------------------------------------------------
# 現在設定表示
# ------------------------------------------------------------

show_current_settings() {
    print_title "EchoLink Current Settings"

    printf "%-20s : %s\n" \
        "コールサイン" \
        "${CALLSIGN:-未設定}"

    if [ -n "$PASSWORD" ]; then
        printf "%-20s : %s\n" \
            "パスワード" \
            "設定済み（非表示）"
    else
        printf "%-20s : %s\n" \
            "パスワード" \
            "未設定"
    fi

    printf "%-20s : %s\n" \
        "管理者名" \
        "${SYSOPNAME:-未設定}"

    printf "%-20s : %s\n" \
        "設置場所" \
        "${LOCATION:-未設定}"

    printf "%-20s : %s\n" \
        "説明文" \
        "${DESCRIPTION:-未設定}"

    printf "%-20s : %s\n" \
        "サーバー" \
        "${SERVERS:-未設定}"

    printf "%-20s : %s\n" \
        "最大接続数" \
        "$MAX_QSOS"

    printf "%-20s : %s\n" \
        "モジュールID" \
        "$MODULE_ID"

    printf "%-20s : %s\n" \
        "タイムアウト" \
        "${MODULE_TIMEOUT}秒"

    echo
    echo "設定ファイル"
    echo "------------------------------------------------------------"
    echo "$ECHOLINK_CONFIG"

    if [ "$CONFIG_CHANGED" -eq 1 ]; then
        echo
        print_info "まだ保存されていない変更があります。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# コールサイン設定
# ------------------------------------------------------------

set_callsign() {
    local input=""

    print_title "EchoLink Callsign Setting"

    echo "現在のコールサイン:"
    echo
    echo "  ${CALLSIGN:-未設定}"
    echo
    echo "EchoLinkに登録したコールサインを入力してください。"
    echo
    echo "リンク局の例:"
    echo "  JQ1ABC-L"
    echo
    echo "リピーター局の例:"
    echo "  JQ1ABC-R"
    echo

    read -r -p "コールサイン: " input

    input="$(
        remove_line_breaks "$input" |
            tr '[:lower:]' '[:upper:]'
    )"

    if [ -z "$input" ]; then
        print_info "変更しませんでした。"
        pause_screen
        return
    fi

    if ! valid_callsign "$input"; then
        print_ng "コールサインの形式が正しくありません。"
        echo
        echo "例: JQ1ABC-L または JQ1ABC-R"
        pause_screen
        return
    fi

    CALLSIGN="$input"
    CONFIG_CHANGED=1

    print_ok "コールサインを設定しました。"
    echo
    echo "  $CALLSIGN"

    pause_screen
}

# ------------------------------------------------------------
# パスワード設定
# ------------------------------------------------------------

set_password() {
    local input1=""
    local input2=""

    print_title "EchoLink Password Setting"

    echo "EchoLinkディレクトリサーバー用パスワードを設定します。"
    echo
    echo "入力中の文字は画面に表示されません。"
    echo "空欄でEnterを押すと、現在のパスワードを保持します。"
    echo

    read -r -s -p "新しいパスワード: " input1
    echo

    if [ -z "$input1" ]; then
        print_info "現在のパスワードを保持します。"
        pause_screen
        return
    fi

    read -r -s -p "確認のため再入力: " input2
    echo

    if [ "$input1" != "$input2" ]; then
        print_ng "パスワードが一致しません。"
        pause_screen
        return
    fi

    if [ "${#input1}" -lt 3 ]; then
        print_ng "パスワードが短すぎます。"
        pause_screen
        return
    fi

    PASSWORD="$input1"
    PASSWORD_CHANGED=1
    CONFIG_CHANGED=1

    print_ok "パスワードを設定しました。"
    echo
    echo "安全のためパスワードは表示しません。"

    pause_screen
}

# ------------------------------------------------------------
# 管理者名
# ------------------------------------------------------------

set_sysop_name() {
    local input=""

    print_title "EchoLink Sysop Name Setting"

    echo "現在の管理者名:"
    echo
    echo "  ${SYSOPNAME:-未設定}"
    echo

    read -r -p "管理者名またはクラブ名: " input
    input="$(remove_line_breaks "$input")"

    if [ -z "$input" ]; then
        print_info "変更しませんでした。"
        pause_screen
        return
    fi

    SYSOPNAME="$input"
    CONFIG_CHANGED=1

    print_ok "管理者名を設定しました。"
    pause_screen
}

# ------------------------------------------------------------
# 設置場所
# ------------------------------------------------------------

set_location() {
    local input=""

    print_title "EchoLink Location Setting"

    echo "現在の設置場所:"
    echo
    echo "  ${LOCATION:-未設定}"
    echo
    echo "例:"
    echo "  [Svx] Tsuru, Yamanashi"
    echo

    read -r -p "設置場所: " input
    input="$(remove_line_breaks "$input")"

    if [ -z "$input" ]; then
        print_info "変更しませんでした。"
        pause_screen
        return
    fi

    LOCATION="$input"
    CONFIG_CHANGED=1

    print_ok "設置場所を設定しました。"
    pause_screen
}

# ------------------------------------------------------------
# 説明文
# ------------------------------------------------------------

set_description() {
    local input=""

    print_title "EchoLink Description Setting"

    echo "現在の説明文:"
    echo
    echo "  ${DESCRIPTION:-未設定}"
    echo
    echo "例:"
    echo "  144.560MHz FM Link Station"
    echo

    read -r -p "説明文: " input
    input="$(remove_line_breaks "$input")"

    if [ -z "$input" ]; then
        print_info "変更しませんでした。"
        pause_screen
        return
    fi

    DESCRIPTION="$input"
    CONFIG_CHANGED=1

    print_ok "説明文を設定しました。"
    pause_screen
}

# ------------------------------------------------------------
# サーバー設定
# ------------------------------------------------------------

set_servers() {
    local input=""

    print_title "EchoLink Server Setting"

    echo "現在のサーバー:"
    echo
    echo "  $SERVERS"
    echo
    echo "通常は次のままで使用できます。"
    echo
    echo "  servers.echolink.org"
    echo
    echo "複数指定するときは空白で区切ります。"
    echo

    read -r -p "サーバー [$SERVERS]: " input
    input="$(remove_line_breaks "$input")"

    if [ -z "$input" ]; then
        print_info "現在の設定を保持します。"
        pause_screen
        return
    fi

    SERVERS="$input"
    CONFIG_CHANGED=1

    print_ok "EchoLinkサーバーを設定しました。"
    pause_screen
}

# ------------------------------------------------------------
# MAX_QSOS設定
# ------------------------------------------------------------

set_max_qsos() {
    local input=""

    print_title "EchoLink MAX_QSOS Setting"

    echo "現在の最大接続数:"
    echo
    echo "  $MAX_QSOS"
    echo
    echo "通常の個人リンク局では1～2程度を推奨します。"
    echo

    read -r -p "最大接続数 [1-99]: " input

    if [ -z "$input" ]; then
        print_info "現在の設定を保持します。"
        pause_screen
        return
    fi

    if ! valid_positive_number "$input"; then
        print_ng "1～99の数字を入力してください。"
        pause_screen
        return
    fi

    MAX_QSOS="$input"
    CONFIG_CHANGED=1

    print_ok "最大接続数を設定しました。"
    pause_screen
}

# ------------------------------------------------------------
# 設定診断
# ------------------------------------------------------------

configuration_diagnosis() {
    local error_count=0
    local first_server=""

    print_title "EchoLink Configuration Diagnosis"

    if [ -n "$CALLSIGN" ] && valid_callsign "$CALLSIGN"; then
        print_ok "コールサイン: $CALLSIGN"
    else
        print_ng "コールサインが未設定または形式不正です。"
        error_count=$((error_count + 1))
    fi

    if [ -n "$PASSWORD" ]; then
        print_ok "パスワード設定済み"
    else
        print_ng "パスワードが未設定です。"
        error_count=$((error_count + 1))
    fi

    if [ -n "$SYSOPNAME" ]; then
        print_ok "管理者名: $SYSOPNAME"
    else
        print_info "管理者名が未設定です。"
    fi

    if [ -n "$LOCATION" ]; then
        print_ok "設置場所: $LOCATION"
    else
        print_info "設置場所が未設定です。"
    fi

    if [ -n "$SERVERS" ]; then
        print_ok "サーバー: $SERVERS"
    else
        print_ng "サーバーが未設定です。"
        error_count=$((error_count + 1))
    fi

    if valid_positive_number "$MAX_QSOS"; then
        print_ok "MAX_QSOS: $MAX_QSOS"
    else
        print_ng "MAX_QSOSの設定が不正です。"
        error_count=$((error_count + 1))
    fi

    echo
    echo "サーバー名前解決"
    echo "------------------------------------------------------------"

    first_server="${SERVERS%% *}"

    if [ -n "$first_server" ] &&
       getent hosts "$first_server" >/dev/null 2>&1; then

        print_ok "$first_server"
        getent hosts "$first_server" |
            head -n 3
    else
        print_ng "$first_server を名前解決できません。"
        error_count=$((error_count + 1))
    fi

    echo
    echo "診断結果"
    echo "------------------------------------------------------------"

    if [ "$error_count" -eq 0 ]; then
        print_ok "EchoLink基本設定は正常です。"
    else
        print_ng "$error_count 件の修正が必要です。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 設定ファイル作成
# ------------------------------------------------------------

create_configuration_file() {
    local temporary_file="$1"

    cat >"$temporary_file" <<EOF
[ModuleEchoLink]
NAME=EchoLink
ID=${MODULE_ID}
TIMEOUT=${MODULE_TIMEOUT}
SERVERS=${SERVERS}
CALLSIGN=${CALLSIGN}
PASSWORD=${PASSWORD}
SYSOPNAME=${SYSOPNAME}
LOCATION=${LOCATION}
DESCRIPTION=${DESCRIPTION}
MAX_QSOS=${MAX_QSOS}
MAX_CONNECTIONS=$((MAX_QSOS + 1))
EOF
}

save_configuration() {
    local temporary_file=""
    local backup_file=""

    print_title "Save EchoLink Configuration"

    if [ -z "$CALLSIGN" ] || ! valid_callsign "$CALLSIGN"; then
        print_ng "正しいコールサインを設定してください。"
        pause_screen
        return
    fi

    if [ -z "$PASSWORD" ]; then
        print_ng "パスワードを設定してください。"
        pause_screen
        return
    fi

    if [ -z "$SERVERS" ]; then
        print_ng "EchoLinkサーバーを設定してください。"
        pause_screen
        return
    fi

    echo "次のファイルへ保存します。"
    echo
    echo "  $ECHOLINK_CONFIG"
    echo
    echo "コールサイン : $CALLSIGN"
    echo "パスワード   : 設定済み（非表示）"
    echo "管理者名     : ${SYSOPNAME:-未設定}"
    echo "設置場所     : ${LOCATION:-未設定}"
    echo "最大接続数   : $MAX_QSOS"

    if ! confirm_action "この内容で保存しますか？"; then
        print_info "保存を中止しました。"
        pause_screen
        return
    fi

    temporary_file="$(mktemp)"

    if ! create_configuration_file "$temporary_file"; then
        rm -f "$temporary_file"
        print_ng "一時設定ファイルを作成できませんでした。"
        pause_screen
        return
    fi

    if [ -f "$ECHOLINK_CONFIG" ]; then
        backup_file="${ECHOLINK_CONFIG}.backup.$(
            date +%Y%m%d-%H%M%S
        )"

        if run_as_root cp -a \
            "$ECHOLINK_CONFIG" \
            "$backup_file"; then

            print_ok "既存設定をバックアップしました。"
            echo "  $backup_file"
        else
            rm -f "$temporary_file"
            print_ng "バックアップに失敗しました。"
            pause_screen
            return
        fi
    fi

    if ! run_as_root mkdir -p \
        "$(dirname "$ECHOLINK_CONFIG")"; then

        rm -f "$temporary_file"
        print_ng "設定ディレクトリを作成できませんでした。"
        pause_screen
        return
    fi

    if run_as_root install \
        -m 640 \
        "$temporary_file" \
        "$ECHOLINK_CONFIG"; then

        print_ok "EchoLink設定を保存しました。"
    else
        rm -f "$temporary_file"
        print_ng "EchoLink設定の保存に失敗しました。"
        pause_screen
        return
    fi

    rm -f "$temporary_file"

    if getent group svxlink >/dev/null 2>&1; then
        run_as_root chown \
            root:svxlink \
            "$ECHOLINK_CONFIG" ||
            true
    else
        run_as_root chown \
            root:root \
            "$ECHOLINK_CONFIG" ||
            true
    fi

    CONFIG_CHANGED=0
    PASSWORD_CHANGED=0

    echo
    print_info "次に「9 ModuleEchoLink有効化」を確認してください。"

    pause_screen
}

# ------------------------------------------------------------
# svxlink.conf内のModuleEchoLink確認
# ------------------------------------------------------------

module_is_enabled() {
    [ -f "$SVXLINK_CONFIG" ] || return 1

    grep -E \
        '^[[:space:]]*MODULES[[:space:]]*=.*(^|,)[[:space:]]*ModuleEchoLink([[:space:]]*,|[[:space:]]*$)' \
        "$SVXLINK_CONFIG" \
        >/dev/null 2>&1
}

show_module_status() {
    print_title "ModuleEchoLink Registration"

    if [ ! -f "$SVXLINK_CONFIG" ]; then
        print_ng "$SVXLINK_CONFIG がありません。"
        echo
        echo "先にSystemメニューからSVXLink本体を"
        echo "インストールしてください。"
        pause_screen
        return
    fi

    echo "MODULES設定"
    echo "------------------------------------------------------------"

    grep -nE \
        '^[[:space:]]*MODULES[[:space:]]*=' \
        "$SVXLINK_CONFIG" ||
        echo "MODULES行が見つかりません。"

    echo

    if grep -q 'ModuleEchoLink' "$SVXLINK_CONFIG"; then
        print_ok "ModuleEchoLinkの記述があります。"
    else
        print_ng "ModuleEchoLinkが登録されていません。"
    fi

    echo
    echo "注意:"
    echo "MODULESは通常、[SimplexLogic]または"
    echo "[RepeaterLogic]セクション内にあります。"

    pause_screen
}

# ------------------------------------------------------------
# SVXLink再起動
# ------------------------------------------------------------

restart_svxlink() {
    print_title "Restart SVXLink"

    if systemctl list-unit-files \
        --type=service \
        --no-legend 2>/dev/null |
        awk '{print $1}' |
        grep -qx 'svxlink.service'; then

        if run_as_root systemctl restart svxlink.service; then
            sleep 2

            if systemctl is-active \
                --quiet \
                svxlink.service; then

                print_ok "SVXLinkを再起動しました。"
            else
                print_ng "再起動後、SVXLinkは停止状態です。"
                echo
                run_as_root journalctl \
                    -u svxlink.service \
                    -n 30 \
                    --no-pager
            fi
        else
            print_ng "SVXLinkの再起動に失敗しました。"
        fi

    elif [ -x /etc/init.d/svxlink ]; then

        if run_as_root /etc/init.d/svxlink restart; then
            print_ok "SVXLinkを再起動しました。"
        else
            print_ng "SVXLinkの再起動に失敗しました。"
        fi

    else
        print_ng "SVXLink起動サービスが見つかりません。"
        echo
        echo "先にSystemメニューからSVXLink本体を"
        echo "インストールしてください。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# ログ表示
# ------------------------------------------------------------

show_echolink_log() {
    print_title "EchoLink Log"

    if systemctl list-unit-files \
        --type=service \
        --no-legend 2>/dev/null |
        awk '{print $1}' |
        grep -qx 'svxlink.service'; then

        run_as_root journalctl \
            -u svxlink.service \
            -n 200 \
            --no-pager |
            grep -iE \
                'echolink|directory|login|callsign|connect|error|warning' ||
            echo "EchoLink関連ログはありません。"

    elif [ -f /var/log/syslog ]; then

        grep -iE \
            'svxlink.*(echolink|directory|login|connect|error)' \
            /var/log/syslog |
            tail -n 100 ||
            echo "EchoLink関連ログはありません。"

    else
        journalctl \
            -n 500 \
            --no-pager 2>/dev/null |
            grep -iE \
                'svxlink.*(echolink|directory|login|connect|error)' ||
            echo "EchoLink関連ログはありません。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# メニュー
# ------------------------------------------------------------

main_menu() {
    local choice=""

    load_configuration

    while true; do
        clear

        echo "============================================================"
        echo "                    EchoLink Menu"
        echo "============================================================"
        echo
        echo " 1  コールサイン設定"
        echo " 2  パスワード設定"
        echo " 3  管理者名・クラブ名設定"
        echo " 4  設置場所設定"
        echo " 5  説明文設定"
        echo " 6  EchoLinkサーバー設定"
        echo " 7  最大接続数 MAX_QSOS設定"
        echo " 8  現在の設定表示"
        echo " 9  ModuleEchoLink登録確認"
        echo "10  設定診断"
        echo "11  設定を保存"
        echo "12  SVXLink再起動"
        echo "13  EchoLinkログ表示"
        echo
        echo " 0  戻る"
        echo
        echo "============================================================"
        echo

        printf "コールサイン : %s\n" \
            "${CALLSIGN:-未設定}"

        if [ -n "$PASSWORD" ]; then
            echo "パスワード   : 設定済み"
        else
            echo "パスワード   : 未設定"
        fi

        if [ "$CONFIG_CHANGED" -eq 1 ]; then
            echo
            echo -e "${YELLOW}未保存の変更があります。${RESET}"
        fi

        echo
        read -r -p "選択してください [0-13]: " choice

        case "$choice" in
            1)
                set_callsign
                ;;
            2)
                set_password
                ;;
            3)
                set_sysop_name
                ;;
            4)
                set_location
                ;;
            5)
                set_description
                ;;
            6)
                set_servers
                ;;
            7)
                set_max_qsos
                ;;
            8)
                show_current_settings
                ;;
            9)
                show_module_status
                ;;
            10)
                configuration_diagnosis
                ;;
            11)
                save_configuration
                ;;
            12)
                restart_svxlink
                ;;
            13)
                show_echolink_log
                ;;
            0)
                if [ "$CONFIG_CHANGED" -eq 1 ]; then
                    if confirm_action \
                        "未保存の変更があります。保存せず戻りますか？"; then
                        return 0
                    fi
                else
                    return 0
                fi
                ;;
            *)
                print_ng "0～13の番号を入力してください。"
                sleep 1
                ;;
        esac
    done
}

main_menu
