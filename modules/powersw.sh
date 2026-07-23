#!/usr/bin/env bash
#
# SVXLinkJP Radio PowerSW Module
# Version 1.2.0
#
# Raspberry Piに接続された無線機の電源をGPIO経由で制御します。
#
# 機能:
#   - 無線機電源ON
#   - 無線機電源OFF
#   - 電源ON/OFF切り替え
#   - GPIO実状態表示
#   - Raspberry Pi起動時の自動ON
#   - 指定時間後の自動OFF
#   - 自動OFFタイマー解除
#   - 無線機起動後のSVXLink再起動
#
# 注意:
#   Raspberry Pi GPIOへ無線機やリレーコイルを直接接続しないでください。
#   トランジスタ、MOSFET、フォトカプラ、
#   または3.3V対応リレーモジュールを使用してください。
#

set -u

POWERSW_CONFIG="${POWERSW_CONFIG:-/etc/svxlinkjp/powersw.conf}"
SYSTEMD_SERVICE="/etc/systemd/system/svxlinkjp-radio-power.service"
TIMER_PID_FILE="/run/svxlinkjp-radio-poweroff.pid"

POWER_GPIO=""
POWER_ACTIVE_LOW="0"
POWER_NAME="Radio"
POWER_STATE="OFF"
AUTO_POWER_ON="0"
RADIO_START_DELAY="10"
RESTART_SVXLINK_AFTER_ON="1"

pause_screen()
{
    echo
    read -r -p "Enterキーを押してください..." _
}

clear_screen()
{
    command -v clear >/dev/null 2>&1 && clear
}

print_header()
{
    clear_screen

    echo "========================================"
    echo " SVXLinkJP 無線機 PowerSW Ver.1.2.0"
    echo "========================================"
    echo
}

