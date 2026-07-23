#!/bin/bash

# ============================================================
# SVXLinkJP Installer
# Version 1.1.0
# ============================================================

set -u

APP_NAME="SVXLinkJP"
INSTALL_DIR="/opt/SVXLinkJP"
COMMAND_FILE="/usr/local/bin/svxlinkjp"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/svxlinkjp-install.log"

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
RESET="\033[0m"

print_ok() {
    echo -e "${GREEN}[ OK ]${RESET} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${RESET} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

error_exit() {
    print_error "$1"
    echo "ログ: $LOG_FILE"
    exit 1
}

# ------------------------------------------------------------
# root確認
# ------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo
    print_error "管理者権限が必要です。"
    echo
    echo "次のコマンドで実行してください。"
    echo
    echo "  sudo ./install.sh"
    echo
    exit 1
fi

echo
echo "============================================================"
echo "          SVXLinkJP Ver.1.1 Installer"
echo "============================================================"
echo

echo "インストール元 : $SOURCE_DIR"
echo "インストール先 : $INSTALL_DIR"
echo

# ------------------------------------------------------------
# 必要ファイル確認
# ------------------------------------------------------------

if [ ! -f "$SOURCE_DIR/menu.sh" ]; then
    error_exit "menu.sh が見つかりません。"
fi

if [ ! -d "$SOURCE_DIR/modules" ]; then
    error_exit "modules ディレクトリが見つかりません。"
fi
if [ ! -f "$SOURCE_DIR/version" ]; then
    error_exit "version ファイルが見つかりません。"
fi

SOURCE_VERSION="$(tr -d '[:space:]' < "$SOURCE_DIR/version")"

if [ -z "$SOURCE_VERSION" ]; then
    error_exit "version ファイルが空です。"
fi

print_ok "インストール対象バージョン: $SOURCE_VERSION"
print_ok "インストール元を確認しました。"

# ------------------------------------------------------------
# apt更新
# ------------------------------------------------------------

print_info "パッケージ情報を更新しています。"

if ! apt-get update >>"$LOG_FILE" 2>&1; then
    error_exit "apt-get update に失敗しました。"
fi

print_ok "パッケージ情報を更新しました。"

# ------------------------------------------------------------
# 必要パッケージ
# ------------------------------------------------------------

REQUIRED_PACKAGES=(
    git
    curl
    rsync
    dialog
    network-manager
    iproute2
)

for package in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
        grep -q "install ok installed"; then

        print_ok "$package はインストール済みです。"
    else
        print_info "$package をインストールしています。"

        if apt-get install -y "$package" >>"$LOG_FILE" 2>&1; then
            print_ok "$package をインストールしました。"
        else
            error_exit "$package のインストールに失敗しました。"
        fi
    fi
done

# ------------------------------------------------------------
# SVXLink本体
# ------------------------------------------------------------

if command -v svxlink >/dev/null 2>&1; then
    print_ok "SVXLink本体はインストール済みです。"
else
    print_info "SVXLink本体を確認しています。"

    if apt-cache show svxlink >/dev/null 2>&1; then
        print_info "SVXLink本体をインストールしています。"

        if apt-get install -y svxlink >>"$LOG_FILE" 2>&1; then
            print_ok "SVXLink本体をインストールしました。"
        else
            print_error "SVXLink本体の自動インストールに失敗しました。"
            print_info "SVXLinkJP本体のインストールは続行します。"
        fi
    else
        print_info "この環境のAPTにはsvxlinkパッケージがありません。"
        print_info "SVXLinkJP本体のインストールは続行します。"
    fi
fi

# ------------------------------------------------------------
# 既存インストールのバックアップ
# ------------------------------------------------------------
# ------------------------------------------------------------
# 既存インストール確認
# ------------------------------------------------------------

if [ -d "$INSTALL_DIR" ]; then
    echo
    print_info "SVXLinkJPは既にインストールされています。"
    echo
    echo "現在のインストール先:"
    echo "  $INSTALL_DIR"
    echo
    echo "1. 更新インストール"
    echo "2. インストールを中止"
    echo

    while true; do
        read -r -p "選択してください [1-2]: " INSTALL_CHOICE

        case "$INSTALL_CHOICE" in
            1)
                print_info "更新インストールを開始します。"
                break
                ;;
            2)
                echo
                print_info "インストールを中止しました。"
                exit 0
                ;;
            *)
                echo "1 または 2 を入力してください。"
                ;;
        esac
    done

    BACKUP_DIR="${INSTALL_DIR}.backup.$(date +%Y%m%d-%H%M%S)"

    print_info "既存のSVXLinkJPをバックアップします。"

    if mv "$INSTALL_DIR" "$BACKUP_DIR"; then
        print_ok "バックアップ先: $BACKUP_DIR"
    else
        error_exit "既存ディレクトリのバックアップに失敗しました。"
    fi
