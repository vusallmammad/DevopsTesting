# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY src/GameWebsite.ApiGateway/GameWebsite.ApiGateway.csproj src/GameWebsite.ApiGateway/
RUN dotnet restore src/GameWebsite.ApiGateway/GameWebsite.ApiGateway.csproj

COPY src/GameWebsite.ApiGateway/ src/GameWebsite.ApiGateway/
RUN dotnet publish src/GameWebsite.ApiGateway/GameWebsite.ApiGateway.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app
EXPOSE 8080 8081
ENV ASPNETCORE_URLS="http://+:8080;http://+:8081" \
    ASPNETCORE_ENVIRONMENT="Development"
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "GameWebsite.ApiGateway.dll"]