run_as_root()
{
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

is_valid_gpio()
{
    [[ "${1:-}" =~ ^[0-9]+$ ]] &&
        [ "$1" -ge 0 ] &&
        [ "$1" -le 53 ]
}

is_valid_number()
{
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

find_gpio_command()
{
    if command -v pinctrl >/dev/null 2>&1; then
        printf '%s\n' "pinctrl"
        return 0
    fi

    if command -v raspi-gpio >/dev/null 2>&1; then
        printf '%s\n' "raspi-gpio"
        return 0
    fi

    printf '%s\n' ""
    return 1
}

detect_service_name()
{
    local unit

    for unit in svxlink.service svxlink-server.service; do
        if systemctl list-unit-files "$unit" \
            --no-legend 2>/dev/null |
            grep -q "^${unit}"; then
            printf '%s\n' "$unit"
            return 0
        fi
    done

    if systemctl status svxlink.service >/dev/null 2>&1; then
        printf '%s\n' "svxlink.service"
        return 0
    fi

    printf '%s\n' ""
}

load_config()
{
    local value

    [ -f "$POWERSW_CONFIG" ] || return 0

    value="$(
        grep -m1 '^POWER_GPIO=' "$POWERSW_CONFIG" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && POWER_GPIO="$value"

    value="$(
        grep -m1 '^POWER_ACTIVE_LOW=' "$POWERSW_CONFIG" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && POWER_ACTIVE_LOW="$value"

    value="$(
        grep -m1 '^POWER_NAME=' "$POWERSW_CONFIG" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && POWER_NAME="$value"

    value="$(
        grep -m1 '^POWER_STATE=' "$POWERSW_CONFIG" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && POWER_STATE="$value"

    value="$(
        grep -m1 '^AUTO_POWER_ON=' "$POWERSW_CONFIG" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && AUTO_POWER_ON="$value"

    value="$(
        grep -m1 '^RADIO_START_DELAY=' "$POWERSW_CONFIG" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && RADIO_START_DELAY="$value"

    value="$(
        grep -m1 '^RESTART_SVXLINK_AFTER_ON=' \
            "$POWERSW_CONFIG" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] &&
        RESTART_SVXLINK_AFTER_ON="$value"
}

save_config()
{
    local temp_file
    local config_dir

    temp_file="$(mktemp)"
    config_dir="$(dirname "$POWERSW_CONFIG")"

    cat > "$temp_file" <<CONFIG
# SVXLinkJP Radio PowerSW configuration
POWER_GPIO=$POWER_GPIO
POWER_ACTIVE_LOW=$POWER_ACTIVE_LOW
POWER_NAME=$POWER_NAME
POWER_STATE=$POWER_STATE
AUTO_POWER_ON=$AUTO_POWER_ON
RADIO_START_DELAY=$RADIO_START_DELAY
RESTART_SVXLINK_AFTER_ON=$RESTART_SVXLINK_AFTER_ON
CONFIG

    run_as_root mkdir -p "$config_dir" || {
        rm -f "$temp_file"
        return 1
    }

    run_as_root install -m 644 "$temp_file" "$POWERSW_CONFIG"
    local result=$?

    rm -f "$temp_file"
    return "$result"
}

get_active_level()
{
    if [ "$POWER_ACTIVE_LOW" = "1" ]; then
        printf '%s\n' "0"
    else
        printf '%s\n' "1"
    fi
}

get_inactive_level()
{
    if [ "$POWER_ACTIVE_LOW" = "1" ]; then
        printf '%s\n' "1"
    else
        printf '%s\n' "0"
    fi
}

set_gpio_level()
{
    local level="$1"
    local gpio_command

    if [ -z "$POWER_GPIO" ]; then
        echo "PowerSW GPIOが未設定です。"
        return 1
    fi

    gpio_command="$(find_gpio_command)" || {
        echo "GPIO制御コマンドが見つかりません。"
        echo
        echo "pinctrlまたはraspi-gpioが必要です。"
        return 1
    }

    case "$gpio_command" in
        pinctrl)
            if [ "$level" = "1" ]; then
                run_as_root pinctrl set "$POWER_GPIO" op dh
            else
                run_as_root pinctrl set "$POWER_GPIO" op dl
            fi
            ;;

        raspi-gpio)
            if [ "$level" = "1" ]; then
                run_as_root raspi-gpio set "$POWER_GPIO" op dh
            else
                run_as_root raspi-gpio set "$POWER_GPIO" op dl
            fi
            ;;
    esac
}

get_gpio_level()
{
    local gpio_command
    local output

    [ -n "$POWER_GPIO" ] || return 1

    gpio_command="$(find_gpio_command)" || return 1

    case "$gpio_command" in
        pinctrl)
            output="$(run_as_root pinctrl get "$POWER_GPIO" 2>/dev/null)" ||
                return 1

            if printf '%s' "$output" |
                grep -Eq '(^|[[:space:]])hi([[:space:]]|$)'; then
                printf '%s\n' "1"
            elif printf '%s' "$output" |
                grep -Eq '(^|[[:space:]])lo([[:space:]]|$)'; then
                printf '%s\n' "0"
            else
                return 1
            fi
            ;;

        raspi-gpio)
            output="$(
                run_as_root raspi-gpio get "$POWER_GPIO" 2>/dev/null
            )" || return 1

            if printf '%s' "$output" | grep -q 'level=1'; then
                printf '%s\n' "1"
            elif printf '%s' "$output" | grep -q 'level=0'; then
                printf '%s\n' "0"
            else
                return 1
            fi
            ;;
    esac
}

get_radio_state()
{
    local level
    local active_level

    level="$(get_gpio_level 2>/dev/null)" || {
        printf '%s\n' "$POWER_STATE"
        return
    }

    active_level="$(get_active_level)"

    if [ "$level" = "$active_level" ]; then
        printf '%s\n' "ON"
    else
        printf '%s\n' "OFF"
    fi
}

