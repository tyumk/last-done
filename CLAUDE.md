# CLAUDE.md

このファイルは、Claude Code がこのリポジトリで作業する際のガイドです。

## プロジェクト概要

`last-done` は、家族で共有する「やったこと記録」アプリ(勉強目的のシンプルなSPA/モバイルアプリ)。
「皿洗い」のような繰り返しタスクを登録し、「更新」ボタンで実施日・実施者を記録、履歴を蓄積する。

- 新規ユーザー登録機能はない。管理者が Azure Table Storage の `Families` テーブルへ家族コードを事前登録する運用。
- 家族コード(6桁英数字)を知っている端末は誰でもその家族のデータを読み書きできる(パスワード認証なし)。

## ディレクトリ構成

```
last-done/
├── frontend/last_done_app/   # Flutter アプリ(現状 Android 想定)
│   ├── lib/main.dart         # 全画面・APIクライアントを含む単一ファイル実装
│   └── test/widget_test.dart # ウィジェットテスト
├── backend/LastDoneApi/      # Azure Functions (C# / .NET Isolated worker)
│   ├── Functions/            # HTTPトリガー関数
│   ├── Models/                # Table Entity / DTO 定義
│   ├── Services/               # ビジネスロジック・Table Storageアクセス
│   ├── Program.cs             # DIコンテナ登録
│   ├── host.json / local.settings.json
├── infra/
│   ├── main.bicep                     # Azureリソース定義(IaC)
│   └── main.parameters.example.json   # デプロイパラメータのサンプル
└── README.md
```

## 技術スタック

### フロントエンド
- Flutter / Dart(Material 3)
- 主要パッケージ: `http`(API呼び出し)、`shared_preferences`(家族コード・ユーザー名のローカル保存)
- 画面構成: `BootPage`(初回判定)→ `SetupPage`(家族コード・ユーザー名入力)/ `HomePage`(一覧・追加・更新)

### バックエンド
- Azure Functions v4、.NET Isolated worker モデル(`TargetFramework` は `net10.0`)
- `Azure.Data.Tables` を使い Azure Table Storage に直接アクセス(ORM等は使用していない)
- DIで `TableStorageService` → `FamilyAuthService` / `DailyItemService` を注入する構成
- `Microsoft.Azure.Functions.Worker` / `Microsoft.Azure.Functions.Worker.Sdk` は 2.x 系を使用。1.x系(例: Sdk 1.18.0)は `net10.0` を認識せず `Invalid combination of TargetFramework and AzureFunctionsVersion` でビルド失敗するため、TargetFrameworkを上げる際はこれらのパッケージも合わせて2.x系以降に更新する必要がある

### インフラ (IaC)
- Bicep で以下を定義: Storage Account、Table3種(`Families`/`DailyItems`/`DailyItemHistory`)、Application Insights、Function App(Linux, FlexConsumptionプラン)

## アーキテクチャ・API仕様

ベースURL例: `http://localhost:7071/api`(ローカル)。本番はFunction AppのURL。

全リクエストで以下のカスタムヘッダーによる認証(Function自体は `AuthorizationLevel.Anonymous`):
- `X-Family-Code`: 家族コード。`Families` テーブルに `PartitionKey=FAMILY`, `RowKey=<コード>`, `IsActive=true` で登録されている必要あり
- `X-User-Name`: 表示用ユーザー名。値の正当性チェックはなく、名乗るだけで誰でもなりすまし可能

| メソッド | パス | 内容 |
|---|---|---|
| GET | `/daily-items` | 家族コードに紐づく一覧取得(履歴込み) |
| POST | `/daily-items` | 新規追加。body: `{ "text": "皿洗い" }` |
| POST | `/daily-items/{id}/refresh` | 実施日/実施者を更新し履歴に1件追加 |

### データモデル(Table Storage)
- `DailyItems`: `PartitionKey=familyCode`, `RowKey=itemId(GUID)`。Text/CreatedBy/CreatedDate/UpdatedBy/UpdatedDate を保持
- `DailyItemHistory`: `PartitionKey={familyCode}_{itemId}`, `RowKey={unixMillis}_{GUID}`。DoneDate/UserNameを保持(項目ごとの実施履歴)
- `Families`: `PartitionKey=FAMILY`, `RowKey=家族コード`, `IsActive`

