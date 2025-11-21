<#
run-tests-and-upload-to-xray.ps1

Runs `dotnet test` and uploads the test results to Jira Xray via its REST API.

Notes:
- By default the script will request TRX results. Xray commonly accepts JUnit/NUnit/other XML formats; adjust `-ResultFormat` accordingly.
- If you want JUnit output from `dotnet test` you may need to add a JUnit logger such as `JunitXml.TestLogger` to your test project:
  dotnet add <TestProject> package JunitXml.TestLogger
  and then use `--logger "junit;LogFileName=TestResults.xml"`.
- For Xray Cloud you can use client credentials (client_id/client_secret) to obtain a token. For other setups use Basic or provide a bearer token.

Examples:
  pwsh ./scripts/run-tests-and-upload-to-xray.ps1 -SolutionPath "./JiraXrayApi.sln" -OutputFile "TestResults.trx" -ResultFormat trx -AuthType Basic -Username "user" -Password "pass" -XrayUrl "https://your-jira.example.com" -ImportEndpoint "/rest/raven/1.0/import/execution" -ProjectKey "PROJ"

  # Xray Cloud example (requires client id/secret and the cloud auth endpoint)
  pwsh ./scripts/run-tests-and-upload-to-xray.ps1 -SolutionPath "./JiraXrayApi.sln" -OutputFile "TestResults.xml" -ResultFormat junit -AuthType XrayCloud -ClientId "XXXX" -ClientSecret "YYYY" -XrayUrl "https://xray.cloud.getxray.app" -TestExecKey "TEST-123"

Parameters:
  -SolutionPath: path to solution or test project to pass to `dotnet test` (default: current directory)
  -TestProject: optional single test project to target
  -OutputFile: filename for test results (default: TestResults.trx)
  -ResultFormat: `trx` or `junit` (default: trx)
  -XrayUrl: base Xray/Jira URL (required for upload)
  -ImportEndpoint: optional override for import endpoint (e.g. `/rest/raven/1.0/import/execution` or `/api/v2/import/execution/junit`)
  -AuthType: `Basic`, `Bearer`, or `XrayCloud` (default: Bearer)
  -Username/Password: for Basic auth
  -BearerToken: pre-obtained bearer token
  -ClientId/ClientSecret: for Xray Cloud auth
  -TestExecKey: Xray Test Execution issue key (optional)
  -ProjectKey: Jira project key (optional; used for server endpoints)
#>

param(
    [string]$SolutionPath = ".",
    [string]$TestProject = "",
    [string]$OutputFile = "TestResults.trx",
    [ValidateSet('trx','junit')][string]$ResultFormat = 'trx',
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

function Write-ErrAndExit($message) {
    Write-Host "ERROR: $message" -ForegroundColor Red
    exit 1
}

if (-not $XrayUrl) {
    Write-ErrAndExit "-XrayUrl is required (base URL for your Jira/Xray instance)"
}

# Build dotnet test args
$testTarget = if ($TestProject -ne '') { $TestProject } else { $SolutionPath }

Write-Host "Running tests for: $testTarget" -ForegroundColor Cyan

if ($ResultFormat -eq 'trx') {
    $loggerArg = "--logger \"trx;LogFileName=$OutputFile\""
} else {
    # JUnit logger may require an extra NuGet logger package in test project.
    $loggerArg = "--logger \"junit;LogFileName=$OutputFile\""
}

# Execute tests
$dotnetArgs = "test --no-build $testTarget $loggerArg"
Write-Host "Running: dotnet $dotnetArgs"
$ps = Start-Process -FilePath dotnet -ArgumentList $dotnetArgs -NoNewWindow -Wait -PassThru
if ($ps.ExitCode -ne 0) {
    Write-Host "dotnet test exited with code $($ps.ExitCode). Continuing to attempt upload if result file exists." -ForegroundColor Yellow
}

# Verify results file
$fullOutputPath = Resolve-Path -Path $OutputFile -ErrorAction SilentlyContinue
if (-not $fullOutputPath) {
    Write-ErrAndExit "Test results file '$OutputFile' not found. Check that the test run produced results and that the logger is available."
}
$fullOutputPath = $fullOutputPath.Path
Write-Host "Test results produced: $fullOutputPath" -ForegroundColor Green

# Determine import endpoint
if ($ImportEndpoint -ne '') {
    $uri = $XrayUrl.TrimEnd('/') + $ImportEndpoint
} else {
    # Default heuristics: pick likely endpoints for JUnit on Cloud vs Server
    if ($AuthType -eq 'XrayCloud') {
        if ($ResultFormat -eq 'junit') {
            $uri = $XrayUrl.TrimEnd('/') + "/api/v2/import/execution/junit"
        } else {
            # TRX via generic import endpoint (server may accept TRX at v1 import)
            $uri = $XrayUrl.TrimEnd('/') + "/api/v2/import/execution"
        }
    } else {
        # Assume server/Data Center Raven endpoints
        if ($ResultFormat -eq 'junit') {
            $uri = $XrayUrl.TrimEnd('/') + "/rest/raven/1.0/import/execution/junit"
        } else {
            $uri = $XrayUrl.TrimEnd('/') + "/rest/raven/1.0/import/execution"
        }
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
    # Authenticate to get JWT token
    $authEndpoint = $AuthUrl
    Write-Host "Authenticating to Xray Cloud at $authEndpoint" -ForegroundColor Cyan
    $authBody = @{ client_id = $ClientId; client_secret = $ClientSecret } | ConvertTo-Json
    try {
        $authResp = Invoke-RestMethod -Uri $authEndpoint -Method Post -Body $authBody -ContentType 'application/json'
    } catch {
        Write-ErrAndExit "Failed to authenticate to Xray Cloud: $($_.Exception.Message)"
    }
    if (-not $authResp) { Write-ErrAndExit "Empty authentication response from Xray Cloud." }
    # authResp is usually a token string
    $token = $authResp
    $headers['Authorization'] = "Bearer $token"
}

# Prepare form for file upload
$form = @{
    file = Get-Item -Path $fullOutputPath
}

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
