# MotoShop

Website bán xe máy với giao diện khách hàng và trang quản trị.

Demo: [motoshop.somee.com](https://motoshop.somee.com/).

## Công nghệ

- C#, ASP.NET MVC 5, .NET Framework 4.7.2.
- SQL Server, Entity Framework 6 theo hướng Database First.
- Razor, HTML/CSS, Bootstrap, JavaScript, jQuery và AJAX.

## Chức năng

| Phần | Chức năng |
| --- | --- |
| Khách hàng | Đăng ký, đăng nhập; tìm kiếm, lọc và phân trang sản phẩm; giỏ hàng, đặt hàng, theo dõi đơn và xuất hóa đơn PDF. |
| Quản trị | Quản lý sản phẩm, hình ảnh, danh mục, hãng, thành viên và quyền; nhập hàng, theo dõi tồn kho, xử lý đơn và thống kê doanh thu. |

## Cài đặt

Yêu cầu Windows, Visual Studio có **ASP.NET and web development**, .NET Framework 4.7.2 Developer Pack và SQL Server.

1. Mở `WebsiteBanHang.sln`, chọn **Restore NuGet Packages**.
2. Tạo database `QuanLyBanHang` trống và chạy các script theo [hướng dẫn cơ sở dữ liệu](deployment/README-database.md).
3. Cập nhật kết nối `QuanLyBanHangEntities` trong `WebsiteBanHang/Web.config` theo SQL Server trên máy.
4. Chọn `WebsiteBanHang` làm startup project, build và nhấn **F5** để chạy bằng IIS Express.

Database đi kèm có dữ liệu sản phẩm mẫu. Tài khoản khách tạo qua trang đăng ký; tài khoản quản trị được tạo theo [hướng dẫn triển khai](deployment/README.md).

## Kiểm tra

Sau khi publish, chạy `.\tools\Test-Deployment.ps1` để kiểm tra đăng nhập, phân quyền, giỏ hàng, đơn hàng và hóa đơn. Cần IIS Express và SQL Server Express cục bộ; script sử dụng database tạm riêng.
