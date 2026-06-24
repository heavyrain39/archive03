param(
    [ValidateSet("StartConverter", "StopConverter", "Convert", "Translate", "Import", "QA", "Deploy", "All")]
    [string]$Action = "QA",

    [string]$BaseName = "",

    [string]$DraftPath = "",

    [string]$OutputPath = "",

    [string]$ConverterRoot = "C:\gemini-converter",

    [string]$ConverterResultsDir = "C:\gemini-converter\results",

    [string]$ConverterUrl = "http://127.0.0.1:5002/api/run-pipeline",

    [string]$ConverterHealthUrl = "http://127.0.0.1:5002/api/config",

    [switch]$Yes
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-ReportsRoot {
    return Join-Path (Get-RepoRoot) "content\reports"
}

function Get-ConverterPidPath {
    return Join-Path (Get-RepoRoot) "tmp\converter-server.pid"
}

function Get-PostBaseNameFromFileName {
    param([string]$Name)
    return ($Name -replace "\.(ko|en)\.md$", "")
}

function Find-PostPair {
    param([string]$RequestedBaseName)

    $reportsRoot = Get-ReportsRoot
    $candidateDirs = @($reportsRoot)
    if (Test-Path -LiteralPath $ConverterResultsDir) {
        $candidateDirs += $ConverterResultsDir
    }

    if ($RequestedBaseName) {
        $requestedDirs = @()
        if ($RequestedBaseName -match "^(\d{4})-") {
            $requestedDirs += (Join-Path (Get-ReportsRoot) $Matches[1])
        }
        $requestedDirs += $candidateDirs

        foreach ($dir in $requestedDirs) {
            if (-not (Test-Path -LiteralPath $dir)) { continue }
            $ko = Join-Path $dir "$RequestedBaseName.ko.md"
            $en = Join-Path $dir "$RequestedBaseName.en.md"
            if ((Test-Path -LiteralPath $ko) -and (Test-Path -LiteralPath $en)) {
                return [pscustomobject]@{ BaseName = $RequestedBaseName; Ko = $ko; En = $en; SourceDir = $dir }
            }
        }

        throw "Could not find both KO/EN files for base name: $RequestedBaseName"
    }

    $pairs = @()
    foreach ($dir in $candidateDirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -File -Filter "*.ko.md" | ForEach-Object {
            $base = Get-PostBaseNameFromFileName $_.Name
            $en = Join-Path $dir "$base.en.md"
            if (Test-Path -LiteralPath $en) {
                $pairs += [pscustomobject]@{
                    BaseName = $base
                    Ko = $_.FullName
                    En = $en
                    SourceDir = $dir
                    LastWriteTime = [Math]::Max($_.LastWriteTimeUtc.Ticks, (Get-Item -LiteralPath $en).LastWriteTimeUtc.Ticks)
                }
            }
        }
    }

    if (-not $pairs) {
        throw "No KO/EN post pair found in content\reports root or converter results."
    }

    return $pairs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Import-PostPair {
    param([object]$Pair)

    if ($Pair.BaseName -notmatch "^(\d{4})-") {
        throw "Base filename must start with YYYY- for year-folder import: $($Pair.BaseName)"
    }

    $year = $Matches[1]
    $reportsRoot = Get-ReportsRoot
    $targetDir = Join-Path $reportsRoot $year
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

    $targetKo = Join-Path $targetDir "$($Pair.BaseName).ko.md"
    $targetEn = Join-Path $targetDir "$($Pair.BaseName).en.md"

    if ((Resolve-Path $Pair.SourceDir).Path -eq (Resolve-Path $targetDir).Path) {
        Write-Host "Already imported: $($Pair.BaseName)"
        return [pscustomobject]@{ BaseName = $Pair.BaseName; Ko = $Pair.Ko; En = $Pair.En; TargetDir = $targetDir }
    }

    foreach ($target in @($targetKo, $targetEn)) {
        if (Test-Path -LiteralPath $target) {
            throw "Target already exists: $target"
        }
    }

    if ((Resolve-Path $Pair.SourceDir).Path -eq (Resolve-Path $reportsRoot).Path) {
        Move-Item -LiteralPath $Pair.Ko -Destination $targetKo
        Move-Item -LiteralPath $Pair.En -Destination $targetEn
    } else {
        Copy-Item -LiteralPath $Pair.Ko -Destination $targetKo
        Copy-Item -LiteralPath $Pair.En -Destination $targetEn
    }

    Write-Host "Imported to $targetDir"
    return [pscustomobject]@{ BaseName = $Pair.BaseName; Ko = $targetKo; En = $targetEn; TargetDir = $targetDir }
}

function Test-ConverterServer {
    try {
        Invoke-RestMethod -Uri $ConverterHealthUrl -Method Get -TimeoutSec 2 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Start-ConverterServer {
    if (Test-ConverterServer) {
        Write-Host "Converter server already running."
        return
    }

    $appPath = Join-Path $ConverterRoot "app.py"
    if (-not (Test-Path -LiteralPath $appPath)) {
        throw "Converter app.py not found: $appPath"
    }

    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw "python was not found on PATH."
    }

    Write-Host "Starting converter server in the background..."
    $process = Start-Process -FilePath $python.Source -ArgumentList "app.py" -WorkingDirectory $ConverterRoot -WindowStyle Hidden -PassThru
    $pidPath = Get-ConverterPidPath
    New-Item -ItemType Directory -Path (Split-Path $pidPath -Parent) -Force | Out-Null
    Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ASCII

    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
        if (Test-ConverterServer) {
            Write-Host "Converter server is ready."
            return
        }
    }

    throw "Converter server did not become ready within 30 seconds."
}

function Stop-ConverterServer {
    $pidPath = Get-ConverterPidPath
    if (Test-Path -LiteralPath $pidPath) {
        $pidText = Get-Content -LiteralPath $pidPath -Raw -Encoding ASCII
        $processId = 0
        if ([int]::TryParse($pidText.Trim(), [ref]$processId)) {
            $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($process) {
                Stop-Process -Id $processId -Force
                Remove-Item -LiteralPath $pidPath -Force
                Write-Host "Stopped converter server process: $processId"
                return
            }
        }
        Remove-Item -LiteralPath $pidPath -Force
    }

    $converterPath = (Resolve-Path $ConverterRoot).Path
    $processes = Get-CimInstance Win32_Process |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine.Contains("app.py") -and
            $_.CommandLine.Contains($converterPath)
        }

    if (-not $processes) {
        Write-Host "No converter server process found."
        return
    }

    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force
        Write-Host "Stopped converter server process: $($process.ProcessId)"
    }
}

