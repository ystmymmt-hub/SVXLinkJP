#!/usr/bin/env bash
#
# SVXLinkJP Audio Setup Module
# Version 1.2.0
#
# 機能:
#   - ALSA録音・再生デバイス一覧
#   - USBオーディオ優先自動検出
#   - 手動デバイス選択
#   - svxlink.conf の AUDIO_DEV 自動更新
#   - 設定バックアップ
#   - 録音・再生テスト
#   - SVXLink再起動
#

set -u

CONFIG_FILE="${SVXLINK_CONFIG:-/etc/svxlink/svxlink.conf}"
BACKUP_DIR="${SVXLINKJP_BACKUP_DIR:-/var/backups/svxlinkjp}"
TEST_WAV="${TMPDIR:-/tmp}/svxlinkjp_audio_test.wav"

SELECTED_CARD=""
SELECTED_DEVICE=""
SELECTED_NAME=""

declare -a CAPTURE_CARDS=()
declare -a CAPTURE_DEVICES=()
declare -a CAPTURE_NAMES=()

declare -a PLAYBACK_CARDS=()
declare -a PLAYBACK_DEVICES=()
declare -a PLAYBACK_NAMES=()

pause_screen()
{
    echo
    read -r -p "Enterキーを押してください..." _
}

clear_screen()
{
    if command -v clear >/dev/null 2>&1; then
        clear
    fi
}

print_header()
{
    clear_screen
    echo "========================================"
    echo " SVXLinkJP オーディオ設定 Ver.1.2.0"
    echo "========================================"
    echo
}

require_command()
{
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "エラー: ${command_name} がインストールされていません。"
        echo
        echo "次のコマンドでインストールしてください。"
        echo
        echo "  sudo apt update"
        echo "  sudo apt install alsa-utils"
        return 1
    fi

    return 0
}

run_as_root()
{
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

detect_service_name()
{
    local unit

    for unit in svxlink.service svxlink-server.service; do
        if systemctl list-unit-files "$unit" \
            --no-legend 2>/dev/null | grep -q "^${unit}"; then
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

is_svxlink_active()
{
    local service_name

    service_name="$(detect_service_name)"

    [ -n "$service_name" ] &&
        systemctl is-active --quiet "$service_name"
}

stop_svxlink_temporarily()
{
    local service_name

    service_name="$(detect_service_name)"

    if [ -z "$service_name" ]; then
        return 0
    fi

    if systemctl is-active --quiet "$service_name"; then
        echo "SVXLinkを一時停止します..."
        run_as_root systemctl stop "$service_name"
        return $?
    fi

    return 0
}

start_svxlink()
{
    local service_name

    service_name="$(detect_service_name)"

    if [ -z "$service_name" ]; then
        echo "警告: SVXLinkサービスが見つかりません。"
        return 1
    fi

    echo "SVXLinkを起動します..."
    run_as_root systemctl start "$service_name"
}

restart_svxlink()
{
    local service_name

    service_name="$(detect_service_name)"

    if [ -z "$service_name" ]; then
        echo "警告: SVXLinkサービスが見つかりません。"
        return 1
    fi

    echo "SVXLinkを再起動しています..."

    if run_as_root systemctl restart "$service_name"; then
        sleep 2

        if systemctl is-active --quiet "$service_name"; then
            echo "SVXLinkは正常に起動しました。"
            return 0
        fi

        echo "エラー: SVXLinkが起動していません。"
        echo
        run_as_root systemctl status "$service_name" \
            --no-pager --lines=15
        return 1
    fi

    echo "エラー: SVXLinkの再起動に失敗しました。"
    return 1
}

read_capture_devices()
{
    local line
    local card
    local card_id
    local card_name
    local device
    local device_id
    local device_name

    CAPTURE_CARDS=()
    CAPTURE_DEVICES=()
    CAPTURE_NAMES=()

    while IFS= read -r line; do
        if [[ "$line" =~ card[[:space:]]+([0-9]+):[[:space:]]*([^\[]+)\[([^\]]+)\],[[:space:]]*device[[:space:]]+([0-9]+):[[:space:]]*([^\[]+)\[([^\]]+)\] ]]; then
            card="${BASH_REMATCH[1]}"
            card_id="${BASH_REMATCH[2]}"
            card_name="${BASH_REMATCH[3]}"
            device="${BASH_REMATCH[4]}"
            device_id="${BASH_REMATCH[5]}"
            device_name="${BASH_REMATCH[6]}"

            card_id="$(printf '%s' "$card_id" |
                sed 's/[[:space:]]*$//')"
            device_id="$(printf '%s' "$device_id" |
                sed 's/[[:space:]]*$//')"

            CAPTURE_CARDS+=("$card")
            CAPTURE_DEVICES+=("$device")
            CAPTURE_NAMES+=(
                "${card_name} / ${device_name} (${card_id}, ${device_id})"
            )
        fi
    done < <(LC_ALL=C arecord -l 2>/dev/null)
}

