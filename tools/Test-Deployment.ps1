[CmdletBinding()]
param([string]$SqlServer = '.\SQLEXPRESS', [string]$PublishedRoot)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$artifactsRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts'))
if ([string]::IsNullOrWhiteSpace($PublishedRoot)) { $PublishedRoot = Join-Path $artifactsRoot 'publish' }
$publishRoot = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PublishedRoot).Path)
$artifactsPrefix = $artifactsRoot.TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar
if (-not $publishRoot.StartsWith($artifactsPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not (Test-Path -LiteralPath $publishRoot -PathType Container)) {
    throw 'PublishedRoot must be a folder inside this workspace artifacts directory.'
}
$iisExe = Join-Path $env:ProgramFiles 'IIS Express\iisexpress.exe'
$iisTemplate = Join-Path $env:ProgramFiles 'IIS Express\AppServer\applicationhost.config'
if (-not (Test-Path -LiteralPath (Join-Path $publishRoot 'bin\WebsiteBanHang.dll'))) {
    throw 'Run tools\Publish-Website.ps1 before this integration check.'
}
if (-not (Test-Path -LiteralPath $iisExe) -or -not (Test-Path -LiteralPath $iisTemplate)) {
    throw 'IIS Express with .NET Framework support is required.'
}
$localServerPattern = '^(\.|localhost|' + [regex]::Escape($env:COMPUTERNAME) + ')(\\[A-Za-z0-9_]+)?$'
if ($SqlServer -notmatch $localServerPattern) {
    throw 'This harness accepts only a local SQL Server instance and always creates its own database.'
}

$runId = [guid]::NewGuid().ToString('N')
$databaseName = 'MotoShop_DeploymentTest_' + $runId
$testRoot = Join-Path $repoRoot ('artifacts\test-' + $runId)
$siteRoot = Join-Path $testRoot 'site'
$databaseCreatedByThisScript = $false
$iisProcess = $null
$iisStartedAt = $null
$checks = 0
$failedHttpResponses = 0
$failure = $null
$cleanupErrors = [System.Collections.Generic.List[string]]::new()
$sqlBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$sqlBuilder['Data Source'] = $SqlServer
$sqlBuilder['Integrated Security'] = $true
$sqlBuilder['Initial Catalog'] = 'master'
$sqlBuilder['Connect Timeout'] = 10
$sqlBuilder['Encrypt'] = $false
$sqlBuilder['TrustServerCertificate'] = $true
$masterConnectionString = $sqlBuilder.ConnectionString
$sqlBuilder['Initial Catalog'] = $databaseName
$sqlBuilder['MultipleActiveResultSets'] = $true
$testConnectionString = $sqlBuilder.ConnectionString

function Invoke-TestSql {
    param([string]$Sql, [hashtable]$Parameters = @{}, [switch]$Scalar)
    if (-not $databaseCreatedByThisScript -or $databaseName -notmatch '^MotoShop_DeploymentTest_[a-f0-9]{32}$') {
        throw 'The isolated test database has not been created by this run.'
    }
    $connection = [System.Data.SqlClient.SqlConnection]::new($testConnectionString)
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandTimeout = 90
        $command.CommandText = $Sql
        foreach ($name in $Parameters.Keys) {
            $null = $command.Parameters.AddWithValue('@' + $name, $Parameters[$name])
        }
        if ($Scalar) { return $command.ExecuteScalar() }
        $null = $command.ExecuteNonQuery()
    } finally { $connection.Dispose() }
}

function Assert-Check {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) { throw ('Check failed: ' + $Label) }
    $script:checks++
    Write-Output ('PASS ' + $Label)
}

