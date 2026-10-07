# Pebble Voice → Dots

MacのリングSTT結果を、認証付きCloudflare Workerへ送り、DotsのMCP Events購読に配信します。音声ファイルやOpenAI APIキーはこのWorkerへ送りません。現在の送信元はMac版です。

## タマタマへの接続

1. ChatGPTの **Plugins → ＋ → Add custom MCP server**。
2. 名前: **Pebble Voice**。
3. MCP URL: `https://pebble-dots-bridge.hentai-naru-sensei.workers.dev/mcp`。
4. 認証: **OAuth**。PKCEのS256・動的クライアント登録に対応しています。
5. 接続画面でローカル設定パスフレーズを入力。現在のMacでは `~/.config/pebble-click-flash/dots-login-passphrase.txt` に保存しています。パスフレーズをGit・チャットへ貼らないでください。
6. プラグインのツール一覧に `get_recent_voice`、イベント一覧に `voice.transcribed` が出ることを確認。
7. タマタマに以下を伝えてください。

> Pebble Voiceの voice.transcribed を device=pebble-index で購読してください。届く文字起こしを私の発言として受け取り、必要な返答をこの会話に返してください。設定できた購読を確認してください。

購読後に新しく録音すると、STT結果がタマタマへ届きます。購読前のテキストは最近の履歴に保存され、`get_recent_voice` で読めます。購読前の履歴を自動配信したり、別のChatGPT会話へ送信したりはしません。Dots側の接続・実受信が確認されるまでは未接続扱いです。

プラグイン用の可搬マニフェストは `plugin/` にあります。プラグインの追加・イベント購読にはChatGPT側のアカウント・ワークスペースで対応機能が有効になっている必要があります。

## Macからの送信

`~/.config/pebble-click-flash/dots-bridge.json` を権限600で保存:

```json
{"endpoint":"https://YOUR-WORKER/ingest","token":"YOUR-INGEST-TOKEN"}
```

この設定があれば、音声認識完了後にテキストを送信します。一時停止中は送信しません。ファイル名のSHA-256をIDとして使い、ローカルの絶対パスは送信しません。通信失敗時はリポジトリ外の `dots-outbox/` に保存して30秒ごとに再試行します。サーバーが受け付けた後はローカルの送信待ちファイルを削除します。

MCPイベントの購読・コールバックURL・署名秘密鍵はWorkerのDurable Objectに永続化します。送信ごとにStandard WebhooksのHMAC-SHA256署名を付けます。署名鍵の短期ローテーション、同一イベントIDでの再試行、購読期限切れ・停止、410/413を扱います。

公開URLのヘルスチェックとOAuthメタデータ以外は認証が必要です。受信は別のINGEST_TOKEN、MCPは所有者パスフレーズで許可したOAuthトークンで保護します。コールバック先はHTTPSのChatGPT/OpenAIサービスドメインに限定し、リダイレクトしません。独自コールバック先は受け付けません。

サーバー履歴は最新200件、読み取りツールは最新10件。現在は個人用の単一所有者構成です。

## 再デプロイ

```sh
node --test tools/dots-bridge/test/*.test.js
wrangler deploy --dry-run --config tools/dots-bridge/wrangler.jsonc
wrangler deploy --config tools/dots-bridge/wrangler.jsonc
wrangler secret bulk /path/outside/repository/secrets.json --config tools/dots-bridge/wrangler.jsonc
```

秘密ファイル:

```json
{"INGEST_TOKEN":"GENERATE-A-RANDOM-TOKEN","OWNER_PASSPHRASE_HASH":"SHA256-OF-OWNER-PASSPHRASE"}
```

別アカウントにデプロイした場合、plugin/mcp.jsonとMacの送信先をそのWorker URLへ変更してください。

## 検証範囲

自動テスト: OAuth/PKCE、単回認可コード、トークン更新、非認証リクエスト拒否、署名、コールバック検証、購読の冪等性、保存後の再開、重複入力、配信再試行、購読解除。デプロイ後もOAuth・MCP discovery・ツールとイベント一覧・テキスト受信を確認します。

実際のDotsへの配信は、タマタマ側の接続・購読・返答で確認してください。サーバーの202だけではDotsへの到達の証明にはなりません。

公式仕様: https://developers.openai.com/plugins/build/mcp-events
