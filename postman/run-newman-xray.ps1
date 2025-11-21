param(
    [string]$PostmanCollectionUrl = "https://api.getpostman.com/collections/9498939-37d1237b-7b54-4090-81c0-d0cf9d8dc26c?apikey=",
    [string]$XrayClientId = "",
    [string]$XrayClientSecret = "",
    [string]$ProjectKey = "SCRUM",
    [string]$TestExecKey = "SCRUM-6",
    [string]$XmlFile = "postman_echo_junitxray.xml"
)

Write-Host "=== Running Newman ==="

newman run $PostmanCollectionUrl `
  -r "cli,junitfull,junitxray" `
  --reporter-junitfull-export "postman_echo_junitfull.xml" `
  --reporter-junitxray-export $XmlFile `
  -n 1


Write-Host "=== Authenticating with Xray ==="

$authBody = @{
    client_id     = $XrayClientId
    client_secret = $XrayClientSecret
} | ConvertTo-Json

$token = Invoke-RestMethod `
    -Uri "https://xray.cloud.getxray.app/api/v2/authenticate" `
    -Method Post `
    -ContentType "application/json" `
    -Body $authBody

# token response is a quoted string → remove quotes
$token = $token.Trim('"')

Write-Host "Token received."


Write-Host "=== Uploading XML Results to Xray ==="

Invoke-RestMethod `
    -Uri "https://xray.cloud.getxray.app/api/v2/import/execution/junit?projectKey=$ProjectKey&testExecKey=$TestExecKey" `
    -Method Post `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "text/xml" `
    -InFile $XmlFile

Write-Host "=== Done! Test results imported to $TestExecKey ==="
