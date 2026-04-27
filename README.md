# MeetingCaptionTranslator

固定の Core Audio tap でシステム音声をキャプチャし、Apple Speech API で文字起こしして、英語から日本語または日本語から英語へ翻訳し、常に最前面に表示されるオーバーレイへ描画する macOS アプリです。

## 必要要件
- macOS 26.0+
- macOS 26 SDK を含む Xcode 16+
- プロジェクト生成用の Ruby/Bundler

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
  -destination 'platform=macOS'
```

## リリース成果物
```bash
ruby tools/build_release.rb
```

ビルド済みのアプリバンドルを `dist/MeetingCaptionTranslator.app` にコピーします。
リリース先のパスは `ruby tools/build_release_test.rb` で検証できます。
この成果物では、プロジェクトのデフォルト署名設定が使用されます。

## テスト
```bash
xcodebuild test \
  -project MeetingCaptionTranslator.xcodeproj \
  -scheme MeetingCaptionTranslatorTests \
  -destination 'platform=macOS'
```

## 実行
ビルドまたは実行する前に、Xcode で `MeetingCaptionTranslator.xcodeproj` を開き、`Signing & Capabilities` で Team と署名 ID を選択してください。ローカル開発では `Apple Development` で十分です。初回使用時には、次の権限を許可してください。
- `System Audio Recording`
- `Speech Recognition`

必要に応じて `Language Direction` で `English -> Japanese` または `Japanese -> English` を選択します。その後、`Start` を押すと Mac のシステム音声ソースをキャプチャし、文字起こしを開始します。言語方向は停止中に変更でき、選択内容は保存されます。

診断目的で意図的に未署名ビルドが必要な場合は、コマンドに `CODE_SIGNING_ALLOWED=NO` を指定して上書きしてください。そのビルドを権限テストに使用しないでください。macOS TCC はアプリの署名を使ってプライバシー許可を記憶するため、未署名ビルドでは起動のたびに `Speech Recognition` の許可を再要求される可能性があります。

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
