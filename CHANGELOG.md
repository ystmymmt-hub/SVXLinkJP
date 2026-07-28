# Change Log

## Version 1.4.0

### EchoLink接続アナウンス機能

- EchoLink接続アナウンス機能を追加
- 独自音声 `JQ1YOF_echo_.wav` に対応
- EchoLink標準の `EchoLink/greeting.wav` 差し替え方式を採用
- `EchoLink.tcl` の直接編集方式を廃止
- 標準音声の自動バックアップに対応
- 独自アナウンスの有効化・無効化・復元に対応
- WAVを16kHz、16bit、mono、PCMへ自動変換
- 英語16kHz音声パックのインストールに対応

### 操作コマンド

```bash
./modules/announcement.sh apply
./modules/announcement.sh enable
./modules/announcement.sh disable
./modules/announcement.sh restore
./modules/announcement.sh status
./modules/announcement.sh audio-info

既存のCHANGELOGを残したい場合は、上書きせず追記します。

```bash
cat >> CHANGELOG.md <<'EOF'

## Version 1.4.0

- EchoLink標準のgreeting.wav差し替え方式を採用
- JQ1YOF_echo_.wavによる接続アナウンスに対応
- 標準音声のバックアップ・復元に対応
- EchoLink.tclを直接編集しない方式へ変更
