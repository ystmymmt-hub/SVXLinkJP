# ?? SVXLinkJP Version 1.2.0

**日本語でSVXLinkを簡単に設定・管理するためのツールです。**

Version 1.2.0では、USBオーディオ管理機能と、無線機の電源を遠隔操作するPowerSW機能を追加しました。

---

## ? 新機能

### ?? Audio Device Management

- USBオーディオデバイスの自動検出
- 録音デバイスと再生デバイスの一覧表示
- USBオーディオの優先選択
- オーディオデバイスの手動選択
- SVXLinkの`AUDIO_DEV`設定を自動更新
- 録音テスト
- 再生テスト
- オーディオ診断
- 設定変更前の自動バックアップ

### ? Radio PowerSW Management

Raspberry PiのGPIOを使用して、無線機の13.8V電源を遠隔制御できます。

- 無線機電源ON
- 無線機電源OFF
- 電源状態の切り替え
- GPIO状態の確認
- Active High / Active Low対応
- Raspberry Pi起動時の無線機自動ON
- 無線機起動待ち時間の設定
- 無線機電源ON後のSVXLink自動再起動
- 指定時間後の自動電源OFF
- 自動OFFタイマーの解除
- PowerSW設定の保存

---

## ?? Eco Smart Radio System

PowerSW機能により、無線機を必要な時間だけ動作させる省エネルギー運用が可能になりました。

期待できる効果：

- 無線機の消費電力削減
- 無線機や冷却ファンの寿命延長
- 夜間や未使用時間帯の電源停止
- SSHを使用した遠隔電源操作
- 無人局や遠隔局の効率的な管理

Raspberry Pi自体は常時動作し、SSH接続を維持したまま無線機のみをON/OFFできます。

---

## ?? 改善内容

- Debian 13対応の改善
- `svxlink-server`および`svxlink-gpio`対応
- Audio管理モジュールの追加
- PowerSW管理モジュールの追加
- 設定ファイルのバックアップ機能改善
- 管理メニュー構成の改善

---

## ?? PowerSW使用時の注意

Raspberry PiのGPIOに無線機やリレーコイルを直接接続しないでください。

次のようなGPIO保護・駆動回路を使用してください。

- トランジスタ回路
- MOSFET回路
- フォトカプラ
- Raspberry Piの3.3V GPIOに対応したリレーモジュール

無線機の13.8V電源を制御する場合は、無線機の最大消費電流に十分対応したリレーや電源制御回路を使用してください。

---

## ???? About SVXLinkJP

SVXLinkJPは、日本のアマチュア無線家がSVXLinkを簡単に導入・設定・管理できる環境を目指して開発しています。

**Created in Japan for Amateur Radio Operators.**
