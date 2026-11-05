# プロジェクト生成スクリプトの廃止

`tools/generate_project.rb` と `xcodeproj` gem（`Gemfile`、Bundler）をやめ、`project.pbxproj` を直接管理する。アプリとテストのフォルダは Xcode 16 以降のフォルダ同期グループ（`PBXFileSystemSynchronizedRootGroup`、objectVersion 77）で参照し、ファイルの追加・削除でプロジェクトを書き換えない。`Resources/Info.plist` と entitlements はビルド設定から参照するため、ターゲットのメンバーから除外している。ビルド設定、リンクする framework、`Embed speech.cpp` のビルドフェーズは生成スクリプトと同じ内容を引き継いだ。ビルド設定を変えるときは Xcode で編集する。スキームは引き続き Xcode の自動生成に任せる。`tools/build_release.rb` と `tools/install_app.rb` は Ruby の標準ライブラリだけで動くので、そのまま残す。新しい macOS 権限や OS バージョン要件はないが、開発には Xcode 16 以降が必要（対象 OS が macOS 26 のため、実質的な変更はない）。
