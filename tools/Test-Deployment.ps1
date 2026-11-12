[CmdletBinding()]
param([string]$SqlServer = '.\SQLEXPRESS')

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$publishRoot = Join-Path $repoRoot 'artifacts\publish'
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
          [string]$Method = 'GET', [hashtable]$Body = @{})
    $request = [System.Net.HttpWebRequest]::CreateHttp($baseUrl + $Path)
    $request.Method = $Method
    $request.AllowAutoRedirect = $false
    $request.Proxy = $null
    $request.Timeout = 45000
    $request.ReadWriteTimeout = 45000
    $request.CookieContainer = $Session.Cookies
    if ($Method -eq 'POST') {
        $pairs = foreach ($key in $Body.Keys) {
            [uri]::EscapeDataString([string]$key) + '=' + [uri]::EscapeDataString([string]$Body[$key])
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes(($pairs -join '&'))
        $request.ContentType = 'application/x-www-form-urlencoded'
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
        $sqlText = Get-Content -LiteralPath (Join-Path $repoRoot ('deployment\Database\' + $file)) -Raw
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
    [xml]$configuration = Get-Content -LiteralPath (Join-Path $siteRoot 'Web.config')
    $entityBuilder = [System.Data.Common.DbConnectionStringBuilder]::new()
    $entityBuilder['metadata'] = 'res://*/Models.QuanLyBanHangModel.csdl|res://*/Models.QuanLyBanHangModel.ssdl|res://*/Models.QuanLyBanHangModel.msl'
    $entityBuilder['provider'] = 'System.Data.SqlClient'
    $entityBuilder['provider connection string'] = $testConnectionString
    $entry = $configuration.configuration.connectionStrings.add | Where-Object name -eq 'QuanLyBanHangEntities'
    $entry.SetAttribute('connectionString', $entityBuilder.ConnectionString)
    $configuration.configuration.'system.web'.authentication.forms.SetAttribute('requireSSL', 'false')
    $configuration.configuration.'system.web'.httpCookies.SetAttribute('requireSSL', 'false')
    $configuration.Save((Join-Path $siteRoot 'Web.config'))

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try { $listener.Start(); $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port } finally { $listener.Stop() }
    $baseUrl = 'http://localhost:' + $port
    [xml]$appHost = Get-Content -LiteralPath $iisTemplate
    $site = $appHost.configuration.'system.applicationHost'.sites.site
    $site.SetAttribute('name', 'MotoShopDeploymentTest')
    $site.application.SetAttribute('applicationPool', 'Clr4IntegratedAppPool')
    $site.application.virtualDirectory.SetAttribute('physicalPath', $siteRoot)
    $site.bindings.binding.SetAttribute('bindingInformation', ('*:' + $port + ':localhost'))
    $appHostPath = Join-Path $testRoot 'applicationhost.config'
    $appHost.Save($appHostPath)
    $iisProcess = Start-Process -FilePath $iisExe -ArgumentList @('/config:' + $appHostPath, '/site:MotoShopDeploymentTest', '/systray:false') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'iis.stdout.log') -RedirectStandardError (Join-Path $testRoot 'iis.stderr.log')
    $iisStartedAt = $iisProcess.StartTime
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

    $sessionA = New-LoginSession 'deployment_a'
    $tokenA = Get-TestToken $sessionA
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