fi


# ------------------------------------------------------------
# ファイルコピー
# ------------------------------------------------------------

print_info "SVXLinkJPをコピーしています。"

mkdir -p "$INSTALL_DIR" ||
    error_exit "$INSTALL_DIR を作成できませんでした。"

if ! rsync -a \
    --exclude=".git" \
    --exclude="backup/" \
    --exclude="*.tar.gz" \
    "$SOURCE_DIR/" "$INSTALL_DIR/" >>"$LOG_FILE" 2>&1; then

    error_exit "ファイルのコピーに失敗しました。"
fi

print_ok "SVXLinkJPを $INSTALL_DIR に配置しました。"

# ------------------------------------------------------------
# 実行権限
# ------------------------------------------------------------

find "$INSTALL_DIR" \
    -type f \
    -name "*.sh" \
    -exec chmod 755 {} \;

chmod 755 "$INSTALL_DIR/menu.sh"

print_ok "シェルスクリプトに実行権限を設定しました。"

# ------------------------------------------------------------
# configディレクトリ
# ------------------------------------------------------------

mkdir -p "$INSTALL_DIR/config"

if [ ! -f "$INSTALL_DIR/config/config.ini" ]; then
    cat >"$INSTALL_DIR/config/config.ini" <<'CONFIG_EOF'
# SVXLinkJP configuration

[system]
language=ja
version=1.1.0

[svxlink]
config_dir=/etc/svxlink
service_name=svxlink
CONFIG_EOF

    chmod 644 "$INSTALL_DIR/config/config.ini"
    print_ok "初期設定ファイルを作成しました。"
else
    print_ok "既存の設定ファイルを使用します。"
fi

# ------------------------------------------------------------
# /etc/svxlink確認
# ------------------------------------------------------------

if [ -d "/etc/svxlink" ]; then
    print_ok "/etc/svxlink が存在します。"
    print_info "既存のSVXLink設定は変更していません。"
else
    mkdir -p /etc/svxlink
    chmod 755 /etc/svxlink
    print_ok "/etc/svxlink を作成しました。"
fi

# ------------------------------------------------------------
# 起動コマンド
# ------------------------------------------------------------

cat >"$COMMAND_FILE" <<'COMMAND_EOF'
#!/bin/bash

INSTALL_DIR="/opt/SVXLinkJP"

if [ ! -f "$INSTALL_DIR/menu.sh" ]; then
    echo "SVXLinkJPが見つかりません。"
    echo "確認先: $INSTALL_DIR"
    exit 1
fi

cd "$INSTALL_DIR" || exit 1
exec ./menu.sh "$@"
COMMAND_EOF

chmod 755 "$COMMAND_FILE"

print_ok "起動コマンドを作成しました。"
echo "コマンド: svxlinkjp"

# ------------------------------------------------------------
# バージョン表示
# ------------------------------------------------------------

if [ -f "$INSTALL_DIR/version" ]; then
    INSTALLED_VERSION="$(cat "$INSTALL_DIR/version")"
else
    INSTALLED_VERSION="不明"
fi

echo
echo "============================================================"
echo "       SVXLinkJP インストール完了"
echo "============================================================"
echo
echo "インストール先 : $INSTALL_DIR"
echo "バージョン     : $INSTALLED_VERSION"
echo "起動コマンド   : svxlinkjp"
echo
echo "既存の /etc/svxlink の設定は上書きしていません。"
echo
echo "起動方法:"
echo
echo "  svxlinkjp"
echo