restart_svxlink()
{
    local service_name

    service_name="$(detect_service_name)"

    if [ -z "$service_name" ]; then
        echo "SVXLinkサービスが見つかりません。"
        return 1
    fi

    echo "SVXLinkを再起動しています..."

    if run_as_root systemctl restart "$service_name"; then
        sleep 2

        if systemctl is-active --quiet "$service_name"; then
            echo "SVXLinkは正常に起動しました。"
            return 0
        fi
    fi

    echo "SVXLinkの再起動に失敗しました。"
    return 1
}

radio_power_on_core()
{
    local active_level

    if [ -z "$POWER_GPIO" ]; then
        echo "PowerSW GPIOが未設定です。"
        return 1
    fi

    active_level="$(get_active_level)"

    if ! set_gpio_level "$active_level"; then
        echo "無線機の電源をONにできませんでした。"
        return 1
    fi

    POWER_STATE="ON"
    save_config || true

    echo "無線機の電源をONにしました。"

    if [ "$RADIO_START_DELAY" -gt 0 ] 2>/dev/null; then
        echo
        echo "無線機の起動を${RADIO_START_DELAY}秒待ちます..."
        sleep "$RADIO_START_DELAY"
    fi

    if [ "$RESTART_SVXLINK_AFTER_ON" = "1" ]; then
        echo
        restart_svxlink || true
    fi

    return 0
}

radio_power_off_core()
{
    local inactive_level

    if [ -z "$POWER_GPIO" ]; then
        echo "PowerSW GPIOが未設定です。"
        return 1
    fi

    inactive_level="$(get_inactive_level)"

    if ! set_gpio_level "$inactive_level"; then
        echo "無線機の電源をOFFにできませんでした。"
        return 1
    fi

    POWER_STATE="OFF"
    save_config || true

    echo "無線機の電源をOFFにしました。"
    return 0
}

radio_power_on()
{
    local current_state

    print_header

    current_state="$(get_radio_state)"

    echo "無線機電源ON"
    echo "----------------------------------------"
    echo "機器名     : $POWER_NAME"
    echo "GPIO       : ${POWER_GPIO:-未設定}"
    echo "現在の状態 : $current_state"
    echo

    if [ "$current_state" = "ON" ]; then
        echo "無線機の電源はすでにONです。"
        pause_screen
        return
    fi

    radio_power_on_core
    pause_screen
}

radio_power_off()
{
    local current_state
    local answer

    print_header

    current_state="$(get_radio_state)"

    echo "無線機電源OFF"
    echo "----------------------------------------"
    echo "機器名     : $POWER_NAME"
    echo "GPIO       : ${POWER_GPIO:-未設定}"
    echo "現在の状態 : $current_state"
    echo

    if [ "$current_state" = "OFF" ]; then
        echo "無線機の電源はすでにOFFです。"
        pause_screen
        return
    fi

    read -r -p "無線機の電源をOFFにしますか？ [y/N]: " answer

    case "$answer" in
        y|Y)
            radio_power_off_core
            ;;
        *)
            echo "中止しました。"
            ;;
    esac

    pause_screen
}

radio_power_toggle()
{
    local current_state
    local answer

    print_header

    current_state="$(get_radio_state)"

    echo "無線機電源切り替え"
    echo "----------------------------------------"
    echo "現在の状態: $current_state"
    echo

    if [ "$current_state" = "ON" ]; then
        read -r -p "電源をOFFに切り替えますか？ [y/N]: " answer

        case "$answer" in
            y|Y)
                radio_power_off_core
                ;;
            *)
                echo "中止しました。"
                ;;
        esac
    else
        read -r -p "電源をONに切り替えますか？ [Y/n]: " answer

        case "${answer:-Y}" in
            y|Y)
                radio_power_on_core
                ;;
            *)
                echo "中止しました。"
                ;;
        esac
    fi

    pause_screen
}