read_playback_devices()
{
    local line
    local card
    local card_id
    local card_name
    local device
    local device_id
    local device_name

    PLAYBACK_CARDS=()
    PLAYBACK_DEVICES=()
    PLAYBACK_NAMES=()

    while IFS= read -r line; do
        if [[ "$line" =~ card[[:space:]]+([0-9]+):[[:space:]]*([^\[]+)\[([^\]]+)\],[[:space:]]*device[[:space:]]+([0-9]+):[[:space:]]*([^\[]+)\[([^\]]+)\] ]]; then
            card="${BASH_REMATCH[1]}"
            card_id="${BASH_REMATCH[2]}"
            card_name="${BASH_REMATCH[3]}"
            device="${BASH_REMATCH[4]}"
            device_id="${BASH_REMATCH[5]}"
            device_name="${BASH_REMATCH[6]}"

            card_id="$(printf '%s' "$card_id" |
                sed 's/[[:space:]]*$//')"
            device_id="$(printf '%s' "$device_id" |
                sed 's/[[:space:]]*$//')"

            PLAYBACK_CARDS+=("$card")
            PLAYBACK_DEVICES+=("$device")
            PLAYBACK_NAMES+=(
                "${card_name} / ${device_name} (${card_id}, ${device_id})"
            )
        fi
    done < <(LC_ALL=C aplay -l 2>/dev/null)
}

detect_audio_devices()
{
    require_command arecord || return 1
    require_command aplay || return 1

    read_capture_devices
    read_playback_devices
}

has_playback_device()
{
    local wanted_card="$1"
    local wanted_device="$2"
    local index

    for index in "${!PLAYBACK_CARDS[@]}"; do
        if [ "${PLAYBACK_CARDS[$index]}" = "$wanted_card" ] &&
            [ "${PLAYBACK_DEVICES[$index]}" = "$wanted_device" ]; then
            return 0
        fi
    done

    for index in "${!PLAYBACK_CARDS[@]}"; do
        if [ "${PLAYBACK_CARDS[$index]}" = "$wanted_card" ]; then
            return 0
        fi
    done

    return 1
}

show_current_setting()
{
    print_header

    echo "現在のSVXLinkオーディオ設定"
    echo "----------------------------------------"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "設定ファイルが見つかりません。"
        echo
        echo "$CONFIG_FILE"
        pause_screen
        return
    fi

    grep -nE '^[[:space:]]*AUDIO_DEV[[:space:]]*=' \
        "$CONFIG_FILE" || echo "AUDIO_DEV設定がありません。"

    echo
    grep -nE '^[[:space:]]*AUDIO_CHANNEL[[:space:]]*=' \
        "$CONFIG_FILE" || true

    pause_screen
}

