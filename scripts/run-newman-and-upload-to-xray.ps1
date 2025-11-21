<#
run-newman-and-upload-to-xray.ps1

Runs a Postman/Newman collection and uploads JUnit results to Jira Xray.

Requirements:
- Node.js and npm installed. If `newman` is not installed globally, the script uses `npx newman`.
- The Newman JUnit reporter is built-in and supported by `newman` (use `--reporters junit`).
- For Xray Cloud: provide `ClientId` + `ClientSecret` (auth endpoint defaults to Xray Cloud URL).
 - You can also provide credentials via environment variables to avoid exposing secrets on the command line:
     - `XRAY_CLIENT_ID`, `XRAY_CLIENT_SECRET`, `XRAY_BEARER_TOKEN`

Parameters:
  -CollectionPath: Path to the Postman collection JSON (required by default: `./postman/collection.json`).
  -EnvironmentPath: Optional Postman environment JSON path.
  -OutputFile: JUnit output file path (default: `newman-junit.xml`).
  -AdditionalNewmanArgs: Optional extra args to pass to `newman` (string).
  -XrayUrl: Base URL for Xray/Jira (required for upload).
  -ImportEndpoint: Optional override for import endpoint (e.g. `/rest/raven/1.0/import/execution/junit` or `/api/v2/import/execution/junit`).
  -AuthType: `Basic`, `Bearer`, or `XrayCloud` (default: Bearer).
  -Username/Password: for Basic auth.
  -BearerToken: pre-obtained bearer token.
  -ClientId/ClientSecret: for Xray Cloud auth.
  -AuthUrl: auth endpoint for XrayCloud (default `https://xray.cloud.getxray.app/api/v2/authenticate`).
  -TestExecKey: Xray Test Execution issue key (optional).
  -ProjectKey: Jira project key (optional; used for server endpoints).

Examples:
  pwsh ./scripts/run-newman-and-upload-to-xray.ps1 -CollectionPath "./postman/collection.json" -EnvironmentPath "./postman/local_environment.json" -OutputFile "newman-junit.xml" -XrayUrl "https://your-jira.example.com" -AuthType Basic -Username "jirauser" -Password "secret" -ImportEndpoint "/rest/raven/1.0/import/execution/junit"

  # Xray Cloud example (client credentials)
  pwsh ./scripts/run-newman-and-upload-to-xray.ps1 -CollectionPath "./postman/collection.json" -OutputFile "newman-junit.xml" -XrayUrl "https://xray.cloud.getxray.app" -AuthType XrayCloud -ClientId "my-id" -ClientSecret "my-secret" -TestExecKey "TEST-123"
#>

param(
    [string]$CollectionPath = "./postman/collection.json",
    [string]$EnvironmentPath = "",
    [string]$OutputFile = "newman-junit.xml",
    [string]$AdditionalNewmanArgs = "",
    [string]$XrayUrl = '',
    [string]$ImportEndpoint = '',
    [ValidateSet('Basic','Bearer','XrayCloud')][string]$AuthType = 'Bearer',
    [string]$Username = '',
    [string]$Password = '',
    [string]$BearerToken = '',
    [string]$ClientId = '',
    [string]$ClientSecret = '',
    [string]$AuthUrl = 'https://xray.cloud.getxray.app/api/v2/authenticate',
    [string]$TestExecKey = '',
    [string]$ProjectKey = ''
)

# Fallback to environment variables if parameters not provided
if (-not $ClientId -and $env:XRAY_CLIENT_ID) { $ClientId = $env:XRAY_CLIENT_ID }
if (-not $ClientSecret -and $env:XRAY_CLIENT_SECRET) { $ClientSecret = $env:XRAY_CLIENT_SECRET }
if (-not $BearerToken -and $env:XRAY_BEARER_TOKEN) { $BearerToken = $env:XRAY_BEARER_TOKEN }

function Write-ErrAndExit($message) {
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $CollectionPath)) {
    Write-ErrAndExit "Collection not found at path '$CollectionPath'. Provide a valid Postman collection JSON path using -CollectionPath."
}

if (-not $XrayUrl) {
    Write-ErrAndExit "-XrayUrl is required (base URL for your Jira/Xray instance)"
}

