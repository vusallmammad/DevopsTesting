using System.Net;
using System.Text.Json;

var registry = ServiceRegistry.FromEnvironment();

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton(registry);
builder.Services.AddHttpClient("proxy", client => client.Timeout = TimeSpan.FromSeconds(30));
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.SerializerOptions.WriteIndented = true;
});
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy => policy.AllowAnyHeader().AllowAnyMethod().AllowAnyOrigin());
});

var app = builder.Build();
app.UseCors();

app.MapGet("/", (ServiceRegistry services) => Results.Ok(new
{
    name = "Game Website Practice API Gateway",
    routes = services.Routes.Select(route => new
    {
        route.Key,
        route.Name,
        route.BaseUrl,
        gatewayPrefix = $"/{route.Key}"
    })
}));

app.MapGet("/routes", (ServiceRegistry services) => Results.Ok(services.Routes));

app.MapGet("/health", async (IHttpClientFactory httpClientFactory, ServiceRegistry services, CancellationToken cancellationToken) =>
{
    var client = httpClientFactory.CreateClient("proxy");
    var checks = new List<ServiceHealth>();

    foreach (var route in services.Routes)
    {
        try
        {
            using var response = await client.GetAsync($"{route.BaseUrl}/health", cancellationToken);
            checks.Add(new ServiceHealth(
                route.Key,
                route.Name,
                response.IsSuccessStatusCode ? "Healthy" : "Unhealthy",
                (int)response.StatusCode));
        }
        catch (Exception ex)
        {
            checks.Add(new ServiceHealth(route.Key, route.Name, "Unreachable", null, ex.Message));
        }
    }

    return Results.Ok(new
    {
        status = checks.All(check => check.Status == "Healthy") ? "Healthy" : "Degraded",
        checkedAt = DateTimeOffset.UtcNow,
        services = checks
    });
});

app.MapMethods("/{serviceKey}/{**path}", new[] { "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS" },
    async (string serviceKey, string? path, HttpContext context, IHttpClientFactory httpClientFactory, ServiceRegistry services) =>
    {
        if (!services.TryResolve(serviceKey, out var route))
        {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
            await context.Response.WriteAsJsonAsync(new
            {
                message = $"Unknown service '{serviceKey}'.",
                availableServices = services.Routes.Select(item => item.Key)
            });
            return;
        }

        var client = httpClientFactory.CreateClient("proxy");
        var target = BuildTargetUri(route.BaseUrl, path, context.Request.QueryString);
        using var proxyRequest = CreateProxyRequest(context, target);
        using var proxyResponse = await client.SendAsync(
            proxyRequest,
            HttpCompletionOption.ResponseHeadersRead,
            context.RequestAborted);

        await CopyProxyResponse(context, proxyResponse);
    });

app.Run();

static Uri BuildTargetUri(string baseUrl, string? path, QueryString queryString)
{
    var trimmedBase = baseUrl.TrimEnd('/');
    var trimmedPath = string.IsNullOrWhiteSpace(path) ? string.Empty : "/" + path.TrimStart('/');
    return new Uri(trimmedBase + trimmedPath + queryString);
}

static HttpRequestMessage CreateProxyRequest(HttpContext context, Uri target)
{
    var request = context.Request;
    var proxyRequest = new HttpRequestMessage(new HttpMethod(request.Method), target);

    if (request.ContentLength > 0 || request.Headers.TransferEncoding.Count > 0)
    {
        proxyRequest.Content = new StreamContent(request.Body);
    }

    foreach (var header in request.Headers)
    {
        if (header.Key.Equals("Host", StringComparison.OrdinalIgnoreCase))
        {
            continue;
        }

        if (!proxyRequest.Headers.TryAddWithoutValidation(header.Key, header.Value.ToArray()))
        {
            proxyRequest.Content?.Headers.TryAddWithoutValidation(header.Key, header.Value.ToArray());
        }
    }

    return proxyRequest;
}

static async Task CopyProxyResponse(HttpContext context, HttpResponseMessage proxyResponse)
{
    context.Response.StatusCode = (int)proxyResponse.StatusCode;

    foreach (var header in proxyResponse.Headers)
    {
        context.Response.Headers[header.Key] = header.Value.ToArray();
    }

    foreach (var header in proxyResponse.Content.Headers)
    {
        context.Response.Headers[header.Key] = header.Value.ToArray();
    }

    context.Response.Headers.Remove("transfer-encoding");

    if (context.Request.Method.Equals("HEAD", StringComparison.OrdinalIgnoreCase) ||
        proxyResponse.StatusCode == HttpStatusCode.NoContent)
    {
        return;
    }

    await proxyResponse.Content.CopyToAsync(context.Response.Body);
}

public sealed record ServiceRoute(string Key, string Name, string BaseUrl);

public sealed record ServiceHealth(string Key, string Name, string Status, int? StatusCode = null, string? Error = null);

public sealed class ServiceRegistry
{
    private readonly Dictionary<string, ServiceRoute> _routes;

    private ServiceRegistry(IEnumerable<ServiceRoute> routes)
    {
        _routes = routes.ToDictionary(route => route.Key, route => route, StringComparer.OrdinalIgnoreCase);
    }

    public IReadOnlyCollection<ServiceRoute> Routes => _routes.Values.OrderBy(route => route.Key).ToArray();

    public bool TryResolve(string key, out ServiceRoute route)
    {
        return _routes.TryGetValue(key, out route!);
    }

    public static ServiceRegistry FromEnvironment()
    {
        return new ServiceRegistry(new[]
        {
            New("security", "Security API", "SECURITY_API_URL", "http://security-api:8080"),
            New("profile", "Profile API", "PROFILE_API_URL", "http://profile-api:8080"),
            New("game", "Game API", "GAME_API_URL", "http://game-api:8080"),
            New("store", "Store API", "STORE_API_URL", "http://store-api:8080"),
            New("notification", "Notification API", "NOTIFICATION_API_URL", "http://notification-api:8080"),
            New("tournaments", "Tournaments API", "TOURNAMENTS_API_URL", "http://tournaments-api:8080"),
            New("matchup", "Matchup API", "MATCHUP_API_URL", "http://matchup-api:8080"),
            New("teams", "Teams API", "TEAMS_API_URL", "http://teams-api:8080")
        });
    }

    private static ServiceRoute New(string key, string name, string environmentName, string fallback)
    {
        return new ServiceRoute(key, name, Environment.GetEnvironmentVariable(environmentName) ?? fallback);
    }
}
