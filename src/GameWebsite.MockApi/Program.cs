using System.Collections.Concurrent;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Nodes;

var serviceInfo = ServiceInfo.FromEnvironment();

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton(serviceInfo);
builder.Services.AddSingleton(new PracticeStore(SeedData.For(serviceInfo.Key)));
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

app.MapGet("/", (ServiceInfo service, PracticeStore store) => Results.Ok(new
{
    service = service.Title,
    service.Key,
    service.Database,
    resources = store.Resources,
    endpoints = new[]
    {
        "/health",
        "/metadata",
        "/api/catalog",
        "/api/{resource}",
        "/api/{resource}/{id}"
    }
}));

app.MapGet("/health", async (bool? deep, ServiceInfo service) =>
{
    var dbReachable = deep == true && service.Database is not null
        ? await TcpProbe.CanConnectAsync(service.Database.Host, service.Database.Port)
        : (bool?)null;

    return Results.Ok(new
    {
        status = "Healthy",
        service = service.Key,
        checkedAt = DateTimeOffset.UtcNow,
        database = service.Database,
        databaseReachable = dbReachable
    });
});

app.MapGet("/metadata", (ServiceInfo service, PracticeStore store) => Results.Ok(new
{
    service,
    store.Resources,
    description = "Practice mock service. Data is in-memory; database containers provide schema practice."
}));

app.MapGet("/api/catalog", (ServiceInfo service, PracticeStore store) => Results.Ok(new
{
    service = service.Key,
    store.Resources
}));

app.MapGet("/api/{resource}", (string resource, PracticeStore store) =>
{
    return store.TryList(resource, out var items)
        ? Results.Ok(items)
        : ResourceNotFound(resource, store);
});

app.MapGet("/api/{resource}/{id}", (string resource, string id, PracticeStore store) =>
{
    return store.TryGet(resource, id, out var item)
        ? Results.Ok(item)
        : Results.NotFound(new { message = $"No '{resource}' item with id '{id}'." });
});

app.MapPost("/api/{resource}", async (string resource, HttpRequest request, PracticeStore store) =>
{
    if (!store.HasResource(resource))
    {
        return ResourceNotFound(resource, store);
    }

    var item = await request.ReadFromJsonAsync<JsonObject>() ?? new JsonObject();
    var created = store.Add(resource, item);
    return Results.Created($"/api/{resource}/{created["id"]}", created);
});

app.MapPut("/api/{resource}/{id}", async (string resource, string id, HttpRequest request, PracticeStore store) =>
{
    if (!store.HasResource(resource))
    {
        return ResourceNotFound(resource, store);
    }

    var item = await request.ReadFromJsonAsync<JsonObject>() ?? new JsonObject();
    return store.TryUpdate(resource, id, item, out var updated)
        ? Results.Ok(updated)
        : Results.NotFound(new { message = $"No '{resource}' item with id '{id}'." });
});

app.MapDelete("/api/{resource}/{id}", (string resource, string id, PracticeStore store) =>
{
    if (!store.HasResource(resource))
    {
        return ResourceNotFound(resource, store);
    }

    return store.TryDelete(resource, id)
        ? Results.NoContent()
        : Results.NotFound(new { message = $"No '{resource}' item with id '{id}'." });
});

MapServiceSpecificEndpoints(app, serviceInfo.Key);

app.Run();

static IResult ResourceNotFound(string resource, PracticeStore store)
{
    return Results.NotFound(new
    {
        message = $"Resource '{resource}' is not exposed by this service.",
        availableResources = store.Resources
    });
}

