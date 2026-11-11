[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Database,
    [Parameter(Mandatory = $true)][string]$SqlUser,
    [Parameter(Mandatory = $true)][Security.SecureString]$SqlPassword,
    [Parameter(Mandatory = $true)][ValidateLength(1, 100)][string]$AdminUser,
    [Parameter(Mandatory = $true)][Security.SecureString]$AdminPassword
)

$ErrorActionPreference = 'Stop'
if ($AdminPassword.Length -lt 12) { throw 'Use at least 12 characters for the administrator password.' }
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$assemblyPath = Join-Path $repoRoot 'artifacts\publish\bin\WebsiteBanHang.dll'
if (-not (Test-Path -LiteralPath $assemblyPath)) { throw 'Run tools\Publish-Website.ps1 first.' }
$assembly = [Reflection.Assembly]::LoadFrom($assemblyPath)
$passwordType = $assembly.GetType('WebsiteBanHang.Security.PasswordService', $true)
$sqlBuilder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
$sqlBuilder['Data Source'] = $Server
$sqlBuilder['Initial Catalog'] = $Database
$sqlBuilder['User ID'] = $SqlUser
$sqlBuilder['Encrypt'] = $true
$sqlBuilder['TrustServerCertificate'] = $false
$sqlBuilder['Connect Timeout'] = 15
$sqlPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SqlPassword)
$adminPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword)
$connection = $null
try {
    $sqlBuilder['Password'] = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($sqlPointer)
    $hash = $passwordType.GetMethod('Hash').Invoke($null, @([Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPointer)))
    $connection = [System.Data.SqlClient.SqlConnection]::new($sqlBuilder.ConnectionString)
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandText = @'
SET XACT_ABORT ON;
BEGIN TRANSACTION;
IF EXISTS (SELECT 1 FROM dbo.ThanhVien WITH (UPDLOCK, HOLDLOCK) WHERE TaiKhoan = @username)
BEGIN
    ROLLBACK;
    THROW 51010, 'This username already exists. No account was modified.', 1;
END;
DECLARE @role int = (SELECT TOP (1) MaLoaiTV FROM dbo.LoaiThanhVien_Quyen WHERE MaQuyen = N'QuanTriWeb' ORDER BY MaLoaiTV);
IF @role IS NULL
BEGIN
    ROLLBACK;
    THROW 51011, 'Administrator role is missing. Import the demo role seed first.', 1;
END;
INSERT INTO dbo.ThanhVien (TaiKhoan, MatKhau, HoTen, DiaChi, Email, SoDienThoai, CauHoi, CauTraLoi, MaLoaiTV)
VALUES (@username, @passwordHash, N'Quan tri MotoShop', N'Demo', N'admin@example.invalid', N'0000000000', N'Tai khoan quan tri', N'Khong dung de khoi phuc mat khau', @role);
COMMIT;
'@
    $null = $command.Parameters.Add('@username', [System.Data.SqlDbType]::NVarChar, 150)
    $command.Parameters['@username'].Value = $AdminUser
    $null = $command.Parameters.Add('@passwordHash', [System.Data.SqlDbType]::NVarChar, 150)
    $command.Parameters['@passwordHash'].Value = $hash
    $null = $command.ExecuteNonQuery()
    Write-Output 'Administrator created with a salted password hash. The password was not logged or stored in a script.'
} finally {
    if ($connection) { $connection.Dispose() }
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($sqlPointer)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($adminPointer)
    $sqlBuilder.Clear()
    $hash = $null
}
