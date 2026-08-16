using Azure;
using Azure.Data.Tables;

namespace LastDoneApi.Models;

public class DailyItemHistoryEntity : ITableEntity
{
    public string PartitionKey { get; set; } = string.Empty;
    public string RowKey { get; set; } = string.Empty;
    public DateTimeOffset? Timestamp { get; set; }
    public ETag ETag { get; set; }

    public string UserName { get; set; } = string.Empty;
    public string DoneDate { get; set; } = string.Empty;
}
