# MotoShop

Website bán xe máy với giao diện khách hàng và trang quản trị.

## Công nghệ

- C#, ASP.NET MVC 5, .NET Framework 4.7.2.
- SQL Server, Entity Framework 6 theo hướng Database First.
- Razor, HTML/CSS, Bootstrap, JavaScript, jQuery và AJAX.

## Chức năng

- Đăng ký, đăng nhập và phân quyền người dùng.
- Tìm kiếm, lọc sản phẩm theo loại và hãng, phân trang danh sách.
- Quản lý giỏ hàng, đặt hàng, theo dõi đơn và xuất hóa đơn PDF.
- Quản trị sản phẩm, hình ảnh, danh mục, nhà sản xuất và thành viên.
- Nhập hàng, theo dõi tồn kho, trạng thái giao hàng và thống kê doanh thu.

## Cài đặt

Yêu cầu Windows, Visual Studio có **ASP.NET and web development**, .NET Framework 4.7.2 Developer Pack và SQL Server.

1. Mở `WebsiteBanHang.sln`, chọn **Restore NuGet Packages**.
2. Tạo database `QuanLyBanHang` trống và chạy các script theo [hướng dẫn cơ sở dữ liệu](deployment/README-database.md).
3. Cập nhật kết nối `QuanLyBanHangEntities` trong `WebsiteBanHang/Web.config` theo SQL Server trên máy.
4. Chọn `WebsiteBanHang` làm startup project, build và nhấn **F5** để chạy bằng IIS Express.

Database đi kèm có dữ liệu sản phẩm mẫu; tài khoản được tạo khi sử dụng ứng dụng.

Xem thêm [hướng dẫn triển khai trên IIS](deployment/README.md).