list_audio_devices()
{
    local index

    print_header

    if ! detect_audio_devices; then
        pause_screen
        return
    fi

    echo "録音デバイス"
    echo "----------------------------------------"

    if [ "${#CAPTURE_CARDS[@]}" -eq 0 ]; then
        echo "録音デバイスが見つかりません。"
    else
        for index in "${!CAPTURE_CARDS[@]}"; do
            printf "%2d. card=%s device=%s\n" \
                "$((index + 1))" \
                "${CAPTURE_CARDS[$index]}" \
                "${CAPTURE_DEVICES[$index]}"
            printf "    %s\n" "${CAPTURE_NAMES[$index]}"
        done
    fi

    echo
    echo "再生デバイス"
    echo "----------------------------------------"

    if [ "${#PLAYBACK_CARDS[@]}" -eq 0 ]; then
        echo "再生デバイスが見つかりません。"
    else
        for index in "${!PLAYBACK_CARDS[@]}"; do
            printf "%2d. card=%s device=%s\n" \
                "$((index + 1))" \
                "${PLAYBACK_CARDS[$index]}" \
                "${PLAYBACK_DEVICES[$index]}"
            printf "    %s\n" "${PLAYBACK_NAMES[$index]}"
        done
    fi

    echo
    echo "ALSAの詳細情報"
    echo "----------------------------------------"
    echo "arecord -l"
    arecord -l 2>/dev/null || true

    echo
    echo "aplay -l"
    aplay -l 2>/dev/null || true

    pause_screen
}

auto_select_audio_device()
{
    local index
    local name
    local score
    local best_score=-1
    local best_index=-1

    detect_audio_devices || return 1

    if [ "${#CAPTURE_CARDS[@]}" -eq 0 ]; then
        echo "録音デバイスが見つかりません。"
        return 1
    fi

    for index in "${!CAPTURE_CARDS[@]}"; do
        name="${CAPTURE_NAMES[$index]}"
        score=0

        # USBオーディオを優先
        if printf '%s' "$name" |
            grep -Eqi 'USB|CM[0-9]+|C-Media|CODEC|Audio Adapter'; then
            score=$((score + 100))
        fi

        # 録音と再生の両方があるデバイスを優先
        if has_playback_device \
            "${CAPTURE_CARDS[$index]}" \
            "${CAPTURE_DEVICES[$index]}"; then
            score=$((score + 20))
        fi

        # card 0以外を少し優先し、内蔵音源を避ける
        if [ "${CAPTURE_CARDS[$index]}" -ne 0 ]; then
            score=$((score + 5))
        fi

        if printf '%s' "$name" |
            grep -Eqi 'HDMI|bcm2835|Headphones'; then
            score=$((score - 20))
        fi

        if [ "$score" -gt "$best_score" ]; then
            best_score="$score"
            best_index="$index"
        fi
    done

    if [ "$best_index" -lt 0 ]; then
        return 1
    fi

    SELECTED_CARD="${CAPTURE_CARDS[$best_index]}"
    SELECTED_DEVICE="${CAPTURE_DEVICES[$best_index]}"
    SELECTED_NAME="${CAPTURE_NAMES[$best_index]}"

    return 0
}

backup_config()
{
    local timestamp
    local backup_file

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "エラー: 設定ファイルがありません。"
        echo "$CONFIG_FILE"
        return 1
    fi

    timestamp="$(date '+%Y%m%d-%H%M%S')"
    backup_file="${BACKUP_DIR}/svxlink.conf.${timestamp}.bak"

    if ! run_as_root mkdir -p "$BACKUP_DIR"; then
        echo "エラー: バックアップディレクトリを作成できません。"
        return 1
    fi

    if ! run_as_root cp -a "$CONFIG_FILE" "$backup_file"; then
        echo "エラー: 設定ファイルをバックアップできません。"
        return 1
    fi

    echo "バックアップを作成しました。"
    echo "$backup_file"

    return 0
}