function Send-TestRequest {
    param([string]$Path, [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
          [string]$Method = 'GET', [hashtable]$Body = @{}, [hashtable]$Files = @{})
    $request = [System.Net.HttpWebRequest]::CreateHttp($baseUrl + $Path)
    $request.Method = $Method
    $request.AllowAutoRedirect = $false
    $request.Proxy = $null
    $request.Timeout = 45000
    $request.ReadWriteTimeout = 45000
    $request.CookieContainer = $Session.Cookies
    if ($Method -eq 'POST') {
        if ($Files.Count -gt 0) {
            $boundary = 'MotoShopTest' + [guid]::NewGuid().ToString('N')
            $multipart = [IO.MemoryStream]::new()
            $writer = [IO.StreamWriter]::new($multipart, [Text.UTF8Encoding]::new($false), 1024, $true)
            try {
                foreach ($key in $Body.Keys) {
                    foreach ($value in @($Body[$key])) {
                        $writer.Write('--' + $boundary + "`r`nContent-Disposition: form-data; name=" + '"' + $key + '"' + "`r`n`r`n" + [string]$value + "`r`n")
                    }
                }
                foreach ($key in $Files.Keys) {
                    $file = $Files[$key]
                    $writer.Write('--' + $boundary + "`r`nContent-Disposition: form-data; name=" + '"' + $key + '"; filename="' + $file.Name + '"' + "`r`nContent-Type: " + $file.ContentType + "`r`n`r`n")
                    $writer.Flush()
                    $multipart.Write($file.Bytes, 0, $file.Bytes.Length)
                    $writer.Write("`r`n")
                }
                $writer.Write('--' + $boundary + "--`r`n")
                $writer.Flush()
                $bytes = $multipart.ToArray()
            } finally { $writer.Dispose(); $multipart.Dispose() }
            $request.ContentType = 'multipart/form-data; boundary=' + $boundary
        } else {
            $pairs = foreach ($key in $Body.Keys) {
                foreach ($value in @($Body[$key])) {
                    [uri]::EscapeDataString([string]$key) + '=' + [uri]::EscapeDataString([string]$value)
                }
            }
            $bytes = [Text.Encoding]::UTF8.GetBytes(($pairs -join '&'))
            $request.ContentType = 'application/x-www-form-urlencoded'
        }
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    $response = $null
    try { $response = $request.GetResponse() }
    catch [System.Net.WebException] {
        if (-not $_.Exception.Response) { throw }
        $response = $_.Exception.Response
    }
    try {
        $bodyBuffer = [IO.MemoryStream]::new()
        try {
            $response.GetResponseStream().CopyTo($bodyBuffer)
            $responseBytes = $bodyBuffer.ToArray()
        } finally { $bodyBuffer.Dispose() }
        if ([int]$response.StatusCode -ge 500 -and ($Method -eq 'GET' -or $Body.ContainsKey('__RequestVerificationToken'))) {
            $errorDirectory = Join-Path $testRoot 'http-errors'
            $null = New-Item -ItemType Directory -Path $errorDirectory -Force
            $safePath = ([regex]::Replace($Path, '[^A-Za-z0-9._-]', '_')).Trim('_')
            if (-not $safePath) { $safePath = 'homepage' }
            if ($safePath.Length -gt 100) { $safePath = $safePath.Substring(0, 100) }
            $script:failedHttpResponses++
            $errorFile = Join-Path $errorDirectory ('{0:000}-{1}-{2}.html' -f $script:failedHttpResponses, $Method, $safePath)
            [IO.File]::WriteAllBytes($errorFile, $responseBytes)
            Write-Host ('HTTP ' + [int]$response.StatusCode + ' ' + $Path + '; diagnostic response: ' + $errorFile)
        }
        return [pscustomobject]@{
            Status = [int]$response.StatusCode
            Content = [Text.Encoding]::UTF8.GetString($responseBytes)
            Bytes = $responseBytes
            ContentType = $response.ContentType
            Location = $response.Headers['Location']
        }
    } finally { if ($response) { $response.Dispose() } }
}

function Test-ImageSignature {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -lt 12) { return $false }
    $prefix = [BitConverter]::ToString($Bytes, 0, 12)
    return $prefix.StartsWith('FF-D8-FF') -or
        $prefix.StartsWith('89-50-4E-47-0D-0A-1A-0A') -or
        $prefix.StartsWith('47-49-46-38-37-61') -or
        $prefix.StartsWith('47-49-46-38-39-61') -or
        $prefix.StartsWith('42-4D') -or
        ($prefix.StartsWith('52-49-46-46') -and [BitConverter]::ToString($Bytes, 8, 4) -eq '57-45-42-50')
}

function Get-InputValue {
    param([string]$Html, [string]$Name)
    $inputMatch = [regex]::Match($Html, '<input\b[^>]*name\s*=\s*["'']' + [regex]::Escape($Name) + '["''][^>]*>', 'IgnoreCase')
    $valueMatch = [regex]::Match($inputMatch.Value, '\bvalue\s*=\s*["'']([^"'']*)["'']', 'IgnoreCase')
    if ($valueMatch.Success) { return [System.Net.WebUtility]::HtmlDecode($valueMatch.Groups[1].Value) }
    return $null
}

function Get-ProductLinks {
    param([string]$Html)
    $seen = @{}
    foreach ($anchor in [regex]::Matches($Html, '<a\b[^>]*\bhref\s*=\s*["'']([^"'']+)["'']', 'IgnoreCase')) {
        $path = [System.Net.WebUtility]::HtmlDecode($anchor.Groups[1].Value)
        $idMatch = [regex]::Match($path, '^/[^/?#]+-(?<id>\d+)(?:[?#]|$)')
        if ($idMatch.Success -and -not $seen.ContainsKey($idMatch.Groups['id'].Value)) {
            $seen[$idMatch.Groups['id'].Value] = $true
            [pscustomobject]@{ Id = [int]$idMatch.Groups['id'].Value; Path = $path }
        }
    }
}

function Assert-ProductResults {
    param($Response, [int[]]$ExpectedIds, [string]$Label)
    $actual = @(Get-ProductLinks -Html $Response.Content | Select-Object -ExpandProperty Id | Sort-Object -Unique)
    $expected = @($ExpectedIds | Sort-Object -Unique)
    $same = $actual.Count -eq $expected.Count
    if ($same -and $expected.Count -gt 0) { $same = @(Compare-Object $expected $actual).Count -eq 0 }
    Assert-Check ($Response.Status -eq 200 -and $same) ($Label + ' (HTTP ' + $Response.Status + '; IDs ' + ($actual -join ',') + ')')
}

function Submit-TestForm {
    param([Microsoft.PowerShell.Commands.WebRequestSession]$Session, [string]$FormPath,
          [string]$PostPath, [hashtable]$Body, [hashtable]$Files = @{})
    $fields = @{} + $Body
    $fields['__RequestVerificationToken'] = Get-TestToken -Session $Session -Path $FormPath
    return Send-TestRequest -Path $PostPath -Session $Session -Method POST -Body $fields -Files $Files
}

function Get-TestToken {
    param([Microsoft.PowerShell.Commands.WebRequestSession]$Session, [string]$Path = '/')
    $page = Send-TestRequest -Path $Path -Session $Session
    if ($page.Status -ne 200) { throw ('Cannot obtain form token from ' + $Path + ', HTTP ' + $page.Status) }
    $inputMatch = [regex]::Match($page.Content, '<input\b[^>]*name\s*=\s*["'']__RequestVerificationToken["''][^>]*>', 'IgnoreCase')
    $tokenMatch = [regex]::Match($inputMatch.Value, '\bvalue\s*=\s*["'']([^"'']+)["'']', 'IgnoreCase')
    if (-not $tokenMatch.Success) { throw ('Anti-forgery form token missing at ' + $Path) }
    return [System.Net.WebUtility]::HtmlDecode($tokenMatch.Groups[1].Value)
}

function New-LoginSession {
    param([string]$Username)
    $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $token = Get-TestToken -Session $session
    $reply = Send-TestRequest -Path '/Home/DangNhap' -Session $session -Method POST -Body @{
        txtTenDangNhap = $Username; txtMatKhau = $testPassword; __RequestVerificationToken = $token
    }
    $authCookie = $session.Cookies.GetCookies([uri]$baseUrl)['.ASPXAUTH']
    if ($reply.Status -ne 200 -or -not $authCookie -or -not $reply.Content.Contains('window.location.reload')) {
        throw 'The synthetic account could not sign in.'
    }
    return $session
}

try {
    $null = New-Item -ItemType Directory -Path $siteRoot -Force
    Copy-Item -Path (Join-Path $publishRoot '*') -Destination $siteRoot -Recurse -Force
    $master = [System.Data.SqlClient.SqlConnection]::new($masterConnectionString)
    try {
        $master.Open()
        $command = $master.CreateCommand()
        $command.CommandText = 'SELECT DB_ID(@name)'
        $null = $command.Parameters.AddWithValue('@name', $databaseName)
        if ($command.ExecuteScalar() -isnot [DBNull]) { throw 'Generated database name unexpectedly exists; nothing was changed.' }
        $command.Parameters.Clear()
        $command.CommandText = 'CREATE DATABASE [' + $databaseName + ']'
        $null = $command.ExecuteNonQuery()
        $databaseCreatedByThisScript = $true
    } finally { $master.Dispose() }
    Write-Output 'Created isolated temporary database; the existing application database is not used.'
    foreach ($file in '01-schema.sql', '02-seed-demo.sql', '03-verify-demo.sql') {
        $sqlText = [IO.File]::ReadAllText((Join-Path $repoRoot ('deployment\Database\' + $file)))
        foreach ($batch in [regex]::Split($sqlText, '(?im)^\s*GO\s*(?:--[^\r\n]*)?$')) {
            if (-not [string]::IsNullOrWhiteSpace($batch)) { Invoke-TestSql -Sql $batch }
        }
    }
    Assert-Check $true 'fresh synthetic schema, seed and foreign keys verified'

    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $siteRoot 'bin\WebsiteBanHang.dll'))
    $passwordType = $assembly.GetType('WebsiteBanHang.Security.PasswordService', $true)
    $testPassword = 'Deployment!' + [guid]::NewGuid().ToString('N')
    $passwordHash = $passwordType.GetMethod('Hash').Invoke($null, @($testPassword))
    $seedAccountSql = @'
INSERT dbo.ThanhVien (TaiKhoan,MatKhau,HoTen,DiaChi,Email,SoDienThoai,CauHoi,CauTraLoi,MaLoaiTV)
VALUES (@username,@hash,N'Deployment tester',N'Synthetic test address',N'test@example.invalid',N'0000000000',N'Test question',N'Test answer',3);
DECLARE @member int = CONVERT(int,SCOPE_IDENTITY());
INSERT dbo.KhachHang (TenKH,DiaChi,Email,SoDienThoai,MaThanhVien)
VALUES (N'Synthetic test customer',N'Test address',N'test@example.invalid',N'0000000000',@member);
DECLARE @customer int = CONVERT(int,SCOPE_IDENTITY());
INSERT dbo.DonDatHang (MaKH,NgayDat,TinhTrangGiaoHang,DaThanhToan,UuDai,DaHuy,DaXoa)
VALUES (@customer,GETDATE(),0,0,0,0,0);
DECLARE @order int = CONVERT(int,SCOPE_IDENTITY());
INSERT dbo.ChiTietDonDatHang (MaDDH,MaSP,TenSP,SoLuong,Dongia)
SELECT @order,MaSP,TenSP,1,DonGia FROM dbo.SanPham WHERE MaSP=1;
SELECT @order;
'@
    $orderA = [int](Invoke-TestSql -Sql $seedAccountSql -Parameters @{ username = 'deployment_a'; hash = $passwordHash } -Scalar)
    $orderB = [int](Invoke-TestSql -Sql $seedAccountSql -Parameters @{ username = 'deployment_b'; hash = $passwordHash } -Scalar)
    Invoke-TestSql -Sql "INSERT dbo.ThanhVien (TaiKhoan,MatKhau,HoTen,DiaChi,Email,SoDienThoai,CauHoi,CauTraLoi,MaLoaiTV) VALUES (N'deployment_admin',@hash,N'Deployment admin',N'Test',N'admin@example.invalid',N'0000000000',N'Test',N'Test',1);" -Parameters @{ hash = $passwordHash }
    $cancelOrder = [int](Invoke-TestSql -Sql 'INSERT dbo.DonDatHang (MaKH,NgayDat,TinhTrangGiaoHang,DaThanhToan,UuDai,DaHuy,DaXoa) SELECT MaKH,GETDATE(),0,0,0,0,0 FROM dbo.DonDatHang WHERE MaDDH=@source; SELECT CONVERT(int,SCOPE_IDENTITY());' -Parameters @{ source = $orderA } -Scalar)
    Invoke-TestSql -Sql 'INSERT dbo.ChiTietDonDatHang (MaDDH,MaSP,TenSP,SoLuong,Dongia) VALUES (@id,1,N''Deployment cancellation fixture'',2,10000000);' -Parameters @{ id = $cancelOrder }

    # Only the disposable site copy receives loopback database/cookie settings.
    [xml]$configuration = [IO.File]::ReadAllText((Join-Path $siteRoot 'Web.config'))
    $entityBuilder = [System.Data.Common.DbConnectionStringBuilder]::new()
    $entityBuilder['metadata'] = 'res://*/Models.QuanLyBanHangModel.csdl|res://*/Models.QuanLyBanHangModel.ssdl|res://*/Models.QuanLyBanHangModel.msl'
    $entityBuilder['provider'] = 'System.Data.SqlClient'
    $entityBuilder['provider connection string'] = $testConnectionString
    $entry = $configuration.configuration.connectionStrings.add | Where-Object name -eq 'QuanLyBanHangEntities'
    $entry.SetAttribute('connectionString', $entityBuilder.ConnectionString)
    $configuration.configuration.'system.web'.authentication.forms.SetAttribute('requireSSL', 'false')
    $configuration.configuration.'system.web'.httpCookies.SetAttribute('requireSSL', 'false')
    $testCustomErrors = $configuration.configuration.'system.web'.SelectSingleNode('customErrors')
    if (-not $testCustomErrors) {
        $testCustomErrors = $configuration.CreateElement('customErrors')
        $null = $configuration.configuration.'system.web'.AppendChild($testCustomErrors)
    }
    $testCustomErrors.SetAttribute('mode', 'Off')
    $configuration.Save((Join-Path $siteRoot 'Web.config'))

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port } finally { $listener.Stop() }
    $baseUrl = 'http://localhost:' + $port
    [xml]$appHost = [IO.File]::ReadAllText($iisTemplate)
    $site = $appHost.configuration.'system.applicationHost'.sites.site
    $site.SetAttribute('name', 'MotoShopDeploymentTest')
    $site.application.SetAttribute('applicationPool', 'Clr4IntegratedAppPool')
    $site.application.virtualDirectory.SetAttribute('physicalPath', $siteRoot)
    $site.bindings.binding.SetAttribute('bindingInformation', ('*:' + $port + ':localhost'))
    $appHostPath = Join-Path $testRoot 'applicationhost.config'
    $appHost.Save($appHostPath)
    $iisProcess = Start-Process -FilePath $iisExe -ArgumentList @('/config:' + $appHostPath, '/site:MotoShopDeploymentTest', '/systray:false') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'iis.stdout.log') -RedirectStandardError (Join-Path $testRoot 'iis.stderr.log')
    $iisStartedAt = $iisProcess.StartTime
    Write-Output ('Isolated fixture URL: ' + $baseUrl)
    Write-Output ('Isolated fixture logs: ' + $testRoot)
    $anonymous = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $homepageResult = $null
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        if ($iisProcess.HasExited) { throw 'The isolated IIS Express exited; inspect artifacts/test-*/iis.stderr.log.' }
        try { $homepageResult = Send-TestRequest -Path '/' -Session $anonymous; break }
        catch [System.Net.WebException] { Start-Sleep -Milliseconds 500 }
    }
    Assert-Check ($homepageResult -and $homepageResult.Status -eq 200 -and $homepageResult.Content.Contains('MotoShop')) 'published Razor homepage renders HTTP 200'
    $bootstrapCss = Send-TestRequest -Path '/Content/css/bootstrap5.min.css' -Session $anonymous
    Assert-Check ($bootstrapCss.Status -eq 200 -and $bootstrapCss.ContentType -match '^text/css\b' -and
        $bootstrapCss.Content -match '\bBootstrap\s+v5\.' -and $bootstrapCss.Content.Contains('--bs-')) 'published Bootstrap CSS is served as CSS with Bootstrap content'
    $bootstrapJs = Send-TestRequest -Path '/Content/js/bootstrap5.bundle.min.js' -Session $anonymous
    Assert-Check ($bootstrapJs.Status -eq 200 -and $bootstrapJs.ContentType -match '^(application|text)/(javascript|x-javascript|ecmascript)\b' -and
        $bootstrapJs.Content -match '\bBootstrap\s+v5\.' -and $bootstrapJs.Content.Contains('data-bs-')) 'published Bootstrap bundle is served as JavaScript with Bootstrap content'
    foreach ($layoutImagePath in '/Content/images/logo.png', '/Content/images/hero-main.jpg', '/Content/images/hero-banner-1.jpg', '/Content/images/hero-banner-2.jpg') {
        $layoutImage = Send-TestRequest -Path $layoutImagePath -Session $anonymous
        Assert-Check ($layoutImage.Status -eq 200 -and $layoutImage.ContentType -match '^image/' -and
            (Test-ImageSignature -Bytes $layoutImage.Bytes)) ('published layout image is served as an image: ' + $layoutImagePath)
    }

    $imageQuery = @'
