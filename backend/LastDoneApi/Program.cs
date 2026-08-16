using LastDoneApi.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureServices(services =>
    {
        services.AddSingleton<TableStorageService>();
        services.AddSingleton<FamilyAuthService>();
        services.AddSingleton<DailyItemService>();
    })
    .Build();

host.Run();
