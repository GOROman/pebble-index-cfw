# Pebble Click Flash (macOS)

CFWリングのクリックで画面を光らせて効果音を鳴らし、長押し録音をノイズ低減・日本語STTしてニコニコ動画風のコメントにするメニューバーアプリです。クリックはペアリング・GATT接続なしで受信し、音声は必要なときだけGATT接続します。Swift、AppKit、CoreBluetoothを使い、Pythonは不要です。

```sh
sh tools/mac-click-flash/build.sh
open "build/Pebble Click Flash.app"
```

初回のBluetooth許可を承認し、リングを押してください。最初に見つかった `Pebble Index CFW` のみを追跡します。複数のリングがある場合はCoreBluetoothのUUIDを指定できます。

```sh
open "build/Pebble Click Flash.app" --args --device YOUR-COREBLUETOOTH-UUID --log "$PWD/build/mac-click-flash.jsonl"
```

メニューバーの稲妻アイコンから一時停止、フラッシュのテスト、終了ができます。フラッシュは入力やフォーカスを奪いません。BLE広告の重複を除去し、カウンターの循環と再起動を区別します。複数のクリックを一度に受信した場合は1回のフラッシュにまとめます。最初の広告のカウンターが0以外なら、最初のクリックにも反応するよう1回光ります。

フラッシュは参考画像のサンダーボルトに合わせた四方向の黄色い稲妻と黄金の光で表示し、約0.22秒で2回ビカビカと点滅し、同時に合成した雷の轟音が鳴ります。「効果音をミュート」で音だけオフにできます。

## 音声

リングを長押しして話し、離すと録音を自動取得します（最大6.144秒）。音声はBLE接続中だけGATTで取得し、取得後は切断してクリック広告の受信に戻ります。Android Flasherも音声を自動取得するため、Macで受信するときは終了しておいてください。

保存先はアプリの隣の `recordings/`（通常 `build/recordings/`）。8 kHz・16-bit・モノラルのWAVと、元のIMA ADPCM・サンプル数情報を保存します。メニューの「最新の録音を再生」「録音フォルダを開く」で確認できます。`--recordings /absolute/path` で保存先を変更できます。音声はローカルに保存され、ネット送信や文字起こしは行いません。

CFWは1件だけ録音を保持し、転送完了時にリング側の録音を消去します。このため受信データは転送中からADPCMファイルにも保存します。中断した転送は部分ファイルが残り、20秒後に再試行します。一時停止中は新たな音声取得も開始しません。

## ノイズ低減・STT・流れるコメント

```sh
brew install ffmpeg whisper-cpp
sh tools/mac-click-flash/setup-stt.sh
sh tools/mac-click-flash/build.sh
open "build/Pebble Click Flash.app"
```

録音保存後にFFmpegで90 Hz以下の低い雑音と帯域外成分を抑え、`afftdn` による12 dBのノイズ低減・音量補正を行います。16 kHzのWAVにして、Whisper smallで日本語をローカル認識します。モデルは公式Whisper.cppの配布元から取得し、SHA-256を確認します。認識結果は大きな白文字・黒い縁取りで、画面の右から左に流れます。コメント表示・文字起こし中もBLEクリックを受信し、稲妻と効果音を出します。5段のレーンを使い、同じレーンのコメントが重ならないようにします。全ディスプレイと全画面アプリ上で表示し、マウス・キーボード・フォーカスを奪いません。

音声・認識結果はネット送信しません。録音の隣に `.clean.wav`、`.transcript.txt`、`.transcript.json`、`.stt.log` を残します。元の録音も保持します。雑音や音楽などの括弧付き説明だけを認識した場合は、コメントを出しません。認識精度と時間は録音品質・Mac・モデルによって変わります。一時停止中はコメントを消し、認識処理が完了してもコメント表示を再開しません。

`--model /path/to/ggml-model.bin` で別モデル、`--ffmpeg` と `--whisper` で実行ファイルを指定できます。デフォルトの実行ファイルはApple Silicon Homebrewの `/opt/homebrew/bin/` です。

コメント表示のテスト（12秒後に自動終了）:

```sh
open -W "build/Pebble Click Flash.app" --args --demo-comment "声が文字になって流れる！"
```

既存WAVのノイズ低減→STT→表示のテスト（認識後12秒で自動終了）:

```sh
open -W "build/Pebble Click Flash.app" --args --transcribe-file /absolute/path/to/recording.wav
```

これらのテスト引数は、常駐アプリを終了してから使ってください。メニューの「コメント表示をテスト」なら起動中にも試せます。

動作確認（1回光って自動終了）:

```sh
open -W "build/Pebble Click Flash.app" --args --self-test --log "$PWD/build/mac-click-flash-test.jsonl"
```

CFWはクリック後だけ短時間広告します。5回素早く押すと復旧モードに戻るため、テスト時は1回ずつ押してください。公式Pebbleアプリは終了したままにしてください。
