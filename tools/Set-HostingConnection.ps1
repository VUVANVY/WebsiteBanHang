[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][string]$SqlUser,
    [Parameter(Mandatory = $true)][Security.SecureString]$SqlPassword
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputPath = Join-Path $repoRoot 'artifacts\publish'
$webConfigPath = Join-Path $outputPath 'Web.config'
if (-not (Test-Path -LiteralPath $webConfigPath)) { throw 'Run tools\Publish-Website.ps1 first.' }

$sqlBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$sqlBuilder['Data Source'] = $Server
$sqlBuilder['Initial Catalog'] = $Database
$sqlBuilder['User ID'] = $SqlUser
$sqlBuilder['Integrated Security'] = $false
$sqlBuilder['Encrypt'] = $true
$sqlBuilder['TrustServerCertificate'] = $false
$sqlBuilder['MultipleActiveResultSets'] = $true
$sqlBuilder['Application Name'] = 'MotoShop'
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlPassword)
try {
    $sqlBuilder['Password'] = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    $entityBuilder = [System.Data.Common.DbConnectionStringBuilder]::new()
    $entityBuilder['metadata'] = 'res://*/Models.QuanLyBanHangModel.csdl|res://*/Models.QuanLyBanHangModel.ssdl|res://*/Models.QuanLyBanHangModel.msl'
    $entityBuilder['provider'] = 'System.Data.SqlClient'
    $entityBuilder['provider connection string'] = $sqlBuilder.ConnectionString
    [xml]$configuration = Get-Content -LiteralPath $webConfigPath
    $connection = $configuration.configuration.connectionStrings.add | Where-Object name -eq 'QuanLyBanHangEntities'
    if (-not $connection) { throw 'Entity Framework connection entry was not found.' }
    $connection.SetAttribute('connectionString', $entityBuilder.ConnectionString)
    $configuration.Save($webConfigPath)
    Compress-Archive -Path (Join-Path $outputPath '*') -DestinationPath (Join-Path $repoRoot 'artifacts\MotoShop-publish.zip') -CompressionLevel Optimal -Force
    Write-Output 'Hosting SQL connection configured and local ZIP refreshed. Credentials were written only into the ignored artifacts directory.'
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    $sqlBuilder.Clear()
    if ($entityBuilder) { $entityBuilder.Clear() }
}
