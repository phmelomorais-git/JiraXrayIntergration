using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using Microsoft.AspNetCore.Http;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Configure OpenAPI (Swagger) for the API
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// In-memory repository for snowparks
var snowparkStore = new ConcurrentDictionary<Guid, SnowparkModel>();
// Seed with one item
var seedId = Guid.NewGuid();
snowparkStore[seedId] = new SnowparkModel(seedId, "Alpine Snowpark", "Valley Ridge", true, -4, 120);
builder.Services.AddSingleton(snowparkStore);

var app = builder.Build();

// Centralized JSON error handling middleware
app.Use(async (context, next) =>
{
    try
    {
        await next();

        // If downstream set an error status code but didn't write a body, return a JSON error
        if (!context.Response.HasStarted && context.Response.StatusCode >= 400 && context.Response.ContentLength == null)
        {
            var err = new ErrorResponse($"Request failed with status code {context.Response.StatusCode}", $"HTTP{context.Response.StatusCode}");
            context.Response.ContentType = "application/json";
            await context.Response.WriteAsJsonAsync(err);
        }
    }
    catch (Exception ex)
    {
        // Try to log the exception if a logger is available
        try
        {
            var logger = context.RequestServices.GetService(typeof(Microsoft.Extensions.Logging.ILogger<Program>)) as Microsoft.Extensions.Logging.ILogger;
            logger?.LogError(ex, "Unhandled exception while processing request {Method} {Path}", context.Request.Method, context.Request.Path);
        }
        catch
        {
            // ignore logging errors
        }

        if (!context.Response.HasStarted)
        {
            context.Response.Clear();
            context.Response.StatusCode = StatusCodes.Status500InternalServerError;
            context.Response.ContentType = "application/json";
            var err = new ErrorResponse("An unexpected error occurred.", "UnhandledException");
            await context.Response.WriteAsJsonAsync(err);
        }
        else
        {
            throw; // can't modify response, rethrow
        }
    }
});


// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}
// Removed app.UseHttpsRedirection() to allow HTTP traffic.

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

app.MapGet("/weatherforecast", () =>
{
    var forecast =  Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast
        (
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20, 55),
            summaries[Random.Shared.Next(summaries.Length)]
        ))
        .ToArray();
    return forecast;
})
.WithName("GetWeatherForecast");

// CRUD endpoints for snowparks (in-memory)
app.MapGet("/snowparks", (ConcurrentDictionary<Guid, SnowparkModel> store) =>
{
    return Results.Ok(store.Values);
})
.WithName("GetSnowparks");

app.MapGet("/snowparks/{id}", (Guid id, ConcurrentDictionary<Guid, SnowparkModel> store) =>
{
    return store.TryGetValue(id, out var model)
        ? Results.Ok(model)
        : Results.NotFound(new ErrorResponse($"Snowpark with id '{id}' not found.", "SnowparkNotFound"));
})
.WithName("GetSnowparkById");

app.MapPost("/snowparks", (SnowparkCreateRequest req, ConcurrentDictionary<Guid, SnowparkModel> store, HttpContext http) =>
{
    // Basic input validation
    if (string.IsNullOrWhiteSpace(req?.Name) || string.IsNullOrWhiteSpace(req?.Location))
    {
        http.Response.StatusCode = StatusCodes.Status400BadRequest;
        return Results.Json(new ErrorResponse("Name and Location are required.", "InvalidInput"));
    }
    var id = Guid.NewGuid();
    var model = new SnowparkModel(id, req.Name, req.Location, req.IsOpen ?? false, req.TemperatureC ?? 0, req.SnowDepthCm ?? 0);
    if (!store.TryAdd(id, model))
    {
        http.Response.StatusCode = StatusCodes.Status500InternalServerError;
        return Results.Json(new ErrorResponse("Failed to create snowpark.", "CreateFailed"));
    }

    var uri = $"/snowparks/{id}";
    return Results.Created(uri, model);
})
.WithName("CreateSnowpark");

app.MapPut("/snowparks/{id}", (Guid id, SnowparkUpdateRequest req, ConcurrentDictionary<Guid, SnowparkModel> store) =>
{
    if (!store.TryGetValue(id, out var existing))
        return Results.NotFound(new ErrorResponse($"Snowpark with id '{id}' not found.", "SnowparkNotFound"));

    // If the client sent nothing to update, return 400
    if (req is null || (req.Name is null && req.Location is null && req.IsOpen is null && req.TemperatureC is null && req.SnowDepthCm is null))
        return Results.BadRequest(new ErrorResponse("No update fields provided.", "InvalidInput"));

    var updated = existing with
    {
        Name = req.Name ?? existing.Name,
        Location = req.Location ?? existing.Location,
        IsOpen = req.IsOpen ?? existing.IsOpen,
        TemperatureC = req.TemperatureC ?? existing.TemperatureC,
        SnowDepthCm = req.SnowDepthCm ?? existing.SnowDepthCm
    };

    store[id] = updated;
    return Results.Ok(updated);
})
.WithName("UpdateSnowpark");