apply_audio_setting()
{
    local card="$1"
    local device="$2"
    local audio_dev
    local temp_file
    local active_count

    audio_dev="alsa:plughw:${card},${device}"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "エラー: 設定ファイルがありません。"
        echo "$CONFIG_FILE"
        return 1
    fi

    active_count="$(
        grep -cE '^[[:space:]]*AUDIO_DEV[[:space:]]*=' \
            "$CONFIG_FILE" 2>/dev/null || true
    )"

    if [ "$active_count" -eq 0 ]; then
        echo "エラー: 有効なAUDIO_DEV設定が見つかりません。"
        return 1
    fi

    backup_config || return 1

    temp_file="$(mktemp)"

    awk -v new_device="$audio_dev" '
        /^[[:space:]]*AUDIO_DEV[[:space:]]*=/ {
            match($0, /^[[:space:]]*/)
            indent = substr($0, RSTART, RLENGTH)
            print indent "AUDIO_DEV=" new_device
            next
        }
        {
            print
        }
    ' "$CONFIG_FILE" > "$temp_file"

    if ! run_as_root cp "$temp_file" "$CONFIG_FILE"; then
        rm -f "$temp_file"
        echo "エラー: 設定ファイルを更新できません。"
        return 1
    fi

    rm -f "$temp_file"

    echo
    echo "オーディオ設定を変更しました。"
    echo
    echo "  AUDIO_DEV=${audio_dev}"
    echo "  更新行数=${active_count}"
    echo

    grep -nE '^[[:space:]]*AUDIO_DEV[[:space:]]*=' \
        "$CONFIG_FILE"

    return 0
}

auto_detect_and_save()
{
    local answer

    print_header

    echo "USBオーディオを自動検出しています..."
    echo

    if ! auto_select_audio_device; then
        echo "使用可能なオーディオデバイスを検出できませんでした。"
        pause_screen
        return
    fi

    echo "推奨デバイス"
    echo "----------------------------------------"
    echo "カード番号   : $SELECTED_CARD"
    echo "デバイス番号 : $SELECTED_DEVICE"
    echo "デバイス名   : $SELECTED_NAME"
    echo
    echo "設定値:"
    echo "AUDIO_DEV=alsa:plughw:${SELECTED_CARD},${SELECTED_DEVICE}"
    echo

    read -r -p "このデバイスを設定しますか？ [Y/n]: " answer
    answer="${answer:-Y}"

    case "$answer" in
        y|Y)
            if apply_audio_setting \
                "$SELECTED_CARD" "$SELECTED_DEVICE"; then
                echo
                read -r -p \
                    "SVXLinkを再起動しますか？ [Y/n]: " answer
                answer="${answer:-Y}"

                case "$answer" in
                    y|Y)
                        restart_svxlink
                        ;;
                esac
            fi
            ;;
        *)
            echo "設定を中止しました。"
            ;;
    esac

    pause_screen
}

