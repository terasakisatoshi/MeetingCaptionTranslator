# MeetingCaptionTranslator

![](./demo.png)

システム音声またはマイク音声をキャプチャし、Apple Speech または speech.cpp の Qwen3-ASR / Haas-ja で文字起こしして、英語から日本語または日本語から英語へ翻訳し、常に最前面に表示されるオーバーレイへ描画する macOS アプリです。

## 必要要件
- macOS 26.0+
- macOS 26 SDK を含む Xcode 16+
- Ruby、Git、CMake 3.20+、C++17 コンパイラ（プロジェクト再生成には Bundler も必要）
- Apple Speech を使う場合は、対象言語の音声認識モデル

## プロジェクト構成
- `MeetingCaptionTranslator/`: アプリのソースコード
- `MeetingCaptionTranslatorTests/`: XCTest テストスイート
- `tools/generate_project.rb`: `.xcodeproj` を再生成するスクリプト
- `docs/plans/`: 設計および実装メモ

## 開発用セットアップ
```bash
bundle install
bundle exec ruby tools/generate_project.rb
```

## macOS の Live Caption について
macOS の Live Caption は、Mac 上のアプリ音声や周囲の会話をリアルタイムに文字起こしするアクセシビリティ機能です。Apple の案内では、Live Caption の音声処理はデバイス上で行われ、初回有効化時には言語データが Mac にダウンロードされます。

Apple Speech を選択した場合、このアプリは Live Caption と同じ Apple の音声認識アセットを使ってシステム音声を文字起こしします。そのため、使用する言語のモデルを事前に macOS へダウンロードしておく必要があります。`English -> Japanese` では英語、`Japanese -> English` では日本語の音声認識モデルが必要です。モデルが未インストールの場合、文字起こしの開始時に準備やダウンロードで待たされる、または環境によって文字起こしを開始できないことがあります。

モデルを準備するには、`System Settings` -> `Accessibility` -> `Live Captions` を開き、Live Caption を一度有効にしてください。初回ダウンロードにはインターネット接続が必要です。Live Caption は Apple silicon 搭載 Mac のみ対応で、利用できる言語、国、地域には制限があります。精度は音声環境や言語によって変わるため、緊急用途や高リスクな判断には使用しないでください。

## インストール

Xcode、Ruby、Git、CMake 3.20 以降、C++17 コンパイラを用意し、リポジトリ内で次を実行します。

```bash
ruby tools/install_app.rb
```

このコマンドは、speech.cpp の取得・ビルド、Haas-ja（約 0.66 GB）と Qwen3-ASR 0.6B（約 0.84 GB）モデルのダウンロード、アプリのビルドを行い、`/Applications/MeetingCaptionTranslator.app` にインストールします。初回はインターネット接続と十分な空き容量が必要です。`/Applications` への書き込み権限や Xcode の署名設定も環境に応じて必要です。

ビルドが成功すると、起動中の MeetingCaptionTranslator は強制終了され、インストール済みのアプリは新しいビルドに置き換わります。準備またはビルドに失敗した場合、インストール済みのアプリは変更されません。

リポジトリをまだ取得していない場合は、先に次を実行してください。

```bash
git clone https://github.com/terasakisatoshi/MeetingCaptionTranslator.git
cd MeetingCaptionTranslator
```

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

ビルド済みのアプリバンドルを `dist/MeetingCaptionTranslator.app` にコピーします。Haas-ja 用の speech.cpp を同梱するには、先に `tools/build_speech.sh` を実行してください。
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
- `System Audio Recording`（システム音声を使う場合）
- `Microphone`（マイクを使う場合）
- `Speech Recognition`（Apple Speech 使用時）

Apple Speech を使う場合は、事前に Live Caption の言語モデルをダウンロードしてください。詳細は「macOS の Live Caption について」を参照してください。

既定の Bundle Identifier は `tools/generate_project.rb` で定義されています。自分の Team や配布方法に合わせて Bundle Identifier を変更する場合は、`PRODUCT_BUNDLE_IDENTIFIER` を編集してから `bundle exec ruby tools/generate_project.rb` を再実行してください。Bundle Identifier を変更すると macOS のプライバシー許可は別アプリとして扱われるため、権限の再付与が必要です。