# Build newman command
$envArg = ''
if ($EnvironmentPath -ne '') {
    if (-not (Test-Path -Path $EnvironmentPath)) {
        Write-ErrAndExit "Environment file not found at '$EnvironmentPath'."
    }
    $envArg = "-e `"$EnvironmentPath`""
}

# Ensure output directory exists
$outDir = Split-Path -Path $OutputFile -Parent
if ($outDir -and -not (Test-Path -Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

# Prepare argument string for npx newman
$newmanArgs = "newman run `"$CollectionPath`" $envArg --reporters junit --reporter-junit-export `"$OutputFile`" $AdditionalNewmanArgs"
Write-Host "Running: npx $newmanArgs" -ForegroundColor Cyan

# Run newman via npx (works whether newman is global or not)
$proc = Start-Process -FilePath npx -ArgumentList $newmanArgs -NoNewWindow -Wait -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Host "newman exited with code $($proc.ExitCode). Continuing to attempt upload if result file exists." -ForegroundColor Yellow
}

# Verify output file
if (-not (Test-Path -Path $OutputFile)) {
    Write-ErrAndExit "Newman did not produce '$OutputFile'. Check newman output and reporter availability."
}
$fullOutputPath = Resolve-Path -Path $OutputFile
$fullOutputPath = $fullOutputPath.Path
Write-Host "Newman JUnit results: $fullOutputPath" -ForegroundColor Green

# Determine import endpoint
if ($ImportEndpoint -ne '') {
    $uri = $XrayUrl.TrimEnd('/') + $ImportEndpoint
} else {
    if ($AuthType -eq 'XrayCloud') {
        $uri = $XrayUrl.TrimEnd('/') + "/api/v2/import/execution/junit"
    } else {
        $uri = $XrayUrl.TrimEnd('/') + "/rest/raven/1.0/import/execution/junit"
    }
}

# Append query params if needed
if ($TestExecKey -ne '') {
    if ($uri -like '*?*') { $uri = "$uri&testExecKey=$TestExecKey" } else { $uri = "$uri?testExecKey=$TestExecKey" }
} elseif ($ProjectKey -ne '') {
    if ($uri -like '*?*') { $uri = "$uri&projectKey=$ProjectKey" } else { $uri = "$uri?projectKey=$ProjectKey" }
}

Write-Host "Uploading results to: $uri" -ForegroundColor Cyan

# Prepare headers and auth
$headers = @{}
if ($AuthType -eq 'Basic') {
    if (-not ($Username -and $Password)) { Write-ErrAndExit "Username and Password are required for Basic auth." }
    $pair = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$Username`:$Password"))
    $headers['Authorization'] = "Basic $pair"
} elseif ($AuthType -eq 'Bearer') {
    if (-not $BearerToken) { Write-ErrAndExit "BearerToken is required for Bearer auth." }
    $headers['Authorization'] = "Bearer $BearerToken"
} elseif ($AuthType -eq 'XrayCloud') {
    if (-not ($ClientId -and $ClientSecret)) { Write-ErrAndExit "ClientId and ClientSecret are required for XrayCloud auth." }
    Write-Host "Authenticating to Xray Cloud at $AuthUrl" -ForegroundColor Cyan
    $authBody = @{ client_id = $ClientId; client_secret = $ClientSecret } | ConvertTo-Json
    try {
        $authResp = Invoke-RestMethod -Uri $AuthUrl -Method Post -Body $authBody -ContentType 'application/json'
    } catch {
        Write-ErrAndExit "Failed to authenticate to Xray Cloud: $($_.Exception.Message)"
    }
    if (-not $authResp) { Write-ErrAndExit "Empty authentication response from Xray Cloud." }
    $token = $authResp
    $headers['Authorization'] = "Bearer $token"
}

# Prepare form for file upload
$form = @{ file = Get-Item -Path $fullOutputPath }

try {
    $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Form $form -ContentType 'multipart/form-data'
    Write-Host "Upload response:" -ForegroundColor Green
    $response | ConvertTo-Json -Depth 5 | Write-Host
} catch {
    Write-Host "Upload failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) {
        try { $body = (New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd(); Write-Host "Response body:`n$body" }
        catch { }
    }
    exit 1
}

Write-Host "Done." -ForegroundColor Green