configure_powersw()
{
    local gpio
    local polarity
    local name
    local delay
    local restart_choice
    local answer

    print_header

    echo "無線機 PowerSW GPIO設定"
    echo "----------------------------------------"
    echo
    echo "現在のGPIO: ${POWER_GPIO:-未設定}"
    echo

    read -r -p "使用するBCM GPIO番号を入力してください: " gpio

    if ! is_valid_gpio "$gpio"; then
        echo "GPIO番号が正しくありません。"
        pause_screen
        return
    fi

    echo
    echo "リレーまたはMOSFETの動作論理"
    echo
    echo " 1. Active High：HIGHで電源ON"
    echo " 2. Active Low ：LOWで電源ON"
    echo

    read -r -p "選択 [1]: " polarity

    case "${polarity:-1}" in
        1)
            POWER_ACTIVE_LOW="0"
            ;;
        2)
            POWER_ACTIVE_LOW="1"
            ;;
        *)
            echo "選択が正しくありません。"
            pause_screen
            return
            ;;
    esac

    echo
    read -r -p "無線機名を入力してください [Radio]: " name
    POWER_NAME="${name:-Radio}"

    echo
    read -r -p \
        "電源ON後の起動待ち時間・秒 [10]: " delay
    delay="${delay:-10}"

    if ! is_valid_number "$delay"; then
        echo "待ち時間が正しくありません。"
        pause_screen
        return
    fi

    RADIO_START_DELAY="$delay"

    echo
    read -r -p \
        "電源ON後にSVXLinkを再起動しますか？ [Y/n]: " \
        restart_choice

    case "${restart_choice:-Y}" in
        y|Y)
            RESTART_SVXLINK_AFTER_ON="1"
            ;;
        *)
            RESTART_SVXLINK_AFTER_ON="0"
            ;;
    esac

    POWER_GPIO="$gpio"

    echo
    echo "保存内容"
    echo "----------------------------------------"
    echo "無線機名       : $POWER_NAME"
    echo "GPIO           : $POWER_GPIO"
    echo "Active Low     : $POWER_ACTIVE_LOW"
    echo "起動待ち時間   : ${RADIO_START_DELAY}秒"
    echo "SVXLink再起動  : $RESTART_SVXLINK_AFTER_ON"
    echo

    read -r -p "設定を保存しますか？ [Y/n]: " answer

    case "${answer:-Y}" in
        y|Y)
            if save_config; then
                echo "PowerSW設定を保存しました。"
                echo "$POWERSW_CONFIG"
            else
                echo "設定を保存できませんでした。"
            fi
            ;;
        *)
            echo "保存を中止しました。"
            ;;
    esac

    pause_screen
}

show_radio_status()
{
    local gpio_command
    local gpio_level
    local current_state
    local service_name
    local service_state="未検出"
    local timer_state="停止"

    print_header

    gpio_command="$(find_gpio_command 2>/dev/null || true)"
    gpio_level="$(get_gpio_level 2>/dev/null || printf '%s' '取得不可')"
    current_state="$(get_radio_state)"
    service_name="$(detect_service_name)"

    if [ -n "$service_name" ]; then
        service_state="$(
            systemctl is-active "$service_name" 2>/dev/null ||
                printf '%s' 'inactive'
        )"
    fi

    if [ -f "$TIMER_PID_FILE" ]; then
        local timer_pid

        timer_pid="$(cat "$TIMER_PID_FILE" 2>/dev/null || true)"

        if [ -n "$timer_pid" ] &&
            kill -0 "$timer_pid" 2>/dev/null; then
            timer_state="動作中 PID=${timer_pid}"
        else
            run_as_root rm -f "$TIMER_PID_FILE" 2>/dev/null || true
        fi
    fi

    echo "無線機電源状態"
    echo "========================================"
    echo
    echo "無線機名       : $POWER_NAME"
    echo "PowerSW GPIO   : ${POWER_GPIO:-未設定}"
    echo "GPIO論理値     : $gpio_level"
    echo "Active Low     : $POWER_ACTIVE_LOW"
    echo "無線機電源     : $current_state"
    echo
    echo "自動電源ON     : $AUTO_POWER_ON"
    echo "起動待ち時間   : ${RADIO_START_DELAY}秒"
    echo "SVXLink再起動  : $RESTART_SVXLINK_AFTER_ON"
    echo "自動OFFタイマー: $timer_state"
    echo
    echo "GPIOコマンド   : ${gpio_command:-利用不可}"
    echo "SVXLink         : $service_state"
    echo "設定ファイル   : $POWERSW_CONFIG"
    echo

    if [ -n "$POWER_GPIO" ] && [ "$gpio_command" = "pinctrl" ]; then
        echo "GPIO詳細"
        echo "----------------------------------------"
        run_as_root pinctrl get "$POWER_GPIO" 2>&1 || true
    elif [ -n "$POWER_GPIO" ] &&
        [ "$gpio_command" = "raspi-gpio" ]; then
        echo "GPIO詳細"
        echo "----------------------------------------"
        run_as_root raspi-gpio get "$POWER_GPIO" 2>&1 || true
    fi

    pause_screen
}