SELECT CONVERT(nvarchar(max), (SELECT ImageName AS [text()]
FROM (
    SELECT HinhAnh AS ImageName FROM dbo.SanPham
    UNION SELECT HinhAnh1 FROM dbo.SanPham
    UNION SELECT HinhAnh2 FROM dbo.SanPham
    UNION SELECT HinhAnh3 FROM dbo.SanPham
    UNION SELECT HinhAnh4 FROM dbo.SanPham
) AS ProductImages
WHERE ImageName IS NOT NULL AND LEN(ImageName) > 0
ORDER BY ImageName
FOR XML PATH('image'), ROOT('images'), TYPE));
'@
    [xml]$imageList = [string](Invoke-TestSql -Sql $imageQuery -Scalar)
    $imageNodes = @($imageList.SelectNodes('/images/image'))
    Assert-Check ($imageNodes.Count -gt 0) 'seeded product image references are available for runtime checks'
    foreach ($imageNode in $imageNodes) {
        $imageName = $imageNode.InnerText
        $imagePath = '/Content/HinhAnhSP/' + [uri]::EscapeDataString($imageName)
        $imageResponse = Send-TestRequest -Path $imagePath -Session $anonymous
        Assert-Check ($imageResponse.Status -eq 200 -and $imageResponse.ContentType -match '^image/' -and
            (Test-ImageSignature -Bytes $imageResponse.Bytes)) ('published product image is served as an image: ' + $imageName)
    }
    $catalogueSql = @'
