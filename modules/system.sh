#!/bin/bash

# ============================================================
# SVXLinkJP System Management Module
# Version 1.2.0
#
# 対応:
#   Debian 13 / Raspberry Pi
#   svxlink-server
#   svxlink-gpio
#
# 機能:
#   ・システム情報
#   ・SVXLink本体のインストール
#   ・SVXLink更新
#   ・起動、停止、再起動
#   ・ログ表示
#   ・設定確認
#   ・EchoLink設定確認
#   ・GPIO確認
#   ・ネットワーク確認
#   ・総合診断
# ============================================================

set -u

# ------------------------------------------------------------
# 基本設定
# ------------------------------------------------------------

SVXLINK_COMMAND="svxlink"
SVXLINK_PACKAGE="svxlink-server"
GPIO_PACKAGE="svxlink-gpio"

SVXLINK_CONFIG="/etc/svxlink/svxlink.conf"
ECHOLINK_CONFIG="/etc/svxlink/svxlink.d/ModuleEchoLink.conf"
GPIO_CONFIG="/etc/svxlink/gpio.conf"

SVXLINK_INIT="/etc/init.d/svxlink"
GPIO_SERVICE="svxlink_gpio_setup.service"

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# ------------------------------------------------------------
# 共通関数
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
    echo "                  $1"
    echo "============================================================"
    echo
}

pause_screen() {
    echo
    read -r -p "Enterキーを押してください..."
}

confirm_action() {
    local message="$1"
    local answer

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

require_root() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    print_info "この操作には管理者権限が必要です。"
    echo
    echo "管理者権限へ切り替えます。"
    echo

    exec sudo -E "$0" "$@"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

package_installed() {
    dpkg-query -W \
        -f='${db:Status-Abbrev}' \
        "$1" 2>/dev/null |
        grep -q '^ii'
}

# ------------------------------------------------------------
# SVXLinkサービス検出
#
# Debianパッケージは /etc/init.d/svxlink を提供する場合があるため、
# systemdとSysV initの両方を確認します。
# ------------------------------------------------------------

systemd_svxlink_exists() {
    systemctl list-unit-files \
        --type=service \
        --no-legend 2>/dev/null |
        awk '{print $1}' |
        grep -qx 'svxlink.service'
}

init_svxlink_exists() {
    [ -x "$SVXLINK_INIT" ]
}

svxlink_service_exists() {
    systemd_svxlink_exists || init_svxlink_exists
}

svxlink_is_active() {
    if systemd_svxlink_exists; then
        systemctl is-active \
            --quiet \
            svxlink.service
        return $?
    fi

    if init_svxlink_exists; then
        "$SVXLINK_INIT" status \
            >/dev/null 2>&1
        return $?
    fi

    pgrep -x svxlink \
        >/dev/null 2>&1
}

start_svxlink_service() {
    if systemd_svxlink_exists; then
        systemctl start svxlink.service
        return $?
    fi

    if init_svxlink_exists; then
        "$SVXLINK_INIT" start
        return $?
    fi

    return 1
}

stop_svxlink_service() {
    if systemd_svxlink_exists; then
        systemctl stop svxlink.service
        return $?
    fi

    if init_svxlink_exists; then
        "$SVXLINK_INIT" stop
        return $?
    fi

    return 1
}

restart_svxlink_service() {
    if systemd_svxlink_exists; then
        systemctl restart svxlink.service
        return $?
    fi

    if init_svxlink_exists; then
        "$SVXLINK_INIT" restart
        return $?
    fi

    return 1
}

enable_svxlink_service() {
    if systemd_svxlink_exists; then
        systemctl enable svxlink.service
        return $?
    fi

    if init_svxlink_exists &&
       command_exists update-rc.d; then

        update-rc.d svxlink defaults
        return $?
    fi

    return 1
}

# ------------------------------------------------------------
# 設定値取得
# ------------------------------------------------------------

read_config_value() {
    local file="$1"
    local key="$2"

    [ -f "$file" ] || {
        echo ""
        return
    }

    awk -F= -v key="$key" '
        /^[[:space:]]*[#;]/ {
            next
        }

        {
            current_key = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", current_key)

            if (current_key == key) {
                value = substr($0, index($0, "=") + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
                exit
            }
        }
    ' "$file"
}

# ------------------------------------------------------------
# 1 システム情報
# ------------------------------------------------------------

system_information() {
    local temperature="取得できません"
    local model="取得できません"

    print_title "System Information"

    echo "ホスト名"
    echo "------------------------------------------------------------"
    hostname
    echo

    echo "OS"
    echo "------------------------------------------------------------"

    if [ -f /etc/os-release ]; then
        grep '^PRETTY_NAME=' /etc/os-release |
            cut -d= -f2- |
            tr -d '"'
    else
        echo "取得できません"
    fi

    echo
    echo "カーネル"
    echo "------------------------------------------------------------"
    uname -srmo

    echo
    echo "Raspberry Piモデル"
    echo "------------------------------------------------------------"

    if [ -r /proc/device-tree/model ]; then
        model="$(tr -d '\0' </proc/device-tree/model)"
    elif grep -q '^Model' /proc/cpuinfo 2>/dev/null; then
        model="$(
            grep '^Model' /proc/cpuinfo |
                head -n 1 |
                cut -d: -f2- |
                sed 's/^[[:space:]]*//'
        )"
    fi

    echo "$model"

    echo
    echo "CPU"
    echo "------------------------------------------------------------"

    if command_exists lscpu; then
        lscpu |
            grep -E \
                '^(Architecture|CPU\(s\)|Model name|Thread|Core|Socket):'
    else
        echo "取得できません"
    fi

    echo
    echo "CPU温度"
    echo "------------------------------------------------------------"

    if command_exists vcgencmd; then
        temperature="$(vcgencmd measure_temp 2>/dev/null || true)"
    elif [ -r /sys/class/thermal/thermal_zone0/temp ]; then
        temperature="$(
            awk '{
                printf "%.1f°C\n", $1 / 1000
            }' /sys/class/thermal/thermal_zone0/temp
        )"
    fi

    echo "$temperature"

    echo
    echo "メモリー"
    echo "------------------------------------------------------------"
    free -h

    echo
    echo "ディスク"
    echo "------------------------------------------------------------"
    df -h /

    echo
    echo "IPアドレス"
    echo "------------------------------------------------------------"
    hostname -I 2>/dev/null || echo "取得できません"

    echo
    echo "稼働時間"
    echo "------------------------------------------------------------"
    uptime -p 2>/dev/null || uptime

    pause_screen
}

