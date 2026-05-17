# MeetingCaptionTranslator

固定の Core Audio tap でシステム音声をキャプチャし、Apple Speech API で文字起こしして、英語から日本語または日本語から英語へ翻訳し、常に最前面に表示されるオーバーレイへ描画する macOS アプリです。

## 必要要件
- macOS 26.0+
- macOS 26 SDK を含む Xcode 16+
- プロジェクト生成用の Ruby/Bundler
- Live Caption / Speech の対象言語モデル

## プロジェクト構成
- `MeetingCaptionTranslator/`: アプリのソースコード
- `MeetingCaptionTranslatorTests/`: XCTest テストスイート
- `tools/generate_project.rb`: `.xcodeproj` を再生成するスクリプト
- `docs/plans/`: 設計および実装メモ

## セットアップ
```bash
bundle install
bundle exec ruby tools/generate_project.rb
```

## アプリを入手する
このリポジトリから実行可能なアプリバンドルを作成するには、次の手順を実行します。

- 先に Xcode、Ruby、Bundler をインストールしてください。
- GitHub SSH アクセスをすでに設定している場合を除き、以下の HTTPS clone URL を使用してください。

```bash
git clone https://github.com/terasakisatoshi/MeetingCaptionTranslator.git
cd MeetingCaptionTranslator
bundle install
bundle exec ruby tools/generate_project.rb
ruby tools/build_release.rb
```

ビルドされたアプリは `dist/MeetingCaptionTranslator.app` に出力されます。

## ビルド
```bash
xcodebuild build \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslator \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

このコマンドはソースのビルド検証用に署名を無効化しています。実際にアプリを起動して権限まわりを確認する場合は、Xcode で Team と署名 ID を設定して署名済みアプリとして実行してください。

## リリース成果物
```bash
ruby tools/build_release.rb
```

ビルド済みのアプリバンドルを `dist/MeetingCaptionTranslator.app` にコピーします。
リリース先のパスは `ruby tools/build_release_test.rb` で検証できます。
この成果物では、プロジェクトのデフォルト署名設定が使用されます。

このプロジェクトは Mac のシステム音声出力を Core Audio tap でキャプチャするため、アプリ Sandbox を無効にしています。Sandbox 設定を変更する場合は、`System Audio Recording` と `Speech Recognition` の権限付与、および実際の音声キャプチャが動作することを再検証してください。

## テスト
```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## 実行
ビルドまたは実行する前に、Xcode で `MeetingCaptionTranslator.xcodeproj` を開き、`Signing & Capabilities` で Team と署名 ID を選択してください。ローカル開発では `Apple Development` で十分です。初回使用時には、次の権限を許可してください。
- `System Audio Recording`
- `Speech Recognition`

このアプリは Live Caption と同じ音声認識基盤を使うため、使用する言語のモデルを事前に macOS へダウンロードしておく必要があります。`English -> Japanese` では英語、`Japanese -> English` では日本語の音声認識モデルが必要です。モデルが未インストールの場合、文字起こしの開始時に準備やダウンロードで待たされる、または環境によって文字起こしを開始できないことがあります。

既定の Bundle Identifier は `tools/generate_project.rb` で定義されています。自分の Team や配布方法に合わせて Bundle Identifier を変更する場合は、`PRODUCT_BUNDLE_IDENTIFIER` を編集してから `bundle exec ruby tools/generate_project.rb` を再実行してください。Bundle Identifier を変更すると macOS のプライバシー許可は別アプリとして扱われるため、権限の再付与が必要です。

必要に応じて `Language Direction` で `English -> Japanese` または `Japanese -> English` を選択します。その後、`Start` を押すと Mac のシステム音声ソースをキャプチャし、文字起こしを開始します。言語方向は停止中に変更でき、選択内容は保存されます。

診断目的で意図的に未署名ビルドが必要な場合は、コマンドに `CODE_SIGNING_ALLOWED=NO` を指定して上書きしてください。そのビルドを権限テストに使用しないでください。macOS TCC はアプリの署名を使ってプライバシー許可を記憶するため、未署名ビルドでは起動のたびに `Speech Recognition` の許可を再要求される可能性があります。

## プライバシー
このアプリは、ユーザーが `Start` を押している間だけ Mac のシステム音声出力をキャプチャし、Apple の Speech framework と Translation framework を使って文字起こしと翻訳を行います。このリポジトリの実装には、開発者が運用する外部サーバー、外部 API キー、独自の認証情報は含まれていません。

キャプチャした音声は、このアプリではファイルに保存しません。字幕履歴はアプリ実行中のメモリ内に保持され、最大 500 行までに制限されます。永続化されるのは、言語方向などのアプリ設定のみです。Apple framework による音声認識および翻訳処理は、ユーザーの macOS 環境と Apple の各 framework の動作に従います。

## アーキテクチャ
- `SystemPlaybackCaptureService`: Mac のシステム音声ソース用 Core Audio tap
- `LiveTranscriptionService`: `SpeechAnalyzer` / `SpeechTranscriber`
- `AppleTranslationService`: `TranslationSession`
- `CaptionPipelineService`: 部分字幕と確定字幕の調整
- `OverlayWindowManager`: 常に最前面に表示される AppKit オーバーレイウィンドウ

## 補足
- 入力/出力言語は `Language Direction` で英語 -> 日本語または日本語 -> 英語を選択できます。既定値は `CaptionLanguagePair.defaultPair` により英語 -> 日本語です。
- キャプチャソースは Mac のシステム音声出力に固定されており、ディスプレイ選択機能はありません。
- ソースファイルを追加または削除した後は、`bundle exec ruby tools/generate_project.rb` を再実行してください。

## ライセンス
MIT License です。詳細は [LICENSE](LICENSE) を参照してください。
