#!/usr/bin/env bash
#
# SVXLinkJP GPIO Setup Module
# Version 1.2.0
#
# 機能:
#   - GPIOチップ・GPIOライン自動検出
#   - COS入力監視
#   - COS/PTT GPIO番号設定
#   - PTT 1秒テスト
#   - svxlink.conf 自動バックアップ
#   - SVXLink再起動
#

set -u

CONFIG_FILE="${SVXLINK_CONFIG:-/etc/svxlink/svxlink.conf}"
BACKUP_DIR="${SVXLINKJP_BACKUP_DIR:-/var/backups/svxlinkjp}"

GPIO_CHIP="${GPIO_CHIP:-gpiochip0}"
COS_GPIO=""
PTT_GPIO=""
COS_ACTIVE_LOW="1"
PTT_ACTIVE_LOW="1"

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
    echo " SVXLinkJP GPIO設定 Ver.1.2.0"
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

require_gpio_tools()
{
    local missing=0
    local cmd

    for cmd in gpiodetect gpioinfo gpioget gpioset gpiomon; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "不足コマンド: $cmd"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        echo
        echo "GPIOツールをインストールしてください。"
        echo
        echo "  sudo apt update"
        echo "  sudo apt install gpiod"
        return 1
    fi

    return 0
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

    printf '%s\n' ""
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
    run_as_root systemctl status "$service_name" \
        --no-pager --lines=15 2>/dev/null || true
    return 1
}

stop_svxlink()
{
    local service_name

    service_name="$(detect_service_name)"

    if [ -n "$service_name" ] &&
        systemctl is-active --quiet "$service_name"; then
        run_as_root systemctl stop "$service_name"
        return 0
    fi

    return 0
}

start_svxlink()
{
    local service_name

    service_name="$(detect_service_name)"

    if [ -n "$service_name" ]; then
        run_as_root systemctl start "$service_name"
    fi
}

is_valid_gpio_number()
{
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

show_gpio_chips()
{
    print_header

    if ! require_gpio_tools; then
        pause_screen
        return
    fi

    echo "GPIOチップ一覧"
    echo "----------------------------------------"
    gpiodetect 2>&1 || true

    echo
    echo "GPIOライン情報"
    echo "----------------------------------------"
    gpioinfo "$GPIO_CHIP" 2>&1 || {
        echo
        echo "${GPIO_CHIP}を取得できません。"
        echo "別のGPIOチップ名を設定してください。"
    }

    pause_screen
}

select_gpio_chip()
{
    local chip

    print_header

    require_gpio_tools || {
        pause_screen
        return
    }

    echo "使用可能なGPIOチップ"
    echo "----------------------------------------"
    gpiodetect 2>/dev/null || true

    echo
    echo "現在の設定: $GPIO_CHIP"
    read -r -p \
        "GPIOチップ名を入力してください [${GPIO_CHIP}]: " chip

    chip="${chip:-$GPIO_CHIP}"

    if [ ! -e "/dev/${chip}" ]; then
        echo
        echo "警告: /dev/${chip} が見つかりません。"
        pause_screen
        return
    fi

    GPIO_CHIP="$chip"

    echo
    echo "GPIOチップを設定しました: $GPIO_CHIP"
    pause_screen
}

show_current_gpio_config()
{
    print_header

    echo "現在のGPIO設定"
    echo "----------------------------------------"
    echo "GPIOチップ    : $GPIO_CHIP"
    echo "COS GPIO      : ${COS_GPIO:-未設定}"
    echo "PTT GPIO      : ${PTT_GPIO:-未設定}"
    echo "COS ActiveLow : $COS_ACTIVE_LOW"
    echo "PTT ActiveLow : $PTT_ACTIVE_LOW"

    echo
    echo "svxlink.conf内のGPIO関連設定"
    echo "----------------------------------------"

    if [ -f "$CONFIG_FILE" ]; then
        grep -nEi \
            '^[[:space:]]*(GPIO|SQL_DET|SQL_GPIOD|PTT|PTT_GPIOD|RX_GPIO|TX_GPIO)' \
            "$CONFIG_FILE" 2>/dev/null ||
            echo "GPIO関連設定は見つかりませんでした。"
    else
        echo "$CONFIG_FILE が見つかりません。"
    fi

    pause_screen
}

set_cos_gpio()
{
    local value
    local polarity

    print_header

    echo "COS入力GPIO設定"
    echo "----------------------------------------"
    echo "無線機のCOSまたはSQL信号を接続したGPIO番号です。"
    echo
    echo "現在値: ${COS_GPIO:-未設定}"
    echo

    read -r -p "COS GPIO番号を入力してください: " value

    if ! is_valid_gpio_number "$value"; then
        echo "GPIO番号が正しくありません。"
        pause_screen
        return
    fi

    echo
    echo "信号論理を選択してください。"
    echo "  1. Active Low：受信時にLOW"
    echo "  2. Active High：受信時にHIGH"
    echo
    read -r -p "選択 [1]: " polarity

    case "${polarity:-1}" in
        1)
            COS_ACTIVE_LOW="1"
            ;;
        2)
            COS_ACTIVE_LOW="0"
            ;;
        *)
            echo "選択が正しくありません。"
            pause_screen
            return
            ;;
    esac

    COS_GPIO="$value"

    echo
    echo "COS GPIOを設定しました。"
    echo "GPIO: $COS_GPIO"
    echo "Active Low: $COS_ACTIVE_LOW"
    pause_screen
}