function Invoke-Converter {
    param([string]$Path)

    if (-not $Path) {
        throw "DraftPath is required for Convert."
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Draft file not found: $Path"
    }

    $draft = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if (-not $draft.Trim()) {
        throw "Draft file is empty: $Path"
    }

    Start-ConverterServer

    $body = @{ original_content = $draft } | ConvertTo-Json -Depth 4
    $result = Invoke-RestMethod -Uri $ConverterUrl -Method Post -ContentType "application/json" -Body $body

    if ($result.status -ne "success") {
        throw "Converter failed: $($result.message)"
    }

    Write-Host "Converter succeeded."
    if ($result.saved_files) {
        Write-Host "Saved files: $($result.saved_files -join ', ')"
        $first = [string]$result.saved_files[0]
        return (Get-PostBaseNameFromFileName $first)
    }

    return ""
}

function Get-GeminiPath {
    $geminiPath = Join-Path $env:APPDATA "npm\gemini.cmd"
    if (Test-Path -LiteralPath $geminiPath) {
        return $geminiPath
    }

    $gemini = Get-Command gemini.cmd -ErrorAction SilentlyContinue
    if ($gemini) {
        return $gemini.Source
    }

    throw "gemini.cmd was not found."
}

function Invoke-GeminiCli {
    param([string]$Prompt)

    $geminiPath = Get-GeminiPath

    $tempDir = Join-Path (Get-RepoRoot) "tmp\gemini-cli"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $id = [guid]::NewGuid().ToString("N")
    $inputPath = Join-Path $tempDir "$id.prompt.txt"
    $stdoutPath = Join-Path $tempDir "$id.stdout.txt"
    $stderrPath = Join-Path $tempDir "$id.stderr.txt"

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($inputPath, $Prompt, $utf8NoBom)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "cmd.exe"
    $startInfo.Arguments = ('/c ""{0}" --prompt . < "{1}" > "{2}" 2> "{3}""' -f $geminiPath, $inputPath, $stdoutPath, $stderrPath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = Get-RepoRoot
    $startInfo.EnvironmentVariables["PATH"] = "C:\Program Files\nodejs;$($env:APPDATA)\npm;$($env:PATH)"

    $process = [System.Diagnostics.Process]::Start($startInfo)
    if (-not $process.WaitForExit(1200000)) {
        $process.Kill()
        Remove-Item -LiteralPath $inputPath, $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
        throw "Gemini CLI timed out after 1200 seconds."
    }

    $stdout = ""
    $stderr = ""
    if (Test-Path -LiteralPath $stdoutPath) {
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
        $stdout = $stdout.Trim()
    }
    if (Test-Path -LiteralPath $stderrPath) {
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8
        $stderr = $stderr.Trim()
    }
    Remove-Item -LiteralPath $inputPath, $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    if ($process.ExitCode -ne 0) {
        throw "Gemini CLI failed: stderr=$stderr stdout=$stdout exit=$($process.ExitCode)"
    }

    $mcpWarning = "MCP issues detected. Run /mcp list for status."
    if ($stdout.StartsWith($mcpWarning)) {
        $stdout = $stdout.Substring($mcpWarning.Length).TrimStart()
    }

    return $stdout
}

function Get-DefaultTranslationOutputPath {
    param([string]$Path)

    if ($Path -match "\.ko\.md$") {
        return ($Path -replace "\.ko\.md$", ".en.md")
    }

    $dir = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    if ($base -match "-source$") {
        $base = $base -replace "-source$", ""
    }
    return (Join-Path $dir "$base.en.md")
}

function Invoke-TranslationOnly {
    param(
        [string]$Path,
        [string]$OutPath
    )

    if (-not $Path) {
        throw "DraftPath is required for Translate."
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Korean source file not found: $Path"
    }

    $configPath = Join-Path $ConverterRoot "converter_config.json"
    $promptFolder = Join-Path $ConverterRoot "prompts"
    $referenceFolder = Join-Path $ConverterRoot "references"
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "converter_config.json not found: $configPath"
    }

    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $stage2PromptName = [string]$config.stage2_prompts[0]
    if (-not $stage2PromptName) {
        throw "No stage2 prompt configured."
    }

    $stage2PromptPath = Join-Path $promptFolder $stage2PromptName
    if (-not (Test-Path -LiteralPath $stage2PromptPath)) {
        throw "Stage2 prompt not found: $stage2PromptPath"
    }

    $systemPrompt = Get-Content -LiteralPath $stage2PromptPath -Raw -Encoding UTF8
    $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $fileContext = ""
    foreach ($fileName in @($config.stage2_files)) {
        $referencePath = Join-Path $referenceFolder ([string]$fileName)
        if (Test-Path -LiteralPath $referencePath) {
            $fileContext += " @$(Resolve-Path $referencePath)"
        }
    }

    $finalPrompt = "$systemPrompt`n`n---`n`n$fileContext`n`n$source".Trim()
    $translated = Invoke-GeminiCli -Prompt $finalPrompt

    if (-not $OutPath) {
        $OutPath = Get-DefaultTranslationOutputPath -Path $Path
    }

    $outDir = Split-Path $OutPath -Parent
    if ($outDir) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    Set-Content -LiteralPath $OutPath -Value $translated -Encoding UTF8
    Write-Host "Translation saved: $OutPath"
    return $OutPath
}