日付は `TimeZoneId` 設定(既定 `Asia/Tokyo`)に基づきサーバー側で `yyyy-MM-dd` 形式に計算。

## 主要コンポーネント

**Backend**
- `Functions/DailyItemsFunctions.cs`: HTTPエンドポイントの入り口。認証・バリデーション・JSON変換を担当
- `Services/FamilyAuthService.cs`: `X-Family-Code` の検証、`X-User-Name` の取得
- `Services/DailyItemService.cs`: 一覧取得・作成・更新(履歴追加含む)のコアロジック
- `Services/TableStorageService.cs`: 設定(`IConfiguration`)からテーブル名・接続文字列を解決し `TableClient` を生成。呼び出し時に `CreateIfNotExists` する

**Frontend**
- `lib/main.dart` に以下をすべて実装(画面数が少ないため単一ファイル構成):
  - `AppConfig`: `API_BASE_URL` を `--dart-define` で外部から注入(既定はAndroidエミュレータ向け `http://10.0.2.2:7071/api`)
  - `LocalAuthStore`: `shared_preferences` で家族コード・ユーザー名を保存/読込/削除
  - `ApiClient`: バックエンドAPIの呼び出しラッパー

## ローカル実行方法

### バックエンド

前提ツール:
- .NET SDK(`net10.0` をビルドできるバージョン)
- Azure Functions Core Tools v4(`func` コマンド)
- Azurite(ローカル Table/Blob/Queue Storage エミュレータ)。Node.js 21+ が必要
  - VS Code拡張版Azurite(`Azurite.azurite`)がインストール済みならそれを使ってよい。ただし拡張はVS Codeの内蔵ランタイムで動くため、**ターミナル単体からは起動できない**。ターミナルから直接起動したい場合は、システムにNode.js 21+を別途インストールした上で、拡張の実体を直接叩く:
    ```bash
    node "<VSCode拡張のインストール先>/dist/src/azurite.js" --location <データ保存先フォルダ>
    ```
    (`<VSCode拡張のインストール先>` は通常 `~/.vscode/extensions/azurite.azurite-<version>`)
  - `--location` は必ずリポジトリ外の作業用フォルダを指定する。リポジトリ直下を指定すると `__azurite_db_*.json` や `__blobstorage__/` 等のDBファイルが生成されリポジトリを汚す

起動手順:
```bash
# 1. Azuriteを起動しておく(上記参照。既定ポート: Blob 10000 / Queue 10001 / Table 10002)

# 2. バックエンドを起動
cd backend/LastDoneApi
dotnet restore
func start
```
- `local.settings.json` の `AzureWebJobsStorage` / `LastDoneStorageConnection` は `UseDevelopmentStorage=true`(Azuriteの既定ポートに接続する簡易記法)
- Azure Functions isolated worker モデルの制約上、`dotnet run` では起動できず `func start` 経由での起動が必要
- `func start` 実行時に `Running 'func start' directly against a .NET Isolated project may not correctly load function extensions...` という警告が出るが、無視してよい(実際にはHTTPトリガー3本とも正常にロードされる)
- 起動後、`http://localhost:7071/api/daily-items` 等にHTTPトリガーが公開される

初回動作確認時の注意:
- `Families` テーブルに家族コードが1件も無い状態では、全エンドポイントが `401 Unauthorized`(`Invalid family code.`)を返す。動作確認するには `Azure.Data.Tables` 等で `Families` テーブルに `PartitionKey=FAMILY`, `RowKey=<6桁コード>`, `IsActive=true` のレコードを事前投入する必要がある(READMEの「運用メモ」と同じ)
- 日本語などマルチバイト文字を含むリクエストボディを `curl` 等でテストする場合、コマンドライン引数にそのまま埋め込むとシェル/OSのエンコーディングにより文字化けし `500` エラー(JSON変換失敗)になることがある。UTF-8で保存したファイルを `--data-binary @file` のように読み込ませれば正しく送信できる(API側の問題ではない)

