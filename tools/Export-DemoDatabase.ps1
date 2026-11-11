<#
.SYNOPSIS
Generates SQL Server schema and synthetic demo data from the public EF6 EDMX.
.DESCRIPTION
Offline generator: never connects to SQL Server and never reads application data.
Run the generated scripts only in a new, dedicated demo database.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $ProjectRoot 'deployment\Database' }
$modelPath = Join-Path $ProjectRoot 'WebsiteBanHang\Models\QuanLyBanHangModel.edmx'
[xml]$model = [IO.File]::ReadAllText($modelPath)
$ns = [Xml.XmlNamespaceManager]::new($model.NameTable)
$ns.AddNamespace('e', 'http://schemas.microsoft.com/ado/2009/11/edmx')
$ns.AddNamespace('s', 'http://schemas.microsoft.com/ado/2009/11/edm/ssdl')
$store = $model.SelectSingleNode('/e:Edmx/e:Runtime/e:StorageModels/s:Schema', $ns)
if ($null -eq $store -or $store.GetAttribute('Provider') -ne 'System.Data.SqlClient') {
    throw 'Expected an SQL Server SSDL schema in the EDMX.'
}

function Quote-Identifier([string]$Value) { '[' + $Value.Replace(']', ']]') + ']' }
function Qualified-Table($Table) { (Quote-Identifier $Table.Schema) + '.' + (Quote-Identifier $Table.Name) }
function Sql-String([string]$Value) { "N'" + $Value.Replace("'", "''") + "'" }
function Sql-Type($Property) {
    $type = $Property.GetAttribute('Type').ToLowerInvariant()
    if ($type -match '^(nvarchar|varchar|varbinary)\(max\)$') { return $type }
    if ($type -in @('nvarchar', 'varchar', 'nchar', 'char', 'binary', 'varbinary')) {
        $length = $Property.GetAttribute('MaxLength')
        if ($length -notmatch '^([1-9][0-9]*|[Mm][Aa][Xx])$') { throw "Missing/invalid length for $type." }
        return $type + '(' + $length.ToLowerInvariant() + ')'
    }
    if ($type -in @('decimal', 'numeric')) {
        $precision = $Property.GetAttribute('Precision')
        $scale = $Property.GetAttribute('Scale')
        if ($precision -notmatch '^\d+$' -or $scale -notmatch '^\d+$') { throw 'Missing decimal precision/scale.' }
        return $type + '(' + $precision + ',' + $scale + ')'
    }
    if ($type -notin @('bigint','int','smallint','tinyint','bit','datetime','smalldatetime','date','datetime2','time','datetimeoffset','float','real','money','smallmoney','uniqueidentifier','xml','text','ntext','image','timestamp','rowversion')) {
        throw "Unsupported SQL type: $type"
    }
    return $type
}
function Sql-Value($Property, $Value) {
    if ($null -eq $Value) {
        if ($Property.GetAttribute('Nullable') -eq 'false') { throw 'NULL supplied for a required property.' }
        return 'NULL'
    }
    $type = $Property.GetAttribute('Type').ToLowerInvariant()
    if ($type -eq 'bit') { if ([bool]$Value) { return '1' }; return '0' }
    if ($type -in @('bigint','int','smallint','tinyint','decimal','numeric','float','real','money','smallmoney')) {
        return ([IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($type -in @('datetime','smalldatetime','date','datetime2','time','datetimeoffset')) {
        return 'CONVERT(' + (Sql-Type $Property) + ', ' + (Sql-String ([string]$Value)) + ', 126)'
    }
    $text = [string]$Value
    $length = $Property.GetAttribute('MaxLength')
    if ($length -match '^\d+$' -and $text.Length -gt [int]$length) { throw 'Synthetic string exceeds mapped column length.' }
    return Sql-String $text
}

$tables = [ordered]@{}
$entities = @{}
foreach ($set in $store.SelectNodes('s:EntityContainer/s:EntitySet', $ns)) {
    $entityName = $set.GetAttribute('EntityType').Split('.')[-1]
    $entity = $store.SelectSingleNode("s:EntityType[@Name='$entityName']", $ns)
    $name = $set.GetAttribute('Table')
    if (-not $name) { $name = $set.GetAttribute('Name') }
    $schema = $set.GetAttribute('Schema')
    if ($schema -ne 'dbo') { throw 'This application expects dbo-mapped tables.' }
    $table = [pscustomobject]@{
        Name = $name; Schema = $schema
        Properties = @($entity.SelectNodes('s:Property', $ns))
        Keys = @($entity.SelectNodes('s:Key/s:PropertyRef', $ns) | ForEach-Object { $_.GetAttribute('Name') })
    }
    foreach ($property in $table.Properties) {
        $null = Sql-Type $property
        if ($property.GetAttribute('StoreGeneratedPattern') -notin @('', 'Identity')) {
            throw 'Computed expressions cannot be reconstructed safely from EDMX alone.'
        }
    }
    $tables[$name] = $table
    $entities[$entityName] = $table
}
if ($tables.Count -ne 15) { throw "Expected 15 mapped tables; found $($tables.Count). Review model changes before publishing." }

$foreignKeys = @()
foreach ($association in $store.SelectNodes('s:Association', $ns)) {
    $principal = $association.SelectSingleNode('s:ReferentialConstraint/s:Principal', $ns)
    $dependent = $association.SelectSingleNode('s:ReferentialConstraint/s:Dependent', $ns)
    $principalEnd = $association.SelectSingleNode("s:End[@Role='$($principal.GetAttribute('Role'))']", $ns)
    $dependentEnd = $association.SelectSingleNode("s:End[@Role='$($dependent.GetAttribute('Role'))']", $ns)
    $parent = $entities[$principalEnd.GetAttribute('Type').Split('.')[-1]]
    $child = $entities[$dependentEnd.GetAttribute('Type').Split('.')[-1]]
    $parentColumns = @($principal.SelectNodes('s:PropertyRef', $ns) | ForEach-Object { $_.GetAttribute('Name') })
    $childColumns = @($dependent.SelectNodes('s:PropertyRef', $ns) | ForEach-Object { $_.GetAttribute('Name') })
    if ($parentColumns.Count -ne $childColumns.Count -or ($parentColumns -join ',') -ne ($parent.Keys -join ',')) {
        throw 'Foreign-key mapping does not match its referenced primary key.'
    }
    foreach ($column in $childColumns) {
        if ($column -notin @($child.Properties | ForEach-Object { $_.GetAttribute('Name') })) { throw 'Foreign-key column missing.' }
    }
    $onDelete = $principalEnd.SelectSingleNode('s:OnDelete', $ns)
    $cascade = $null -ne $onDelete -and $onDelete.GetAttribute('Action') -eq 'Cascade'
    $foreignKeys += [pscustomobject]@{ Name = $association.GetAttribute('Name'); Parent = $parent; Child = $child; ParentColumns = $parentColumns; ChildColumns = $childColumns; Cascade = $cascade }
}

$header = @(
    '-- Generated offline by tools/Export-DemoDatabase.ps1 from QuanLyBanHangModel.edmx.',
    '-- Contains no database export, account, password, customer, order or comment data.',
    '-- Select a NEW dedicated demo database in your SQL client before running this file.',
    'SET ANSI_NULLS ON;', 'SET QUOTED_IDENTIFIER ON;', 'SET NOCOUNT ON;', 'SET XACT_ABORT ON;',
    "IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb') THROW 51000, 'Select a dedicated demo database first.', 1;"
)
$schemaLines = [Collections.Generic.List[string]]::new()
foreach ($line in $header) { $schemaLines.Add($line) }
$existingNames = @($tables.Keys | ForEach-Object { Sql-String $_ }) -join ', '
$schemaLines.Add("IF EXISTS (SELECT 1 FROM sys.tables WHERE schema_id = SCHEMA_ID(N'dbo') AND name IN ($existingNames)) THROW 51001, 'Mapped tables already exist; this script never replaces existing tables.', 1;")
$schemaLines.Add('BEGIN TRY')
$schemaLines.Add('BEGIN TRANSACTION;')
foreach ($table in $tables.Values) {
    $schemaLines.Add('CREATE TABLE ' + (Qualified-Table $table) + ' (')
    $definitions = [Collections.Generic.List[string]]::new()
    foreach ($property in $table.Properties) {
        $definition = '    ' + (Quote-Identifier $property.GetAttribute('Name')) + ' ' + (Sql-Type $property)
        if ($property.GetAttribute('StoreGeneratedPattern') -eq 'Identity') { $definition += ' IDENTITY(1,1)' }
        if ($property.GetAttribute('Nullable') -eq 'false') { $definition += ' NOT NULL' } else { $definition += ' NULL' }
        $definitions.Add($definition)
    }
    $keyColumns = @($table.Keys | ForEach-Object { Quote-Identifier $_ }) -join ', '
    $definitions.Add('    CONSTRAINT ' + (Quote-Identifier ('PK_' + $table.Name)) + ' PRIMARY KEY (' + $keyColumns + ')')
    $schemaLines.Add(($definitions -join (',' + [Environment]::NewLine)))
    $schemaLines.Add(');')
}
foreach ($fk in $foreignKeys) {
    $childColumns = @($fk.ChildColumns | ForEach-Object { Quote-Identifier $_ }) -join ', '
    $parentColumns = @($fk.ParentColumns | ForEach-Object { Quote-Identifier $_ }) -join ', '
    $statement = 'ALTER TABLE ' + (Qualified-Table $fk.Child) + ' WITH CHECK ADD CONSTRAINT ' + (Quote-Identifier $fk.Name) + ' FOREIGN KEY (' + $childColumns + ') REFERENCES ' + (Qualified-Table $fk.Parent) + ' (' + $parentColumns + ')'
    if ($fk.Cascade) { $statement += ' ON DELETE CASCADE' }
    $schemaLines.Add($statement + ';')
}
$schemaLines.Add('COMMIT TRANSACTION;')
$schemaLines.Add('END TRY')
$schemaLines.Add('BEGIN CATCH')
$schemaLines.Add('IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;')
$schemaLines.Add('THROW;')
$schemaLines.Add('END CATCH;')

# All rows below are synthetic. Existing images are public project assets used as illustrations.
$seed = [ordered]@{}
$seed.LoaiSanPham = @(
    @{ MaLoaiSP = 1; TenLoai = 'Xe số'; Icon = 'fas fa-motorcycle'; BiDanh = 'xe-so' },
    @{ MaLoaiSP = 2; TenLoai = 'Xe tay ga'; Icon = 'fas fa-motorcycle'; BiDanh = 'xe-tay-ga' },
    @{ MaLoaiSP = 7; TenLoai = 'Xe tay côn'; Icon = 'fas fa-motorcycle'; BiDanh = 'xe-tay-con' }
)
$seed.LoaiThanhVien = @(
    @{ MaLoaiTV = 1; TenLoai = 'Quản trị website'; UuDai = 0 },
    @{ MaLoaiTV = 2; TenLoai = 'Quản lý'; UuDai = 0 },
    @{ MaLoaiTV = 3; TenLoai = 'Khách hàng'; UuDai = 0 }
)
$seed.NhaCungCap = @(@{ MaNCC = 1; TenNCC = 'Nhà cung cấp demo'; DiaChi = $null; Email = $null; SoDienThoai = $null; Fax = $null })
$seed.NhaSanXuat = @(
    @{ MaNSX = 1; TenNSX = 'Hãng demo A'; ThongTin = 'Thông tin minh họa cho bản demo CV.' },
    @{ MaNSX = 2; TenNSX = 'Hãng demo B'; ThongTin = 'Thông tin minh họa cho bản demo CV.' },
    @{ MaNSX = 3; TenNSX = 'Hãng demo C'; ThongTin = 'Thông tin minh họa cho bản demo CV.' }
)
$seed.Quyen = @(
    @{ MaQuyen = 'QuanTriWeb'; TenQuyen = 'Quản trị website' },
    @{ MaQuyen = 'QuanLy'; TenQuyen = 'Quản lý' },
    @{ MaQuyen = 'KhachHang'; TenQuyen = 'Khách hàng' }
)
$seed.LoaiThanhVien_Quyen = @(
    @{ MaLoaiTV = 1; MaQuyen = 'QuanTriWeb'; GhiChu = 'Cấu hình quyền demo' },
    @{ MaLoaiTV = 2; MaQuyen = 'QuanLy'; GhiChu = 'Cấu hình quyền demo' },
    @{ MaLoaiTV = 3; MaQuyen = 'KhachHang'; GhiChu = 'Cấu hình quyền demo' }
)
$images = @('download.jpg','download (1).jpg','download (2).jpg','download (3).jpg','download (4).jpg','download (5).jpg','download (8).jpg','download (9).jpg','download (10).jpg','download (11).jpg','download (12).jpg','download (13).jpg','xe-may-honda-winner-x-phien-ban-the-thao-phanh-thuong296.jpg')
$products = @()
for ($i = 1; $i -le 13; $i++) {
    $image = $images[$i - 1]
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ('WebsiteBanHang\Content\HinhAnhSP\' + $image)))) { throw "Missing public demo image asset: $image" }
    $category = if ($i -le 4) { 1 } elseif ($i -le 8) { 2 } else { 7 }
    $label = if ($category -eq 1) { 'Xe số' } elseif ($category -eq 2) { 'Xe tay ga' } else { 'Xe tay côn' }
    $products += @{
        MaSP = $i; TenSP = ('[DEMO] ' + $label + ' ' + $i.ToString('00'))
        DonGia = [decimal](18000000 + $i * 3500000); NgayCapNhat = '2026-01-01T00:00:00'
        DongCo = 'Thông số minh họa cho bản demo CV.'
        MoTa = '<p>Sản phẩm và giá hoàn toàn là dữ liệu demo. Hình ảnh chỉ dùng minh họa; website không phục vụ giao dịch thật.</p>'
        HinhAnh = $image; HinhAnh1 = $image; HinhAnh2 = $image; HinhAnh3 = $image; HinhAnh4 = $image
        SoLuongTon = 10; LuotXem = 0; LuotBinhChon = 0; LuotBinhLuan = 0; SoLuotMua = 0; Moi = 1
        MaNCC = 1; MaNSX = (($i - 1) % 3 + 1); MaLoaiSP = $category; DaXoa = $false
    }
}
$seed.SanPham = $products
$allowedSeedTables = @('LoaiSanPham','LoaiThanhVien','NhaCungCap','NhaSanXuat','Quyen','LoaiThanhVien_Quyen','SanPham')
$seedLines = [Collections.Generic.List[string]]::new()
foreach ($line in $header) { $seedLines.Add($line) }
$seedLines.Add('-- Run 01-schema.sql first. Refuses to mix this seed with any existing mapped application data.')
foreach ($table in $tables.Values) {
    $qualified = Qualified-Table $table
    $seedLines.Add("IF OBJECT_ID(N'$qualified', N'U') IS NULL THROW 51002, 'Run 01-schema.sql in this database first.', 1;")
    $seedLines.Add("IF EXISTS (SELECT 1 FROM $qualified) THROW 51003, 'Demo seed requires empty application tables; no existing data is modified.', 1;")
}
$seedLines.Add('BEGIN TRY')
$seedLines.Add('BEGIN TRANSACTION;')
foreach ($tableName in $seed.Keys) {
    if ($tableName -notin $allowedSeedTables) { throw 'Seed table is not allowlisted.' }
    $table = $tables[$tableName]
    $identity = @($table.Properties | Where-Object { $_.GetAttribute('StoreGeneratedPattern') -eq 'Identity' }).Count -gt 0
    if ($identity) { $seedLines.Add('SET IDENTITY_INSERT ' + (Qualified-Table $table) + ' ON;') }
    foreach ($row in $seed[$tableName]) {
        $knownColumns = @($table.Properties | ForEach-Object { $_.GetAttribute('Name') })
        foreach ($column in $row.Keys) { if ($column -notin $knownColumns) { throw "Unknown seed property in $tableName." } }
        $properties = @($table.Properties | Where-Object { $row.ContainsKey($_.GetAttribute('Name')) })
        $columns = @($properties | ForEach-Object { Quote-Identifier $_.GetAttribute('Name') }) -join ', '
        $values = @($properties | ForEach-Object { Sql-Value $_ $row[$_.GetAttribute('Name')] }) -join ', '
        $seedLines.Add('INSERT INTO ' + (Qualified-Table $table) + ' (' + $columns + ') VALUES (' + $values + ');')
    }
    if ($identity) { $seedLines.Add('SET IDENTITY_INSERT ' + (Qualified-Table $table) + ' OFF;') }
}
$seedLines.Add('COMMIT TRANSACTION;')
$seedLines.Add('END TRY')
$seedLines.Add('BEGIN CATCH')
$seedLines.Add('IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;')
$seedLines.Add('THROW;')
$seedLines.Add('END CATCH;')

$verifyLines = [Collections.Generic.List[string]]::new()
$verifyLines.Add('-- Read-only checks for the fresh synthetic demo, before creating any administrator account.')
$verifyLines.Add('SET NOCOUNT ON;')
foreach ($table in $tables.Values) {
    $expected = if ($seed.Contains($table.Name)) { @($seed[$table.Name]).Count } else { 0 }
    $verifyLines.Add('IF (SELECT COUNT_BIG(*) FROM ' + (Qualified-Table $table) + ') <> ' + $expected + " THROW 51004, 'Unexpected demo row count in $($table.Name).', 1;")
}
$verifyLines.Add("IF (SELECT COUNT(*) FROM sys.foreign_keys WHERE schema_id = SCHEMA_ID(N'dbo')) <> $($foreignKeys.Count) THROW 51005, 'Unexpected foreign-key count.', 1;")
$verifyLines.Add("IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE schema_id = SCHEMA_ID(N'dbo') AND (is_disabled = 1 OR is_not_trusted = 1)) THROW 51006, 'A foreign key is disabled or untrusted.', 1;")
$verifyLines.Add("SELECT N'Demo schema and synthetic row counts verified.' AS Result;")

$null = [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory))
$utf8 = [Text.UTF8Encoding]::new($false)
foreach ($artifact in @(@('01-schema.sql', $schemaLines), @('02-seed-demo.sql', $seedLines), @('03-verify-demo.sql', $verifyLines))) {
    [IO.File]::WriteAllText((Join-Path $OutputDirectory $artifact[0]), (($artifact[1] -join [Environment]::NewLine) + [Environment]::NewLine), $utf8)
}
$columnCount = ($tables.Values | ForEach-Object { $_.Properties.Count } | Measure-Object -Sum).Sum
[pscustomobject]@{
    OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    Tables = $tables.Count; Columns = $columnCount; ForeignKeys = $foreignKeys.Count
    SyntheticProducts = $products.Count; AccountRows = 0; CustomerRows = 0; OrderRows = 0; CommentRows = 0
    DatabaseConnections = 0; SqlExecuted = $false
} | ConvertTo-Json -Compress
