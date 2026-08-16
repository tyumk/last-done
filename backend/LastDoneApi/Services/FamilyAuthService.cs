using Azure;
using LastDoneApi.Models;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Configuration;

namespace LastDoneApi.Services;

public class FamilyAuthService
{
    private readonly TableStorageService _tableStorageService;
    private readonly IConfiguration _configuration;

    public FamilyAuthService(TableStorageService tableStorageService, IConfiguration configuration)
    {
        _tableStorageService = tableStorageService;
        _configuration = configuration;
    }

    public async Task<string?> ValidateAndGetFamilyCodeAsync(HttpRequestData request)
    {
        var headerName = _configuration["FamilyCodeHeaderName"] ?? "X-Family-Code";
        if (!request.Headers.TryGetValues(headerName, out var values))
        {
            return null;
        }

        var code = values.FirstOrDefault()?.Trim();
        if (string.IsNullOrWhiteSpace(code))
        {
            return null;
        }

        var families = _tableStorageService.GetClient("TableNameFamilies");
        try
        {
            var family = await families.GetEntityAsync<FamilyEntity>("FAMILY", code);
            if (family.Value.IsActive)
            {
                return code;
            }

            return null;
        }
        catch (RequestFailedException ex) when (ex.Status == 404)
        {
            return null;
        }
    }

    public string? GetUserNameFromHeader(HttpRequestData request)
    {
        var headerName = _configuration["UserNameHeaderName"] ?? "X-User-Name";
        if (!request.Headers.TryGetValues(headerName, out var values))
        {
            return null;
        }

        var userName = values.FirstOrDefault()?.Trim();
        return string.IsNullOrWhiteSpace(userName) ? null : userName;
    }
}