# ------------------------------------------------------------
# 2 SVXLink状態
# ------------------------------------------------------------

svxlink_status() {
    print_title "SVXLink Status"

    echo "実行ファイル"
    echo "------------------------------------------------------------"

    if command_exists "$SVXLINK_COMMAND"; then
        print_ok "SVXLink本体がインストールされています。"
        echo
        echo "場所: $(command -v "$SVXLINK_COMMAND")"
    else
        print_ng "SVXLink本体がインストールされていません。"
    fi

    echo
    echo "パッケージ"
    echo "------------------------------------------------------------"

    if package_installed "$SVXLINK_PACKAGE"; then
        print_ok "$SVXLINK_PACKAGE"
        dpkg-query -W \
            -f='バージョン: ${Version}\n' \
            "$SVXLINK_PACKAGE" 2>/dev/null || true
    else
        print_ng "$SVXLINK_PACKAGE"
    fi

    if package_installed "$GPIO_PACKAGE"; then
        print_ok "$GPIO_PACKAGE"
        dpkg-query -W \
            -f='バージョン: ${Version}\n' \
            "$GPIO_PACKAGE" 2>/dev/null || true
    else
        print_info "$GPIO_PACKAGE は未導入です。"
    fi

    echo
    echo "設定ファイル"
    echo "------------------------------------------------------------"

    if [ -f "$SVXLINK_CONFIG" ]; then
        print_ok "$SVXLINK_CONFIG"
    else
        print_ng "$SVXLINK_CONFIG"
    fi

    if [ -f "$ECHOLINK_CONFIG" ]; then
        print_ok "$ECHOLINK_CONFIG"
    else
        print_info "$ECHOLINK_CONFIG はありません。"
    fi

    echo
    echo "起動方式"
    echo "------------------------------------------------------------"

    if systemd_svxlink_exists; then
        print_ok "systemd: svxlink.service"
    elif init_svxlink_exists; then
        print_ok "SysV init: $SVXLINK_INIT"
    else
        print_ng "SVXLink起動サービスが見つかりません。"
    fi

    echo
    echo "動作状態"
    echo "------------------------------------------------------------"

    if svxlink_is_active; then
        print_ok "SVXLinkは動作中です。"
    else
        print_info "SVXLinkは停止中です。"
    fi

    echo
    echo "プロセス"
    echo "------------------------------------------------------------"

    if pgrep -a svxlink >/dev/null 2>&1; then
        pgrep -a svxlink
    else
        echo "svxlinkプロセスはありません。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 3 SVXLinkインストール
# ------------------------------------------------------------

install_svxlink() {
    local backup_dir=""

    print_title "Install SVXLink"

    require_root "$@"

    if command_exists "$SVXLINK_COMMAND" &&
       package_installed "$SVXLINK_PACKAGE"; then

        print_ok "SVXLink本体はすでにインストールされています。"
        echo
        dpkg-query -W \
            -f='${Package} ${Version}\n' \
            "$SVXLINK_PACKAGE" 2>/dev/null || true

        pause_screen
        return
    fi

    echo "次のパッケージをインストールします。"
    echo
    echo "  $SVXLINK_PACKAGE"
    echo "  $GPIO_PACKAGE"
    echo

    if [ -d /etc/svxlink ]; then
        backup_dir="/etc/svxlink.backup-before-install.$(
            date +%Y%m%d-%H%M%S
        )"

        echo "現在の設定を次へバックアップします。"
        echo
        echo "  $backup_dir"
        echo
    fi

    if ! confirm_action "インストールを開始しますか？"; then
        print_info "インストールを中止しました。"
        pause_screen
        return
    fi

    if [ -d /etc/svxlink ]; then
        if cp -a /etc/svxlink "$backup_dir"; then
            print_ok "既存設定をバックアップしました。"
        else
            print_ng "既存設定のバックアップに失敗しました。"
            pause_screen
            return
        fi
    fi

    echo
    print_info "APTパッケージ情報を更新しています。"

    if ! apt-get update; then
        print_ng "apt updateに失敗しました。"
        pause_screen
        return
    fi

    echo
    print_info "SVXLink本体をインストールしています。"

    if DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        "$SVXLINK_PACKAGE" \
        "$GPIO_PACKAGE"; then

        print_ok "SVXLink本体をインストールしました。"
    else
        print_ng "SVXLink本体のインストールに失敗しました。"
        pause_screen
        return
    fi

    echo
    echo "インストール確認"
    echo "------------------------------------------------------------"

    if command_exists "$SVXLINK_COMMAND"; then
        print_ok "$(command -v "$SVXLINK_COMMAND")"
    else
        print_ng "svxlinkコマンドを確認できません。"
    fi

    if [ -f "$SVXLINK_CONFIG" ]; then
        print_ok "$SVXLINK_CONFIG"
    else
        print_ng "$SVXLINK_CONFIG がありません。"
    fi

    if svxlink_service_exists; then
        print_ok "SVXLink起動サービスを確認しました。"

        if confirm_action "OS起動時の自動起動を有効にしますか？"; then
            if enable_svxlink_service; then
                print_ok "SVXLinkの自動起動を有効にしました。"
            else
                print_info "自動起動設定を変更できませんでした。"
            fi
        fi
    else
        print_info "SVXLink起動サービスを確認できませんでした。"
    fi

    echo
    print_info "インストール後にRadio設定を確認してください。"
    print_info "音声デバイスとPTT設定が未設定の場合、起動に失敗します。"

    pause_screen
}