install_auto_power_service()
{
    local script_path
    local temp_file

    script_path="$(readlink -f "${BASH_SOURCE[0]}")"
    temp_file="$(mktemp)"

    cat > "$temp_file" <<SERVICE
[Unit]
Description=SVXLinkJP Radio Power ON
After=multi-user.target
Before=svxlink.service svxlink-server.service

[Service]
Type=oneshot
ExecStart=${script_path} --boot-power-on
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

    if ! run_as_root install -m 644 \
        "$temp_file" "$SYSTEMD_SERVICE"; then
        rm -f "$temp_file"
        return 1
    fi

    rm -f "$temp_file"

    run_as_root systemctl daemon-reload || return 1
    run_as_root systemctl enable \
        svxlinkjp-radio-power.service || return 1

    return 0
}

remove_auto_power_service()
{
    run_as_root systemctl disable \
        svxlinkjp-radio-power.service 2>/dev/null || true

    run_as_root rm -f "$SYSTEMD_SERVICE" || return 1
    run_as_root systemctl daemon-reload || return 1

    return 0
}

configure_auto_power_on()
{
    local choice

    print_header

    echo "ラズパイ起動時の無線機自動ON"
    echo "----------------------------------------"
    echo "現在の設定: $AUTO_POWER_ON"
    echo
    echo " 1. 自動ONを有効にする"
    echo " 2. 自動ONを無効にする"
    echo " 0. 中止"
    echo

    read -r -p "選択してください: " choice

    case "$choice" in
        1)
            if [ -z "$POWER_GPIO" ]; then
                echo "先にPowerSW GPIOを設定してください。"
                pause_screen
                return
            fi

            AUTO_POWER_ON="1"
            save_config || {
                echo "設定を保存できませんでした。"
                pause_screen
                return
            }

            if install_auto_power_service; then
                echo
                echo "無線機の自動電源ONを有効にしました。"
                echo
                echo "次回のRaspberry Pi起動時から有効です。"
            else
                echo
                echo "自動起動サービスを登録できませんでした。"
            fi
            ;;

        2)
            AUTO_POWER_ON="0"
            save_config || true

            if remove_auto_power_service; then
                echo
                echo "無線機の自動電源ONを無効にしました。"
            else
                echo
                echo "自動起動サービスを削除できませんでした。"
            fi
            ;;

        0)
            return
            ;;

        *)
            echo "選択が正しくありません。"
            ;;
    esac

    pause_screen
}

timer_poweroff_worker()
{
    local seconds="$1"

    sleep "$seconds"

    load_config
    radio_power_off_core >/dev/null 2>&1 || true

    rm -f "$TIMER_PID_FILE" 2>/dev/null || true
}

