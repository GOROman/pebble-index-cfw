# Android Thunder + audio waveform

対象: https://github.com/elvisoliveira/pebble-index-flasher の commit `0b131bc64cfa77a558a61299bb999e42435c39e7`。

CFWシングルクリックを受信するとアプリ画面に四方向の黄金の稲妻を2回点滅させ、雷の音を鳴らします。音声の転送開始通知で白フラッシュ、転送完了後にPCMの波形を緑のオシロスコープ風グリッドへ表示します。波形は1画素ごとの最小・最大振幅を描き、短いピークも残します。音声の波形・白フラッシュはアクティビティ内、クリック時の雷は常駐サービスのシステムオーバーレイに表示します。

## 適用

1. 対象Flasherへ `offline-fix.patch`、`MainActivity.patch`、`AudioMainActivity.patch`、`ClipDownload.patch`、`OverlayManifest.patch`、`OverlayMainActivity.patch`、`OverlayScanner.patch`、`ForegroundAudio.patch` の順で `git apply`。
2. `OfflineEnvironment.kt`、`ThunderEffect.kt`、`AudioWaveView.kt`、`ThunderService.kt` を `src/main/kotlin/poc/ringclick/` にコピー。
3. `thunder.wav` を `src/main/res/raw/` にコピー。
4. Android SDKとJDK 17以降で `./gradlew assembleDebug -PcfwLocal=/absolute/path/DA14531_App.bin`。
5. `adb -s IP:PORT install -r build/outputs/apk/debug/pebble-index-flasher-debug.apk`。

オフライン修正は自動ファームウェア更新を無効化し、ローカルCFWを使います。アプリのインストールだけではリングのファームウェアを書き換えません。

## 確認

雷: `adb shell am start -n poc.ringclick/.MainActivity --ez thunder_test true`。

波形: PCM16/8kHz/mono/44バイトヘッダーのWAVを `run-as poc.ringclick` で `files/wave-test.wav` に置き、アプリを停止後 `adb shell am start -n poc.ringclick/.MainActivity --ez wave_test true`。実音声の受信時も同じ白フラッシュと波形表示を呼びます。

Mac側とAndroid側が同時に録音を取得しようとすると、先に取得した側へ届きます。Androidで録音を確認するときはMac側を一時停止してください。クリック広告は両方で受信できます。


## 常駐・システムオーバーレイ

「他のアプリの上に表示」と通知を許可すると、connectedDevice型のForeground ServiceがBLEスキャンを継続します。アプリをホームへ戻しても、クリックで全画面の黄金の稲妻と雷音が出ます。通知の「停止」で終了できます。アプリを再度開くと再開します。サービスが有効な状態での再起動はBOOT_COMPLETEDで再開を試みます。OSやメーカーによる停止・強制停止・電源オフ・Bluetoothオフ中までの検知は保証しません。

TYPE_APPLICATION_OVERLAYで画面を表示し、触れたりフォーカスを奪ったりしません。ウィンドウの不透明度は0.75に抑えています。BLEのメーカーIDフィルターを使い、無フィルタースキャンが画面オフで止まる問題を避けます。ロック画面や権限ダイアログなどの保護されたシステム画面ではOSにより表示が制限される場合があります。

Androidの自動録音取得はアプリ画面を開いている間だけ動きます。ホームや別アプリに移動した後はMacが録音を取得できます。雷の常駐サービスは引き続き動きます。
