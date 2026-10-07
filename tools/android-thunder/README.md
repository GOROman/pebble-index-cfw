# Android Thunder + audio waveform

対象: https://github.com/elvisoliveira/pebble-index-flasher の commit `0b131bc64cfa77a558a61299bb999e42435c39e7`。

CFWクリックを受信するとアプリ画面に四方向の黄金の稲妻を2回点滅させ、雷の音を鳴らします。音声の転送開始通知で白フラッシュ、転送完了後にPCMの波形を緑のオシロスコープ風グリッドへ表示します。波形は1画素ごとの最小・最大振幅を描き、短いピークも残します。アクティビティ内の表示で、他アプリへのオーバーレイ権限は使いません。

## 適用

1. 対象Flasherへ `offline-fix.patch`、`MainActivity.patch`、`AudioMainActivity.patch`、`ClipDownload.patch` の順で `git apply`。
2. `OfflineEnvironment.kt`、`ThunderEffect.kt`、`AudioWaveView.kt` を `src/main/kotlin/poc/ringclick/` にコピー。
3. `thunder.wav` を `src/main/res/raw/` にコピー。
4. Android SDKとJDK 17以降で `./gradlew assembleDebug -PcfwLocal=/absolute/path/DA14531_App.bin`。
5. `adb -s IP:PORT install -r build/outputs/apk/debug/pebble-index-flasher-debug.apk`。

オフライン修正は自動ファームウェア更新を無効化し、ローカルCFWを使います。アプリのインストールだけではリングのファームウェアを書き換えません。

## 確認

雷: `adb shell am start -n poc.ringclick/.MainActivity --ez thunder_test true`。

波形: PCM16/8kHz/mono/44バイトヘッダーのWAVを `run-as poc.ringclick` で `files/wave-test.wav` に置き、アプリを停止後 `adb shell am start -n poc.ringclick/.MainActivity --ez wave_test true`。実音声の受信時も同じ白フラッシュと波形表示を呼びます。

Mac側とAndroid側が同時に録音を取得しようとすると、先に取得した側へ届きます。Androidで録音を確認するときはMac側を一時停止してください。クリック広告は両方で受信できます。
