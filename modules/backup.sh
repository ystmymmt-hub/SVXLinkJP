#!/bin/bash

# ============================================================
# SVXLinkJP Backup / Restore Module
# ============================================================

PROJECT_DIR="$HOME/SVXLinkJP"
BACKUP_DIR="$PROJECT_DIR/backup/system"
SERVICE_NAME="svxlink"

mkdir -p "$BACKUP_DIR"

show_error()
{
    whiptail --title "Error" --msgbox "$1" 12 70
}

show_info()
{
    whiptail --title "SVXLinkJP Backup" --msgbox "$1" 14 72
}

create_backup()
{
    local mode="${1:-normal}"
    local timestamp
    local hostname_now
    local archive
    local temp_dir

    timestamp=$(date '+%Y%m%d_%H%M%S')
    hostname_now=$(hostname 2>/dev/null || echo unknown)

    if [ "$mode" = "safety" ]; then
        archive="$BACKUP_DIR/SVXLinkJP_safety_${hostname_now}_${timestamp}.tar.gz"
    else
        archive="$BACKUP_DIR/SVXLinkJP_system_${hostname_now}_${timestamp}.tar.gz"
    fi

    temp_dir=$(mktemp -d /tmp/svxlinkjp_backup.XXXXXX)

    if [ -z "$temp_dir" ] || [ ! -d "$temp_dir" ]; then
        show_error "一時ディレクトリを作成できませんでした。"
        return 1
    fi

    mkdir -p \
        "$temp_dir/etc" \
        "$temp_dir/system" \
        "$temp_dir/SVXLinkJP"

    # SVXLink設定
    if [ -d /etc/svxlink ]; then
        if ! sudo cp -a /etc/svxlink "$temp_dir/etc/"; then
            rm -rf "$temp_dir"
            show_error "/etc/svxlink のコピーに失敗しました。"
            return 1
        fi
    fi

    # システム設定
    [ -f /etc/asound.conf ] &&
        sudo cp -a /etc/asound.conf "$temp_dir/etc/"

    [ -f /etc/hostname ] &&
        sudo cp -a /etc/hostname "$temp_dir/etc/"

    [ -f /etc/hosts ] &&
        sudo cp -a /etc/hosts "$temp_dir/etc/"

    # SVXLinkJPプロジェクト
    # backupと.gitは再帰・肥大化防止のため除外
    tar \
        -C "$PROJECT_DIR" \
        --exclude='./backup' \
        --exclude='./.git' \
        -cf - . 2>/dev/null |
        tar -C "$temp_dir/SVXLinkJP" -xf -

    # システム情報
    {
        echo "SVXLinkJP backup"
        echo "DATE=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "HOSTNAME=$hostname_now"
        echo "USER=$(whoami)"
        echo "KERNEL=$(uname -a)"
        echo "MODE=$mode"
        echo
        echo "[SVXLink binary]"
        command -v svxlink || true
        echo
        echo "[SVXLink version]"
        svxlink --version 2>&1 || true
        echo
        echo "[Package]"
        dpkg -l 2>/dev/null | grep -i svxlink || true
    } > "$temp_dir/system/backup_info.txt"

    systemctl status "$SERVICE_NAME" --no-pager \
        > "$temp_dir/system/svxlink_status.txt" 2>&1 || true

    ip address \
        > "$temp_dir/system/ip_address.txt" 2>&1 || true

    # 内容一覧
    (
        cd "$temp_dir" || exit 1
        find . -type f -print | sort
    ) > "$temp_dir/MANIFEST.txt"

    if [ ! -d "$temp_dir/etc/svxlink" ]; then
        rm -rf "$temp_dir"
        show_error \
"/etc/svxlink が見つからないため、
バックアップを中止しました。"
        return 1
    fi

    if ! tar -C "$temp_dir" -czf "${archive}.tmp" .; then
        rm -rf "$temp_dir" "${archive}.tmp"
        show_error "圧縮ファイルの作成に失敗しました。"
        return 1
    fi

    mv "${archive}.tmp" "$archive"
    rm -rf "$temp_dir"

    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        rm -f "$archive"
        show_error "作成したバックアップの検査に失敗しました。"
        return 1
    fi

    if [ "$mode" = "normal" ]; then
        local size
        size=$(du -h "$archive" | awk '{print $1}')

        show_info \
"バックアップを作成しました。

ファイル:
$(basename "$archive")

サイズ:
$size

保存先:
$BACKUP_DIR"
    fi

    echo "$archive"
    return 0
}