# ------------------------------------------------------------
# 4 SVXLink更新
# ------------------------------------------------------------

update_svxlink() {
    print_title "Update SVXLink"

    require_root "$@"

    if ! package_installed "$SVXLINK_PACKAGE"; then
        print_ng "SVXLink本体がインストールされていません。"
        echo
        echo "先に「3 SVXLink本体インストール」を実行してください。"
        pause_screen
        return
    fi

    echo "更新対象:"
    echo
    echo "  $SVXLINK_PACKAGE"
    echo "  $GPIO_PACKAGE"
    echo

    if ! confirm_action "SVXLinkを更新しますか？"; then
        print_info "更新を中止しました。"
        pause_screen
        return
    fi

    if ! apt-get update; then
        print_ng "apt updateに失敗しました。"
        pause_screen
        return
    fi

    if apt-get install \
        --only-upgrade \
        -y \
        "$SVXLINK_PACKAGE" \
        "$GPIO_PACKAGE"; then

        print_ok "SVXLinkの更新処理が完了しました。"
    else
        print_ng "SVXLinkの更新に失敗しました。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 5 SVXLink起動
# ------------------------------------------------------------

start_svxlink() {
    print_title "Start SVXLink"

    require_root "$@"

    if ! command_exists "$SVXLINK_COMMAND"; then
        print_ng "SVXLink本体がインストールされていません。"
        pause_screen
        return
    fi

    if ! svxlink_service_exists; then
        print_ng "SVXLink起動サービスが見つかりません。"
        echo
        echo "確認対象:"
        echo "  svxlink.service"
        echo "  $SVXLINK_INIT"
        pause_screen
        return
    fi

    if svxlink_is_active; then
        print_info "SVXLinkはすでに動作中です。"
        pause_screen
        return
    fi

    if start_svxlink_service; then
        sleep 2

        if svxlink_is_active; then
            print_ok "SVXLinkを起動しました。"
        else
            print_ng "起動命令後も動作状態を確認できません。"
            show_recent_svxlink_log
        fi
    else
        print_ng "SVXLinkの起動に失敗しました。"
        show_recent_svxlink_log
    fi

    pause_screen
}

# ------------------------------------------------------------
# 6 SVXLink停止
# ------------------------------------------------------------

stop_svxlink() {
    print_title "Stop SVXLink"

    require_root "$@"

    if ! svxlink_service_exists; then
        print_ng "SVXLink起動サービスが見つかりません。"
        pause_screen
        return
    fi

    if ! svxlink_is_active; then
        print_info "SVXLinkはすでに停止しています。"
        pause_screen
        return
    fi

    if stop_svxlink_service; then
        sleep 1
        print_ok "SVXLinkを停止しました。"
    else
        print_ng "SVXLinkの停止に失敗しました。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 7 SVXLink再起動
# ------------------------------------------------------------

restart_svxlink() {
    print_title "Restart SVXLink"

    require_root "$@"

    if ! svxlink_service_exists; then
        print_ng "SVXLink起動サービスが見つかりません。"
        pause_screen
        return
    fi

    if restart_svxlink_service; then
        sleep 2

        if svxlink_is_active; then
            print_ok "SVXLinkを再起動しました。"
        else
            print_ng "再起動後の動作を確認できません。"
            show_recent_svxlink_log
        fi
    else
        print_ng "SVXLinkの再起動に失敗しました。"
        show_recent_svxlink_log
    fi

    pause_screen
}

# ------------------------------------------------------------
# ログ取得
# ------------------------------------------------------------

show_recent_svxlink_log() {
    echo
    echo "直近のログ"
    echo "------------------------------------------------------------"

    if systemd_svxlink_exists; then
        journalctl \
            -u svxlink.service \
            -n 30 \
            --no-pager 2>/dev/null || true
        return
    fi

    if [ -f /var/log/svxlink ]; then
        tail -n 30 /var/log/svxlink
        return
    fi

    if [ -f /var/log/syslog ]; then
        grep -i svxlink /var/log/syslog |
            tail -n 30
        return
    fi

    journalctl \
        -n 100 \
        --no-pager 2>/dev/null |
        grep -i svxlink |
        tail -n 30 || true
}

show_svxlink_log() {
    print_title "SVXLink Log"

    if ! command_exists "$SVXLINK_COMMAND"; then
        print_info "SVXLink本体はインストールされていません。"
    fi

    if systemd_svxlink_exists; then
        journalctl \
            -u svxlink.service \
            -n 100 \
            --no-pager
    elif [ -f /var/log/svxlink ]; then
        tail -n 100 /var/log/svxlink
    elif [ -f /var/log/syslog ]; then
        grep -i svxlink /var/log/syslog |
            tail -n 100
    else
        journalctl \
            -n 300 \
            --no-pager 2>/dev/null |
            grep -i svxlink |
            tail -n 100 ||
            echo "SVXLink関連ログは見つかりませんでした。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 9 設定確認
# ------------------------------------------------------------

configuration_check() {
    local cfg_dir=""
    local modules=""

    print_title "SVXLink Configuration Check"

    if [ -d /etc/svxlink ]; then
        print_ok "/etc/svxlink"
    else
        print_ng "/etc/svxlink がありません。"
    fi

    if [ -f "$SVXLINK_CONFIG" ]; then
        print_ok "$SVXLINK_CONFIG"

        cfg_dir="$(read_config_value "$SVXLINK_CONFIG" "CFG_DIR")"
        modules="$(read_config_value "$SVXLINK_CONFIG" "MODULES")"

        echo
        echo "メイン設定"
        echo "------------------------------------------------------------"
        echo "CFG_DIR : ${cfg_dir:-未設定}"
        echo "MODULES : ${modules:-未設定}"
    else
        print_ng "$SVXLINK_CONFIG がありません。"
    fi

    echo
    echo "EchoLink設定"
    echo "------------------------------------------------------------"

    if [ -f "$ECHOLINK_CONFIG" ]; then
        print_ok "$ECHOLINK_CONFIG"
    else
        print_info "$ECHOLINK_CONFIG はありません。"
    fi

    echo
    echo "GPIO設定"
    echo "------------------------------------------------------------"

    if [ -f "$GPIO_CONFIG" ]; then
        print_ok "$GPIO_CONFIG"
    else
        print_info "$GPIO_CONFIG はありません。"
    fi

    echo
    echo "ファイル権限"
    echo "------------------------------------------------------------"

    for file in \
        "$SVXLINK_CONFIG" \
        "$ECHOLINK_CONFIG" \
        "$GPIO_CONFIG"
    do
        if [ -e "$file" ]; then
            stat \
                -c '%A %U:%G %n' \
                "$file"
        fi
    done

    pause_screen
}

# ------------------------------------------------------------
# 10 EchoLink状態
# ------------------------------------------------------------

echolink_status() {
    local callsign=""
    local sysop=""
    local location=""
    local server=""
    local password=""
    local description=""

    print_title "EchoLink Status"

    if [ ! -f "$ECHOLINK_CONFIG" ]; then
        print_ng "EchoLink設定ファイルがありません。"
        echo
        echo "$ECHOLINK_CONFIG"
        pause_screen
        return
    fi

    callsign="$(read_config_value "$ECHOLINK_CONFIG" "CALLSIGN")"
    sysop="$(read_config_value "$ECHOLINK_CONFIG" "SYSOPNAME")"
    location="$(read_config_value "$ECHOLINK_CONFIG" "LOCATION")"
    server="$(read_config_value "$ECHOLINK_CONFIG" "SERVERS")"
    password="$(read_config_value "$ECHOLINK_CONFIG" "PASSWORD")"
    description="$(read_config_value "$ECHOLINK_CONFIG" "DESCRIPTION")"

    echo "設定ファイル"
    echo "------------------------------------------------------------"
    echo "$ECHOLINK_CONFIG"
    echo

    printf "%-18s : %s\n" \
        "コールサイン" \
        "${callsign:-未設定}"

    printf "%-18s : %s\n" \
        "管理者名" \
        "${sysop:-未設定}"

    printf "%-18s : %s\n" \
        "設置場所" \
        "${location:-未設定}"

    printf "%-18s : %s\n" \
        "説明文" \
        "${description:-未設定}"

    printf "%-18s : %s\n" \
        "サーバー" \
        "${server:-未設定}"

    if [ -n "$password" ]; then
        printf "%-18s : %s\n" \
            "パスワード" \
            "設定済み（非表示）"
    else
        printf "%-18s : %s\n" \
            "パスワード" \
            "未設定"
    fi

    echo
    echo "設定診断"
    echo "------------------------------------------------------------"

    if [ -n "$callsign" ]; then
        print_ok "コールサイン"
    else
        print_ng "コールサインが未設定です。"
    fi

    if [ -n "$password" ]; then
        print_ok "パスワード"
    else
        print_ng "パスワードが未設定です。"
    fi

    if [ -n "$server" ]; then
        print_ok "ディレクトリサーバー"
    else
        print_ng "ディレクトリサーバーが未設定です。"
    fi

    echo
    echo "名前解決"
    echo "------------------------------------------------------------"

    if [ -n "$server" ]; then
        # 複数指定の場合は先頭だけ検査
        local first_server
        first_server="${server%%[ ,]*}"

        if getent hosts "$first_server" >/dev/null 2>&1; then
            print_ok "$first_server"
            getent hosts "$first_server" |
                head -n 3
        else
            print_ng "$first_server を名前解決できません。"
        fi
    fi

    echo
    echo "注意:"
    echo "この画面ではEchoLinkパスワードを表示しません。"
    echo "実際のログイン成功はSVXLink起動後のログで確認します。"

    pause_screen
}

# ------------------------------------------------------------
# 11 GPIO状態
# ------------------------------------------------------------

gpio_status() {
    print_title "GPIO Status"

    echo "パッケージ"
    echo "------------------------------------------------------------"

    if package_installed "$GPIO_PACKAGE"; then
        print_ok "$GPIO_PACKAGE"
        dpkg-query -W \
            -f='バージョン: ${Version}\n' \
            "$GPIO_PACKAGE" 2>/dev/null || true
    else
        print_info "$GPIO_PACKAGE は未導入です。"
    fi

    echo
    echo "設定ファイル"
    echo "------------------------------------------------------------"

    if [ -f "$GPIO_CONFIG" ]; then
        print_ok "$GPIO_CONFIG"
        echo
        grep -Ev \
            '^[[:space:]]*($|#|;)' \
            "$GPIO_CONFIG" 2>/dev/null ||
            echo "有効なGPIO設定はありません。"
    else
        print_ng "$GPIO_CONFIG がありません。"
    fi

    echo
    echo "GPIO初期化サービス"
    echo "------------------------------------------------------------"

    if systemctl list-unit-files \
        --no-legend 2>/dev/null |
        awk '{print $1}' |
        grep -qx "$GPIO_SERVICE"; then

        if systemctl is-active \
            --quiet \
            "$GPIO_SERVICE"; then

            print_ok "$GPIO_SERVICE は動作中です。"
        else
            print_info "$GPIO_SERVICE は停止中です。"
        fi

        echo
        systemctl status \
            "$GPIO_SERVICE" \
            --no-pager \
            -l 2>/dev/null || true
    else
        print_info "$GPIO_SERVICE は見つかりません。"
    fi

    echo
    echo "GPIOチップ"
    echo "------------------------------------------------------------"

    if command_exists gpioinfo; then
        gpioinfo 2>/dev/null |
            head -n 60
    elif [ -d /sys/class/gpio ]; then
        ls -la /sys/class/gpio
    else
        echo "GPIO情報を取得できません。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 12 ネットワーク状態
# ------------------------------------------------------------

network_status() {
    print_title "Network Status"

    echo "インターフェース"
    echo "------------------------------------------------------------"
    ip -brief address 2>/dev/null ||
        ip address

    echo
    echo "デフォルトゲートウェイ"
    echo "------------------------------------------------------------"
    ip route |
        grep '^default' ||
        echo "デフォルトルートがありません。"

    echo
    echo "DNS"
    echo "------------------------------------------------------------"

    if command_exists resolvectl; then
        resolvectl status 2>/dev/null |
            grep -E \
                'Link|Current DNS Server|DNS Servers|DNS Domain' ||
            true
    else
        cat /etc/resolv.conf
    fi

    echo
    echo "NetworkManager"
    echo "------------------------------------------------------------"

    if systemctl is-active \
        --quiet \
        NetworkManager.service; then

        print_ok "NetworkManagerは動作中です。"
    else
        print_info "NetworkManagerは停止中です。"
    fi

    if command_exists nmcli; then
        echo
        nmcli \
            -f DEVICE,TYPE,STATE,CONNECTION \
            device status
    fi

    echo
    echo "インターネット疎通"
    echo "------------------------------------------------------------"

    if ping \
        -c 1 \
        -W 3 \
        1.1.1.1 \
        >/dev/null 2>&1; then

        print_ok "外部IPへ接続できました。"
    else
        print_ng "外部IPへ接続できません。"
    fi

    if getent hosts \
        servers.echolink.org \
        >/dev/null 2>&1; then

        print_ok "EchoLinkサーバーを名前解決できました。"
    else
        print_ng "EchoLinkサーバーを名前解決できません。"
    fi

    pause_screen
}

# ------------------------------------------------------------
# 13 ディスク使用率
# ------------------------------------------------------------

disk_status() {
    print_title "Disk Usage"

    df -hT

    echo
    echo "ルート領域"
    echo "------------------------------------------------------------"

    local usage
    usage="$(
        df -P / |
            awk 'NR == 2 {
                gsub(/%/, "", $5)
                print $5
            }'
    )"

    if [ -n "$usage" ] &&
       [ "$usage" -lt 90 ]; then

        print_ok "ディスク使用率: ${usage}%"
    else
        print_ng "ディスク使用率が90%以上です: ${usage:-不明}%"
    fi

    echo
    echo "大きなディレクトリ"
    echo "------------------------------------------------------------"

    du -xhd1 /var /home 2>/dev/null |
        sort -h |
        tail -n 15

    pause_screen
}

# ------------------------------------------------------------
# 14 総合診断
# ------------------------------------------------------------

system_diagnosis() {
    local ng_count=0
    local warning_count=0
    local disk_usage=""
    local callsign=""
    local password=""
    local server=""

    print_title "System Diagnosis"

    echo "SVXLink本体"
    echo "------------------------------------------------------------"

    if command_exists "$SVXLINK_COMMAND"; then
        print_ok "svxlinkコマンド"
    else
        print_ng "SVXLink本体が未導入です。"
        ng_count=$((ng_count + 1))
    fi

    if package_installed "$SVXLINK_PACKAGE"; then
        print_ok "$SVXLINK_PACKAGE"
    else
        print_ng "$SVXLINK_PACKAGE"
        ng_count=$((ng_count + 1))
    fi

    echo
    echo "設定ファイル"
    echo "------------------------------------------------------------"

    if [ -f "$SVXLINK_CONFIG" ]; then
        print_ok "$SVXLINK_CONFIG"
    else
        print_ng "$SVXLINK_CONFIG"
        ng_count=$((ng_count + 1))
    fi

    if [ -f "$ECHOLINK_CONFIG" ]; then
        print_ok "$ECHOLINK_CONFIG"
    else
        print_info "EchoLink設定がありません。"
        warning_count=$((warning_count + 1))
    fi

    echo
    echo "SVXLinkサービス"
    echo "------------------------------------------------------------"

    if svxlink_service_exists; then
        print_ok "起動サービス"
    else
        print_ng "起動サービスが見つかりません。"
        ng_count=$((ng_count + 1))
    fi

    if svxlink_is_active; then
        print_ok "SVXLinkは動作中です。"
    else
        print_info "SVXLinkは停止中です。"
        warning_count=$((warning_count + 1))
    fi

    echo
    echo "EchoLink"
    echo "------------------------------------------------------------"

    if [ -f "$ECHOLINK_CONFIG" ]; then
        callsign="$(
            read_config_value \
                "$ECHOLINK_CONFIG" \
                "CALLSIGN"
        )"

        password="$(
            read_config_value \
                "$ECHOLINK_CONFIG" \
                "PASSWORD"
        )"

        server="$(
            read_config_value \
                "$ECHOLINK_CONFIG" \
                "SERVERS"
        )"

        if [ -n "$callsign" ]; then
            print_ok "コールサイン: $callsign"
        else
            print_ng "コールサインが未設定です。"
            ng_count=$((ng_count + 1))
        fi

        if [ -n "$password" ]; then
            print_ok "パスワード設定済み"
        else
            print_ng "パスワードが未設定です。"
            ng_count=$((ng_count + 1))
        fi

        if [ -n "$server" ]; then
            print_ok "サーバー: $server"
        else
            print_ng "サーバーが未設定です。"
            ng_count=$((ng_count + 1))
        fi
    fi

    echo
    echo "ネットワーク"
    echo "------------------------------------------------------------"

    if ip route |
        grep -q '^default'; then

        print_ok "デフォルトゲートウェイ"
    else
        print_ng "デフォルトゲートウェイがありません。"
        ng_count=$((ng_count + 1))
    fi

    if ping \
        -c 1 \
        -W 3 \
        1.1.1.1 \
        >/dev/null 2>&1; then

        print_ok "インターネット接続"
    else
        print_ng "インターネットへ接続できません。"
        ng_count=$((ng_count + 1))
    fi

    if getent hosts \
        servers.echolink.org \
        >/dev/null 2>&1; then

        print_ok "DNS名前解決"
    else
        print_ng "DNS名前解決に失敗しました。"
        ng_count=$((ng_count + 1))
    fi

    echo
    echo "ディスク"
    echo "------------------------------------------------------------"

    disk_usage="$(
        df -P / |
            awk 'NR == 2 {
                gsub(/%/, "", $5)
                print $5
            }'
    )"

    if [ -n "$disk_usage" ] &&
       [ "$disk_usage" -lt 90 ]; then

        print_ok "使用率 ${disk_usage}%"
    else
        print_ng "使用率 ${disk_usage:-不明}%"
        ng_count=$((ng_count + 1))
    fi

    echo
    echo "============================================================"
    echo "診断結果"
    echo "============================================================"
    echo

    if [ "$ng_count" -eq 0 ] &&
       [ "$warning_count" -eq 0 ]; then

        echo -e "${GREEN}SYSTEM NORMAL${RESET}"
    elif [ "$ng_count" -eq 0 ]; then
        echo -e "${YELLOW}注意事項があります。${RESET}"
    else
        echo -e "${RED}修正が必要な項目があります。${RESET}"
    fi

    echo
    echo "エラー : $ng_count"
    echo "注意   : $warning_count"

    if ! command_exists "$SVXLINK_COMMAND"; then
        echo
        if confirm_action \
            "SVXLink本体がありません。インストール画面へ進みますか？"; then

            install_svxlink
            return
        fi
    fi

    pause_screen
}

