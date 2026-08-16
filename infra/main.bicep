targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for resource names')
@minLength(3)
@maxLength(11)
param namePrefix string

@description('Family code header name')
param familyCodeHeaderName string = 'X-Family-Code'

@description('User name header name')
param userNameHeaderName string = 'X-User-Name'

@description('Time zone used by the API')
param timeZoneId string = 'Asia/Tokyo'

var storageName = toLower('${namePrefix}std${uniqueString(resourceGroup().id)}')
var functionName = toLower('${namePrefix}-func-${uniqueString(resourceGroup().id)}')
var appInsightsName = '${namePrefix}-appi'
var planName = '${namePrefix}-plan-flex'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource dailyItemsTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  name: '${storage.name}/default/DailyItems'
}

resource historyTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  name: '${storage.name}/default/DailyItemHistory'
}

resource familiesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  name: '${storage.name}/default/Families'
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource flexPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: flexPlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'LastDoneStorageConnection'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'TableNameFamilies'
          value: 'Families'
        }
        {
          name: 'TableNameDailyItems'
          value: 'DailyItems'
        }
        {
          name: 'TableNameDailyItemHistory'
          value: 'DailyItemHistory'
        }
        {
          name: 'FamilyCodeHeaderName'
          value: familyCodeHeaderName
        }
        {
          name: 'UserNameHeaderName'
          value: userNameHeaderName
        }
        {
          name: 'TimeZoneId'
          value: timeZoneId
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      linuxFxVersion: 'DOTNET-ISOLATED|8.0'
    }
  }
}

output functionAppName string = functionApp.name
output functionBaseUrl string = 'https://${functionApp.properties.defaultHostName}/api'
output storageAccountName string = storage.name
