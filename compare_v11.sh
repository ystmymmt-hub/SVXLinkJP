#!/bin/bash

# ============================================================
# SVXLinkJP Ver1.1 Comparison Tool
# GitHub Ver1.1 と現在の作業ファイルを比較
# ============================================================

set -u

PROJECT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

REPORT_DIR="${PROJECT_DIR}/comparison_report"
DATE_TEXT="$(date +%Y%m%d-%H%M%S)"

SUMMARY_FILE="${REPORT_DIR}/summary-${DATE_TEXT}.txt"
DIFF_FILE="${REPORT_DIR}/full-diff-${DATE_TEXT}.txt"
UNTRACKED_FILE="${REPORT_DIR}/untracked-${DATE_TEXT}.txt"

cd "$PROJECT_DIR" || exit 1

if [ ! -d ".git" ]; then
    echo "エラー: このフォルダーはGitリポジトリではありません。"
    echo
    echo "確認場所:"
    echo "$PROJECT_DIR"
    exit 1
fi

mkdir -p "$REPORT_DIR"

echo "GitHub情報を取得しています..."
git fetch --all --tags --prune

BASE_TAG=""

for tag_name in \
    "v1.1" \
    "V1.1" \
    "Ver1.1" \
    "ver1.1" \
    "1.1"
do
    if git rev-parse \
        --verify \
        --quiet \
        "refs/tags/${tag_name}" \
        >/dev/null
    then
        BASE_TAG="$tag_name"
        break
    fi
done

if [ -z "$BASE_TAG" ]; then
    echo
    echo "Ver1.1に該当するタグが見つかりませんでした。"
    echo
    echo "現在のタグ一覧:"
    git tag -l
    echo
    echo "GitHubのVer1.1として使用した"
    echo "コミット番号またはタグ名を確認してください。"
    exit 1
fi

{
    echo "============================================================"
    echo "          SVXLinkJP Ver1.1 → 現在版 変更一覧"
    echo "============================================================"
    echo
    echo "比較元タグ : $BASE_TAG"
    echo "比較日時   : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "現在ブランチ: $(git branch --show-current)"
    echo "現在位置   : $PROJECT_DIR"
    echo
    echo "------------------------------------------------------------"
    echo "変更されたファイル"
    echo "------------------------------------------------------------"

    git diff \
        --name-status \
        "$BASE_TAG" \
        -- \
        . \
        ':(exclude)comparison_report/**' \
        ':(exclude)*.backup.*'

    echo
    echo "------------------------------------------------------------"
    echo "変更量"
    echo "------------------------------------------------------------"

    git diff \
        --stat \
        "$BASE_TAG" \
        -- \
        . \
        ':(exclude)comparison_report/**' \
        ':(exclude)*.backup.*'

    echo
    echo "------------------------------------------------------------"
    echo "現在の未保存変更"
    echo "------------------------------------------------------------"

    git status --short

    echo
    echo "------------------------------------------------------------"
    echo "記号の意味"
    echo "------------------------------------------------------------"
    echo "M = 変更されたファイル"
    echo "A = 追加されたファイル"
    echo "D = 削除されたファイル"
    echo "R = 名前変更されたファイル"
    echo "?? = Gitにまだ登録されていないファイル"

} >"$SUMMARY_FILE"

git diff \
    "$BASE_TAG" \
    -- \
    . \
    ':(exclude)comparison_report/**' \
    ':(exclude)*.backup.*' \
    >"$DIFF_FILE"

git ls-files \
    --others \
    --exclude-standard \
    >"$UNTRACKED_FILE"

echo
echo "比較が完了しました。"
echo
echo "比較元: $BASE_TAG"
echo
echo
echo "概要:"
echo "$SUMMARY_FILE"
echo
echo "詳細差分:"
echo "$DIFF_FILE"
echo
echo "新規未登録ファイル:"
echo "$UNTRACKED_FILE"
echo
echo "概要を表示します。"
echo

cat "$SUMMARY_FILE"