set_ptt_gpio()
{
    local value
    local polarity

    print_header

    echo "PTT出力GPIO設定"
    echo "----------------------------------------"
    echo "送信制御に使用するGPIO番号です。"
    echo
    echo "現在値: ${PTT_GPIO:-未設定}"
    echo

    read -r -p "PTT GPIO番号を入力してください: " value

    if ! is_valid_gpio_number "$value"; then
        echo "GPIO番号が正しくありません。"
        pause_screen
        return
    fi

    echo
    echo "PTT信号論理を選択してください。"
    echo "  1. Active Low：LOWで送信"
    echo "  2. Active High：HIGHで送信"
    echo
    read -r -p "選択 [1]: " polarity

    case "${polarity:-1}" in
        1)
            PTT_ACTIVE_LOW="1"
            ;;
        2)
            PTT_ACTIVE_LOW="0"
            ;;
        *)
            echo "選択が正しくありません。"
            pause_screen
            return
            ;;
    esac

    PTT_GPIO="$value"

    echo
    echo "PTT GPIOを設定しました。"
    echo "GPIO: $PTT_GPIO"
    echo "Active Low: $PTT_ACTIVE_LOW"
    pause_screen
}

read_gpio_value()
{
    local gpio="$1"

    if gpioget --help 2>&1 | grep -q -- '--chip'; then
        gpioget --chip "$GPIO_CHIP" "$gpio"
    else
        gpioget "$GPIO_CHIP" "$gpio"
    fi
}

cos_status_test()
{
    local count
    local value
    local state

    print_header

    require_gpio_tools || {
        pause_screen
        return
    }

    if [ -z "$COS_GPIO" ]; then
        echo "先にCOS GPIO番号を設定してください。"
        pause_screen
        return
    fi

    echo "COS入力状態を10秒間表示します。"
    echo "無線機へ信号を入れて確認してください。"
    echo
    echo "GPIO: $COS_GPIO"
    echo "終了する場合は Ctrl+C"
    echo

    for count in $(seq 1 20); do
        value="$(read_gpio_value "$COS_GPIO" 2>/dev/null)" || {
            echo
            echo "GPIOを読み取れませんでした。"
            echo "他のプロセスが使用中の可能性があります。"
            break
        }

        value="${value##* }"

        if [ "$COS_ACTIVE_LOW" = "1" ]; then
            if [ "$value" = "0" ]; then
                state="受信中・COS ON"
            else
                state="待機中・COS OFF"
            fi
        else
            if [ "$value" = "1" ]; then
                state="受信中・COS ON"
            else
                state="待機中・COS OFF"
            fi
        fi

        printf '\rGPIO=%s  値=%s  %-24s' \
            "$COS_GPIO" "$value" "$state"

        sleep 0.5
    done

    echo
    pause_screen
}

