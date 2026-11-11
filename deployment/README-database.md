# Cơ sở dữ liệu demo

Các script trong `Database/` được sinh **offline từ mô hình EDMX công khai** và dữ liệu giả định viết trong `tools/Export-DemoDatabase.ps1`. Công cụ không kết nối SQL Server, không đọc hoặc xuất dữ liệu từ máy cá nhân.

## Khởi tạo trên hosting

1. Tạo một cơ sở dữ liệu SQL Server **mới, riêng cho bản demo** bằng trang quản lý của hosting. Không chạy các script này trong cơ sở dữ liệu đang sử dụng hoặc trong `master`.
2. Mở SQL client được hosting hỗ trợ và chọn cơ sở dữ liệu demo đó.
3. Chạy lần lượt `Database/01-schema.sql`, `Database/02-seed-demo.sql`, rồi `Database/03-verify-demo.sql`.
4. Cấu hình connection string `QuanLyBanHangEntities` bằng thông tin SQL của hosting theo hướng dẫn triển khai chính. Không đưa mật khẩu vào Git.
5. Publish cả thư mục `Content/HinhAnhSP` cùng website. Dữ liệu seed trỏ tới những ảnh đã có trong mã nguồn.

`01-schema.sql` từ chối chạy nếu có bảng ứng dụng cùng tên; `02-seed-demo.sql` từ chối chạy nếu bất kỳ bảng ứng dụng nào đã có dữ liệu. Các script không xóa, ghi đè hoặc cập nhật dữ liệu cũ. Nếu cần làm lại bản demo, tạo một database demo trống mới bằng công cụ của hosting.

## Dữ liệu được tạo

- 15 bảng đúng tên, kiểu SQL, độ dài, precision/scale, nullability, khóa chính, identity và khóa ngoại được mô tả trong EDMX; giữ các quan hệ cascade có trong EDMX.
- 13 sản phẩm giả định, giá minh họa, 3 nhóm sản phẩm, 3 hãng giả định và 1 nhà cung cấp giả không có thông tin liên hệ.
- Nhóm sản phẩm dùng ID `1`, `2`, `7` để khớp trang chủ; số lượng tương ứng `4`, `4`, `5`. Nhóm ID `7` có ít nhất 5 sản phẩm để hiện khối nổi bật.
- Sản phẩm có `Moi = 1`, `DaXoa = 0` và tồn kho demo để trang danh sách/chi tiết hoạt động.
- Loại thành viên: `1 = QuanTriWeb`, `2 = QuanLy`, `3 = KhachHang`; mỗi loại có liên kết quyền tương ứng. Loại `3` khớp với luồng đăng ký khách hàng của ứng dụng.
- Các bảng thành viên, khách hàng, đơn hàng, chi tiết đơn, bình luận và phiếu nhập đều **để trống**. Không tạo tài khoản hoặc mật khẩu quản trị dùng chung.

Kiểm tra `03-verify-demo.sql` được thiết kế để chạy ngay sau seed, trước khi bạn tự tạo tài khoản quản trị hoặc sử dụng website. Sau khi website đã có hoạt động, số lượng dòng sẽ thay đổi và kiểm tra này không còn là kiểm tra tình trạng hoạt động chung.

## Sinh lại script

Từ thư mục gốc dự án, chạy PowerShell:

```powershell
pwsh -NoProfile -File .\tools\Export-DemoDatabase.ps1
```

Công cụ kiểm tra đủ 15 bảng, các cột/khóa tham chiếu trong EDMX, kiểu dữ liệu, độ dài chuỗi seed và sự tồn tại của các ảnh minh họa trước khi ghi ra SQL. Kết quả tái lập được và không chứa thời gian sinh ngẫu nhiên.

EDMX không lưu định nghĩa mọi index phụ, default/check constraint, trigger, stored procedure hoặc expression của cột computed từ database gốc. Các đối tượng không có trong EDMX không được phục hồi bởi công cụ này; đây là database demo tương thích mô hình ứng dụng, không phải bản backup đầy đủ. Công cụ sẽ dừng nếu mô hình xuất hiện kiểu hoặc cột computed chưa hỗ trợ để tránh sinh cấu trúc sai.

Các script đã được đối chiếu tĩnh với EDMX và dữ liệu seed; không được thực thi trên database thật của máy phát triển trong quá trình chuẩn bị.