manual_select_audio_device()
{
    local index
    local selection
    local selected_index
    local answer

    print_header

    if ! detect_audio_devices; then
        pause_screen
        return
    fi

    if [ "${#CAPTURE_CARDS[@]}" -eq 0 ]; then
        echo "録音デバイスが見つかりません。"
        pause_screen
        return
    fi

    echo "SVXLinkで使用する録音デバイスを選択してください。"
    echo

    for index in "${!CAPTURE_CARDS[@]}"; do
        printf "%2d. card=%s device=%s\n" \
            "$((index + 1))" \
            "${CAPTURE_CARDS[$index]}" \
            "${CAPTURE_DEVICES[$index]}"
        printf "    %s\n" "${CAPTURE_NAMES[$index]}"
    done

    echo
    read -r -p "番号を入力してください [0=中止]: " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        echo "入力が正しくありません。"
        pause_screen
        return
    fi

    if [ "$selection" -eq 0 ]; then
        return
    fi

    if [ "$selection" -lt 1 ] ||
        [ "$selection" -gt "${#CAPTURE_CARDS[@]}" ]; then
        echo "選択番号が範囲外です。"
        pause_screen
        return
    fi

    selected_index=$((selection - 1))

    SELECTED_CARD="${CAPTURE_CARDS[$selected_index]}"
    SELECTED_DEVICE="${CAPTURE_DEVICES[$selected_index]}"
    SELECTED_NAME="${CAPTURE_NAMES[$selected_index]}"

    echo
    echo "選択したデバイス:"
    echo "$SELECTED_NAME"
    echo
    echo "AUDIO_DEV=alsa:plughw:${SELECTED_CARD},${SELECTED_DEVICE}"
    echo

    read -r -p "設定を保存しますか？ [Y/n]: " answer
    answer="${answer:-Y}"

    case "$answer" in
        y|Y)
            apply_audio_setting \
                "$SELECTED_CARD" "$SELECTED_DEVICE"

            echo
            read -r -p \
                "SVXLinkを再起動しますか？ [Y/n]: " answer
            answer="${answer:-Y}"

            case "$answer" in
                y|Y)
                    restart_svxlink
                    ;;
            esac
            ;;
        *)
            echo "設定を中止しました。"
            ;;
    esac

    pause_screen
}

get_configured_device()
{
    local setting

    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    setting="$(
        grep -m1 -E '^[[:space:]]*AUDIO_DEV[[:space:]]*=' \
            "$CONFIG_FILE" |
        sed -E 's/^[[:space:]]*AUDIO_DEV[[:space:]]*=[[:space:]]*//'
    )"

    setting="${setting#alsa:}"

    if [ -z "$setting" ]; then
        return 1
    fi

    printf '%s\n' "$setting"
}

record_test()
{
    local device
    local was_active=0
    local answer

    print_header

    require_command arecord || {
        pause_screen
        return
    }

    device="$(get_configured_device)" || {
        echo "AUDIO_DEV設定を取得できません。"
        pause_screen
        return
    }

    echo "録音テスト"
    echo "----------------------------------------"
    echo "使用デバイス : $device"
    echo "録音時間     : 5秒"
    echo "保存先       : $TEST_WAV"
    echo
    echo "マイクへ向かって話してください。"
    echo

    if is_svxlink_active; then
        was_active=1
        echo "SVXLinkがオーディオデバイスを使用中です。"
        read -r -p \
            "SVXLinkを一時停止して録音しますか？ [Y/n]: " answer
        answer="${answer:-Y}"

        case "$answer" in
            y|Y)
                stop_svxlink_temporarily || {
                    pause_screen
                    return
                }
                ;;
            *)
                echo "録音テストを中止しました。"
                pause_screen
                return
                ;;
        esac
    fi

    rm -f "$TEST_WAV"

    if arecord \
        -D "$device" \
        -d 5 \
        -f S16_LE \
        -r 48000 \
        -c 1 \
        "$TEST_WAV"; then
        echo
        echo "録音テストが完了しました。"
        echo "$TEST_WAV"
    else
        echo
        echo "録音に失敗しました。"
        echo
        echo "別の形式で再試行します..."

        if arecord \
            -D "$device" \
            -d 5 \
            -f S16_LE \
            -r 44100 \
            -c 1 \
            "$TEST_WAV"; then
            echo "44100Hzで録音できました。"
        else
            echo "録音テストに失敗しました。"
        fi
    fi

    if [ "$was_active" -eq 1 ]; then
        start_svxlink
    fi

    pause_screen
}