cos_edge_monitor()
{
    print_header

    require_gpio_tools || {
        pause_screen
        return
    }

    if [ -z "$COS_GPIO" ]; then
        echo "先にCOS GPIO番号を設定してください。"
        pause_screen
        return
    fi

    echo "COS信号の変化を監視します。"
    echo "無線機へ信号を入れると変化が表示されます。"
    echo
    echo "GPIO: $COS_GPIO"
    echo "監視時間: 15秒"
    echo

    if gpiomon --help 2>&1 | grep -q -- '--chip'; then
        timeout 15 \
            gpiomon \
            --chip "$GPIO_CHIP" \
            --edges both \
            "$COS_GPIO" 2>&1 || true
    else
        timeout 15 \
            gpiomon \
            --num-events 20 \
            "$GPIO_CHIP" \
            "$COS_GPIO" 2>&1 || true
    fi

    echo
    echo "監視を終了しました。"
    pause_screen
}

run_gpioset_timed()
{
    local gpio="$1"
    local active_value="$2"
    local inactive_value="$3"

    if gpioset --help 2>&1 | grep -q -- '--toggle'; then
        gpioset \
            --chip "$GPIO_CHIP" \
            --toggle 1s,0 \
            "${gpio}=${active_value}"
    elif gpioset --help 2>&1 | grep -q -- '--mode'; then
        gpioset \
            --mode=time \
            --sec=1 \
            "$GPIO_CHIP" \
            "${gpio}=${active_value}"
    else
        gpioset \
            "$GPIO_CHIP" \
            "${gpio}=${active_value}" &
        local pid=$!

        sleep 1
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true

        gpioset \
            "$GPIO_CHIP" \
            "${gpio}=${inactive_value}" &
        local reset_pid=$!

        sleep 0.2
        kill "$reset_pid" 2>/dev/null || true
        wait "$reset_pid" 2>/dev/null || true
    fi
}

ptt_test()
{
    local answer
    local active_value
    local inactive_value
    local was_active=0

    print_header

    require_gpio_tools || {
        pause_screen
        return
    }

    if [ -z "$PTT_GPIO" ]; then
        echo "先にPTT GPIO番号を設定してください。"
        pause_screen
        return
    fi

    echo "警告"
    echo "========================================"
    echo "このテストを実行すると無線機が1秒間送信状態になります。"
    echo
    echo "・アンテナまたはダミーロードを接続してください。"
    echo "・使用周波数が空いていることを確認してください。"
    echo "・PTT回路を直接GPIOへ接続しないでください。"
    echo "・トランジスタまたはフォトカプラを使用してください。"
    echo
    echo "GPIO      : $PTT_GPIO"
    echo "ActiveLow : $PTT_ACTIVE_LOW"
    echo

    read -r -p \
        "安全を確認しました。PTTテストを実行しますか？ [y/N]: " \
        answer

    case "$answer" in
        y|Y)
            ;;
        *)
            echo "PTTテストを中止しました。"
            pause_screen
            return
            ;;
    esac

    if [ "$PTT_ACTIVE_LOW" = "1" ]; then
        active_value="0"
        inactive_value="1"
    else
        active_value="1"
        inactive_value="0"
    fi

    local service_name
    service_name="$(detect_service_name)"

    if [ -n "$service_name" ] &&
        systemctl is-active --quiet "$service_name"; then
        was_active=1
        echo
        echo "SVXLinkを一時停止します..."
        stop_svxlink || {
            echo "SVXLinkを停止できませんでした。"
            pause_screen
            return
        }
    fi

    echo
    echo "3秒後に1秒間PTTをONにします..."
    sleep 1
    echo "3"
    sleep 1
    echo "2"
    sleep 1
    echo "1"

    if run_gpioset_timed \
        "$PTT_GPIO" "$active_value" "$inactive_value"; then
        echo
        echo "PTTテストが終了しました。"
    else
        echo
        echo "PTT GPIOを制御できませんでした。"
        echo "GPIOが使用中または権限不足の可能性があります。"
    fi

    if [ "$was_active" -eq 1 ]; then
        echo "SVXLinkを再起動します..."
        start_svxlink
    fi

    pause_screen
}

