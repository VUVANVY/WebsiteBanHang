# Triển khai MotoShop lên hosting Windows

Ứng dụng dùng ASP.NET MVC 5 trên .NET Framework 4.7.2, Entity Framework 6 và SQL Server. Cần hosting Windows/IIS hỗ trợ .NET Framework 4.x, HTTPS và Microsoft SQL Server.

## Hosting miễn phí để bắt đầu

Somee Free hỗ trợ ASP.NET 4.x, MSSQL và tên miền phụ `*.somee.com`. Gói miễn phí có 150 MB lưu trữ website và 30 MB database, có chèn quảng cáo. Website và database cần được sử dụng ít nhất một lần trong mỗi 30 ngày; SSL miễn phí cần gia hạn thủ công. Xem giới hạn hiện tại trước khi đăng ký:

- Gói Free: https://www.somee.com/FreeAspNetHosting.aspx
- Tính năng và giới hạn: https://www.somee.com/Faq/216/Free_ASP.NET_Hosting
- SSL: https://www.somee.com/DOKA/Help/Article/293/Free_certificate_orders

Khi dùng Somee, chọn gói **Free Hosting**, tạo website cùng database MSSQL, bật ASP.NET 4.x rồi áp dụng các bước publish chung dưới đây. Chỉ dùng phần đăng nhập/đăng ký khi HTTPS của website đã hoạt động.

### Phương án khác: MonsterASP.NET

MonsterASP.NET có gói Free gồm một website, một database SQL Server và tên miền phụ `*.runasp.net` hoặc `*.tryasp.net`. Đây là gói demo/học tập có giới hạn tài nguyên; website có thể khởi động chậm sau thời gian không hoạt động. Tài khoản do chủ dự án tự đăng ký bằng email và kích hoạt.

- Đăng ký: https://www.monsterasp.net/
- Hỗ trợ MVC 5: https://help.monsterasp.net/getting-started/first-steps/supported-technologies
- Giới hạn Free/Premium: https://help.monsterasp.net/getting-started/first-steps/free-vs-premium
- Bật HTTPS: https://help.monsterasp.net/domains-https/https/lets-encrypt

Gói Free cần tải website lên rồi yêu cầu bộ phận hỗ trợ bật HTTPS. Không dùng chức năng đăng nhập/đăng ký qua HTTP. Bản Release yêu cầu cookie HTTPS; sau khi HTTPS hoạt động, bật chuyển hướng HTTP sang HTTPS trong Control Panel.

## 1. Tạo website và database

1. Trong Control Panel, tạo website Free với tên miền phụ còn trống.
2. Trong **Scripting**, chuyển sang **ASP.NET (.NET Framework 4.x)**. Dự án này không dùng ASP.NET Core.
3. Tạo database **MSSQL**, tạo SQL user và gán quyền cho database đó.
4. Ghi lại SQL Server, tên database và SQL username trong nơi riêng tư. Mật khẩu được nhập cục bộ khi cấu hình publish, không đưa vào Git.
5. Chạy script database trong `deployment/Database/` theo hướng dẫn ở `README-database.md`. Dữ liệu demo độc lập với dữ liệu người dùng trên máy cá nhân.

## 2. Tạo bản Release

Mở PowerShell tại thư mục chứa `WebsiteBanHang.sln`:

```powershell
.\tools\Publish-Website.ps1
```

Kết quả ở `artifacts/publish/` và `artifacts/MotoShop-publish.zip`. Thư mục `artifacts/` được bỏ qua trong Git. Cấu hình Release tắt debug, ẩn lỗi chi tiết và yêu cầu HTTPS cho cookie đăng nhập.

## 3. Điền kết nối database hosting

```powershell
$hostingSqlPassword = Read-Host 'SQL password' -AsSecureString
.\tools\Set-HostingConnection.ps1 -Server 'SQL_SERVER_FROM_HOSTING' -Database 'DATABASE_FROM_HOSTING' -SqlUser 'SQL_USER_FROM_HOSTING' -SqlPassword $hostingSqlPassword
```

Script chỉ sửa `artifacts/publish/Web.config` và tạo lại ZIP. `WebsiteBanHang/Web.config` trong mã nguồn vẫn dùng SQL Server cục bộ. Kết nối hosting bật mã hóa TLS và xác minh chứng chỉ; dùng hostname/cổng do nhà cung cấp chỉ định.

## 4. Tải bản publish lên hosting

Upload nội dung **bên trong** `artifacts/publish/` vào web root bằng File Manager, Web Deploy hoặc FTP/SFTP. Không tải cả solution, `packages/`, `.git/` hay database cá nhân lên web root. Nếu dùng ZIP, giải nén sao cho `Web.config`, `bin/`, `Views/` và `Content/` nằm trực tiếp trong thư mục website.

Đảm bảo thư mục `Content/HinhAnhSP/` có quyền ghi của ứng dụng để upload ảnh sản phẩm. Giữ ảnh khi cập nhật website.

Sau khi import database demo, tạo tài khoản quản trị riêng bằng PowerShell (không có mật khẩu quản trị dùng chung trong mã nguồn):

```powershell
$hostingSqlPassword = Read-Host 'SQL password' -AsSecureString
$newAdminPassword = Read-Host 'Admin password (at least 12 characters)' -AsSecureString
.\tools\New-HostingAdmin.ps1 -Server 'SQL_SERVER_FROM_HOSTING' -Database 'DATABASE_FROM_HOSTING' -SqlUser 'SQL_USER_FROM_HOSTING' -SqlPassword $hostingSqlPassword -AdminUser 'YOUR_ADMIN_USERNAME' -AdminPassword $newAdminPassword
```

Lệnh chỉ tạo tài khoản mới có quyền `QuanTriWeb`, không sửa tài khoản đã tồn tại. Không công khai tài khoản quản trị trong CV; người xem có thể duyệt sản phẩm hoặc tự đăng ký tài khoản khách để dùng thử.

## 5. Kiểm tra trước khi gắn CV

- HTTPS mở được và trang chủ hiển thị sản phẩm.
- Tìm kiếm, lọc và phân trang hoạt động.
- Đăng ký tài khoản thử với mật khẩu riêng cho demo, đăng nhập và thêm giỏ hàng.
- Người chưa đăng nhập không vào được trang quản trị hoặc thao tác đơn hàng.
- Tài khoản khách hàng chỉ xem/thao tác đơn hàng của chính mình.
- Không có thông tin tài khoản quản trị, SQL password hoặc dữ liệu khách hàng thật trong Git/ZIP chia sẻ.

Sau khi website online, thêm URL demo HTTPS vào README và CV, cùng đường dẫn repository.