function Test-FrontMatter {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $errors = @()

    if (-not $text.StartsWith("---")) { $errors += "missing front matter fence" }
    foreach ($key in @("title:", "date:", "draft:", "summary:", "tags:")) {
        if ($text -notmatch "(?m)^$([regex]::Escape($key))") {
            $errors += "missing $key"
        }
    }
    if ($text -match "(?m)^draft:\s*true\s*$") {
        $errors += "draft is true"
    }

    $leakPatterns = @(
        'private/',
        ('private' + [char]92),
        'C:\gemini-converter',
        'SKILL.md',
        'system prompt',
        'GEMINI_PATH',
        'APPDATA'
    )
    foreach ($pattern in $leakPatterns) {
        if ($text.Contains($pattern)) {
            $errors += "possible private/workflow leak: $pattern"
        }
    }

    return $errors
}

function Invoke-PostQA {
    param([object]$Pair)

    $year = if ($Pair.BaseName -match "^(\d{4})-") { $Matches[1] } else { "" }
    if (-not $year) {
        throw "Base filename must start with YYYY- for QA: $($Pair.BaseName)"
    }

    $reportsRoot = Get-ReportsRoot
    $yearDir = Join-Path $reportsRoot $year
    $ko = Join-Path $yearDir "$($Pair.BaseName).ko.md"
    $en = Join-Path $yearDir "$($Pair.BaseName).en.md"

    if (-not ((Test-Path -LiteralPath $ko) -and (Test-Path -LiteralPath $en))) {
        throw "QA expects imported files under $yearDir. Run -Action Import first."
    }

    $errors = @()
    foreach ($path in @($ko, $en)) {
        $fileErrors = Test-FrontMatter -Path $path
        foreach ($err in $fileErrors) {
            $errors += "$(Split-Path $path -Leaf): $err"
        }
    }

    if ($errors.Count -gt 0) {
        throw "QA failed:`n - $($errors -join "`n - ")"
    }

    $repoRoot = Get-RepoRoot
    $dest = Join-Path $repoRoot "tmp\hugo-public"
    & hugo --destination $dest --cleanDestinationDir --gc --minify --noTimes --noChmod --printPathWarnings --printI18nWarnings
    if ($LASTEXITCODE -ne 0) {
        throw "Hugo build failed."
    }

    $flatKo = Join-Path $dest "reports\$($Pair.BaseName)\index.html"
    $flatEn = Join-Path $dest "en\reports\$($Pair.BaseName)\index.html"
    $nestedKo = Join-Path $dest "reports\$year\$($Pair.BaseName)\index.html"
    $nestedEn = Join-Path $dest "en\reports\$year\$($Pair.BaseName)\index.html"

    if (-not (Test-Path -LiteralPath $flatKo)) { throw "Missing KO flat URL output: $flatKo" }
    if (-not (Test-Path -LiteralPath $flatEn)) { throw "Missing EN flat URL output: $flatEn" }
    if (Test-Path -LiteralPath $nestedKo) { throw "Unexpected KO nested URL output: $nestedKo" }
    if (Test-Path -LiteralPath $nestedEn) { throw "Unexpected EN nested URL output: $nestedEn" }

    Write-Host "QA passed: $($Pair.BaseName)"
    Write-Host "KO URL output: /reports/$($Pair.BaseName)/"
    Write-Host "EN URL output: /en/reports/$($Pair.BaseName)/"
}

function Invoke-Deploy {
    if (-not $Yes) {
        $answer = Read-Host "Type DEPLOY to run deploy.sh"
        if ($answer -ne "DEPLOY") {
            throw "Deploy cancelled."
        }
    }

    $repoRoot = Get-RepoRoot
    Push-Location $repoRoot
    try {
        $gitBashCandidates = @(
            "C:\Program Files\Git\bin\bash.exe",
            "C:\Program Files\Git\usr\bin\bash.exe"
        )
        $bashPath = $gitBashCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $bashPath) {
            $bash = Get-Command bash -ErrorAction SilentlyContinue
            if ($bash) {
                $bashPath = $bash.Source
            }
        }
        if (-not $bashPath) {
            throw "bash was not found. Run deploy.sh from Git Bash or install bash on PATH."
        }
        & $bashPath ".\deploy.sh"
        if ($LASTEXITCODE -ne 0) {
            throw "deploy.sh failed."
        }
    } finally {
        Pop-Location
    }
}

$pair = $null

switch ($Action) {
    "StartConverter" {
        Start-ConverterServer
    }
    "StopConverter" {
        Stop-ConverterServer
    }
    "Convert" {
        Invoke-Converter -Path $DraftPath | Out-Null
    }
    "Translate" {
        Invoke-TranslationOnly -Path $DraftPath -OutPath $OutputPath | Out-Null
    }
    "Import" {
        $pair = Find-PostPair -RequestedBaseName $BaseName
        Import-PostPair -Pair $pair | Out-Null
    }
    "QA" {
        $pair = Find-PostPair -RequestedBaseName $BaseName
        if ($pair.BaseName -match "^(\d{4})-") {
            $yearDir = Join-Path (Get-ReportsRoot) $Matches[1]
            $yearPair = Find-PostPair -RequestedBaseName $pair.BaseName
            if ((Resolve-Path $yearPair.SourceDir).Path -ne (Resolve-Path $yearDir -ErrorAction SilentlyContinue).Path) {
                throw "Post pair is not imported into the year folder. Run -Action Import first."
            }
        }
        Invoke-PostQA -Pair $pair
    }
    "Deploy" {
        Invoke-Deploy
    }
    "All" {
        if ($DraftPath) {
            $convertedBase = Invoke-Converter -Path $DraftPath
            if ($convertedBase) {
                $BaseName = $convertedBase
            }
        }
        $pair = Find-PostPair -RequestedBaseName $BaseName
        $imported = Import-PostPair -Pair $pair
        Invoke-PostQA -Pair $imported
        Invoke-Deploy
    }
}
