using Azure;
using Azure.Data.Tables;
using LastDoneApi.Models;
using Microsoft.Extensions.Configuration;

namespace LastDoneApi.Services;

public class DailyItemService
{
    private readonly TableStorageService _tableStorageService;
    private readonly TimeZoneInfo _timeZone;

    public DailyItemService(TableStorageService tableStorageService, IConfiguration configuration)
    {
        _tableStorageService = tableStorageService;
        var timeZoneId = configuration["TimeZoneId"] ?? "Asia/Tokyo";
        _timeZone = TimeZoneInfo.FindSystemTimeZoneById(timeZoneId);
    }

    public async Task<DailyItemDto> CreateAsync(string familyCode, string text, string userName)
    {
        var nowDate = Today();
        var id = Guid.NewGuid().ToString("N");
        var item = new DailyItemEntity
        {
            PartitionKey = familyCode,
            RowKey = id,
            Text = text,
            CreatedBy = userName,
            CreatedDate = nowDate,
            UpdatedBy = userName,
            UpdatedDate = nowDate
        };

        var itemTable = _tableStorageService.GetClient("TableNameDailyItems");
        await itemTable.AddEntityAsync(item);

        await AddHistoryAsync(familyCode, id, nowDate, userName);
        var history = await GetHistoryAsync(familyCode, id);
        return ToDto(item, history);
    }

    public async Task<bool> RefreshAsync(string familyCode, string itemId, string userName)
    {
        var itemTable = _tableStorageService.GetClient("TableNameDailyItems");

        try
        {
            var current = await itemTable.GetEntityAsync<DailyItemEntity>(familyCode, itemId);
            var entity = current.Value;
            entity.UpdatedBy = userName;
            entity.UpdatedDate = Today();

            await itemTable.UpdateEntityAsync(entity, current.Value.ETag, TableUpdateMode.Replace);
            await AddHistoryAsync(familyCode, itemId, entity.UpdatedDate, userName);
            return true;
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            return false;
        }
    }

    public async Task<IReadOnlyList<DailyItemDto>> GetByFamilyAsync(string familyCode)
    {
        var itemTable = _tableStorageService.GetClient("TableNameDailyItems");
        var items = new List<DailyItemEntity>();

        await foreach (var item in itemTable.QueryAsync<DailyItemEntity>(x => x.PartitionKey == familyCode))
        {
            items.Add(item);
        }

        var sorted = items
            .OrderByDescending(x => x.UpdatedDate)
            .ThenBy(x => x.RowKey)
            .ToList();

        var result = new List<DailyItemDto>(sorted.Count);
        foreach (var item in sorted)
        {
            var history = await GetHistoryAsync(familyCode, item.RowKey);
            result.Add(ToDto(item, history));
        }

        return result;
    }

    private async Task AddHistoryAsync(string familyCode, string itemId, string doneDate, string userName)
    {
        var historyTable = _tableStorageService.GetClient("TableNameDailyItemHistory");
        var history = new DailyItemHistoryEntity
        {
            PartitionKey = HistoryPartition(familyCode, itemId),
            RowKey = $"{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}_{Guid.NewGuid():N}",
            DoneDate = doneDate,
            UserName = userName
        };

        await historyTable.AddEntityAsync(history);
    }

    private async Task<IReadOnlyList<HistoryDto>> GetHistoryAsync(string familyCode, string itemId)
    {
        var historyTable = _tableStorageService.GetClient("TableNameDailyItemHistory");
        var partition = HistoryPartition(familyCode, itemId);
        var list = new List<HistoryDto>();

        await foreach (var history in historyTable.QueryAsync<DailyItemHistoryEntity>(x => x.PartitionKey == partition))
        {
            list.Add(new HistoryDto(history.DoneDate, history.UserName));
        }

        return list
            .OrderByDescending(x => x.DoneDate)
            .ToList();
    }

    private static string HistoryPartition(string familyCode, string itemId) => $"{familyCode}_{itemId}";

    private string Today()
    {
        var now = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, _timeZone);
        return now.ToString("yyyy-MM-dd");
    }

    private static DailyItemDto ToDto(DailyItemEntity e, IReadOnlyList<HistoryDto> history)
    {
        return new DailyItemDto(
            e.RowKey,
            e.Text,
            e.CreatedDate,
            e.CreatedBy,
            e.UpdatedDate,
            e.UpdatedBy,
            history);
    }
}