playback_test()
{
    local device
    local card
    local card_device
    local was_active=0
    local answer

    print_header

    require_command aplay || {
        pause_screen
        return
    }

    if [ ! -s "$TEST_WAV" ]; then
        echo "録音テストファイルがありません。"
        echo
        echo "先に「録音テスト」を実行してください。"
        pause_screen
        return
    fi

    device="$(get_configured_device)" || {
        echo "AUDIO_DEV設定を取得できません。"
        pause_screen
        return
    }

    # plughw:CARD,DEVICE 形式から番号を抽出
    card_device="${device#plughw:}"
    card_device="${card_device#hw:}"
    card="${card_device%%,*}"

    # 再生側のデバイス番号は通常0
    device="plughw:${card},0"

    echo "再生テスト"
    echo "----------------------------------------"
    echo "使用デバイス : $device"
    echo "再生ファイル : $TEST_WAV"
    echo

    if is_svxlink_active; then
        was_active=1
        echo "SVXLinkがオーディオデバイスを使用中です。"
        read -r -p \
            "SVXLinkを一時停止して再生しますか？ [Y/n]: " answer
        answer="${answer:-Y}"

        case "$answer" in
            y|Y)
                stop_svxlink_temporarily || {
                    pause_screen
                    return
                }
                ;;
            *)
                echo "再生テストを中止しました。"
                pause_screen
                return
                ;;
        esac
    fi

    if aplay -D "$device" "$TEST_WAV"; then
        echo
        echo "再生テストが完了しました。"
    else
        echo
        echo "指定デバイスで再生できませんでした。"
        echo "デフォルトデバイスで再試行します..."

        if aplay "$TEST_WAV"; then
            echo "デフォルトデバイスで再生できました。"
        else
            echo "再生テストに失敗しました。"
        fi
    fi

    if [ "$was_active" -eq 1 ]; then
        start_svxlink
    fi

    pause_screen
}

show_audio_status()
{
    local service_name

    print_header

    echo "オーディオ診断"
    echo "========================================"
    echo

    echo "[SVXLink設定]"
    if [ -f "$CONFIG_FILE" ]; then
        grep -nE \
            '^[[:space:]]*(CARD_SAMPLE_RATE|CARD_CHANNELS|AUDIO_DEV|AUDIO_CHANNEL)[[:space:]]*=' \
            "$CONFIG_FILE" || true
    else
        echo "$CONFIG_FILE がありません。"
    fi

    echo
    echo "[ALSAカード]"
    if [ -r /proc/asound/cards ]; then
        cat /proc/asound/cards
    else
        echo "ALSAカード情報を取得できません。"
    fi

    echo
    echo "[録音デバイス]"
    arecord -l 2>&1 || true

    echo
    echo "[再生デバイス]"
    aplay -l 2>&1 || true

    echo
    echo "[SVXLinkサービス]"
    service_name="$(detect_service_name)"

    if [ -n "$service_name" ]; then
        systemctl is-active "$service_name" 2>/dev/null || true
        systemctl status "$service_name" \
            --no-pager --lines=8 2>/dev/null || true
    else
        echo "SVXLinkサービスが見つかりません。"
    fi

    pause_screen
}

audio_menu()
{
    local choice

    while true; do
        print_header

        echo " 1. USBオーディオ自動検出・設定"
        echo " 2. オーディオデバイス一覧"
        echo " 3. オーディオデバイス手動選択"
        echo " 4. 現在のSVXLink設定"
        echo " 5. 録音テスト（5秒）"
        echo " 6. 録音ファイル再生テスト"
        echo " 7. オーディオ診断"
        echo " 8. SVXLink再起動"
        echo " 0. 戻る"
        echo

        read -r -p "選択してください: " choice

        case "$choice" in
            1)
                auto_detect_and_save
                ;;
            2)
                list_audio_devices
                ;;
            3)
                manual_select_audio_device
                ;;
            4)
                show_current_setting
                ;;
            5)
                record_test
                ;;
            6)
                playback_test
                ;;
            7)
                show_audio_status
                ;;
            8)
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

# 直接実行された場合はAudioメニューを起動する。
# menu.shからsourceされた場合はaudio_menu関数だけを提供する。
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    audio_menu
fi
