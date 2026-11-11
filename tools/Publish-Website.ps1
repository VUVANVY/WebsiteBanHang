[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$solution = Join-Path $repoRoot 'WebsiteBanHang.sln'
$outputPath = Join-Path $repoRoot 'artifacts\publish'
$archivePath = Join-Path $repoRoot 'artifacts\MotoShop-publish.zip'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'

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

Compress-Archive -Path (Join-Path $outputPath '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
Write-Output "Published folder: $outputPath"
Write-Output "Deployment ZIP: $archivePath"
Write-Output 'Configure the hosting SQL connection in this local package before upload. HTTPS must be enabled before signing in.'
