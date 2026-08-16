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

Flutter(Android想定)。基本コマンドのみ:
```bash
cd frontend/last_done_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:7071/api
```
実機やAzure上のバックエンドに接続する場合は `API_BASE_URL` を接続先に合わせて変更する。

## ビルド方法

- バックエンド: `dotnet build backend/LastDoneApi/LastDoneApi.csproj`(`.vscode/tasks.json` に `build`/`publish`/`watch` タスクあり)
- フロントエンド: `flutter build apk`(Android向け。iOS/Web/Desktop用の設定ファイルも存在するが、READMEが前提とする配布形態はAndroidのみ)

## テスト方法

- フロントエンド: `flutter test`(`frontend/last_done_app/test/`配下)
- バックエンド: 現状 xUnit 等のテストプロジェクトは無い(新規追加する場合は `backend/` 配下に別プロジェクトを作成する形になる)

## Azureデプロイ

`infra/main.bicep` を使う。

```bash
az group create -n <リソースグループ名> -l japaneast
az deployment group create \
  -g <リソースグループ名> \
  -f infra/main.bicep \
  -p @infra/main.parameters.example.json
```

- Function App へのコードデプロイは別途 `func azure functionapp publish <name>` または `dotnet publish` + zip deploy 等が必要(Bicepはリソース作成のみ)
- デプロイ後、`Families` テーブルへ家族コードを手動登録しないとアプリを利用できない(自己登録機能なし)
- フロントエンドはAzureにはデプロイしない(APKとして配布する想定)。バックエンドURLに合わせて `API_BASE_URL` を切り替えてビルドする

## 重要な設計上の特徴

- **認証はカスタムヘッダーのみ**: Function自体は `AuthorizationLevel.Anonymous`。`X-Family-Code` の正当性のみ `Families` テーブルで検証し、`X-User-Name` は検証なし(名乗るだけ)。Function KeyやAPIM等での追加保護を前提としない、学習目的の簡易実装
- **CORS設定は `main.bicep` に含まれていない**: Flutter Web版など、ブラウザから直接APIを叩く構成を追加する場合は別途CORS設定が必要
- **Table Storageに直接依存**: ORMやリポジトリ抽象を挟まず、`Services` 層が `Azure.Data.Tables` のAPIを直接扱う設計
- **履歴は正規化された別テーブル**: `DailyItemHistory` のパーティションキーを `{familyCode}_{itemId}` とすることで、項目ごとの履歴をパーティション内クエリで取得
- **設定はすべて `IConfiguration` 経由**: テーブル名・ヘッダー名・タイムゾーンなどはハードコードせず `local.settings.json`(ローカル)/ Function App の設定(本番)から注入され、Bicep側でも同名のapp settingsとして定義されている