backup_config()
{
    local timestamp
    local backup_file

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "設定ファイルが見つかりません。"
        echo "$CONFIG_FILE"
        return 1
    fi

    timestamp="$(date '+%Y%m%d-%H%M%S')"
    backup_file="${BACKUP_DIR}/svxlink.conf.${timestamp}.bak"

    run_as_root mkdir -p "$BACKUP_DIR" || return 1
    run_as_root cp -a "$CONFIG_FILE" "$backup_file" || return 1

    echo "バックアップを作成しました。"
    echo "$backup_file"
}

update_or_append_setting()
{
    local file="$1"
    local key="$2"
    local value="$3"
    local temp_file

    temp_file="$(mktemp)"

    awk -v key="$key" -v value="$value" '
        BEGIN {
            updated = 0
        }

        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            if (updated == 0) {
                print key "=" value
                updated = 1
            }
            next
        }

        {
            print
        }

        END {
            if (updated == 0) {
                print key "=" value
            }
        }
    ' "$file" > "$temp_file"

    run_as_root cp "$temp_file" "$file"
    local result=$?

    rm -f "$temp_file"
    return "$result"
}

save_gpio_settings()
{
    local answer

    print_header

    if [ -z "$COS_GPIO" ] || [ -z "$PTT_GPIO" ]; then
        echo "COSまたはPTT GPIOが未設定です。"
        echo
        echo "COS: ${COS_GPIO:-未設定}"
        echo "PTT: ${PTT_GPIO:-未設定}"
        pause_screen
        return
    fi

    echo "保存するGPIO設定"
    echo "----------------------------------------"
    echo "GPIO_CHIP=$GPIO_CHIP"
    echo "COS_GPIO=$COS_GPIO"
    echo "COS_ACTIVE_LOW=$COS_ACTIVE_LOW"
    echo "PTT_GPIO=$PTT_GPIO"
    echo "PTT_ACTIVE_LOW=$PTT_ACTIVE_LOW"
    echo
    echo "注意:"
    echo "SVXLinkの設定キーは構成やパッケージにより異なります。"
    echo "このモジュールではSVXLinkJP管理用設定として保存します。"
    echo

    read -r -p "保存しますか？ [y/N]: " answer

    case "$answer" in
        y|Y)
            ;;
        *)
            echo "保存を中止しました。"
            pause_screen
            return
            ;;
    esac

    backup_config || {
        echo "バックアップに失敗しました。"
        pause_screen
        return
    }

    update_or_append_setting \
        "$CONFIG_FILE" \
        "SVXLINKJP_GPIO_CHIP" \
        "$GPIO_CHIP" || return

    update_or_append_setting \
        "$CONFIG_FILE" \
        "SVXLINKJP_COS_GPIO" \
        "$COS_GPIO" || return

    update_or_append_setting \
        "$CONFIG_FILE" \
        "SVXLINKJP_COS_ACTIVE_LOW" \
        "$COS_ACTIVE_LOW" || return

    update_or_append_setting \
        "$CONFIG_FILE" \
        "SVXLINKJP_PTT_GPIO" \
        "$PTT_GPIO" || return

    update_or_append_setting \
        "$CONFIG_FILE" \
        "SVXLINKJP_PTT_ACTIVE_LOW" \
        "$PTT_ACTIVE_LOW" || return

    echo
    echo "GPIO設定を保存しました。"
    echo
    grep -nE \
        '^SVXLINKJP_(GPIO_CHIP|COS_GPIO|COS_ACTIVE_LOW|PTT_GPIO|PTT_ACTIVE_LOW)=' \
        "$CONFIG_FILE" || true

    echo
    read -r -p "SVXLinkを再起動しますか？ [Y/n]: " answer

    case "${answer:-Y}" in
        y|Y)
            restart_svxlink
            ;;
    esac

    pause_screen
}

