#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${PROJECT_DIR}/config/echolink_announce.conf"

DEFAULT_SOURCE_WAV="/usr/share/svxlink/sounds/ja_JP/JQ1YOF_echo_.wav"
DEFAULT_LANGUAGE="en_US"
DEFAULT_SOUND_ROOT="/usr/share/svxlink/sounds"
DEFAULT_SOUND_PACK_URL="https://github.com/sm0svx/svxlink-sounds-en_US-heather/releases/download/19.09/svxlink-sounds-en_US-heather-16k-19.09.tar.bz2"

ENABLE=1
SOURCE_WAV="${DEFAULT_SOURCE_WAV}"
LANGUAGE="${DEFAULT_LANGUAGE}"
SOUND_ROOT="${DEFAULT_SOUND_ROOT}"
SOUND_PACK_URL="${DEFAULT_SOUND_PACK_URL}"

print_ok() {
    printf '[ OK ] %s\n' "$*"
}

print_info() {
    printf '[INFO] %s\n' "$*"
}

print_warn() {
    printf '[WARN] %s\n' "$*" >&2
}

print_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

require_command() {
    local cmd="$1"

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        print_error "必要なコマンドがありません: ${cmd}"
        return 1
    fi
}

load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${CONFIG_FILE}"

        # 相対パスはSVXLinkJPのプロジェクトディレクトリ基準
        if [[ "${SOURCE_WAV}" != /* ]]; then
            SOURCE_WAV="${PROJECT_DIR}/${SOURCE_WAV}"
        fi
    else
        print_warn "設定ファイルがありません: ${CONFIG_FILE}"
        print_info "標準設定を使用します"
    fi

    : "${ENABLE:=1}"
    : "${SOURCE_WAV:=${DEFAULT_SOURCE_WAV}}"
    : "${LANGUAGE:=${DEFAULT_LANGUAGE}}"
    : "${SOUND_ROOT:=${DEFAULT_SOUND_ROOT}}"
    : "${SOUND_PACK_URL:=${DEFAULT_SOUND_PACK_URL}}"
}

sound_language_dir() {
    printf '%s/%s' "${SOUND_ROOT%/}" "${LANGUAGE}"
}

greeting_file() {
    printf '%s/EchoLink/greeting.wav' "$(sound_language_dir)"
}

original_file() {
    printf '%s.svxlink-original' "$(greeting_file)"
}

disabled_file() {
    printf '%s.svxlinkjp-disabled' "$(greeting_file)"
}

check_source_wav() {
    if [[ ! -f "${SOURCE_WAV}" ]]; then
        print_error "元音声ファイルがありません"
        print_error "${SOURCE_WAV}"
        return 1
    fi

    if ! ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,sample_rate,channels,bits_per_sample \
        -of default=noprint_wrappers=1 \
        "${SOURCE_WAV}" >/dev/null 2>&1; then
        print_error "音声ファイルを解析できません"
        return 1
    fi
}

show_audio_info() {
    local file="$1"

    if [[ ! -f "${file}" ]]; then
        print_warn "ファイルがありません: ${file}"
        return 1
    fi

    ffprobe -v error \
        -select_streams a:0 \
        -show_entries stream=codec_name,sample_rate,channels,bits_per_sample,bit_rate \
        -of default=noprint_wrappers=1 \
        "${file}"
}

install_sound_pack() {
    local language_dir
    local greeting
    local temp_dir
    local archive
    local extracted_dir

    language_dir="$(sound_language_dir)"
    greeting="$(greeting_file)"

    if [[ -f "${greeting}" ]]; then
        print_ok "英語音声パックはすでに存在します"
        return 0
    fi

    require_command wget || return 1
    require_command tar || return 1

    temp_dir="$(mktemp -d)"
    archive="${temp_dir}/svxlink-sounds.tar.bz2"

    cleanup_pack() {
        rm -rf "${temp_dir}"
    }
    trap cleanup_pack RETURN

    print_info "英語16kHz音声パックをダウンロードします"
    if ! wget -q --show-progress \
        -O "${archive}" \
        "${SOUND_PACK_URL}"; then
        print_error "音声パックのダウンロードに失敗しました"
        return 1
    fi

    print_info "音声パックを展開します"
    if ! tar -xjf "${archive}" -C "${temp_dir}"; then
        print_error "音声パックの展開に失敗しました"
        return 1
    fi

    extracted_dir="$(
        find "${temp_dir}" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -name 'en_US*16k*' \
            | head -n 1
    )"

    if [[ -z "${extracted_dir}" ]]; then
        print_error "展開された音声ディレクトリを検出できません"
        return 1
    fi

    print_info "インストール先: ${language_dir}"

    if ! sudo mkdir -p "${language_dir}"; then
        print_error "音声ディレクトリを作成できません"
        return 1
    fi

    if ! sudo cp -a "${extracted_dir}/." "${language_dir}/"; then
        print_error "音声パックをコピーできません"
        return 1
    fi

    if [[ ! -f "${greeting}" ]]; then
        print_error "greeting.wavが見つかりません"
        print_error "${greeting}"
        return 1
    fi

    print_ok "英語16kHz音声パックをインストールしました"
}

backup_original_greeting() {
    local greeting
    local original

    greeting="$(greeting_file)"
    original="$(original_file)"

    if [[ ! -f "${greeting}" ]]; then
        print_error "標準greeting.wavがありません"
        return 1
    fi

    if [[ -f "${original}" ]]; then
        print_info "標準音声バックアップはすでに存在します"
        return 0
    fi

    if ! sudo cp -a "${greeting}" "${original}"; then
        print_error "標準音声のバックアップに失敗しました"
        return 1
    fi

    print_ok "標準greeting.wavを保存しました"
    print_info "${original}"
}

convert_and_install() {
    local greeting
    local temp_wav

    greeting="$(greeting_file)"
    temp_wav="$(mktemp --suffix=.wav)"

    cleanup_wav() {
        rm -f "${temp_wav}"
    }
    trap cleanup_wav RETURN

    require_command ffmpeg || return 1
    require_command ffprobe || return 1
    check_source_wav || return 1

    print_info "16kHz・16bit・mono・PCMへ変換します"

    if ! ffmpeg -hide_banner -loglevel error -y \
        -i "${SOURCE_WAV}" \
        -map_metadata -1 \
        -acodec pcm_s16le \
        -ar 16000 \
        -ac 1 \
        "${temp_wav}"; then
        print_error "音声変換に失敗しました"
        return 1
    fi

    if ! sudo install \
        -o root \
        -g root \
        -m 0644 \
        "${temp_wav}" \
        "${greeting}"; then
        print_error "greeting.wavの設置に失敗しました"
        return 1
    fi

    print_ok "独自接続アナウンスを設置しました"
    print_info "${greeting}"

    echo
    show_audio_info "${greeting}"
}

remove_old_tcl_block() {
    local tcl_file="/usr/share/svxlink/events.d/EchoLink.tcl"
    local backup_dir="/var/backups/svxlinkjp/echolink"
    local timestamp
    local backup_file

    if [[ ! -f "${tcl_file}" ]]; then
        print_warn "EchoLink.tclがありません: ${tcl_file}"
        return 0
    fi

    if ! grep -q \
        '^# BEGIN SVXLINKJP ECHOLINK ANNOUNCEMENT$' \
        "${tcl_file}"; then
        print_info "旧Tcl管理ブロックはありません"
        return 0
    fi

    timestamp="$(date '+%Y%m%d-%H%M%S')"
    backup_file="${backup_dir}/EchoLink.tcl.${timestamp}.before-soundpack.bak"

    sudo mkdir -p "${backup_dir}" || return 1
    sudo cp -a "${tcl_file}" "${backup_file}" || return 1

    if ! sudo python3 - "${tcl_file}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

begin = "# BEGIN SVXLINKJP ECHOLINK ANNOUNCEMENT"
end = "# END SVXLINKJP ECHOLINK ANNOUNCEMENT"

start = text.find(begin)
finish = text.find(end)

if start == -1 and finish == -1:
    raise SystemExit(0)

if start == -1 or finish == -1 or finish < start:
    raise SystemExit("管理ブロックの範囲が不正です")

finish += len(end)

before = text[:start].rstrip()
after = text[finish:].lstrip()

path.write_text(before + "\n\n" + after, encoding="utf-8")
PY
    then
        print_error "旧Tcl管理ブロックの削除に失敗しました"
        return 1
    fi

    print_ok "旧Tcl管理ブロックを削除しました"
    print_info "バックアップ: ${backup_file}"
}

restart_svxlink() {
    print_info "SVXLinkを再起動します"

    if ! sudo systemctl restart svxlink; then
        print_error "SVXLinkの再起動に失敗しました"
        return 1
    fi

    sleep 2

    if systemctl is-active --quiet svxlink; then
        print_ok "SVXLinkは稼働中です"
        return 0
    fi

    print_error "SVXLinkが起動していません"
    sudo systemctl --no-pager --full status svxlink || true
    return 1
}

apply_announcement() {
    load_config

    if [[ "${ENABLE}" != "1" ]]; then
        print_warn "ENABLE=0です"
        print_info "有効化する場合は設定をENABLE=1へ変更してください"
        return 1
    fi

    remove_old_tcl_block || return 1
    install_sound_pack || return 1
    backup_original_greeting || return 1
    convert_and_install || return 1
    restart_svxlink || return 1

    echo
    print_ok "JR6PUE方式の接続アナウンスを適用しました"
}

disable_announcement() {
    local greeting
    local original
    local disabled

    load_config

    greeting="$(greeting_file)"
    original="$(original_file)"
    disabled="$(disabled_file)"

    if [[ ! -f "${original}" ]]; then
        print_error "標準音声バックアップがありません"
        print_error "${original}"
        return 1
    fi

    if [[ -f "${greeting}" ]]; then
        sudo cp -a "${greeting}" "${disabled}" || return 1
    fi

    sudo cp -a "${original}" "${greeting}" || return 1

    print_ok "標準greeting.wavへ戻しました"
    restart_svxlink
}

enable_announcement() {
    local greeting
    local disabled

    load_config

    greeting="$(greeting_file)"
    disabled="$(disabled_file)"

    if [[ -f "${disabled}" ]]; then
        sudo cp -a "${disabled}" "${greeting}" || return 1
        print_ok "独自接続アナウンスを再度有効にしました"
        restart_svxlink
        return $?
    fi

    print_info "保存済み独自音声がないため再適用します"
    apply_announcement
}

restore_original() {
    disable_announcement
}

show_status() {
    local greeting
    local original

    load_config

    greeting="$(greeting_file)"
    original="$(original_file)"

    echo "========================================"
    echo " EchoLink 接続アナウンス状態"
    echo "========================================"
    echo "方式       : EchoLink/greeting.wav 差替え"
    echo "有効設定   : ${ENABLE}"
    echo "元音声     : ${SOURCE_WAV}"
    echo "言語       : ${LANGUAGE}"
    echo "音声ルート : ${SOUND_ROOT}"
    echo "接続音声   : ${greeting}"
    echo

    if [[ -f "${greeting}" ]]; then
        print_ok "greeting.wavは存在します"
        show_audio_info "${greeting}" || true
    else
        print_warn "greeting.wavがありません"
    fi

    echo

    if [[ -f "${original}" ]]; then
        print_ok "標準音声バックアップがあります"
    else
        print_warn "標準音声バックアップがありません"
    fi

    if grep -q \
        '^# BEGIN SVXLINKJP ECHOLINK ANNOUNCEMENT$' \
        /usr/share/svxlink/events.d/EchoLink.tcl 2>/dev/null; then
        print_warn "旧Tcl管理ブロックが残っています"
    else
        print_ok "旧Tcl管理ブロックはありません"
    fi

    if systemctl is-active --quiet svxlink; then
        print_ok "SVXLinkは稼働中です"
    else
        print_warn "SVXLinkは停止中です"
    fi
}

show_help() {
    cat <<EOF_HELP
使用方法:

  $0 install-pack
      英語16kHz音声パックをインストール

  $0 apply
      音声パックを導入し、greeting.wavを独自音声へ差し替える

  $0 enable
      独自接続アナウンスを有効化

  $0 disable
      標準greeting.wavへ戻す

  $0 restore
      disableと同じ。標準音声へ復元

  $0 status
      現在の状態を表示

  $0 audio-info
      独自元音声の形式を表示

注意:
  この方式はEchoLink標準のgreeting.wavを差し替えます。
  EchoLink.tclへplayFileを追加しません。
EOF_HELP
}

main() {
    local command="${1:-status}"

    case "${command}" in
        install-pack)
            load_config
            install_sound_pack
            ;;
        apply)
            apply_announcement
            ;;
        enable)
            enable_announcement
            ;;
        disable)
            disable_announcement
            ;;
        restore)
            restore_original
            ;;
        status)
            show_status
            ;;
        audio-info)
            load_config
            require_command ffprobe || exit 1
            show_audio_info "${SOURCE_WAV}"
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            print_error "不明なコマンドです: ${command}"
            echo
            show_help
            exit 1
            ;;
    esac
}

main "$@"