app.MapDelete("/snowparks/{id}", (Guid id, ConcurrentDictionary<Guid, SnowparkModel> store) =>
{
    return store.TryRemove(id, out _)
        ? Results.NoContent()
        : Results.NotFound(new ErrorResponse($"Snowpark with id '{id}' not found.", "SnowparkNotFound"));
})
.WithName("DeleteSnowpark");

// Existing snowpark condition endpoint (keeps previous behavior)
app.MapGet("/snowpark/{location?}", (string? location) =>
{
    // Basic heuristic: snowpark is more likely open when temperature <= 0�C
    var tempC = Random.Shared.Next(-20, 8); // simulated current temp
    var isOpen = tempC <= 0;
    var snowDepth = isOpen ? Random.Shared.Next(20, 200) : Random.Shared.Next(0, 20);
    var groomed = isOpen && Random.Shared.NextDouble() > 0.3;
    var message = isOpen ? "Snowpark open and operating" : "Snowpark closed or insufficient snow";

    return Results.Ok(new SnowparkCondition(location ?? "Unknown", isOpen, tempC, snowDepth, groomed, message));
})
.WithName("GetSnowparkCondition");

// New endpoint: get air quality (AQI) for a city (optional)
app.MapGet("/airquality", (string? city) =>
{
    // Simulated AQI value between 0 and 500
    var aqi = Random.Shared.Next(0, 501);
    string category = aqi switch
    {
        <= 50 => "Good",
        <= 100 => "Moderate",
        <= 150 => "Unhealthy for Sensitive Groups",
        <= 200 => "Unhealthy",
        <= 300 => "Very Unhealthy",
        _ => "Hazardous"
    };

    var advice = category switch
    {
        "Good" => "Air quality is good. Enjoy outdoor activities.",
        "Moderate" => "Acceptable; consider limiting prolonged exertion.",
        "Unhealthy for Sensitive Groups" => "Sensitive individuals should reduce prolonged or heavy exertion.",
        "Unhealthy" => "Reduce outdoor activities, especially if you have respiratory issues.",
        "Very Unhealthy" => "Avoid outdoor exertion. Consider staying indoors.",
        _ => "Avoid outdoor activities. Limit exposure."
    };

    return Results.Ok(new AirQuality(city ?? "Unknown", aqi, category, advice));
})
.WithName("GetAirQuality");

// New endpoint: suggest activities for today based on a provided temperature or a simulated one
app.MapGet("/activities", (int? temperatureC) =>
{
    var temp = temperatureC ?? Random.Shared.Next(-20, 40);
    var activities = new List<string>();

    if (temp <= 0)
    {
        activities.AddRange(new[] { "Skiing", "Snowboarding", "Snowshoeing" });
    }
    else if (temp <= 10)
    {
        activities.AddRange(new[] { "Hiking", "Trail Running", "Brisk Walk" });
    }
    else if (temp <= 25)
    {
        activities.AddRange(new[] { "Picnic", "Cycling", "Outdoor Yoga" });
    }
    else
    {
        activities.AddRange(new[] { "Swimming", "Kayaking", "Beach Volleyball" });
    }

    var notes = temp switch
    {
        <= 0 => "Cold conditions. Dress warmly and check snow safety.",
        <= 10 => "Cool weather, layers recommended.",
        <= 25 => "Pleasant weather for most outdoor activities.",
        _ => "Hot weather. Stay hydrated and seek shade when possible."
    };

    return Results.Ok(new ActivitiesResponse(temp, activities.ToArray(), notes));
})
.WithName("GetRecommendedActivities");

app.Run();

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}

// Snowpark model and requests for CRUD
public record SnowparkModel(Guid Id, string Name, string Location, bool IsOpen, int TemperatureC, int SnowDepthCm);
public record SnowparkCreateRequest(string Name, string Location, bool? IsOpen, int? TemperatureC, int? SnowDepthCm);
public record SnowparkUpdateRequest(string? Name, string? Location, bool? IsOpen, int? TemperatureC, int? SnowDepthCm);

// Snowpark condition response
public record SnowparkCondition(string Location, bool IsOpen, int TemperatureC, int SnowDepthCm, bool Groomed, string Message);

// Air quality response
public record AirQuality(string City, int AQI, string Category, string Advice);

// Activities response
public record ActivitiesResponse(int TemperatureC, string[] RecommendedActivities, string Notes);

// Standardized error response for API errors
public record ErrorResponse(string Message, string? ErrorCode = null);

// Make the implicit Program class public for testing
public partial class Program { }