SELECT CONVERT(nvarchar(max), (SELECT MaSP AS [@id], MaLoaiSP AS [@category], MaNSX AS [@brand], TenSP AS [@name]
FROM dbo.SanPham WHERE DaXoa = 0 ORDER BY MaSP FOR XML PATH('product'), ROOT('products'), TYPE));
'@
    [xml]$catalogue = [string](Invoke-TestSql -Sql $catalogueSql -Scalar)
    $products = @($catalogue.SelectNodes('/products/product'))
    $catalogueCases = @()
    foreach ($category in 1, 2, 7) {
        $expected = @($products | Where-Object { [int]$_.GetAttribute('category') -eq $category } | Select-Object -First 6 | ForEach-Object { [int]$_.GetAttribute('id') })
        foreach ($action in 'SanPham', 'LoaiSanPham') {
            $catalogueCases += [pscustomobject]@{ Path = ('/SanPham/' + $action + '?MaLoaiSP=' + $category); Expected = $expected; Label = ($action + ' category ' + $category); Response = $null }
        }
    }
    $catalogueCases += [pscustomobject]@{ Path = '/SanPham/SanPham?MaLoaiSP=2&MaNSX=2'; Expected = @($products | Where-Object { $_.GetAttribute('category') -eq '2' -and $_.GetAttribute('brand') -eq '2' } | ForEach-Object { [int]$_.GetAttribute('id') }); Label = 'category and manufacturer filters intersect'; Response = $null }
    $catalogueCases += [pscustomobject]@{ Path = '/SanPham/SanPham?MaNSX=2'; Expected = @($products | Where-Object { $_.GetAttribute('brand') -eq '2' } | Select-Object -First 6 | ForEach-Object { [int]$_.GetAttribute('id') }); Label = 'manufacturer-only catalogue filter'; Response = $null }
    # Fetch all high-priority pages before asserting, so both listing/detail failures are captured.
    foreach ($case in $catalogueCases) { $case.Response = Send-TestRequest -Path $case.Path -Session $anonymous }
    $detailOne = Send-TestRequest -Path '/SanPham/XemChiTiet/1' -Session $anonymous
    $detailTwo = Send-TestRequest -Path '/SanPham/XemChiTiet/2' -Session $anonymous
    $slugTwo = @(Get-ProductLinks -Html $homepageResult.Content | Where-Object Id -eq 2 | Select-Object -First 1)
    $slugDetail = if ($slugTwo.Count) { Send-TestRequest -Path $slugTwo[0].Path -Session $anonymous } else { $null }
    foreach ($case in $catalogueCases) { Assert-ProductResults -Response $case.Response -ExpectedIds $case.Expected -Label $case.Label }
    $productTwoName = [string](Invoke-TestSql -Sql 'SELECT TenSP FROM dbo.SanPham WHERE MaSP=2;' -Scalar)
    Assert-Check ($detailOne.Status -eq 200 -and $detailTwo.Status -eq 200 -and [System.Net.WebUtility]::HtmlDecode($detailTwo.Content).Contains($productTwoName)) 'product details render by direct IDs1 and2'
    Assert-Check ($slugTwo.Count -eq 1 -and $slugDetail.Status -eq 200 -and [System.Net.WebUtility]::HtmlDecode($slugDetail.Content).Contains($productTwoName)) 'actual rendered product2 slug URL resolves to its detail page'
    $galleryImages = @([regex]::Matches($detailTwo.Content, '<img\b[^>]*\bsrc\s*=\s*["'']([^"'']*Content/HinhAnhSP/[^"'']+)["'']', 'IgnoreCase') | ForEach-Object { [System.Net.WebUtility]::HtmlDecode($_.Groups[1].Value) } | Sort-Object -Unique)
    Assert-Check ($galleryImages.Count -gt 0) 'product detail renders gallery image references'
    foreach ($galleryPath in $galleryImages) {
        $galleryReply = Send-TestRequest -Path $galleryPath -Session $anonymous
        Assert-Check ($galleryReply.Status -eq 200 -and (Test-ImageSignature -Bytes $galleryReply.Bytes)) 'product detail gallery image loads successfully'
    }
    Assert-Check ((Send-TestRequest -Path '/SanPham/XemChiTiet/2147483000' -Session $anonymous).Status -eq 404) 'nonexistent product returns404'
    Assert-Check ((Send-TestRequest -Path '/SanPham/XemChiTiet' -Session $anonymous).Status -eq 400) 'product detail withoutID returns400'

    $emptySearch = Send-TestRequest -Path '/TimKiem/KQTimKiem?sTuKhoa=' -Session $anonymous
    Assert-ProductResults -Response $emptySearch -ExpectedIds @() -Label 'empty search renders without product results'
    $exactSearch = Send-TestRequest -Path ('/TimKiem/KQTimKiem?sTuKhoa=' + [uri]::EscapeDataString($productTwoName)) -Session $anonymous
    Assert-ProductResults -Response $exactSearch -ExpectedIds @(2) -Label 'search finds exact product name'
    $noMatchSearch = Send-TestRequest -Path ('/TimKiem/KQTimKiem?sTuKhoa=no_match_' + $runId) -Session $anonymous
    Assert-ProductResults -Response $noMatchSearch -ExpectedIds @() -Label 'unmatched search renders an empty result page'
    $searchOne = Send-TestRequest -Path '/TimKiem/KQTimKiem?sTuKhoa=DEMO&page=1' -Session $anonymous
    $searchTwo = Send-TestRequest -Path '/TimKiem/KQTimKiem?sTuKhoa=DEMO&page=2' -Session $anonymous
    $firstSearchIds = @(Get-ProductLinks -Html $searchOne.Content | Select-Object -ExpandProperty Id)
    $secondSearchIds = @(Get-ProductLinks -Html $searchTwo.Content | Select-Object -ExpandProperty Id)
    $overlap = @($secondSearchIds | Where-Object { $_ -in $firstSearchIds })
    Assert-Check ($searchOne.Status -eq 200 -and $searchTwo.Status -eq 200 -and $firstSearchIds.Count -eq 6 -and $secondSearchIds.Count -eq 6 -and $overlap.Count -eq 0) 'search pagination returns distinct six-product pages'

    $registration = Send-TestRequest -Path '/Home/DangKy' -Session $anonymous
    Assert-Check ($registration.Status -eq 200 -and $registration.Content.Contains('Captcha')) 'registration form renders a CAPTCHA'
    $membersBeforeInvalidSignup = [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ThanhVien;' -Scalar)
    $invalidSignup = Send-TestRequest -Path '/Home/DangKy' -Session $anonymous -Method POST -Body @{
        __RequestVerificationToken = Get-InputValue -Html $registration.Content -Name '__RequestVerificationToken'
        CaptchaDeText = Get-InputValue -Html $registration.Content -Name 'CaptchaDeText'
        CaptchaInputText = 'definitely-not-the-captcha'; TaiKhoan = 'invalid_captcha_' + $runId.Substring(0,8)
        MatKhau = $testPassword; HoTen = 'Synthetic registration'; DiaChi = 'Test address'; Email = 'fixture@example.com'
        SoDienThoai = '0123456789'; CauHoi = 'Test question'; CauTraLoi = 'Test answer'
    }
    Assert-Check ($invalidSignup.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ThanhVien;' -Scalar) -eq $membersBeforeInvalidSignup) 'invalid CAPTCHA prevents account creation'
    foreach ($path in '/Home/PhanQuyen?Taikhoan=forged&Quyen=QuanTriWeb', '/ThongKe/PhanQuyen?Taikhoan=forged&Quyen=QuanTriWeb') {
        Assert-Check ((Send-TestRequest -Path $path -Session $anonymous).Status -eq 404) 'role-ticket helper cannot be routed'
    }
    foreach ($path in '/ThongKe/Index', '/ThongKe/DangkyAdmin', '/DonHang/Index') {
        Assert-Check ((Send-TestRequest -Path $path -Session $anonymous).Status -in @(302,401,403)) 'anonymous protected endpoint is denied'
    }
    $malformed = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $malformed.Cookies.Add([System.Net.Cookie]::new('.ASPXAUTH', 'invalid-auth-ticket', '/', 'localhost'))
    Assert-Check ((Send-TestRequest -Path '/' -Session $malformed).Status -eq 200) 'malformed authentication cookie does not cause HTTP 500'
    $noToken = Send-TestRequest -Path '/Home/DangNhap' -Session $anonymous -Method POST -Body @{ txtTenDangNhap = 'deployment_a'; txtMatKhau = $testPassword }
    Assert-Check ($noToken.Status -in @(302,400,403,500) -and -not $anonymous.Cookies.GetCookies([uri]$baseUrl)['.ASPXAUTH']) 'login without CSRF token is rejected'
    $anonymousToken = Get-TestToken -Session $anonymous
    $badLogin = Send-TestRequest -Path '/Home/DangNhap' -Session $anonymous -Method POST -Body @{ txtTenDangNhap = 'deployment_a'; txtMatKhau = 'Incorrect-' + $runId; __RequestVerificationToken = $anonymousToken }
    Assert-Check ($badLogin.Status -eq 200 -and -not $anonymous.Cookies.GetCookies([uri]$baseUrl)['.ASPXAUTH']) 'incorrect password does not create an authentication cookie'
    $null = Send-TestRequest -Path '/GioHang/ThemGioHangAjax' -Session $anonymous -Method POST -Body @{ MaSP = 3; __RequestVerificationToken = $anonymousToken }
    $ordersBeforeAnonymousCheckout = [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang;' -Scalar)
    $anonymousCheckout = Send-TestRequest -Path '/GioHang/DatHang' -Session $anonymous -Method POST -Body @{ __RequestVerificationToken = $anonymousToken }
    Assert-Check ($anonymousCheckout.Status -in @(302,401,403) -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang;' -Scalar) -eq $ordersBeforeAnonymousCheckout) 'anonymous checkout cannot create an order'

    $sessionA = New-LoginSession 'deployment_a'
    $tokenA = Get-TestToken $sessionA
    foreach ($state in '', 'chuatt', 'hoanthanh') {
        $ordersPage = Send-TestRequest -Path ('/DonHang/Index?trangThai=' + $state) -Session $sessionA
        $visibleOrders = @([regex]::Matches($ordersPage.Content, '<td>\s*#(?<id>\d+)\s*</td>') | ForEach-Object { [int]$_.Groups['id'].Value })
        Assert-Check ($ordersPage.Status -eq 200 -and $orderB -notin $visibleOrders) ('customer order list/filter renders without foreign orders: ' + $state)
    }
    Assert-Check ((Send-TestRequest -Path ('/DonHang/ChiTiet/' + $orderA) -Session $sessionA).Status -eq 200) 'signed-in member can view own order Razor page'
    Assert-Check ((Send-TestRequest -Path ('/DonHang/XuatHoaDon/' + $orderA) -Session $sessionA).Content.StartsWith('%PDF-')) 'own invoice is generated as PDF'
    foreach ($path in ('/DonHang/ChiTiet/' + $orderB), ('/DonHang/XuatHoaDon/' + $orderB)) {
        Assert-Check ((Send-TestRequest -Path $path -Session $sessionA).Status -eq 404) 'foreign order and invoice return 404'
    }
    foreach ($action in 'ThanhToan', 'HuyDon') {
        Assert-Check ((Send-TestRequest -Path ('/DonHang/' + $action + '/' + $orderB) -Session $sessionA -Method POST -Body @{ __RequestVerificationToken = $tokenA }).Status -eq 404) 'foreign order mutation returns 404'
        Assert-Check ((Send-TestRequest -Path ('/DonHang/' + $action + '/' + $orderA) -Session $sessionA).Status -eq 404) 'GET cannot mutate customer order'
    }
    Assert-Check ([int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang WHERE MaDDH=@id AND DaThanhToan=0 AND DaHuy=0;' -Parameters @{ id = $orderB } -Scalar) -eq 1) 'foreign order remains unchanged'
    $withoutToken = Send-TestRequest -Path ('/DonHang/ThanhToan/' + $orderA) -Session $sessionA -Method POST
    Assert-Check ($withoutToken.Status -in @(302,400,403,500) -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang WHERE MaDDH=@id AND DaThanhToan=0;' -Parameters @{ id = $orderA } -Scalar) -eq 1) 'customer state change requires CSRF token'
    $null = Send-TestRequest -Path ('/DonHang/ThanhToan/' + $orderA) -Session $sessionA -Method POST -Body @{ __RequestVerificationToken = $tokenA }
    Assert-Check ([int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang WHERE MaDDH=@id AND DaThanhToan=1;' -Parameters @{ id = $orderA } -Scalar) -eq 1) 'owned demo payment status can be updated'
    $stockBefore = [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=1;' -Scalar)
    for ($repeat = 0; $repeat -lt 2; $repeat++) {
        $null = Send-TestRequest -Path ('/DonHang/HuyDon/' + $cancelOrder) -Session $sessionA -Method POST -Body @{ __RequestVerificationToken = $tokenA }
    }
    Assert-Check ([int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang WHERE MaDDH=@id AND DaHuy=1;' -Parameters @{ id = $cancelOrder } -Scalar) -eq 1 -and [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=1;' -Scalar) -eq $stockBefore) 'repeated cancellation does not inflate stock'
    Assert-Check ((Send-TestRequest -Path '/ThongKe/DangkyAdmin' -Session $sessionA).Status -in @(302,401,403)) 'customer cannot open admin registration'
    $adminSignup = Send-TestRequest -Path '/ThongKe/DangkyAdmin' -Session $sessionA -Method POST -Body @{ __RequestVerificationToken = $tokenA; TaiKhoan = 'forged_admin'; MatKhau = $testPassword; HoTen = 'Deployment fixture'; DiaChi = 'Demo'; Email = 'fixture@example.invalid'; SoDienThoai = '0000000000'; CauHoi = 'Demo'; CauTraLoi = 'Demo' }
    Assert-Check ($adminSignup.Status -in @(302,401,403) -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ThanhVien;' -Scalar) -eq 3) 'customer cannot create an administrator'

    Assert-Check ((Send-TestRequest -Path '/GioHang/XemGioHang' -Session $sessionA).Status -eq 200) 'empty cart Razor page renders'
    $blockedAdd = Send-TestRequest -Path '/GioHang/ThemGioHangAjax' -Session $sessionA -Method POST -Body @{ MaSP = 1 }
    Assert-Check ($blockedAdd.Status -in @(302,400,403,500)) 'cart mutation without CSRF token is rejected'
    $added = Send-TestRequest -Path '/GioHang/ThemGioHangAjax' -Session $sessionA -Method POST -Body @{ MaSP = 1; __RequestVerificationToken = $tokenA }
    $cartResult = $added.Content | ConvertFrom-Json
    Assert-Check ($added.Status -eq 200 -and $cartResult.success -and $cartResult.total -eq 1) 'valid AJAX add creates a one-item cart'
    Assert-Check ((Send-TestRequest -Path '/GioHang/SuaGioHang?MaSP=1' -Session $sessionA).Status -eq 200) 'cart editing Razor page renders'
    $updatedCart = Send-TestRequest -Path '/GioHang/CapNhatGioHang' -Session $sessionA -Method POST -Body @{ MaSP = 1; SoLuong = 2; DonGia = 1; ThanhTien = 1; __RequestVerificationToken = $tokenA }
    $cartEdit = Send-TestRequest -Path '/GioHang/SuaGioHang?MaSP=1' -Session $sessionA
    Assert-Check ($updatedCart.Status -eq 302 -and (Get-InputValue -Html $cartEdit.Content -Name 'SoLuong') -eq '2') 'valid cart quantity update persists server-side'
    $null = Send-TestRequest -Path '/GioHang/CapNhatGioHang' -Session $sessionA -Method POST -Body @{ MaSP = 1; SoLuong = 999999; __RequestVerificationToken = $tokenA }
    $cartEdit = Send-TestRequest -Path '/GioHang/SuaGioHang?MaSP=1' -Session $sessionA
    Assert-Check ((Get-InputValue -Html $cartEdit.Content -Name 'SoLuong') -eq '2') 'quantity above stock does not change the cart'
    $null = Send-TestRequest -Path '/GioHang/XoaGioHang' -Session $sessionA -Method POST -Body @{ MaSP = 1 }
    Assert-Check ((Send-TestRequest -Path '/GioHang/SuaGioHang?MaSP=1' -Session $sessionA).Status -eq 200) 'cart removal without CSRF token is rejected'
    $removedCart = Send-TestRequest -Path '/GioHang/XoaGioHang' -Session $sessionA -Method POST -Body @{ MaSP = 1; __RequestVerificationToken = $tokenA }
    Assert-Check ($removedCart.Status -eq 302 -and (Send-TestRequest -Path '/GioHang/SuaGioHang?MaSP=1' -Session $sessionA).Status -eq 404) 'valid cart removal removes the selected product'
    $readded = Send-TestRequest -Path '/GioHang/ThemGioHangAjax' -Session $sessionA -Method POST -Body @{ MaSP = 1; __RequestVerificationToken = $tokenA }
    Assert-Check (($readded.Content | ConvertFrom-Json).total -eq 1) 'cart can add again after removal'
    $null = Send-TestRequest -Path '/GioHang/CapNhatGioHang' -Session $sessionA -Method POST -Body @{ MaSP = 1; SoLuong = -1; __RequestVerificationToken = $tokenA }
    Invoke-TestSql -Sql 'UPDATE dbo.SanPham SET SoLuongTon=0 WHERE MaSP=2; UPDATE dbo.SanPham SET DonGia=12345000 WHERE MaSP=1;'
    $outOfStock = Send-TestRequest -Path '/GioHang/ThemGioHangAjax' -Session $sessionA -Method POST -Body @{ MaSP = 2; __RequestVerificationToken = $tokenA }
    Assert-Check ($outOfStock.Status -eq 409 -and -not ($outOfStock.Content | ConvertFrom-Json).success) 'out-of-stock product cannot be added'
    $beforeCheckout = [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang;' -Scalar)
    $checkout = Send-TestRequest -Path '/GioHang/DatHang' -Session $sessionA -Method POST -Body @{ __RequestVerificationToken = $tokenA; DonGia = 1; ThanhTien = 1 }
    Assert-Check ($checkout.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang;' -Scalar) -eq ($beforeCheckout + 1)) 'checkout creates exactly one order'
    Assert-Check ([int](Invoke-TestSql -Sql "SELECT COUNT(*) FROM dbo.ChiTietDonDatHang WHERE MaDDH=(SELECT MAX(MaDDH) FROM dbo.DonDatHang) AND MaSP=1 AND SoLuong=1 AND Dongia=12345000;" -Scalar) -eq 1) 'checkout rejects negative cart quantity and uses fresh database price'
    $emptyAgain = Send-TestRequest -Path '/GioHang/DatHang' -Session $sessionA -Method POST -Body @{ __RequestVerificationToken = $tokenA }
    Assert-Check ($emptyAgain.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang;' -Scalar) -eq ($beforeCheckout + 1)) 'empty checkout creates no order'

    $sessionB = New-LoginSession 'deployment_b'
    Assert-Check ((Send-TestRequest -Path ('/DonHang/ChiTiet/' + $orderB) -Session $sessionB).Status -eq 200 -and (Send-TestRequest -Path ('/DonHang/ChiTiet/' + $orderA) -Session $sessionB).Status -eq 404) 'second member is restricted to own orders'
    $admin = New-LoginSession 'deployment_admin'
    $adminToken = Get-TestToken -Session $admin -Path ('/QuanLyDonHang/DuyetDonHang/' + $orderA)
    Assert-Check ((Send-TestRequest -Path '/ThongKe/Index' -Session $admin).Status -eq 200) 'authorized admin dashboard Razor page renders'
    Assert-Check ((Send-TestRequest -Path ('/QuanLyDonHang/GiaoHang/' + $orderA) -Session $admin).Status -eq 404) 'GET cannot change admin delivery state'
    $null = Send-TestRequest -Path ('/QuanLyDonHang/GiaoHang/' + $orderA) -Session $admin -Method POST -Body @{ __RequestVerificationToken = $adminToken }
    Assert-Check ([int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.DonDatHang WHERE MaDDH=@id AND TinhTrangGiaoHang=1;' -Parameters @{ id = $orderA } -Scalar) -eq 1) 'admin delivery POST works with authorization and CSRF token'
    $completedOrders = Send-TestRequest -Path '/DonHang/Index?trangThai=hoanthanh' -Session $sessionA
    Assert-Check ($completedOrders.Status -eq 200 -and $completedOrders.Content -match ('<td>\s*#' + $orderA + '\s*</td>')) 'completed customer order filter shows the delivered owned order'

    $memberAId = [int](Invoke-TestSql -Sql "SELECT MaThanhVien FROM dbo.ThanhVien WHERE TaiKhoan=N'deployment_a';" -Scalar)
    $adminReadPaths = @(
        '/QuanLySanPham/Index', '/QuanLySanPham/TaoMoi', '/QuanLySanPham/ChinhSua/1', '/QuanLySanPham/UploadHinh/1',
        '/QuanLyLoai/Index', '/QuanLyLoai/TaoMoi', '/QuanLyLoai/ChinhSua/1', '/QuanLyLoai/Xoa/1',
        '/QuanLyNhaSX/Index', '/QuanLyNhaSX/TaoMoi', '/QuanLyNhaSX/ChinhSua/1', '/QuanLyNhaSX/Xoa/1',
        '/QuanLyQuyen/Index', '/QuanLyQuyen/TaoMoi', '/QuanLyQuyen/ChinhSua/QuanLy', '/QuanLyQuyen/Xoa/QuanLy',
        '/PhanQuyen/Index', '/PhanQuyen/PhanQuyen/1', '/ThongKe/DangkyAdmin',
        '/QuanLyThanhVien/Index', '/QuanLyThanhVien/TaoMoi', ('/QuanLyThanhVien/ChinhSua/' + $memberAId), ('/QuanLyThanhVien/Xoa/' + $memberAId),
        '/QuanLyPhieuNhap/DSSPHetHang', '/QuanLyPhieuNhap/NhapHang', '/QuanLyPhieuNhap/NhapHangDon/1',
        '/QuanLyDonHang/ChuaThanhToan', '/QuanLyDonHang/ChuaGiao', '/QuanLyDonHang/DaGiaoDaThanhToan', ('/QuanLyDonHang/DuyetDonHang/' + $orderA)
    )
    $adminReadResults = foreach ($path in $adminReadPaths) { [pscustomobject]@{ Path = $path; Reply = Send-TestRequest -Path $path -Session $admin } }
    foreach ($result in $adminReadResults) {
        Assert-Check ($result.Reply.Status -eq 200) ('authorized admin read page renders: ' + $result.Path)
        $postForms = @([regex]::Matches($result.Reply.Content, '<form\b(?<attrs>[^>]*)>(?<body>[\s\S]*?)</form>', 'IgnoreCase') | Where-Object { $_.Groups['attrs'].Value -match '\bmethod\s*=\s*["'']?post\b' })
        if ($postForms.Count -gt 0) {
            $missingFormTokens = @($postForms | Where-Object { -not (Get-InputValue -Html $_.Groups['body'].Value -Name '__RequestVerificationToken') })
            Assert-Check ($missingFormTokens.Count -eq 0) ('every rendered admin POST form contains its own CSRF token: ' + $result.Path)
        }
    }
    $lowStockPage = @($adminReadResults | Where-Object Path -eq '/QuanLyPhieuNhap/DSSPHetHang')[0].Reply
    Assert-Check ([System.Net.WebUtility]::HtmlDecode($lowStockPage.Content).Contains($productTwoName)) 'low-stock administration includes the out-of-stock seeded product'
    foreach ($path in '/QuanLySanPham/Index', '/QuanLyThanhVien/Index', '/QuanLyQuyen/Index', '/PhanQuyen/Index', '/QuanLyPhieuNhap/NhapHang') {
        Assert-Check ((Send-TestRequest -Path $path -Session $sessionA).Status -in @(302,401,403)) ('customer cannot open admin page: ' + $path)
    }
    $lookupCases = @(
        @{ Controller = 'QuanLyLoai'; Table = 'LoaiSanPham'; Key = 'MaLoaiSP'; Name = 'TenLoai'; Maximum = 150; Extra = @{ BiDanh = 'deployment-category'; Icon = 'fas fa-motorcycle' } },
        @{ Controller = 'QuanLyNhaSX'; Table = 'NhaSanXuat'; Key = 'MaNSX'; Name = 'TenNSX'; Maximum = 100; Extra = @{ ThongTin = 'Synthetic deployment manufacturer' } },
        @{ Controller = 'QuanLyQuyen'; Table = 'Quyen'; Key = 'MaQuyen'; Name = 'TenQuyen'; Maximum = 100; Extra = @{ MaQuyen = 'Deployment_' + $runId.Substring(0,8) } }
    )
    foreach ($lookup in $lookupCases) {
        $createPath = '/' + $lookup.Controller + '/TaoMoi'
        $label = 'Deployment ' + $lookup.Table + ' ' + $runId.Substring(0,8)
        $body = @{} + $lookup.Extra
        $body[$lookup.Name] = $label
        $beforeRows = [int](Invoke-TestSql -Sql ('SELECT COUNT(*) FROM dbo.[' + $lookup.Table + '];') -Scalar)
        $missingToken = Send-TestRequest -Path $createPath -Session $admin -Method POST -Body $body
        Assert-Check ($missingToken.Status -in @(302,400,403,500) -and [int](Invoke-TestSql -Sql ('SELECT COUNT(*) FROM dbo.[' + $lookup.Table + '];') -Scalar) -eq $beforeRows) ($lookup.Controller + ' creation requires CSRF token')
        $invalidBody = @{} + $body
        $invalidBody[$lookup.Name] = ''
        $invalid = Submit-TestForm -Session $admin -FormPath $createPath -PostPath $createPath -Body $invalidBody
        Assert-Check ($invalid.Status -eq 200 -and [int](Invoke-TestSql -Sql ('SELECT COUNT(*) FROM dbo.[' + $lookup.Table + '];') -Scalar) -eq $beforeRows) ($lookup.Controller + ' rejects blank names without inserting')
        $invalidBody[$lookup.Name] = 'X' * ($lookup.Maximum + 1)
        $tooLong = Submit-TestForm -Session $admin -FormPath $createPath -PostPath $createPath -Body $invalidBody
        Assert-Check ($tooLong.Status -eq 200 -and [int](Invoke-TestSql -Sql ('SELECT COUNT(*) FROM dbo.[' + $lookup.Table + '];') -Scalar) -eq $beforeRows) ($lookup.Controller + ' enforces mapped name length')
        $createdLookup = Submit-TestForm -Session $admin -FormPath $createPath -PostPath $createPath -Body $body
        $lookupId = [string](Invoke-TestSql -Sql ('SELECT [' + $lookup.Key + '] FROM dbo.[' + $lookup.Table + '] WHERE [' + $lookup.Name + ']=@name;') -Parameters @{ name = $label } -Scalar)
        Assert-Check ($createdLookup.Status -eq 302 -and -not [string]::IsNullOrWhiteSpace($lookupId)) ($lookup.Controller + ' creates a synthetic row')
        $editPath = '/' + $lookup.Controller + '/ChinhSua/' + [uri]::EscapeDataString($lookupId)
        $body[$lookup.Key] = $lookupId
        $body[$lookup.Name] = $label + ' updated'
        $changedLookup = Submit-TestForm -Session $admin -FormPath $editPath -PostPath $editPath -Body $body
        Assert-Check ($changedLookup.Status -eq 302 -and [string](Invoke-TestSql -Sql ('SELECT [' + $lookup.Name + '] FROM dbo.[' + $lookup.Table + '] WHERE [' + $lookup.Key + ']=@id;') -Parameters @{ id = $lookupId } -Scalar) -eq $body[$lookup.Name]) ($lookup.Controller + ' persists an edited name')
        $invalidBody = @{} + $body
        $invalidBody[$lookup.Name] = ''
        $invalidEdit = Submit-TestForm -Session $admin -FormPath $editPath -PostPath $editPath -Body $invalidBody
        Assert-Check ($invalidEdit.Status -eq 200 -and [string](Invoke-TestSql -Sql ('SELECT [' + $lookup.Name + '] FROM dbo.[' + $lookup.Table + '] WHERE [' + $lookup.Key + ']=@id;') -Parameters @{ id = $lookupId } -Scalar) -eq $body[$lookup.Name]) ($lookup.Controller + ' invalid edit leaves the row unchanged')

        if ($lookup.Table -eq 'Quyen') {
            $groupId = [int](Invoke-TestSql -Sql "INSERT dbo.LoaiThanhVien(TenLoai,UuDai) VALUES(N'Deployment permission fixture',0); SELECT CONVERT(int,SCOPE_IDENTITY());" -Scalar)
            $permissionPath = '/PhanQuyen/PhanQuyen/' + $groupId
            $assigned = Submit-TestForm -Session $admin -FormPath $permissionPath -PostPath $permissionPath -Body @{ MaLTV = $groupId; selectedPermissions = @($lookupId, $lookupId) }
            Assert-Check ($assigned.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.LoaiThanhVien_Quyen WHERE MaLoaiTV=@group AND MaQuyen=@right;' -Parameters @{ group = $groupId; right = $lookupId } -Scalar) -eq 1) 'role assignment stores one link for duplicate checkbox values'
            $badRights = Submit-TestForm -Session $admin -FormPath $permissionPath -PostPath $permissionPath -Body @{ MaLTV = $groupId; selectedPermissions = @('Unknown_' + $runId.Substring(0,8)) }
            Assert-Check ($badRights.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.LoaiThanhVien_Quyen WHERE MaLoaiTV=@group AND MaQuyen=@right;' -Parameters @{ group = $groupId; right = $lookupId } -Scalar) -eq 1) 'invalid role selection does not erase existing rights'
            $referencedPath = '/QuanLyQuyen/Xoa/' + $lookupId
            $referencedDelete = Submit-TestForm -Session $admin -FormPath $referencedPath -PostPath $referencedPath -Body @{ id = $lookupId }
            Assert-Check ($referencedDelete.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.Quyen WHERE MaQuyen=@right;' -Parameters @{ right = $lookupId } -Scalar) -eq 1) 'permission referenced by a role cannot be deleted'
            $cleared = Submit-TestForm -Session $admin -FormPath $permissionPath -PostPath $permissionPath -Body @{ MaLTV = $groupId }
            Assert-Check ($cleared.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.LoaiThanhVien_Quyen WHERE MaLoaiTV=@group;' -Parameters @{ group = $groupId } -Scalar) -eq 0) 'unchecking every permission clears only the selected fixture role'
            Invoke-TestSql -Sql 'DELETE dbo.LoaiThanhVien WHERE MaLoaiTV=@group;' -Parameters @{ group = $groupId }
        } else {
            $referencedPath = '/' + $lookup.Controller + '/Xoa/1'
            $referencedDelete = Submit-TestForm -Session $admin -FormPath $referencedPath -PostPath $referencedPath -Body @{ id = 1 }
            Assert-Check ($referencedDelete.Status -eq 200 -and [int](Invoke-TestSql -Sql ('SELECT COUNT(*) FROM dbo.[' + $lookup.Table + '] WHERE [' + $lookup.Key + ']=1;') -Scalar) -eq 1) ($lookup.Controller + ' preserves rows referenced by products')
        }
        $deletePath = '/' + $lookup.Controller + '/Xoa/' + [uri]::EscapeDataString($lookupId)
        $deletedLookup = Submit-TestForm -Session $admin -FormPath $deletePath -PostPath $deletePath -Body @{ id = $lookupId }
        Assert-Check ($deletedLookup.Status -eq 302 -and [int](Invoke-TestSql -Sql ('SELECT COUNT(*) FROM dbo.[' + $lookup.Table + '] WHERE [' + $lookup.Key + ']=@id;') -Parameters @{ id = $lookupId } -Scalar) -eq 0) ($lookup.Controller + ' deletes an unreferenced synthetic row')
        Assert-Check ((Send-TestRequest -Path $editPath -Session $admin).Status -eq 404) ($lookup.Controller + ' missing edit target returns404')
    }

    $memberName = 'deployment_member_' + $runId.Substring(0,8)
    $memberFields = @{ TaiKhoan = $memberName; MatKhau = $testPassword; HoTen = 'Synthetic managed member'; DiaChi = 'Test address'; Email = 'fixture@example.com'; SoDienThoai = '0123456789'; CauHoi = 'Test question'; CauTraLoi = 'Test answer'; MaLoaiTV = 3 }
    $createdMember = Submit-TestForm -Session $admin -FormPath '/QuanLyThanhVien/TaoMoi' -PostPath '/QuanLyThanhVien/TaoMoi' -Body $memberFields
    $createdMemberId = [int](Invoke-TestSql -Sql 'SELECT MaThanhVien FROM dbo.ThanhVien WHERE TaiKhoan=@name;' -Parameters @{ name = $memberName } -Scalar)
    $createdMemberHash = [string](Invoke-TestSql -Sql 'SELECT MatKhau FROM dbo.ThanhVien WHERE MaThanhVien=@id;' -Parameters @{ id = $createdMemberId } -Scalar)
    Assert-Check ($createdMember.Status -eq 302 -and $createdMemberId -gt 0 -and $createdMemberHash.StartsWith('PBKDF2-SHA256$')) 'admin member creation persists a salted password hash'
    $newMemberSession = New-LoginSession $memberName
    Assert-Check ((Send-TestRequest -Path '/DonHang/Index' -Session $newMemberSession).Status -eq 200) 'newly managed customer can sign in and view an empty order list'
    $duplicateMember = Submit-TestForm -Session $admin -FormPath '/QuanLyThanhVien/TaoMoi' -PostPath '/QuanLyThanhVien/TaoMoi' -Body $memberFields
    Assert-Check ($duplicateMember.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ThanhVien WHERE TaiKhoan=@name;' -Parameters @{ name = $memberName } -Scalar) -eq 1) 'duplicate managed username does not create a second account'
    $memberEditPath = '/QuanLyThanhVien/ChinhSua/' + $createdMemberId
    $memberEditPage = Send-TestRequest -Path $memberEditPath -Session $admin
    Assert-Check ($memberEditPage.Status -eq 200 -and -not $memberEditPage.Content.Contains($createdMemberHash)) 'member edit page does not expose the stored password hash'
    $memberFields.MaThanhVien = $createdMemberId
    $memberFields.MatKhau = ''
    $memberFields.HoTen = 'Synthetic member updated'
    $memberEdited = Submit-TestForm -Session $admin -FormPath $memberEditPath -PostPath $memberEditPath -Body $memberFields
    Assert-Check ($memberEdited.Status -eq 302 -and [string](Invoke-TestSql -Sql 'SELECT HoTen FROM dbo.ThanhVien WHERE MaThanhVien=@id;' -Parameters @{ id = $createdMemberId } -Scalar) -eq $memberFields.HoTen -and [string](Invoke-TestSql -Sql 'SELECT MatKhau FROM dbo.ThanhVien WHERE MaThanhVien=@id;' -Parameters @{ id = $createdMemberId } -Scalar) -eq $createdMemberHash) 'member update with blank password preserves the original hash'
    $memberDeletePath = '/QuanLyThanhVien/Xoa/' + $createdMemberId
    $memberDeleted = Submit-TestForm -Session $admin -FormPath $memberDeletePath -PostPath $memberDeletePath -Body @{ id = $createdMemberId }
    Assert-Check ($memberDeleted.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ThanhVien WHERE MaThanhVien=@id;' -Parameters @{ id = $createdMemberId } -Scalar) -eq 0) 'admin can delete the unreferenced synthetic member'

    $managerName = 'deployment_manager_' + $runId.Substring(0,8)
    $managerFields = @{ TaiKhoan = $managerName; MatKhau = $testPassword; HoTen = 'Synthetic manager'; DiaChi = 'Test address'; Email = 'manager@example.com'; SoDienThoai = '0123456789'; CauHoi = 'Test question'; CauTraLoi = 'Test answer' }
    $createdManager = Submit-TestForm -Session $admin -FormPath '/ThongKe/DangkyAdmin' -PostPath '/ThongKe/DangkyAdmin' -Body $managerFields
    Assert-Check ($createdManager.Status -in @(200,302) -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ThanhVien WHERE TaiKhoan=@name AND MaLoaiTV=2;' -Parameters @{ name = $managerName } -Scalar) -eq 1) 'owner administrator can create a manager account'
    $managerSession = New-LoginSession $managerName
    Assert-Check ((Send-TestRequest -Path '/ThongKe/Index' -Session $managerSession).Status -eq 200 -and (Send-TestRequest -Path '/QuanLyThanhVien/Index' -Session $managerSession).Status -in @(302,401,403)) 'manager can view dashboard but cannot manage owner-only member settings'

    $fileBytes = [IO.File]::ReadAllBytes((Join-Path $siteRoot 'Content\HinhAnhSP\download.jpg'))
    $mainUpload = 'deployment-main-' + $runId + '.jpg'
    $productName = 'Deployment product ' + $runId.Substring(0,8)
    $productFields = @{ TenSP = $productName; DonGia = 20000000; SoLuongTon = 4; LuotXem = 0; Moi = 1; MaNCC = 1; MaLoaiSP = 1; MaNSX = 1; DongCo = 'Synthetic engine'; MoTa = 'Synthetic deployment product.' }
    $productsBeforeInvalidPosts = [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.SanPham;' -Scalar)
    foreach ($invalidFields in @(@{ TenSP = '' }, @{ DonGia = '' }, @{ DonGia = -1 }, @{ SoLuongTon = -1 }, @{ SoLuongTon = 'not-an-integer' })) {
        $invalidProduct = @{} + $productFields
        foreach ($key in $invalidFields.Keys) { $invalidProduct[$key] = $invalidFields[$key] }
        $badProductReply = Submit-TestForm -Session $admin -FormPath '/QuanLySanPham/TaoMoi' -PostPath '/QuanLySanPham/TaoMoi' -Body $invalidProduct
        Assert-Check ($badProductReply.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.SanPham;' -Scalar) -eq $productsBeforeInvalidPosts) ('invalid product creation is rejected without insert: ' + ($invalidFields.Keys -join ','))
    }
    $createdProduct = Submit-TestForm -Session $admin -FormPath '/QuanLySanPham/TaoMoi' -PostPath '/QuanLySanPham/TaoMoi' -Body $productFields -Files @{
        HinhAnh = @{ Name = $mainUpload; ContentType = 'image/jpeg'; Bytes = $fileBytes }
    }
    $createdProductId = [int](Invoke-TestSql -Sql 'SELECT MaSP FROM dbo.SanPham WHERE TenSP=@name;' -Parameters @{ name = $productName } -Scalar)
    Assert-Check ($createdProduct.Status -eq 302 -and $createdProductId -gt 0 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.SanPham WHERE MaSP=@id AND HinhAnh=@main AND DaXoa=0;' -Parameters @{ id = $createdProductId; main = $mainUpload } -Scalar) -eq 1) 'main-image-only multipart product creation persists the product and image name'
    foreach ($imageName in @($mainUpload)) {
        $uploadedImage = Send-TestRequest -Path ('/Content/HinhAnhSP/' + $imageName) -Session $anonymous
        Assert-Check ($uploadedImage.Status -eq 200 -and (Test-ImageSignature -Bytes $uploadedImage.Bytes)) 'new product upload is served as an actual image'
    }
    $mainOnlyDetail = Send-TestRequest -Path ('/SanPham/XemChiTiet/' + $createdProductId) -Session $anonymous
    $mainImageTag = [regex]::Match($mainOnlyDetail.Content, '<img\b[^>]*\bid\s*=\s*["'']mainImg["''][^>]*>', 'IgnoreCase').Value
    Assert-Check ($mainOnlyDetail.Status -eq 200 -and $mainImageTag.Contains($mainUpload)) 'main-image-only product has a usable detail gallery fallback'
    $productFields.MaSP = $createdProductId
    $productFields.TenSP = $productName + ' updated'
    $productFields.DonGia = 22222000
    $productEditPath = '/QuanLySanPham/ChinhSua/' + $createdProductId
    $productEdited = Submit-TestForm -Session $admin -FormPath $productEditPath -PostPath $productEditPath -Body $productFields
    Assert-Check ($productEdited.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.SanPham WHERE MaSP=@id AND TenSP=@name AND DonGia=22222000;' -Parameters @{ id = $createdProductId; name = $productFields.TenSP } -Scalar) -eq 1) 'product edit persists title and price changes'
    $invalidProductEdit = @{} + $productFields
    $invalidProductEdit.DonGia = -1
    $badProductEdit = Submit-TestForm -Session $admin -FormPath $productEditPath -PostPath $productEditPath -Body $invalidProductEdit
    Assert-Check ($badProductEdit.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.SanPham WHERE MaSP=@id AND DonGia=22222000;' -Parameters @{ id = $createdProductId } -Scalar) -eq 1) 'invalid product edit preserves the saved price'
    $newGalleryUpload = 'deployment-replaced-' + $runId + '.jpg'
    $uploadPath = '/QuanLySanPham/UploadHinh/' + $createdProductId
    $imageEdited = Submit-TestForm -Session $admin -FormPath $uploadPath -PostPath $uploadPath -Body @{ id = $createdProductId } -Files @{ HinhAnh1 = @{ Name = $newGalleryUpload; ContentType = 'image/jpeg'; Bytes = $fileBytes } }
    Assert-Check ($imageEdited.Status -eq 302 -and [string](Invoke-TestSql -Sql 'SELECT HinhAnh1 FROM dbo.SanPham WHERE MaSP=@id;' -Parameters @{ id = $createdProductId } -Scalar) -eq $newGalleryUpload) 'separate product gallery upload updates the selected image'
    $newGalleryReply = Send-TestRequest -Path ('/Content/HinhAnhSP/' + $newGalleryUpload) -Session $anonymous
    Assert-Check ($newGalleryReply.Status -eq 200 -and (Test-ImageSignature -Bytes $newGalleryReply.Bytes)) 'replacement gallery image is served successfully'

    $singleImportPath = '/QuanLyPhieuNhap/NhapHangDon/' + $createdProductId
    $receiptCountBefore = [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar)
    $stockBeforeImport = [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=@id;' -Parameters @{ id = $createdProductId } -Scalar)
    $singleImport = Submit-TestForm -Session $admin -FormPath $singleImportPath -PostPath $singleImportPath -Body @{ MaSP = $createdProductId; MaNCC = 1; SoLuongNhap = 3; DonGiaNhap = 10000000 }
    Assert-Check ($singleImport.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar) -eq ($receiptCountBefore + 1) -and [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=@id;' -Parameters @{ id = $createdProductId } -Scalar) -eq ($stockBeforeImport + 3) -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ChiTietPhieuNhap WHERE MaSP=@id AND SoLuongNhap=3 AND DonGiaNhap=10000000;' -Parameters @{ id = $createdProductId } -Scalar) -eq 1) 'single import atomically creates receipt/detail and adds stock'

    $batchImportPath = '/QuanLyPhieuNhap/NhapHang'
    $batchFields = @{ MaNCC = 1; 'lstModel[0].MaSP' = $createdProductId; 'lstModel[0].SoLuongNhap' = 4; 'lstModel[0].DonGiaNhap' = 9000000; 'lstModel[1].MaSP' = 3; 'lstModel[1].SoLuongNhap' = 2; 'lstModel[1].DonGiaNhap' = 8000000 }
    $thirdStockBefore = [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=3;' -Scalar)
    $stockBeforeBatch = [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=@id;' -Parameters @{ id = $createdProductId } -Scalar)
    $batchImport = Submit-TestForm -Session $admin -FormPath $batchImportPath -PostPath $batchImportPath -Body $batchFields
    $batchReceiptId = [int](Invoke-TestSql -Sql 'SELECT MAX(MaPN) FROM dbo.PhieuNhap;' -Scalar)
    Assert-Check ($batchImport.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar) -eq ($receiptCountBefore + 2) -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ChiTietPhieuNhap WHERE MaPN=@id;' -Parameters @{ id = $batchReceiptId } -Scalar) -eq 2 -and [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=@id;' -Parameters @{ id = $createdProductId } -Scalar) -eq ($stockBeforeBatch + 4) -and [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=3;' -Scalar) -eq ($thirdStockBefore + 2)) 'batch import persists both details and both stock increments in one receipt'
    $duplicateBatch = @{ MaNCC = 1; 'lstModel[0].MaSP' = $createdProductId; 'lstModel[0].SoLuongNhap' = 2; 'lstModel[0].DonGiaNhap' = 0; 'lstModel[1].MaSP' = $createdProductId; 'lstModel[1].SoLuongNhap' = 3; 'lstModel[1].DonGiaNhap' = 0 }
    $duplicateStockBefore = [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=@id;' -Parameters @{ id = $createdProductId } -Scalar)
    $duplicateImport = Submit-TestForm -Session $admin -FormPath $batchImportPath -PostPath $batchImportPath -Body $duplicateBatch
    $duplicateReceiptId = [int](Invoke-TestSql -Sql 'SELECT MAX(MaPN) FROM dbo.PhieuNhap;' -Scalar)
    Assert-Check ($duplicateImport.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT SUM(SoLuongNhap) FROM dbo.ChiTietPhieuNhap WHERE MaPN=@receipt AND MaSP=@product;' -Parameters @{ receipt = $duplicateReceiptId; product = $createdProductId } -Scalar) -eq 5 -and [int](Invoke-TestSql -Sql 'SELECT SoLuongTon FROM dbo.SanPham WHERE MaSP=@id;' -Parameters @{ id = $createdProductId } -Scalar) -eq ($duplicateStockBefore + 5)) 'duplicate batch product lines account for the full quantity without lost updates'

    $receiptsAfterValidImports = [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar)
    $detailsAfterValidImports = [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ChiTietPhieuNhap;' -Scalar)
    $totalStockAfterValidImports = [int](Invoke-TestSql -Sql 'SELECT SUM(COALESCE(SoLuongTon,0)) FROM dbo.SanPham;' -Scalar)
    $invalidSingleCases = @(@{ SoLuongNhap = 0 }, @{ SoLuongNhap = -1 }, @{ SoLuongNhap = 'not-an-integer' }, @{ DonGiaNhap = -1 }, @{ MaNCC = 2147483000 }, @{ MaNCC = '' })
    foreach ($invalidFields in $invalidSingleCases) {
        $invalidImport = @{ MaSP = $createdProductId; MaNCC = 1; SoLuongNhap = 1; DonGiaNhap = 1 }
        foreach ($key in $invalidFields.Keys) { $invalidImport[$key] = $invalidFields[$key] }
        $reply = Submit-TestForm -Session $admin -FormPath $singleImportPath -PostPath $singleImportPath -Body $invalidImport
        Assert-Check ($reply.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar) -eq $receiptsAfterValidImports -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ChiTietPhieuNhap;' -Scalar) -eq $detailsAfterValidImports -and [int](Invoke-TestSql -Sql 'SELECT SUM(COALESCE(SoLuongTon,0)) FROM dbo.SanPham;' -Scalar) -eq $totalStockAfterValidImports) ('invalid single import makes no writes: ' + ($invalidFields.Keys -join ','))
    }
    $missingSingleProduct = Submit-TestForm -Session $admin -FormPath $singleImportPath -PostPath '/QuanLyPhieuNhap/NhapHangDon/2147483000' -Body @{ MaSP = 2147483000; MaNCC = 1; SoLuongNhap = 1; DonGiaNhap = 1 }
    Assert-Check ($missingSingleProduct.Status -eq 404 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar) -eq $receiptsAfterValidImports) 'single import cannot create a receipt for a nonexistent product'
    $invalidBatchCases = @(@{ 'lstModel[1].SoLuongNhap' = 0 }, @{ 'lstModel[0].SoLuongNhap' = -1 }, @{ 'lstModel[0].SoLuongNhap' = 'not-an-integer' }, @{ 'lstModel[0].DonGiaNhap' = -1 }, @{ MaNCC = 2147483000 }, @{ MaNCC = '' }, @{ 'lstModel[0].MaSP' = 2147483000 })
    foreach ($invalidFields in $invalidBatchCases) {
        $invalidBatch = @{} + $batchFields
        foreach ($key in $invalidFields.Keys) { $invalidBatch[$key] = $invalidFields[$key] }
        $reply = Submit-TestForm -Session $admin -FormPath $batchImportPath -PostPath $batchImportPath -Body $invalidBatch
        Assert-Check ($reply.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar) -eq $receiptsAfterValidImports -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.ChiTietPhieuNhap;' -Scalar) -eq $detailsAfterValidImports -and [int](Invoke-TestSql -Sql 'SELECT SUM(COALESCE(SoLuongTon,0)) FROM dbo.SanPham;' -Scalar) -eq $totalStockAfterValidImports) ('invalid batch import rolls back every line: ' + ($invalidFields.Keys -join ','))
    }
    $emptyImport = Submit-TestForm -Session $admin -FormPath $batchImportPath -PostPath $batchImportPath -Body @{ MaNCC = 1 }
    Assert-Check ($emptyImport.Status -eq 200 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar) -eq $receiptsAfterValidImports) 'batch import without detail lines cannot create an empty receipt'
    foreach ($case in @(@{ Path = $singleImportPath; Fields = @{ MaSP = $createdProductId; MaNCC = 1; SoLuongNhap = 1; DonGiaNhap = 1 } }, @{ Path = $batchImportPath; Fields = $batchFields })) {
        $withoutImportToken = Send-TestRequest -Path $case.Path -Session $admin -Method POST -Body $case.Fields
        Assert-Check ($withoutImportToken.Status -in @(302,400,403,500) -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.PhieuNhap;' -Scalar) -eq $receiptsAfterValidImports) 'stock import requires CSRF token before any receipt write'
    }

    $deletedProduct = Submit-TestForm -Session $admin -FormPath $productEditPath -PostPath ('/QuanLySanPham/Xoa/' + $createdProductId) -Body @{ id = $createdProductId }
    Assert-Check ($deletedProduct.Status -eq 302 -and [int](Invoke-TestSql -Sql 'SELECT COUNT(*) FROM dbo.SanPham WHERE MaSP=@id AND DaXoa=1;' -Parameters @{ id = $createdProductId } -Scalar) -eq 1 -and (Send-TestRequest -Path ('/SanPham/XemChiTiet/' + $createdProductId) -Session $anonymous).Status -eq 404) 'admin product deletion is soft and hides the public detail page'
    $deletedSearch = Send-TestRequest -Path ('/TimKiem/KQTimKiem?sTuKhoa=' + [uri]::EscapeDataString($productFields.TenSP)) -Session $anonymous
    Assert-ProductResults -Response $deletedSearch -ExpectedIds @() -Label 'soft-deleted product is absent from public search results'
    $logoutSession = New-LoginSession 'deployment_b'
    $logout = Send-TestRequest -Path '/Home/DangXuat' -Session $logoutSession
    Assert-Check ($logout.Status -eq 302 -and (Send-TestRequest -Path '/DonHang/Index' -Session $logoutSession).Status -in @(302,401,403)) 'customer logout invalidates access to protected order pages'
    $adminLogout = Send-TestRequest -Path '/ThongKe/DangXuatAdmin' -Session $admin
    Assert-Check ($adminLogout.Status -eq 302 -and (Send-TestRequest -Path '/ThongKe/Index' -Session $admin).Status -in @(302,401,403)) 'administrator logout invalidates access to the dashboard'
    Write-Output ('PASS: ' + $checks + ' isolated deployment integration checks.')
} catch {
    $failure = $_.Exception.Message
} finally {
    if ($iisProcess) {
        try {
            $ownedProcess = Get-Process -Id $iisProcess.Id -ErrorAction SilentlyContinue
            if ($ownedProcess -and $ownedProcess.ProcessName -eq 'iisexpress' -and $ownedProcess.StartTime -eq $iisStartedAt) {
                Stop-Process -Id $ownedProcess.Id -Force -ErrorAction Stop
                $ownedProcess.WaitForExit(10000) | Out-Null
            }
        } catch { $cleanupErrors.Add('Could not stop the exact test IIS process.') }
    }
    if ($databaseCreatedByThisScript) {
        try {
            if ($databaseName -notmatch '^MotoShop_DeploymentTest_[a-f0-9]{32}$' -or $databaseName -ne ('MotoShop_DeploymentTest_' + $runId)) {
                throw 'Temporary database identity changed; cleanup refused.'
            }
            [System.Data.SqlClient.SqlConnection]::ClearAllPools()
            $cleanup = [System.Data.SqlClient.SqlConnection]::new($masterConnectionString)
            try {
                $cleanup.Open()
                $command = $cleanup.CreateCommand()
                $command.CommandTimeout = 30
                $command.CommandText = 'ALTER DATABASE [' + $databaseName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [' + $databaseName + '];'
                $null = $command.ExecuteNonQuery()
            } finally { $cleanup.Dispose() }
            Write-Output 'Removed the generated temporary database; test files remain only under ignored artifacts.'
        } catch { $cleanupErrors.Add('Temporary test database cleanup failed: ' + $_.Exception.Message) }
    }
    $testPassword = $null
    $passwordHash = $null
    $sqlBuilder.Clear()
}
if ($failure -or $cleanupErrors.Count -gt 0) {
    throw ((@($failure) + @($cleanupErrors) | Where-Object { $_ }) -join ' ')
}