static void MapServiceSpecificEndpoints(WebApplication app, string serviceKey)
{
    switch (serviceKey)
    {
        case "security":
            app.MapPost("/api/auth/login", async (HttpRequest request) =>
            {
                var login = await request.ReadFromJsonAsync<LoginRequest>() ?? new LoginRequest("demo", "demo");
                return Results.Ok(new
                {
                    accessToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray()),
                    tokenType = "Bearer",
                    expiresIn = 3600,
                    user = new { id = "usr-001", login.UserName, roles = new[] { "player", "admin" } }
                });
            });
            app.MapGet("/api/auth/me", () => Results.Ok(new
            {
                id = "usr-001",
                userName = "demo",
                roles = new[] { "player", "admin" }
            }));
            break;

        case "profile":
            app.MapGet("/api/profiles/by-user/{userId}", (string userId, PracticeStore store) =>
            {
                store.TryList("profiles", out var profiles);
                var match = profiles.FirstOrDefault(profile => profile["userId"]?.GetValue<string>() == userId);
                return match is null ? Results.NotFound() : Results.Ok(match);
            });
            break;

        case "game":
            app.MapPost("/api/games/{gameId}/sessions", (string gameId, PracticeStore store) =>
            {
                var session = new JsonObject
                {
                    ["gameId"] = gameId,
                    ["status"] = "Created",
                    ["maxPlayers"] = 8
                };
                var created = store.Add("sessions", session);
                return Results.Created($"/api/sessions/{created["id"]}", created);
            });
            break;

        case "store":
            app.MapPost("/api/orders/checkout", async (HttpRequest request, PracticeStore store) =>
            {
                var checkout = await request.ReadFromJsonAsync<JsonObject>() ?? new JsonObject();
                checkout["status"] = "Paid";
                checkout["total"] ??= 19.99;
                return Results.Created("/api/purchases", store.Add("purchases", checkout));
            });
            break;

        case "notification":
            app.MapPost("/api/notifications/send", async (HttpRequest request, PracticeStore store) =>
            {
                var notification = await request.ReadFromJsonAsync<JsonObject>() ?? new JsonObject();
                notification["status"] = "Queued";
                notification["queuedAt"] = DateTimeOffset.UtcNow;
                var created = store.Add("notifications", notification);
                return Results.Accepted($"/api/notifications/{created["id"]}", created);
            });
            break;

        case "tournaments":
            app.MapPost("/api/tournaments/{tournamentId}/registrations", (string tournamentId, PracticeStore store) =>
            {
                var registration = new JsonObject
                {
                    ["tournamentId"] = tournamentId,
                    ["teamId"] = "team-001",
                    ["status"] = "Registered"
                };
                var created = store.Add("registrations", registration);
                return Results.Created($"/api/registrations/{created["id"]}", created);
            });
            break;

        case "matchup":
            app.MapPost("/api/matchups/queue", async (HttpRequest request, PracticeStore store) =>
            {
                var queueItem = await request.ReadFromJsonAsync<JsonObject>() ?? new JsonObject();
                queueItem["status"] = "Searching";
                queueItem["estimatedWaitSeconds"] = 42;
                var created = store.Add("queues", queueItem);
                return Results.Accepted($"/api/queues/{created["id"]}", created);
            });
            break;

        case "teams":
            app.MapPost("/api/teams/{teamId}/members", async (string teamId, HttpRequest request, PracticeStore store) =>
            {
                var member = await request.ReadFromJsonAsync<JsonObject>() ?? new JsonObject();
                member["teamId"] = teamId;
                member["role"] ??= "Member";
                var created = store.Add("members", member);
                return Results.Created($"/api/members/{created["id"]}", created);
            });
            break;
    }
}

public sealed record LoginRequest(string UserName, string Password);

public sealed record DatabaseInfo(string Kind, string Host, int Port, string Name, string User);

public sealed record ServiceInfo(string Key, string Title, DatabaseInfo? Database)
{
    public static ServiceInfo FromEnvironment()
    {
        var key = Env("SERVICE_KEY", "practice").Trim().ToLowerInvariant();
        var title = Env("SERVICE_TITLE", $"{ToTitle(key)} API");
        var dbKind = Env("DB_KIND", string.Empty);
        DatabaseInfo? database = null;

        if (!string.IsNullOrWhiteSpace(dbKind))
        {
            database = new DatabaseInfo(
                dbKind,
                Env("DB_HOST", $"{key}-db"),
                int.TryParse(Env("DB_PORT", "5432"), out var port) ? port : 5432,
                Env("DB_NAME", key.Replace("-", "_")),
                Env("DB_USER", "game"));
        }

        return new ServiceInfo(key, title, database);
    }

    private static string Env(string name, string fallback)
    {
        return Environment.GetEnvironmentVariable(name) ?? fallback;
    }

    private static string ToTitle(string value)
    {
        return string.Join(' ', value.Split('-', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => char.ToUpperInvariant(part[0]) + part[1..]));
    }
}

