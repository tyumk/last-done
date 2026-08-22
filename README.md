# last-done

勉強目的のシンプルな「やったこと記録」アプリです。

- フロントエンド: Flutter (Android)
- バックエンド: Azure Functions (C# / .NET Isolated)
- DB: Azure Table Storage
- IaC: Bicep

## ディレクトリ構成

- `frontend/last_done_app`: Flutter アプリ
- `backend/LastDoneApi`: Azure Functions API
- `infra`: Azure リソース作成用 Bicep

## 仕様メモ

- 初回起動時に「家族コード(6桁英数字)」「ユーザー名」を入力してローカル保存
- API リクエスト時はヘッダーに以下を付与
	- `X-Family-Code`
	- `X-User-Name`
- 家族コードで同一家族のデータのみ参照
- 「更新」ボタン押下で、対象項目の実施日/実施者を更新し履歴追加

## API エンドポイント

ベース URL 例: `http://localhost:7071/api`

- `GET /daily-items`
	- 一覧取得
- `POST /daily-items`
	- 新規追加
	- body: `{ "text": "皿洗い" }`
- `POST /daily-items/{id}/refresh`
	- 日付/ユーザー更新 + 履歴追加

## ローカル実行

### 1. バックエンド

前提:

- .NET SDK 8
- Azure Functions Core Tools v4
- Azurite (ローカル Table Storage 用)

実行:

```bash
cd backend/LastDoneApi
dotnet restore
func start
```

`LastDoneStorageConnection` は VS Code 拡張版 Azurite の Table endpoint (`http://127.0.0.1:10002`) を使う設定です。
`AzureWebJobsStorage` は Functions Host 用に既定値のままです。

### 2. フロントエンド

前提:

- Flutter SDK

実行:

```bash
cd frontend/last_done_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:7071/api
```

Android エミュレーターからローカル PC の `localhost` に接続するため、`10.0.2.2` を使用します。

## Azure デプロイ (Bicep)

`infra/main.bicep` で以下を作成します。

- Storage Account
- Table (`Families`, `DailyItems`, `DailyItemHistory`)
- Application Insights
- Function App (FlexConsumption)

デプロイ例:

```bash
az group create -n rg-last-done -l japaneast
az deployment group create \
	-g rg-last-done \
	-f infra/main.bicep \
	-p @infra/main.parameters.example.json
```

## 運用メモ

新規登録機能は実装していません。
管理者が `Families` テーブルへ家族コードを事前登録してください。

- `PartitionKey`: `FAMILY`
- `RowKey`: 家族コード (6桁英数字)
- `IsActive`: `true`(真偽値。`Edm.Boolean`型で登録する必要がある。詳細は `scripts/register-family.ps1` 参照)

登録には `scripts/register-family.ps1` が使える:

```powershell
./scripts/register-family.ps1 -ResourceGroupName <リソースグループ名> -FamilyCode <6桁英数字>
```