### フロントエンド

```bash
cd frontend/last_done_app
flutter pub get
```
`flutter doctor` で対象プラットフォームのツールチェーンが揃っているか事前確認できる。

起動先(device)ごとの違い:

| 起動先 | コマンド例 | 前提 | 備考 |
|---|---|---|---|
| Android実機/エミュレータ(本来の対象) | `flutter run -d <device-id> --dart-define=API_BASE_URL=http://10.0.2.2:7071/api` | Android SDK | `10.0.2.2` はAndroidエミュレータから見たホストPCの`localhost`のエイリアス。実機接続の場合はホストPCの実IPアドレスに変更する |
| Windowsデスクトップアプリ | `flutter run -d windows --dart-define=API_BASE_URL=http://localhost:7071/api` | Visual Studio(C++によるデスクトップ開発ワークロード) | `shared_preferences`等プラグインを使うアプリはビルド時にシンボリックリンク作成が必要。Windowsの「開発者モード」(`設定 > プライバシーとセキュリティ > 開発者向け`)を有効化していないと `Error: Building with plugins requires symlink support` でビルド失敗する |
| Chrome等ブラウザ(Web) | `flutter run -d web-server --web-port=<port> --dart-define=API_BASE_URL=http://localhost:7071/api` の後、ブラウザで `http://localhost:<port>` を開く | Chrome等 | 現状のバックエンドは**CORS未対応のためWeb版は実用不可**(`OPTIONS`プリフライトが404になりAPI呼び出しが全て失敗する)。また`X-User-Name`ヘッダーに日本語等の非ASCII文字を入れるとブラウザのFetch API仕様上エラーになる(`Headers`の値はISO-8859-1相当のみ許容)。動作確認目的なら、`flutter run -d chrome`(Flutterが別途独自にChromeを起動し外部から制御しづらい)より、`web-server`ターゲット+手動でブラウザを開く方法の方が検証しやすい |

#### Androidエミュレータ(AVD)をゼロから用意する場合

Android Studio未導入、またはAVD未作成の環境でコマンドラインのみで用意する手順:

```bash
# 0. sdkmanager/avdmanagerの実行にはJDK 17+が必要。Android Studio同梱JDKを指定すると確実
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"   # Windows の例

# 1. システムイメージのダウンロード(数百MB~1.5GB程度。既にインストール済みのSDK Platformバージョンに合わせるとよい)
sdkmanager "system-images;android-36;google_apis;x86_64"

# 2. AVD作成(-d でデバイスプロファイルを指定)
avdmanager create avd -n <AVD名> -k "system-images;android-36;google_apis;x86_64" -d pixel_6

# 3. 起動
emulator -avd <AVD名>
```
- `sdkmanager` / `avdmanager` は `<Android SDKのパス>/cmdline-tools/latest/bin/` にある
- 起動完了待ちは `adb shell getprop sys.boot_completed` が `1` を返すまでポーリングするのが確実
- 起動後は `flutter devices` や `adb devices` でデバイスIDを確認し、通常通り `flutter run -d <device-id>` でアプリを実行できる

#### 既知の制約

- **リモート/自動化環境でのキーボード入力**: エミュレータのプロセスを起動したWindowsセッション(例: RDPログイン時のセッション)と、実際にキー入力しているセッション(物理コンソール等)が異なると、エミュレータのウィンドウは表示・マウス操作できてもキーボード入力だけが届かないことがある(Windowsのセッション分離による制約で、エミュレータやアプリ自体の不具合ではない)。この場合、`adb shell input tap <x> <y>` / `adb shell input text <text>` でUI操作・文字入力を代替できる(ただし`input text`はASCII文字のみ対応。日本語等マルチバイト文字を送るにはADBKeyboardのような別のIME経由の仕組みが別途必要)

## ビルド方法

