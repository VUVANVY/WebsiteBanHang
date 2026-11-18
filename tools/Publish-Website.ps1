[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$solution = Join-Path $repoRoot 'WebsiteBanHang.sln'
$outputPath = Join-Path $repoRoot 'artifacts\publish'
$archivePath = Join-Path $repoRoot 'artifacts\MotoShop-publish.zip'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'

function Assert-PublishedContent {
    param([string]$ProjectPath, [string]$PublishedRoot)

    $sourceRoot = Split-Path -Parent $ProjectPath
    [xml]$project = [IO.File]::ReadAllText($ProjectPath)
    $projectNamespaces = [Xml.XmlNamespaceManager]::new($project.NameTable)
    $projectNamespaces.AddNamespace('p', 'http://schemas.microsoft.com/developer/msbuild/2003')
    $contentPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $validatedFiles = 0

    function Get-PublishedContentHash([string]$FilePath) {
        $stream = [IO.File]::OpenRead($FilePath)
        try { return [BitConverter]::ToString($sha256.ComputeHash($stream)) }
        finally { $stream.Dispose() }
    }

    try {
        foreach ($content in $project.SelectNodes('/p:Project/p:ItemGroup/p:Content', $projectNamespaces)) {
            $relativePath = $content.GetAttribute('Include').Replace('\', '/')
            if ($relativePath -match '[*?]|\$\(') { throw "Cannot validate non-literal Content include: $relativePath" }
            $null = $contentPaths.Add($relativePath)
            $sourcePath = Join-Path $sourceRoot $relativePath
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Content source file is missing: $relativePath" }

            # MSBuild consumes T4 templates and root Web.config transforms without publishing them.
            $isConfigTransform = $relativePath -match '^Web\.[^/]+\.config$' -and
                $content.SelectSingleNode('p:DependentUpon', $projectNamespaces).InnerText -eq 'Web.config'
            if ([IO.Path]::GetExtension($relativePath) -eq '.tt' -or $isConfigTransform) { continue }

            $publishedPath = Join-Path $PublishedRoot $relativePath
            if (-not (Test-Path -LiteralPath $publishedPath -PathType Leaf)) { throw "Published content file is missing: $relativePath" }
            # The root configuration is transformed; Release checks below validate it separately.
            if ($relativePath -ne 'Web.config' -and
                (Get-PublishedContentHash $sourcePath) -ne (Get-PublishedContentHash $publishedPath)) {
                throw "Published content differs from source: $relativePath"
            }
            $validatedFiles++
        }

        $viewRoot = Join-Path $sourceRoot 'Views'
        $runtimeViews = @(Get-ChildItem -LiteralPath $viewRoot -Recurse -File |
            Where-Object { $_.Extension -eq '.cshtml' -or $_.Name -eq 'Web.config' })
        foreach ($runtimeView in $runtimeViews) {
            $relativePath = $runtimeView.FullName.Substring($sourceRoot.Length + 1).Replace('\', '/')
            if (-not $contentPaths.Contains($relativePath)) { throw "Runtime view is not a Content include: $relativePath" }
        }
        foreach ($requiredAsset in @('Content/css/bootstrap5.min.css', 'Content/js/bootstrap5.bundle.min.js')) {
            if (-not $contentPaths.Contains($requiredAsset)) { throw "Runtime asset is not a Content include: $requiredAsset" }
        }
        Write-Output "Validated $validatedFiles published content files and $($runtimeViews.Count) Razor view/config inputs."
    } finally { $sha256.Dispose() }
}

$msbuild = Get-Command MSBuild.exe -ErrorAction SilentlyContinue
if ($msbuild) {
    $msbuildPath = $msbuild.Source
} elseif (Test-Path -LiteralPath $vswhere) {
    $msbuildPath = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
} else {
    throw 'Install Visual Studio with ASP.NET and web development before publishing.'
}
if (-not $msbuildPath) { throw 'MSBuild was not found.' }

& $msbuildPath $solution /t:Build /p:Configuration=Release /p:DeployOnBuild=true /p:PublishProfile=FolderProfile /m /nologo /verbosity:minimal
if ($LASTEXITCODE -ne 0) { throw 'Release publish failed.' }

$webConfigPath = Join-Path $outputPath 'Web.config'
if (-not (Test-Path -LiteralPath $webConfigPath)) { throw 'Published Web.config was not found.' }
[xml]$configuration = Get-Content -LiteralPath $webConfigPath
if ($configuration.configuration.'system.web'.compilation.debug -eq 'true') { throw 'Release package still enables debug.' }
$connection = $configuration.configuration.connectionStrings.add | Where-Object name -eq 'QuanLyBanHangEntities'
if ($connection.connectionString -notlike '*CONFIGURE_HOSTING_SQL_SERVER*') { throw 'Expected deployment connection placeholders were not generated.' }

Assert-PublishedContent -ProjectPath (Join-Path $repoRoot 'WebsiteBanHang\WebsiteBanHang.csproj') -PublishedRoot $outputPath

Compress-Archive -Path (Join-Path $outputPath '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
Write-Output "Published folder: $outputPath"
Write-Output "Deployment ZIP: $archivePath"
Write-Output 'Configure the hosting SQL connection in this local package before upload. HTTPS must be enabled before signing in.'
