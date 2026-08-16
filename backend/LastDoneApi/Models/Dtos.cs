namespace LastDoneApi.Models;

public record CreateItemRequest(string Text);

public record HistoryDto(string DoneDate, string UserName);

public record DailyItemDto(
    string Id,
    string Text,
    string CreatedDate,
    string CreatedBy,
    string UpdatedDate,
    string UpdatedBy,
    IReadOnlyList<HistoryDto> History);