- バックエンド: `dotnet build backend/LastDoneApi/LastDoneApi.csproj`(`.vscode/tasks.json` に `build`/`publish`/`watch` タスクあり)
- フロントエンド: `flutter build apk --dart-define=API_BASE_URL=<バックエンドのAPI URL>`(Android向け。iOS/Web/Desktop用の設定ファイルも存在するが、READMEが前提とする配布形態はAndroidのみ)

### Android リリース署名鍵の準備(初回のみ)

`android/app/build.gradle.kts` はデフォルトのFlutterテンプレートのままだと **リリースビルドもdebug鍵で署名される**(`flutter build apk` は成功しdebugビルドとして問題なく動くが、Play Store配布不可・別マシンでの再ビルド時に署名不一致で上書きインストール不可、という問題がある)。`android/key.properties` の有無で自動的に切り替わるようになっている(無ければdebug鍵にフォールバック、開発時の `flutter run --release` 等はそのまま動く)ので、配布用ビルドの前に一度だけ専用鍵を作成する。

```bash
# Android StudioのJDKに含まれる keytool を使う例(Windows)
KEYTOOL="/c/Program Files/Android/Android Studio/jbr/bin/keytool"

"$KEYTOOL" -genkeypair -v \
  -keystore frontend/last_done_app/android/app/upload-keystore.jks \
  -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <ストアパスワード> -keypass <ストアパスワードと同じ値> \
  -dname "CN=<任意>, OU=<任意>, O=<任意>, L=<任意>, ST=<任意>, C=JP"
```

- PKCS12形式(現在の`keytool`の既定)では **ストアパスワードとキーパスワードを別々にできない**(`-keypass`に別の値を指定しても無視され、ストアパスワードに統一される)。`key.properties`の`storePassword`/`keyPassword`には同じ値を書く
- `frontend/last_done_app/android/key.properties` を作成し、鍵情報を記載する(`.gitignore`で除外済みなのでコミットされない):
  ```properties
  storePassword=<ストアパスワード>
  keyPassword=<ストアパスワードと同じ値>
  keyAlias=upload
  storeFile=upload-keystore.jks
  ```
- **`upload-keystore.jks` と `key.properties` は紛失・流出させないこと**。紛失すると同じアプリの署名更新ができなくなり(Play Store配布時は特に致命的)、流出すると第三者が同じアプリIDでなりすましビルドを配布できてしまう。安全な場所(パスワードマネージャ等)にバックアップする
- 署名の確認は `apksigner verify --print-certs <apkパス>`(Android SDKの `build-tools/<version>/apksigner.bat`)。証明書DNが上記で指定した値になっていればdebug鍵ではなく専用鍵で署名されている

## テスト方法

- フロントエンド: `flutter test`(`frontend/last_done_app/test/`配下)
- バックエンド: 現状 xUnit 等のテストプロジェクトは無い(新規追加する場合は `backend/` 配下に別プロジェクトを作成する形になる)

## Azureデプロイ

`infra/main.bicep` を使う。`main.bicep` は Flex Consumption プラン(`FC1`)向けに `functionAppConfig.runtime` / `functionAppConfig.deployment.storage` を使う構成になっている(通常のY1/EP消費プランのような `siteConfig.linuxFxVersion` 単体では動かない)。ランタイムバージョンはバックエンドの `TargetFramework`(`net10.0`)に合わせて `10.0` を指定済み。対応バージョンはリージョンごとに `az functionapp list-flexconsumption-runtimes --location <region> --runtime dotnet-isolated` で確認できる。

### 0. Azure CLI のセットアップ・認証(Windows環境での注意点)

- `az` コマンドがインストール済みでもPowerShell/Git BashのPATHに含まれないことがある。その場合はフルパス(`C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd`)を指定するか、セッションのPATHに追加する
- テナントの条件付きアクセスポリシーによっては、`az login` 自体は成功しても `az deployment group create` 等のARM管理操作時に別途MFA再認証(claims-challenge)を要求されることがある。その場合はエラーメッセージ中に表示される以下の形式のコマンドをそのまま実行する:
  ```bash
  az login --tenant "<tenantId>" --scope "https://management.core.windows.net//.default" --claims-challenge "<challenge>"
  ```

