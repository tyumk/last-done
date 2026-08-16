using Azure.Data.Tables;
using Microsoft.Extensions.Configuration;

namespace LastDoneApi.Services;

public class TableStorageService
{
    private readonly IConfiguration _configuration;

    public TableStorageService(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public TableClient GetClient(string settingName, bool ensureCreated = true)
    {
        var connection = _configuration["LastDoneStorageConnection"]
            ?? _configuration["AzureWebJobsStorage"]
            ?? throw new InvalidOperationException("Storage connection string is not configured.");

        var tableName = _configuration[settingName]
            ?? throw new InvalidOperationException($"Table setting '{settingName}' is not configured.");

        var client = new TableClient(connection, tableName);
        if (ensureCreated)
        {
            client.CreateIfNotExists();
        }

        return client;
    }
}