schedule_power_off()
{
    local minutes
    local seconds
    local answer
    local pid

    print_header

    echo "無線機自動OFFタイマー"
    echo "----------------------------------------"
    echo
    echo "指定時間経過後に無線機の電源をOFFにします。"
    echo

    read -r -p "何分後にOFFにしますか？ [60]: " minutes
    minutes="${minutes:-60}"

    if ! is_valid_number "$minutes" || [ "$minutes" -eq 0 ]; then
        echo "時間の入力が正しくありません。"
        pause_screen
        return
    fi

    echo
    echo "${minutes}分後に無線機をOFFにします。"
    read -r -p "タイマーを開始しますか？ [Y/n]: " answer

    case "${answer:-Y}" in
        y|Y)
            ;;
        *)
            echo "中止しました。"
            pause_screen
            return
            ;;
    esac

    cancel_poweroff_timer_core

    seconds=$((minutes * 60))

    nohup "$0" \
        --timer-power-off "$seconds" \
        >/tmp/svxlinkjp-radio-poweroff.log 2>&1 &

    pid=$!

    printf '%s\n' "$pid" |
        run_as_root tee "$TIMER_PID_FILE" >/dev/null

    echo
    echo "自動OFFタイマーを開始しました。"
    echo "OFF予定: ${minutes}分後"
    echo "PID     : $pid"

    pause_screen
}

cancel_poweroff_timer_core()
{
    local pid

    if [ ! -f "$TIMER_PID_FILE" ]; then
        return 0
    fi

    pid="$(cat "$TIMER_PID_FILE" 2>/dev/null || true)"

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
    fi

    run_as_root rm -f "$TIMER_PID_FILE" 2>/dev/null || true
}

cancel_poweroff_timer()
{
    print_header

    if [ ! -f "$TIMER_PID_FILE" ]; then
        echo "自動OFFタイマーは設定されていません。"
        pause_screen
        return
    fi

    cancel_poweroff_timer_core

    echo "自動OFFタイマーを解除しました。"
    pause_screen
}

boot_power_on()
{
    load_config

    if [ "$AUTO_POWER_ON" != "1" ]; then
        exit 0
    fi

    if [ -z "$POWER_GPIO" ]; then
        exit 1
    fi

    radio_power_on_core
}

powersw_menu()
{
    local choice
    local current_state

    load_config

    while true; do
        current_state="$(get_radio_state)"

        print_header

        echo " 無線機名 : $POWER_NAME"
        echo " GPIO     : ${POWER_GPIO:-未設定}"
        echo " 電源状態 : $current_state"
        echo " 自動ON   : $AUTO_POWER_ON"
        echo
        echo " 1. 無線機電源 ON"
        echo " 2. 無線機電源 OFF"
        echo " 3. 無線機電源 ON/OFF切り替え"
        echo " 4. 無線機電源状態表示"
        echo " 5. PowerSW GPIO設定"
        echo " 6. 起動時の無線機自動ON設定"
        echo " 7. 指定時間後に無線機OFF"
        echo " 8. 自動OFFタイマー解除"
        echo " 9. SVXLink再起動"
        echo " 0. 戻る"
        echo

        read -r -p "選択してください: " choice

        case "$choice" in
            1)
                radio_power_on
                ;;
            2)
                radio_power_off
                ;;
            3)
                radio_power_toggle
                ;;
            4)
                show_radio_status
                ;;
            5)
                configure_powersw
                ;;
            6)
                configure_auto_power_on
                ;;
            7)
                schedule_power_off
                ;;
            8)
                cancel_poweroff_timer
                ;;
            9)
                print_header
                restart_svxlink
                pause_screen
                ;;
            0)
                return 0
                ;;
            *)
                echo
                echo "正しい番号を入力してください。"
                sleep 1
                ;;
        esac
    done
}

case "${1:-}" in
    --boot-power-on)
        boot_power_on
        exit $?
        ;;

    --timer-power-off)
        if ! is_valid_number "${2:-}"; then
            exit 1
        fi

        timer_poweroff_worker "$2"
        exit $?
        ;;
esac

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    powersw_menu
fi