load_saved_settings()
{
    local value

    [ -f "$CONFIG_FILE" ] || return 0

    value="$(
        grep -m1 '^SVXLINKJP_GPIO_CHIP=' "$CONFIG_FILE" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && GPIO_CHIP="$value"

    value="$(
        grep -m1 '^SVXLINKJP_COS_GPIO=' "$CONFIG_FILE" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && COS_GPIO="$value"

    value="$(
        grep -m1 '^SVXLINKJP_PTT_GPIO=' "$CONFIG_FILE" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && PTT_GPIO="$value"

    value="$(
        grep -m1 '^SVXLINKJP_COS_ACTIVE_LOW=' \
            "$CONFIG_FILE" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && COS_ACTIVE_LOW="$value"

    value="$(
        grep -m1 '^SVXLINKJP_PTT_ACTIVE_LOW=' \
            "$CONFIG_FILE" 2>/dev/null |
        cut -d= -f2-
    )"
    [ -n "$value" ] && PTT_ACTIVE_LOW="$value"
}

gpio_diagnosis()
{
    local service_name

    print_header

    echo "GPIO診断"
    echo "========================================"
    echo

    echo "[GPIOデバイス]"
    ls -l /dev/gpiochip* 2>&1 || true

    echo
    echo "[GPIOチップ]"
    if command -v gpiodetect >/dev/null 2>&1; then
        gpiodetect 2>&1 || true
    else
        echo "gpiodetectがありません。"
    fi

    echo
    echo "[現在の設定]"
    echo "GPIO_CHIP=$GPIO_CHIP"
    echo "COS_GPIO=${COS_GPIO:-未設定}"
    echo "COS_ACTIVE_LOW=$COS_ACTIVE_LOW"
    echo "PTT_GPIO=${PTT_GPIO:-未設定}"
    echo "PTT_ACTIVE_LOW=$PTT_ACTIVE_LOW"

    echo
    echo "[GPIOライン使用状況]"
    if command -v gpioinfo >/dev/null 2>&1; then
        gpioinfo "$GPIO_CHIP" 2>&1 || true
    fi

    echo
    echo "[SVXLinkサービス]"
    service_name="$(detect_service_name)"

    if [ -n "$service_name" ]; then
        systemctl is-active "$service_name" 2>/dev/null || true
        systemctl status "$service_name" \
            --no-pager --lines=10 2>/dev/null || true
    else
        echo "SVXLinkサービスが見つかりません。"
    fi

    pause_screen
}

gpio_menu()
{
    local choice

    load_saved_settings

    while true; do
        print_header

        echo " GPIOチップ : $GPIO_CHIP"
        echo " COS GPIO   : ${COS_GPIO:-未設定}"
        echo " PTT GPIO   : ${PTT_GPIO:-未設定}"
        echo
        echo " 1. GPIOチップ・ライン一覧"
        echo " 2. GPIOチップ選択"
        echo " 3. COS GPIO設定"
        echo " 4. PTT GPIO設定"
        echo " 5. COS現在値テスト"
        echo " 6. COS信号変化監視"
        echo " 7. PTT 1秒送信テスト"
        echo " 8. GPIO設定保存"
        echo " 9. 現在のGPIO設定表示"
        echo "10. GPIO診断"
        echo "11. SVXLink再起動"
        echo " 0. 戻る"
        echo

        read -r -p "選択してください: " choice

        case "$choice" in
            1)
                show_gpio_chips
                ;;
            2)
                select_gpio_chip
                ;;
            3)
                set_cos_gpio
                ;;
            4)
                set_ptt_gpio
                ;;
            5)
                cos_status_test
                ;;
            6)
                cos_edge_monitor
                ;;
            7)
                ptt_test
                ;;
            8)
                save_gpio_settings
                ;;
            9)
                show_current_gpio_config
                ;;
            10)
                gpio_diagnosis
                ;;
            11)
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    gpio_menu
fi
