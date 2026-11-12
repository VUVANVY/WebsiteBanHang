# Triển khai trên IIS

Máy chủ cần IIS, .NET Framework 4.7.2 trở lên, SQL Server và HTTPS.

## Cơ sở dữ liệu

Tạo database và SQL user, sau đó chạy các script theo [hướng dẫn cơ sở dữ liệu](README-database.md).

## Publish

Tại thư mục chứa `WebsiteBanHang.sln`, chạy:

```powershell
.\tools\Publish-Website.ps1
```

Kết quả nằm trong `artifacts/publish/` và `artifacts/MotoShop-publish.zip`. Bản Release tắt debug và yêu cầu HTTPS khi đăng nhập.

## Cấu hình kết nối

```powershell
$hostingSqlPassword = Read-Host 'SQL password' -AsSecureString
.\tools\Set-HostingConnection.ps1 -Server 'SQL_SERVER_FROM_HOSTING' -Database 'DATABASE_FROM_HOSTING' -SqlUser 'SQL_USER_FROM_HOSTING' -SqlPassword $hostingSqlPassword
```

Lệnh cập nhật `artifacts/publish/Web.config` và tạo lại ZIP. Thư mục `artifacts/` được bỏ qua trong Git vì bản cấu hình này chứa thông tin kết nối riêng.

## Đưa lên máy chủ

1. Tải nội dung bên trong `artifacts/publish/` vào thư mục website. `Web.config`, `bin/`, `Views/` và `Content/` phải nằm ngay tại thư mục gốc.
2. Chọn ASP.NET Framework 4.x và application pool Integrated.
3. Cấp quyền ghi cho ứng dụng tại `Content/HinhAnhSP/` để tải ảnh sản phẩm lên.
4. Bật HTTPS trước khi sử dụng chức năng đăng nhập và đăng ký.

## Tài khoản quản trị

Sau khi khởi tạo database, chạy:

```powershell
$hostingSqlPassword = Read-Host 'SQL password' -AsSecureString
$newAdminPassword = Read-Host 'Admin password (at least 12 characters)' -AsSecureString
.\tools\New-HostingAdmin.ps1 -Server 'SQL_SERVER_FROM_HOSTING' -Database 'DATABASE_FROM_HOSTING' -SqlUser 'SQL_USER_FROM_HOSTING' -SqlPassword $hostingSqlPassword -AdminUser 'YOUR_ADMIN_USERNAME' -AdminPassword $newAdminPassword
```

Lệnh tạo tài khoản mới có quyền `QuanTriWeb`; tên tài khoản đã tồn tại sẽ bị từ chối.
