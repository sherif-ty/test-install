

# =========================
# Authenticate and Push Configurations to Cribl Leader
# =========================
$AuthUrl = "http://localhost:9420/api/v1/auth/login"
$Username = "admin"
$Password = "admin"
$CriblHost = "http://localhost:9420"

try {
    $response = Invoke-WebRequest -Method Post -Uri $AuthUrl -Headers @{
        "Content-Type" = "application/json"
        "Accept" = "application/json"
    } -Body (@{ username = $Username; password = $Password } | ConvertTo-Json) -ErrorAction Stop

    $AuthResponse = $response.Content | ConvertFrom-Json

    if ($AuthResponse.token) {
        $AuthToken = $AuthResponse.token
        Write-Host "Authenticated successfully. Token: $AuthToken"

        $Headers = @{
            "Authorization" = "Bearer $AuthToken"
            "Content-Type"  = "application/json"
        }

        Invoke-RestMethod -Method Post -Uri "$CriblHost/api/v1/system/outputs" -Headers $Headers -InFile "payload.json"
        Invoke-RestMethod -Method Post -Uri "$CriblHost/api/v1/system/inputs" -Headers $Headers -InFile "sources.json"
        Invoke-RestMethod -Method Post -Uri "$CriblHost/api/v1/pipelines" -Headers $Headers -InFile "pipeline.json"
        Invoke-RestMethod -Method Patch -Uri "$CriblHost/api/v1/pipelines/node-info" -Headers $Headers -InFile "pipeline_patch.json"
        Invoke-RestMethod -Method Patch -Uri "$CriblHost/api/v1/routes/default" -Headers $Headers -InFile "routes_patch.json"

        Write-Host "Configuration pushed successfully."
    } else {
        Write-Error "Authentication failed. Message: $($AuthResponse.message)"
        exit 1
    }
} catch {
    Write-Error "Failed to authenticate or push configurations: $_"
    exit 1
}