select_backup()
{
    local files=()
    local menu_items=()
    local file
    local number=1
    local selected

    while IFS= read -r file; do
        [ -n "$file" ] && files+=("$file")
    done < <(
        find "$BACKUP_DIR" \
            -maxdepth 1 \
            -type f \
            -name 'SVXLinkJP_*.tar.gz' \
            -printf '%T@ %p\n' 2>/dev/null |
        sort -rn |
        cut -d' ' -f2-
    )

    if [ "${#files[@]}" -eq 0 ]; then
        show_error "バックアップファイルがありません。"
        return 1
    fi

    for file in "${files[@]}"; do
        menu_items+=(
            "$number"
            "$(basename "$file")"
        )
        number=$((number + 1))
    done

    selected=$(whiptail \
        --title "Backup selection" \
        --menu "使用するバックアップを選択してください" \
        22 78 12 \
        "${menu_items[@]}" \
        3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && return 1

    SELECTED_BACKUP="${files[$((selected - 1))]}"
    return 0
}

list_backups()
{
    local list

    list=$(
        find "$BACKUP_DIR" \
            -maxdepth 1 \
            -type f \
            -name 'SVXLinkJP_*.tar.gz' \
            -printf '%TY-%Tm-%Td %TH:%TM  %10s bytes  %f\n' \
            2>/dev/null |
        sort -r
    )

    if [ -z "$list" ]; then
        show_info "バックアップファイルはまだありません。"
        return
    fi

    whiptail \
        --title "Backup List" \
        --scrolltext \
        --msgbox "$list" \
        22 78
}

verify_backup()
{
    local temp_dir

    select_backup || return

    if ! tar -tzf "$SELECTED_BACKUP" >/dev/null 2>&1; then
        show_error \
"圧縮ファイルが破損しています。

$(basename "$SELECTED_BACKUP")"
        return
    fi

    temp_dir=$(mktemp -d /tmp/svxlinkjp_verify.XXXXXX)

    tar -xzf "$SELECTED_BACKUP" \
        -C "$temp_dir" \
        ./MANIFEST.txt \
        ./system/backup_info.txt 2>/dev/null || true

    if tar -tzf "$SELECTED_BACKUP" |
        grep -qE '^\./etc/svxlink(/|$)'; then

        whiptail \
            --title "Backup verification" \
            --scrolltext \
            --msgbox \
"検査結果: 正常

ファイル:
$(basename "$SELECTED_BACKUP")

SVXLink設定:
含まれています

$(cat "$temp_dir/system/backup_info.txt" 2>/dev/null)" \
            22 78
    else
        show_error \
"バックアップ内に /etc/svxlink がありません。

このファイルは復元に使用できません。"
    fi

    rm -rf "$temp_dir"
}

restore_svxlink()
{
    local temp_dir
    local safety_backup

    select_backup || return

    if ! tar -tzf "$SELECTED_BACKUP" |
        grep -qE '^\./etc/svxlink(/|$)'; then

        show_error \
"選択したバックアップ内に
/etc/svxlink がありません。"
        return
    fi

    whiptail \
        --title "SVXLink Restore" \
        --yesno \
"SVXLink設定を復元します。

対象:
$(basename "$SELECTED_BACKUP")

復元対象:
/etc/svxlink

現在の設定は復元前に安全バックアップされます。

実行しますか？" \
        18 72

    [ $? -ne 0 ] && return

    safety_backup=$(create_backup safety | tail -1)

    if [ -z "$safety_backup" ] ||
       [ ! -f "$safety_backup" ]; then
        show_error \
"安全バックアップを作成できなかったため、
復元を中止しました。"
        return
    fi

    temp_dir=$(mktemp -d /tmp/svxlinkjp_restore.XXXXXX)

    if ! tar -xzf "$SELECTED_BACKUP" -C "$temp_dir"; then
        rm -rf "$temp_dir"
        show_error "バックアップの展開に失敗しました。"
        return
    fi

    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    if ! sudo rm -rf /etc/svxlink; then
        sudo systemctl start "$SERVICE_NAME" 2>/dev/null || true
        rm -rf "$temp_dir"
        show_error "/etc/svxlink を準備できませんでした。"
        return
    fi

    if ! sudo cp -a "$temp_dir/etc/svxlink" /etc/; then
        sudo systemctl start "$SERVICE_NAME" 2>/dev/null || true
        rm -rf "$temp_dir"
        show_error "SVXLink設定の復元に失敗しました。"
        return
    fi

    sudo chown -R root:root /etc/svxlink 2>/dev/null || true
    sudo systemctl start "$SERVICE_NAME" 2>/dev/null || true

    rm -rf "$temp_dir"

    if systemctl is-active --quiet "$SERVICE_NAME"; then
        show_info \
"SVXLink設定を復元しました。

サービス状態:
稼働中

安全バックアップ:
$(basename "$safety_backup")"
    else
        show_error \
"設定は復元されましたが、
SVXLinkサービスが起動していません。

次のコマンドで確認してください:

sudo systemctl status svxlink"
    fi
}

restore_full()
{
    local temp_dir
    local safety_backup

    select_backup || return

    if ! tar -tzf "$SELECTED_BACKUP" |
        grep -qE '^\./etc/svxlink(/|$)'; then
        show_error "バックアップ内にSVXLink設定がありません。"
        return
    fi

    whiptail \
        --title "FULL RESTORE" \
        --yesno \
"システム設定を復元します。

対象:
$(basename "$SELECTED_BACKUP")

復元対象:
・/etc/svxlink
・/etc/asound.conf
・/etc/hostname
・/etc/hosts

注意:
ネットワーク名やホスト名が変わる可能性があります。

本当に実行しますか？" \
        22 74

    [ $? -ne 0 ] && return

    whiptail \
        --title "Final confirmation" \
        --yesno \
"最終確認です。

完全復元を開始しますか？" \
        12 60

    [ $? -ne 0 ] && return

    safety_backup=$(create_backup safety | tail -1)

    if [ -z "$safety_backup" ] ||
       [ ! -f "$safety_backup" ]; then
        show_error "安全バックアップ作成失敗のため中止しました。"
        return
    fi

    temp_dir=$(mktemp -d /tmp/svxlinkjp_full_restore.XXXXXX)

    if ! tar -xzf "$SELECTED_BACKUP" -C "$temp_dir"; then
        rm -rf "$temp_dir"
        show_error "バックアップの展開に失敗しました。"
        return
    fi

    sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true

    sudo rm -rf /etc/svxlink
    sudo cp -a "$temp_dir/etc/svxlink" /etc/

    [ -f "$temp_dir/etc/asound.conf" ] &&
        sudo cp -a "$temp_dir/etc/asound.conf" /etc/asound.conf

    [ -f "$temp_dir/etc/hostname" ] &&
        sudo cp -a "$temp_dir/etc/hostname" /etc/hostname

    [ -f "$temp_dir/etc/hosts" ] &&
        sudo cp -a "$temp_dir/etc/hosts" /etc/hosts

    sudo chown -R root:root /etc/svxlink 2>/dev/null || true
    sudo systemctl start "$SERVICE_NAME" 2>/dev/null || true

    rm -rf "$temp_dir"

    show_info \
"完全復元が終了しました。

安全バックアップ:
$(basename "$safety_backup")

ホスト名を反映するには、
再起動が必要な場合があります。"
}

while true
do
    CHOICE=$(whiptail \
        --title "SVXLinkJP Backup / Restore" \
        --menu "操作を選択してください" \
        20 74 10 \
        1 "Create backup     バックアップ作成" \
        2 "Backup list       バックアップ一覧" \
        3 "Verify backup     バックアップ検査" \
        4 "Restore SVXLink   SVXLink設定のみ復元" \
        5 "Full restore      システム設定を含めて復元" \
        0 "Back              戻る" \
        3>&1 1>&2 2>&3)

    RET=$?

    [ "$RET" -ne 0 ] && exit 0

    case "$CHOICE" in
        1)
            create_backup normal
            ;;
        2)
            list_backups
            ;;
        3)
            verify_backup
            ;;
        4)
            restore_svxlink
            ;;
        5)
            restore_full
            ;;
        0)
            exit 0
            ;;
    esac
done
