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
3. Chuẩn bị cơ sở dữ liệu SQL Server `QuanLyBanHang` với cấu trúc phù hợp mô hình `WebsiteBanHang/Models/QuanLyBanHangModel.edmx`.
4. Sửa connection string `QuanLyBanHangEntities` trong `WebsiteBanHang/Web.config` cho phù hợp máy của bạn. Cấu hình hiện tại kết nối tới `VUVANVY\SQLEXPRESS` bằng Windows Authentication.
5. Đặt `WebsiteBanHang` làm startup project, build solution rồi nhấn **F5** để chạy với IIS Express.

Dự án hiện chưa kèm script SQL hoặc bản sao lưu cơ sở dữ liệu. Cần chuẩn bị cơ sở dữ liệu trước khi sử dụng các chức năng truy cập dữ liệu.

## Cấu trúc

- `WebsiteBanHang/Controllers`: xử lý yêu cầu và nghiệp vụ.
- `WebsiteBanHang/Models`: mô hình dữ liệu Entity Framework và view model.
- `WebsiteBanHang/Views`: giao diện Razor.
- `WebsiteBanHang/Content`, `Scripts`, `fonts`: tài nguyên giao diện.
- `WebsiteBanHang/App_Start`: cấu hình route, bundle và filter.

Các thư mục build, bộ nhớ đệm Visual Studio và thư viện NuGet được khôi phục tự động nên không được đưa vào Git.