`Audio Input` で `Mac System Audio` または `Microphone` を選択します。マイクは macOS の標準入力デバイスを使用します。入力は停止中に切り替えられ、既定値はシステム音声です。

`Language Direction` で `English -> Japanese` または `Japanese -> English` を選択します。`Speech Recognition` で `Apple Speech` または speech.cpp を選べます。speech.cpp では英語入力に Qwen3-ASR 0.6B、日本語入力に Haas-ja を使用します。言語方向と認識エンジンは停止中に変更でき、選択内容は保存されます。Apple Speech を選択した場合は `Download Apple Speech Model` で選択中の入力言語のモデルを事前に準備できます。準備中はスピナーが表示されます。`Start` を押すと音声のキャプチャと文字起こしが始まります。

診断目的で意図的に未署名ビルドが必要な場合は、コマンドに `CODE_SIGNING_ALLOWED=NO` を指定して上書きしてください。そのビルドを権限テストに使用しないでください。macOS TCC はアプリの署名を使ってプライバシー許可を記憶するため、未署名ビルドでは起動のたびに `Speech Recognition` の許可を再要求される可能性があります。

## プライバシー
このアプリは、ユーザーが `Start` を押している間だけ 選択したシステム音声またはマイク音声をキャプチャし、Apple Speech またはローカルの speech.cpp で文字起こしし、Apple の Translation framework で翻訳します。このリポジトリの実装には、開発者が運用する外部サーバー、外部 API キー、独自の認証情報は含まれていません。

キャプチャした音声は、このアプリではファイルに保存しません。字幕履歴はアプリ実行中のメモリ内に保持され、最大 500 行までに制限されます。永続化されるのは、言語方向などのアプリ設定のみです。Apple framework による音声認識および翻訳処理は、ユーザーの macOS 環境と Apple の各 framework の動作に従います。

## アーキテクチャ
- `SystemPlaybackCaptureService`: Mac のシステム音声ソース用 Core Audio tap
- `MicrophoneCaptureService`: macOS の標準マイク入力用 AVAudioEngine
- `LiveTranscriptionService`: `SpeechAnalyzer` / `SpeechTranscriber`
- `HaasTranscriptionService`: speech.cpp worker を使った日本語音声認識
- `AppleTranslationService`: `TranslationSession`
- `CaptionPipelineService`: 部分字幕と確定字幕の調整
- `OverlayWindowManager`: 常に最前面に表示される AppKit オーバーレイウィンドウ

## 補足
- 入力/出力言語は `Language Direction` で英語 -> 日本語または日本語 -> 英語を選択できます。既定値は `CaptionLanguagePair.defaultPair` により英語 -> 日本語です。
- システム音声またはマイクを入力に選択できます。ディスプレイ選択機能はありません。
- ソースファイルを追加または削除した後は、`bundle exec ruby tools/generate_project.rb` を再実行してください。

## speech.cpp による音声認識

英語入力では Qwen3-ASR 0.6B、日本語入力では Haas-ja と Apple Speech を切り替えられます。`ruby tools/install_app.rb` は speech.cpp を準備し、モデルをダウンロードしてからアプリをインストールします。手動で Xcode ビルドする場合、speech.cpp を同梱するには `tools/build_speech.sh` を先に実行してください。SpeechCxx.jl と同じくソースおよび固定された ggml を CMake でビルドします（speech.cpp 0.9.4）。生成物は次のアプリビルド時に同梱されます。ビルドは実行した Mac の CPU 向けです。別アーキテクチャの Mac 向けにはその環境でビルドしてください。同梱されない場合、アプリは `~/.local/bin/speech`、`/opt/homebrew/bin/speech`、`/usr/local/bin/speech` の順に外部インストールを探します（0.9.3 以降）。

インストール時にモデルを取得しなかった場合は、初回使用時にモデル（Haas-ja 約 0.66 GB、Qwen3-ASR 約 0.84 GB）のダウンロードと読み込みが必要です。認識はローカルで実行されますが、初回ダウンロードにはインターネット接続が必要です。字幕は発話の切れ目で確定するため、Apple Speech より表示が遅れることがあります。音量による簡易的な発話検出を使用するため、静かな声や騒音環境では認識が途切れることがあります。Qwen3-ASR の英語認識精度は話者や音声環境によって異なります。

## ライセンス

MIT License です。詳細は [LICENSE](LICENSE) を参照してください。
