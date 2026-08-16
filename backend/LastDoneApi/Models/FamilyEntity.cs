using Azure;
using Azure.Data.Tables;

namespace LastDoneApi.Models;

public class FamilyEntity : ITableEntity
{
    public string PartitionKey { get; set; } = "FAMILY";
    public string RowKey { get; set; } = string.Empty;
    public DateTimeOffset? Timestamp { get; set; }
    public ETag ETag { get; set; }

    public bool IsActive { get; set; } = true;
}
