<#
.SYNOPSIS
    Azure Table Storage の Families テーブルへ家族コードを登録する。
.EXAMPLE
    ./register-family.ps1 -ResourceGroupName last-done -FamilyCode yy1123
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9]{6}$')]
    [string]$FamilyCode,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    # 省略時はリソースグループ内のストレージアカウントを自動解決する(1件のみの場合)
    [string]$StorageAccountName,

    [switch]$IsActiveFalse,

    # 既存コードを上書きする場合に指定
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$az = (Get-Command az -ErrorAction SilentlyContinue).Source
if (-not $az) {
    $fallback = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
    if (Test-Path $fallback) {
        $az = $fallback
    } else {
        throw "az CLI が見つかりません。インストールするか PATH に追加してください。"
    }
}

if (-not $StorageAccountName) {
    $rawAccounts = & $az storage account list -g $ResourceGroupName --query "[].name" -o tsv
    $accounts = @($rawAccounts | Where-Object { $_ -and $_.Trim() -ne '' })
    if ($accounts.Count -ne 1) {
        throw "リソースグループ '$ResourceGroupName' 内のストレージアカウントを一意に特定できません(見つかった数: $($accounts.Count))。-StorageAccountName を指定してください。"
    }
    $StorageAccountName = $accounts[0]
}

$accountKey = & $az storage account keys list -g $ResourceGroupName -n $StorageAccountName --query "[0].value" -o tsv

$isActive = if ($IsActiveFalse) { 'false' } else { 'true' }
$ifExists = if ($Force) { 'replace' } else { 'fail' }

& $az storage entity insert `
    --account-name $StorageAccountName `
    --account-key $accountKey `
    --table-name Families `
    --entity PartitionKey=FAMILY RowKey=$FamilyCode IsActive=$isActive "IsActive@odata.type=Edm.Boolean" `
    --if-exists $ifExists `
    -o table

if ($LASTEXITCODE -eq 0) {
    Write-Host "登録しました: PartitionKey=FAMILY, RowKey=$FamilyCode, IsActive=$isActive (storage account: $StorageAccountName)"
}
