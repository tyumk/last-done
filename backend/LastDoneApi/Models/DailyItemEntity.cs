using Azure;
using Azure.Data.Tables;

namespace LastDoneApi.Models;

public class DailyItemEntity : ITableEntity
{
    public string PartitionKey { get; set; } = string.Empty;
    public string RowKey { get; set; } = string.Empty;
    public DateTimeOffset? Timestamp { get; set; }
    public ETag ETag { get; set; }

    public string Text { get; set; } = string.Empty;
    public string CreatedBy { get; set; } = string.Empty;
    public string CreatedDate { get; set; } = string.Empty;
    public string UpdatedBy { get; set; } = string.Empty;
    public string UpdatedDate { get; set; } = string.Empty;
}