public sealed class PracticeStore
{
    private readonly ConcurrentDictionary<string, List<JsonObject>> _data;

    public PracticeStore(Dictionary<string, List<JsonObject>> seed)
    {
        _data = new ConcurrentDictionary<string, List<JsonObject>>(
            seed.ToDictionary(pair => Normalize(pair.Key), pair => pair.Value));
    }

    public IReadOnlyList<string> Resources => _data.Keys.OrderBy(key => key).ToArray();

    public bool HasResource(string resource)
    {
        return _data.ContainsKey(Normalize(resource));
    }

    public bool TryList(string resource, out IReadOnlyList<JsonObject> items)
    {
        if (!_data.TryGetValue(Normalize(resource), out var list))
        {
            items = Array.Empty<JsonObject>();
            return false;
        }

        lock (list)
        {
            items = list.Select(Clone).ToArray();
        }

        return true;
    }

    public bool TryGet(string resource, string id, out JsonObject? item)
    {
        item = null;
        if (!_data.TryGetValue(Normalize(resource), out var list))
        {
            return false;
        }

        lock (list)
        {
            var match = list.FirstOrDefault(value => IdOf(value) == id);
            item = match is null ? null : Clone(match);
        }

        return item is not null;
    }

    public JsonObject Add(string resource, JsonObject item)
    {
        var normalized = Normalize(resource);
        var list = _data.GetOrAdd(normalized, _ => new List<JsonObject>());
        var copy = Clone(item);
        copy["id"] = copy["id"]?.GetValue<string>() ?? NewId(normalized);
        copy["createdAt"] = copy["createdAt"]?.GetValue<string>() ?? DateTimeOffset.UtcNow.ToString("O");

        lock (list)
        {
            list.Add(copy);
        }

        return Clone(copy);
    }

    public bool TryUpdate(string resource, string id, JsonObject item, out JsonObject? updated)
    {
        updated = null;
        if (!_data.TryGetValue(Normalize(resource), out var list))
        {
            return false;
        }

        lock (list)
        {
            var index = list.FindIndex(value => IdOf(value) == id);
            if (index < 0)
            {
                return false;
            }

            var copy = Clone(item);
            copy["id"] = id;
            copy["updatedAt"] = DateTimeOffset.UtcNow.ToString("O");
            list[index] = copy;
            updated = Clone(copy);
            return true;
        }
    }

    public bool TryDelete(string resource, string id)
    {
        if (!_data.TryGetValue(Normalize(resource), out var list))
        {
            return false;
        }

        lock (list)
        {
            var index = list.FindIndex(value => IdOf(value) == id);
            if (index < 0)
            {
                return false;
            }

            list.RemoveAt(index);
            return true;
        }
    }

    private static JsonObject Clone(JsonObject source)
    {
        return JsonNode.Parse(source.ToJsonString())!.AsObject();
    }

    private static string? IdOf(JsonObject item)
    {
        return item["id"]?.GetValue<string>();
    }

    private static string Normalize(string resource)
    {
        return resource.Trim().ToLowerInvariant();
    }

    private static string NewId(string resource)
    {
        var compact = Guid.NewGuid().ToString("N")[..8];
        return $"{resource}-{compact}";
    }
}

