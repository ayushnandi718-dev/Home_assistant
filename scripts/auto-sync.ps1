# Aura Hub Auto-Sync Script
# Watches for file changes and auto-commits/pushes with descriptive messages

param(
    [int]$IntervalSeconds = 15,
    [string]$Branch = "main"
)

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "🔄 Auto-sync started for $projectRoot" -ForegroundColor Green
Write-Host "   Checking every $IntervalSeconds seconds..." -ForegroundColor Gray
Write-Host "   Press Ctrl+C to stop" -ForegroundColor Gray

function Get-SmartCommitMessage {
    $status = git status --porcelain
    $lines = $status -split "`n" | Where-Object { $_ -match '\S' }
    
    if ($lines.Count -eq 0) { return $null }
    
    # Categorize changes
    $added = @()
    $modified = @()
    $deleted = @()
    $renamed = @()
    
    foreach ($line in $lines) {
        $code = $line.Substring(0, 2)
        $file = $line.Substring(3).Trim()
        
        switch -Wildcard ($code) {
            "??*" { $added += $file }
            "?M*" { $added += $file; $modified += $file }
            "*M*" { $modified += $file }
            "*D*" { $deleted += $file }
            "*R*" { $renamed += $file }
            default { $modified += $file }
        }
    }
    
    # Analyze scope from paths
    $scopes = @()
    foreach ($f in ($modified + $added + $deleted)) {
        if ($f -match 'lib/features/([^/]+)') { $scopes += $matches[1] }
        elseif ($f -match 'lib/app/(.+?)\.dart') { $scopes += "app" }
        elseif ($f -match 'lib/core/(.+?)/') { $scopes += $matches[1] }
        elseif ($f -match 'lib/shared/(.+?)/') { $scopes += "shared" }
        elseif ($f -match 'test/') { $scopes += "tests" }
        elseif ($f -match 'pubspec') { $scopes += "deps" }
        elseif ($f -match 'README|\.md$') { $scopes += "docs" }
        elseif ($f -match '\.yaml$|\.json$') { $scopes += "config" }
        elseif ($f -match 'windows/') { $scopes += "windows" }
    }
    $uniqueScopes = $scopes | Sort-Object -Unique
    $scope = if ($uniqueScopes.Count -gt 0) { ($uniqueScopes | Select-Object -First 2) -join ", " } else { "core" }
    
    # Determine type and description
    $type = "chore"
    $description = ""
    
    $allFiles = $modified + $added + $deleted + $renamed
    $hasNewFeature = $added.Count -gt 0
    $hasOnlyDocs = ($allFiles | Where-Object { $_ -notmatch '\.md$|\.txt$' }).Count -eq 0
    $hasOnlyConfig = ($allFiles | Where-Object { $_ -notmatch '\.yaml$|\.json$|\.toml$|\.lock$' }).Count -eq 0
    
    # Get diff summary for better description
    $diff = git diff --stat
    $diffLines = git diff --unified=0 | Select-String '^\+' | Where-Object { $_ -notmatch '^\+\+\+' }
    
    if ($hasOnlyDocs) {
        $type = "docs"
        $description = "Update documentation"
    } elseif ($hasOnlyConfig) {
        $type = "chore"
        $description = "Update configuration"
    } elseif ($deleted.Count -gt 0 -and $modified.Count -eq 0 -and $added.Count -eq 0) {
        $type = "refactor"
        $description = "Remove deprecated files"
    } elseif ($hasNewFeature -and $modified.Count -eq 0) {
        $type = "feat"
        $description = "Add $($added.Count) new file$(if ($added.Count -gt 1) { 's' })"
    } else {
        # Analyze diff content for keywords
        $content = ($diffLines -join " ").ToLower()
        if ($content -match 'fix|bug|error|crash|null') {
            $type = "fix"
            $description = "Fix issue in $scope"
        } elseif ($content -match 'color|theme|style|padding|margin|font|ui|design|widget') {
            $type = "style"
            $description = "Refine $scope visuals"
        } elseif ($content -match 'refactor|rename|move|restructure|extract') {
            $type = "refactor"
            $description = "Restructure $scope"
        } elseif ($content -match 'test|assert|expect') {
            $type = "test"
            $description = "Update tests for $scope"
        } else {
            $type = "feat"
            $description = "Update $scope module"
        }
    }
    
    # Add file count context
    $total = $lines.Count
    if ($total -gt 1) {
        $description += " ($total files)"
    }
    
    return "${type}(${scope}): ${description}"
}

function Sync-Changes {
    $status = git status --porcelain
    if ([string]::IsNullOrWhiteSpace($status)) { return }
    
    # Get smart message based on changes
    $message = Get-SmartCommitMessage
    if (-not $message) { return }
    
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] 📝 Changes detected" -ForegroundColor Cyan
    Write-Host "   $message" -ForegroundColor White
    
    git add -A
    
    $commitResult = git commit -m $message 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   ❌ Commit failed: $commitResult" -ForegroundColor Red
        return
    }
    
    Write-Host "   ✅ Committed" -ForegroundColor Green
    
    $pushResult = git push origin $Branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   ⚠️ Push failed (will retry next cycle): $pushResult" -ForegroundColor Yellow
    } else {
        Write-Host "   🚀 Pushed to GitHub" -ForegroundColor Green
    }
}

# Initial sync check
Sync-Changes

# Watch loop
while ($true) {
    Start-Sleep -Seconds $IntervalSeconds
    Sync-Changes
}
