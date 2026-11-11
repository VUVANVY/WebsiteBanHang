# WebsiteBanHang

Website bán hàng sử dụng ASP.NET MVC 5, C#, .NET Framework 4.7.2 và Entity Framework 6.

## Chức năng

- Xem, tìm kiếm sản phẩm và quản lý giỏ hàng.
- Đăng ký thành viên, đặt hàng và xem đơn hàng.
- Quản lý sản phẩm, loại sản phẩm, nhà sản xuất và nhập hàng.
- Quản lý đơn hàng, thành viên, quyền truy cập và thống kê.

## Yêu cầu

- Windows và Visual Studio với workload **ASP.NET and web development**.
- .NET Framework 4.7.2 Developer Pack.
- SQL Server hoặc SQL Server Express.

## Chạy dự án

1. Mở `WebsiteBanHang.sln` bằng Visual Studio.
2. Nhấp phải vào solution, chọn **Restore NuGet Packages** để tải các thư viện trong `packages.config`.
3. Tạo database SQL Server `QuanLyBanHang` trống, chạy lần lượt các script trong `deployment/Database/` theo [hướng dẫn database demo](deployment/README-database.md).
4. Sửa connection string `QuanLyBanHangEntities` trong `WebsiteBanHang/Web.config` cho phù hợp máy của bạn. Cấu hình hiện tại kết nối tới `VUVANVY\SQLEXPRESS` bằng Windows Authentication.
5. Đặt `WebsiteBanHang` làm startup project, build solution rồi nhấn **F5** để chạy với IIS Express.

Các script đi kèm tạo cấu trúc và sản phẩm giả định cho bản demo. Không có dữ liệu tài khoản, khách hàng hoặc đơn hàng cá nhân. Chỉ chạy trên database demo mới, không chạy trên database đang sử dụng.

## Triển khai website để gắn CV

Xem [hướng dẫn triển khai hosting Windows](deployment/README.md). Dự án có profile publish Release và công cụ tạo gói trong `tools/Publish-Website.ps1`. Cấu hình hosting thật được điền vào thư mục `artifacts/` được bỏ qua trong Git.

Tài khoản mới dùng mật khẩu được băm có salt; đăng nhập hợp lệ sẽ nâng cấp mật khẩu cũ nếu có. Các thao tác đơn hàng kiểm tra chủ sở hữu và dùng POST kèm token chống CSRF. Bản Release yêu cầu HTTPS cho cookie đăng nhập.

## Cấu trúc

- `WebsiteBanHang/Controllers`: xử lý yêu cầu và nghiệp vụ.
- `WebsiteBanHang/Models`: mô hình dữ liệu Entity Framework và view model.
- `WebsiteBanHang/Views`: giao diện Razor.
- `WebsiteBanHang/Content`, `Scripts`, `fonts`: tài nguyên giao diện.
- `WebsiteBanHang/App_Start`: cấu hình route, bundle và filter.

Các thư mục build, bộ nhớ đệm Visual Studio và thư viện NuGet được khôi phục tự động nên không được đưa vào Git.
