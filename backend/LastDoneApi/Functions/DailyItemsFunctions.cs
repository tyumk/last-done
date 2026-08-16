using System.Net;
using System.Text.Json;
using LastDoneApi.Models;
using LastDoneApi.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace LastDoneApi.Functions;

public class DailyItemsFunctions
{
    private readonly FamilyAuthService _familyAuthService;
    private readonly DailyItemService _dailyItemService;

    public DailyItemsFunctions(FamilyAuthService familyAuthService, DailyItemService dailyItemService)
    {
        _familyAuthService = familyAuthService;
        _dailyItemService = dailyItemService;
    }

    [Function("GetDailyItems")]
    public async Task<HttpResponseData> GetDailyItems(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "daily-items")] HttpRequestData req)
    {
        var familyCode = await _familyAuthService.ValidateAndGetFamilyCodeAsync(req);
        if (familyCode is null)
        {
            return await Json(req, HttpStatusCode.Unauthorized, new { message = "Invalid family code." });
        }

        var items = await _dailyItemService.GetByFamilyAsync(familyCode);
        return await Json(req, HttpStatusCode.OK, items);
    }

    [Function("CreateDailyItem")]
    public async Task<HttpResponseData> CreateDailyItem(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "daily-items")] HttpRequestData req)
    {
        var familyCode = await _familyAuthService.ValidateAndGetFamilyCodeAsync(req);
        if (familyCode is null)
        {
            return await Json(req, HttpStatusCode.Unauthorized, new { message = "Invalid family code." });
        }

        var userName = _familyAuthService.GetUserNameFromHeader(req);
        if (userName is null)
        {
            return await Json(req, HttpStatusCode.BadRequest, new { message = "User header is required." });
        }

        var body = await JsonSerializer.DeserializeAsync<CreateItemRequest>(req.Body, JsonOptions());
        if (body is null || string.IsNullOrWhiteSpace(body.Text))
        {
            return await Json(req, HttpStatusCode.BadRequest, new { message = "Text is required." });
        }

        var item = await _dailyItemService.CreateAsync(familyCode, body.Text.Trim(), userName);
        return await Json(req, HttpStatusCode.Created, item);
    }

    [Function("RefreshDailyItem")]
    public async Task<HttpResponseData> RefreshDailyItem(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "daily-items/{id}/refresh")] HttpRequestData req,
        string id)
    {
        var familyCode = await _familyAuthService.ValidateAndGetFamilyCodeAsync(req);
        if (familyCode is null)
        {
            return await Json(req, HttpStatusCode.Unauthorized, new { message = "Invalid family code." });
        }

        var userName = _familyAuthService.GetUserNameFromHeader(req);
        if (userName is null)
        {
            return await Json(req, HttpStatusCode.BadRequest, new { message = "User header is required." });
        }

        var updated = await _dailyItemService.RefreshAsync(familyCode, id, userName);
        if (!updated)
        {
            return await Json(req, HttpStatusCode.NotFound, new { message = "Item not found." });
        }

        return await Json(req, HttpStatusCode.OK, new { message = "Updated." });
    }

    private static async Task<HttpResponseData> Json(HttpRequestData req, HttpStatusCode status, object payload)
    {
        var res = req.CreateResponse(status);
        res.Headers.Add("Content-Type", "application/json; charset=utf-8");
        await res.WriteStringAsync(JsonSerializer.Serialize(payload, JsonOptions()));
        return res;
    }

    private static JsonSerializerOptions JsonOptions()
    {
        return new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        };
    }
}