# ------------------------------------------------------------
# メインメニュー
# ------------------------------------------------------------

main_menu() {
    local choice

    while true; do
        clear

        echo "============================================================"
        echo "                    System Menu"
        echo "============================================================"
        echo
        echo " 1  システム情報"
        echo " 2  SVXLink本体状態"
        echo " 3  SVXLink本体インストール"
        echo " 4  SVXLink本体アップデート"
        echo " 5  SVXLink起動"
        echo " 6  SVXLink停止"
        echo " 7  SVXLink再起動"
        echo " 8  SVXLinkログ表示"
        echo " 9  SVXLink設定確認"
        echo "10  EchoLink状態確認"
        echo "11  GPIO状態確認"
        echo "12  ネットワーク状態"
        echo "13  ディスク使用率"
        echo "14  システム総合診断"
        echo
        echo " 0  戻る"
        echo
        echo "============================================================"

        read -r -p "選択してください [0-14]: " choice

        case "$choice" in
            1)
                system_information
                ;;
            2)
                svxlink_status
                ;;
            3)
                install_svxlink
                ;;
            4)
                update_svxlink
                ;;
            5)
                start_svxlink
                ;;
            6)
                stop_svxlink
                ;;
            7)
                restart_svxlink
                ;;
            8)
                show_svxlink_log
                ;;
            9)
                configuration_check
                ;;
            10)
                echolink_status
                ;;
            11)
                gpio_status
                ;;
            12)
                network_status
                ;;
            13)
                disk_status
                ;;
            14)
                system_diagnosis
                ;;
            0)
                return 0
                ;;
            *)
                print_ng "0～14の番号を入力してください。"
                sleep 1
                ;;
        esac
    done
}

main_menu