### 1. リソースグループ作成

```bash
az group create -n <リソースグループ名> -l japaneast
```

### 2. 必要なリソースプロバイダーの登録(サブスクリプションで未登録の場合のみ)

未登録のまま `az deployment group create` を実行すると `MissingSubscriptionRegistration` / プロバイダー登録エラーで失敗する。事前に登録しておく:

```bash
az provider register --namespace Microsoft.Web --wait
az provider register --namespace microsoft.operationalinsights --wait
az provider register --namespace Microsoft.Storage --wait
az provider register --namespace Microsoft.Insights --wait
```

### 3. インフラのデプロイ

```bash
# 事前検証(何も作成されない)
az deployment group validate \
  -g <リソースグループ名> \
  -f infra/main.bicep \
  -p infra/main.parameters.example.json

az deployment group create \
  -g <リソースグループ名> \
  -f infra/main.bicep \
  -p infra/main.parameters.example.json
```

デプロイ完了後、output の `functionAppName` / `functionBaseUrl` を控えておく(以降の手順で使用)。

### 4. コードのデプロイ

```bash
cd backend/LastDoneApi
func azure functionapp publish <functionAppName>
```

- Bicepによるリソース作成だけではコードは配置されない。上記コマンド、または `dotnet publish` + zip deploy 等で別途デプロイする必要がある
- `func` コマンドも内部で `az` を呼ぶため、手順0のPATH設定が必要な場合がある

### 5. 家族コード登録

デプロイ後、`Families` テーブルへ家族コードを手動登録しないとアプリを利用できない(自己登録機能なし)。`scripts/register-family.ps1` で登録できる:

```powershell
./scripts/register-family.ps1 -ResourceGroupName <リソースグループ名> -FamilyCode <6桁英数字>
```

- リソースグループ内のストレージアカウントが1つの場合は自動解決するが、複数ある場合は `-StorageAccountName` で明示する
- **`az storage entity insert` の型自動推定は `IsActive=true` を文字列 `"true"` として保存してしまい、バックエンド側の `FamilyEntity.IsActive`(`bool`型)へのデシリアライズで `InvalidCastException`(APIが500を返す)が発生する**。`scripts/register-family.ps1` は `IsActive@odata.type=Edm.Boolean` を明示することでこれを回避している。az CLIで直接操作する場合も同様に型指定が必要
- 既存コードを上書きする場合は `-Force`(内部的に `--if-exists replace`)を指定する

### 6. フロントエンド接続先の切り替え

(未実施・詳細未検証)

- フロントエンドはAzureにはデプロイしない(APKとして配布する想定)。バックエンドURLに合わせて `API_BASE_URL` を切り替えてビルドする

## 重要な設計上の特徴

- **認証はカスタムヘッダーのみ**: Function自体は `AuthorizationLevel.Anonymous`。`X-Family-Code` の正当性のみ `Families` テーブルで検証し、`X-User-Name` は検証なし(名乗るだけ)。Function KeyやAPIM等での追加保護を前提としない、学習目的の簡易実装
- **CORS設定は `main.bicep` に含まれていない**: Flutter Web版など、ブラウザから直接APIを叩く構成を追加する場合は別途CORS設定が必要。現状ではブラウザからの`OPTIONS`プリフライトリクエストが404になりAPI呼び出しが全て失敗するため、Web版は実質的に動作しない(詳細は「ローカル実行方法 > フロントエンド」参照)
- **Table Storageに直接依存**: ORMやリポジトリ抽象を挟まず、`Services` 層が `Azure.Data.Tables` のAPIを直接扱う設計
- **履歴は正規化された別テーブル**: `DailyItemHistory` のパーティションキーを `{familyCode}_{itemId}` とすることで、項目ごとの履歴をパーティション内クエリで取得
- **設定はすべて `IConfiguration` 経由**: テーブル名・ヘッダー名・タイムゾーンなどはハードコードせず `local.settings.json`(ローカル)/ Function App の設定(本番)から注入され、Bicep側でも同名のapp settingsとして定義されている
