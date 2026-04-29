# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY src/GameWebsite.MockApi/GameWebsite.MockApi.csproj src/GameWebsite.MockApi/
RUN dotnet restore src/GameWebsite.MockApi/GameWebsite.MockApi.csproj

COPY src/GameWebsite.MockApi/ src/GameWebsite.MockApi/
RUN dotnet publish src/GameWebsite.MockApi/GameWebsite.MockApi.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app
EXPOSE 8080 8081
ENV ASPNETCORE_URLS="http://+:8080;http://+:8081" \
    ASPNETCORE_ENVIRONMENT="Development"
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "GameWebsite.MockApi.dll"]