public static class SeedData
{
    public static Dictionary<string, List<JsonObject>> For(string serviceKey)
    {
        return serviceKey switch
        {
            "security" => New(new
            {
                users = new object[]
                {
                    new { id = "usr-001", userName = "demo", email = "demo@example.test", status = "Active" },
                    new { id = "usr-002", userName = "captain", email = "captain@example.test", status = "Locked" }
                },
                roles = new object[]
                {
                    new { id = "role-admin", name = "Admin" },
                    new { id = "role-player", name = "Player" }
                },
                audit_events = new object[]
                {
                    new { id = "audit-001", userId = "usr-001", action = "LoginSucceeded", occurredAt = "2026-04-20T09:00:00Z" }
                }
            }),
            "profile" => New(new
            {
                profiles = new object[]
                {
                    new { id = "profile-001", userId = "usr-001", displayName = "Nova", level = 18, region = "EU" },
                    new { id = "profile-002", userId = "usr-002", displayName = "Vector", level = 31, region = "NA" }
                },
                achievements = new object[]
                {
                    new { id = "ach-001", profileId = "profile-001", code = "FIRST_WIN", unlockedAt = "2026-04-19T14:10:00Z" }
                },
                settings = new object[]
                {
                    new { id = "settings-001", profileId = "profile-001", notifications = true, language = "en" }
                }
            }),
            "game" => New(new
            {
                games = new object[]
                {
                    new { id = "game-001", title = "Arena Rush", genre = "Action", status = "Published" },
                    new { id = "game-002", title = "Puzzle Forge", genre = "Puzzle", status = "Beta" }
                },
                sessions = new object[]
                {
                    new { id = "session-001", gameId = "game-001", status = "Open", maxPlayers = 8 }
                },
                leaderboards = new object[]
                {
                    new { id = "leaderboard-001", gameId = "game-001", profileId = "profile-001", score = 12400 }
                }
            }),
            "store" => New(new
            {
                products = new object[]
                {
                    new { id = "product-001", sku = "coins-1000", name = "1000 Coins", price = 9.99, currency = "USD" },
                    new { id = "product-002", sku = "skin-neon", name = "Neon Skin", price = 4.99, currency = "USD" }
                },
                carts = new object[]
                {
                    new { id = "cart-001", userId = "usr-001", status = "Open" }
                },
                purchases = new object[]
                {
                    new { id = "purchase-001", userId = "usr-001", productId = "product-001", status = "Paid" }
                }
            }),
            "notification" => New(new
            {
                notifications = new object[]
                {
                    new { id = "notification-001", userId = "usr-001", channel = "Email", status = "Sent", subject = "Welcome" }
                },
                templates = new object[]
                {
                    new { id = "template-001", code = "WELCOME", channel = "Email" }
                },
                subscriptions = new object[]
                {
                    new { id = "subscription-001", userId = "usr-001", channel = "Push", enabled = true }
                }
            }),
            "tournaments" => New(new
            {
                tournaments = new object[]
                {
                    new { id = "tournament-001", name = "Spring Cup", status = "RegistrationOpen", maxTeams = 16 }
                },
                registrations = new object[]
                {
                    new { id = "registration-001", tournamentId = "tournament-001", teamId = "team-001", status = "Registered" }
                },
                brackets = new object[]
                {
                    new { id = "bracket-001", tournamentId = "tournament-001", round = 1, status = "Pending" }
                }
            }),
            "matchup" => New(new
            {
                queues = new object[]
                {
                    new { id = "queue-001", profileId = "profile-001", rating = 1510, status = "Searching" }
                },
                match_requests = new object[]
                {
                    new { id = "request-001", profileId = "profile-001", gameId = "game-001", status = "Queued" }
                },
                matches = new object[]
                {
                    new { id = "match-001", gameId = "game-001", status = "Ready", blueTeamId = "team-001", redTeamId = "team-002" }
                }
            }),
            "teams" => New(new
            {
                teams = new object[]
                {
                    new { id = "team-001", name = "Northwind", ownerUserId = "usr-001", status = "Active" },
                    new { id = "team-002", name = "Contoso", ownerUserId = "usr-002", status = "Active" }
                },
                members = new object[]
                {
                    new { id = "member-001", teamId = "team-001", userId = "usr-001", role = "Captain" }
                },
                invitations = new object[]
                {
                    new { id = "invite-001", teamId = "team-001", email = "new-player@example.test", status = "Pending" }
                }
            }),
            _ => New(new
            {
                items = new object[]
                {
                    new { id = "item-001", name = "Practice item", status = "Ready" }
                }
            })
        };
    }

    private static Dictionary<string, List<JsonObject>> New(object resources)
    {
        var node = JsonSerializer.SerializeToNode(resources)!.AsObject();
        return node.ToDictionary(
            pair => pair.Key.Replace('_', '-'),
            pair => pair.Value!.AsArray().Select(value => value!.AsObject()).ToList());
    }
}

public static class TcpProbe
{
    public static async Task<bool> CanConnectAsync(string host, int port)
    {
        try
        {
            using var client = new TcpClient();
            var connectTask = client.ConnectAsync(host, port);
            var timeoutTask = Task.Delay(TimeSpan.FromSeconds(2));
            return await Task.WhenAny(connectTask, timeoutTask) == connectTask && client.Connected;
        }
        catch
        {
            return false;
        }
    }
}
