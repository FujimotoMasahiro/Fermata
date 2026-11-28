# Fermata (Apple Silicon / Universal Fork)

[iccir/Fermata](https://github.com/iccir/Fermata) (by Ricci Adams) をフォークし、**Apple Silicon ネイティブ（Universal Binary: `arm64` + `x86_64`）対応** および **終了時フリーズ・スリープ未解除バグの修正** を行ったメンテナンス版です。

Fermata is a small macOS utility that prevents Lid Close Sleep when specific applications are running or preventing idle sleep, or when manually toggled from the menu bar.

---

## このフォークでの主な変更点 / What's Changed

- **Apple Silicon ネイティブ対応（Universal Binary）**: `arm64` + `x86_64` 両対応（macOS 12.0 以降）
- **多言語設定（日本語 / English / システム設定に従う）**: 設定画面の「表示言語 / Language」からアプリ再起動なしで即座に日本語・英語を切替可能
- **各設定項目のツールチップ解説**: メニューおよび設定画面の全項目に、`ⓘ` ボタンのホバー／クリックで実際の制御挙動（`SleepDisabled` / `IOPMAssertion` / `NSTimer` / `SMAppService` 等）を確認できる解説 Popover を追加
- **電源アサーションのリアルタイムステータス表示**: 設定画面の各アプリ行に「電源アサーション中 / 起動中（アサーションなし） / 未起動」をリアルタイム表示（アサーション詳細のツールチップ付き）し、メニューバー上部にも現在の発動要因を表示
- **蓋を閉じたら画面だけ消灯（処理は継続）**:
  - Fermata が有効なあいだに蓋を閉じると、`IOPMrootDomain` の Clamshell 通知で検知し `pmset displaysleepnow` で内蔵ディスプレイだけを消灯します（システムスリープはしないので AI エージェント等の処理は継続）
  - 外部ディスプレイ使用中（クラムシェルモード）は消灯しません。蓋を開けると通常どおり画面が点きます
  - 無効にする場合: `defaults write com.fujimotomasahiro.Fermata SleepDisplayOnLidClose -bool NO`
- **「Quit Fermata」で固まるバグを修正**:
  - `allowLidCloseSleepWithCallback:` でヘルパー未応答・バージョン不一致時にコールバックが呼ばれず `NSTerminateLater` のまま永久にフリーズしていた問題を修正
  - XPC 通信のエラーハンドリング・タイムアウト（最大 2.5〜3 秒）・メインスレッド保証・接続破棄を実装
- **強制終了・クラッシュ時の自動スリープ復元（フェイルセーフ）**:
  - 特権ヘルパー側でクライアント接続の切断を監視し、Fermata がクラッシュや強制終了されても自動で `SleepDisabled = 0` に戻す安全装置を追加
- **macOS モダン API 対応**: `SMAppService`（macOS 13+ のログイン項目登録）、`UniformTypeIdentifiers`、`NSStatusItem.button` 等へ更新
- **GitHub Actions 自動ビルド対応**:
  - デフォルトは **無料（ad-hoc 署名）** で Universal Binary を自動ビルド
  - 将来 Apple Developer ID 証明書を GitHub Secrets に追加すれば、そのまま **Developer ID 署名＋Apple 公証（Notarization）** ビルドに自動切替

---

## インストール方法（無料・ad-hoc 署名ビルド）

1. [GitHub Releases](https://github.com/FujimotoMasahiro/Fermata/releases)（または Actions の Artifacts）から `Fermata-universal.zip` をダウンロードして解凍します。
2. `Fermata.app` を `/Applications` へコピーします。
3. 未署名（ad-hoc 署名）ビルドのため、初回のみターミナルで以下を実行して Gatekeeper 隔離属性を外し、特権ヘルパーを登録します。

```bash
xattr -cr /Applications/Fermata.app
sudo ./Scripts/install-helper.sh /Applications/Fermata.app
```

4. `/Applications/Fermata.app` を起動します。

### アンインストール（スリープ設定の復元込み）

```bash
sudo ./Scripts/uninstall-helper.sh
rm -rf /Applications/Fermata.app
```

※ 万が一スリープできなくなった場合は、いつでも以下で元に戻せます：
```bash
sudo pmset -a disablesleep 0
```

---

## 将来 Developer ID 署名・公証を有効にする場合（GitHub Secrets）

リポジトリの **Settings → Secrets and variables → Actions** に以下を登録すると、`.github/workflows/build.yml` が自動で署名・公証ビルドに切り替わります。

| Secret 名 | 内容 |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application 証明書（`.p12` を base64 化した文字列） |
| `MACOS_CERTIFICATE_P12_PASSWORD` | `.p12` のパスワード |
| `APPLE_TEAM_ID` | Apple Developer の Team ID（10文字） |
| `APPLE_ID` *(任意・公証用)* | Apple ID メールアドレス |
| `APPLE_APP_SPECIFIC_PASSWORD` *(任意・公証用)* | App 用パスワード |

---

## Credits & License

This project is a fork of [iccir/Fermata](https://github.com/iccir/Fermata) originally created by **Ricci Adams**.

Licensed under the same dual license as the original repository:
- [MIT License](LICENSE) OR [1-clause BSD License](https://opensource.org/license/bsd-1-clause)
- `SPDX-License-Identifier: MIT OR BSD-1-Clause`

## Disclaimer

This software modifies macOS's `SleepDisabled` power setting (unsupported private SPI). While fail-safes are included, use at your own risk—do not place a running laptop inside a closed bag where it could overheat.
