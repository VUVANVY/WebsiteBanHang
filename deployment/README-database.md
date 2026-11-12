# Cơ sở dữ liệu

Thư mục `Database/` chứa cấu trúc SQL Server theo mô hình EDMX và dữ liệu mẫu cho ứng dụng.

## Khởi tạo

1. Tạo và chọn một cơ sở dữ liệu SQL Server mới, trống. Chỉ chạy các script khởi tạo trên cơ sở dữ liệu này.
2. Chạy lần lượt [01-schema.sql](Database/01-schema.sql), [02-seed-demo.sql](Database/02-seed-demo.sql), [03-verify-demo.sql](Database/03-verify-demo.sql). Bước kiểm tra cần thực hiện ngay sau khi thêm dữ liệu mẫu, trước khi sử dụng ứng dụng.
3. Cập nhật connection string `QuanLyBanHangEntities` trong cấu hình ứng dụng bằng thông tin máy chủ SQL và cơ sở dữ liệu vừa tạo.

Publish thư mục `Content/HinhAnhSP` cùng website để hiển thị ảnh sản phẩm.

## Dữ liệu mẫu

Cấu trúc gồm 15 bảng. Dữ liệu mẫu có 13 sản phẩm, 3 nhóm sản phẩm, 3 hãng và 1 nhà cung cấp; tên, giá và thông tin sản phẩm chỉ dùng minh họa.

Loại thành viên và quyền tương ứng: `1 = QuanTriWeb`, `2 = QuanLy`, `3 = KhachHang`.

Các bảng thành viên, khách hàng, đơn hàng, bình luận và phiếu nhập được để trống. Script không tạo tài khoản hoặc mật khẩu dùng chung.

## Tạo lại script

Chạy từ thư mục gốc dự án bằng PowerShell 7:

```powershell
pwsh -NoProfile -File .\tools\Export-DemoDatabase.ps1
```
