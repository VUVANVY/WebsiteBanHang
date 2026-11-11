-- Generated offline by tools/Export-DemoDatabase.ps1 from QuanLyBanHangModel.edmx.
-- Contains no database export, account, password, customer, order or comment data.
-- Select a NEW dedicated demo database in your SQL client before running this file.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF DB_NAME() IN (N'master', N'model', N'msdb', N'tempdb') THROW 51000, 'Select a dedicated demo database first.', 1;
IF EXISTS (SELECT 1 FROM sys.tables WHERE schema_id = SCHEMA_ID(N'dbo') AND name IN (N'BinhLuan', N'ChiTietDonDatHang', N'ChiTietPhieuNhap', N'DonDatHang', N'KhachHang', N'LoaiSanPham', N'LoaiThanhVien', N'LoaiThanhVien_Quyen', N'NhaCungCap', N'NhaSanXuat', N'PhieuNhap', N'Quyen', N'SanPham', N'sysdiagrams', N'ThanhVien')) THROW 51001, 'Mapped tables already exist; this script never replaces existing tables.', 1;
BEGIN TRY
BEGIN TRANSACTION;
CREATE TABLE [dbo].[BinhLuan] (
    [MaBL] int IDENTITY(1,1) NOT NULL,
    [NoidungBL] nvarchar(max) NULL,
    [MaThanhVien] int NULL,
    [MaSP] int NULL,
    CONSTRAINT [PK_BinhLuan] PRIMARY KEY ([MaBL])
);
CREATE TABLE [dbo].[ChiTietDonDatHang] (
    [MaChiTietDDh] int IDENTITY(1,1) NOT NULL,
    [MaDDH] int NULL,
    [MaSP] int NULL,
    [TenSP] nvarchar(50) NULL,
    [SoLuong] int NULL,
    [Dongia] decimal(18,0) NULL,
    CONSTRAINT [PK_ChiTietDonDatHang] PRIMARY KEY ([MaChiTietDDh])
);
CREATE TABLE [dbo].[ChiTietPhieuNhap] (
    [MaChiTietPN] int IDENTITY(1,1) NOT NULL,
    [MaPN] int NULL,
    [MaSP] int NULL,
    [DonGiaNhap] decimal(18,0) NULL,
    [SoLuongNhap] int NULL,
    CONSTRAINT [PK_ChiTietPhieuNhap] PRIMARY KEY ([MaChiTietPN])
);
CREATE TABLE [dbo].[DonDatHang] (
    [MaDDH] int IDENTITY(1,1) NOT NULL,
    [NgayDat] datetime NULL,
    [TinhTrangGiaoHang] bit NULL,
    [NgayGiao] datetime NULL,
    [DaThanhToan] bit NULL,
    [MaKH] int NULL,
    [UuDai] int NULL,
    [DaHuy] bit NULL,
    [DaXoa] bit NULL,
    CONSTRAINT [PK_DonDatHang] PRIMARY KEY ([MaDDH])
);
CREATE TABLE [dbo].[KhachHang] (
    [MaKH] int IDENTITY(1,1) NOT NULL,
    [TenKH] nvarchar(150) NULL,
    [DiaChi] nvarchar(max) NULL,
    [Email] nvarchar(250) NULL,
    [SoDienThoai] nvarchar(50) NULL,
    [MaThanhVien] int NULL,
    CONSTRAINT [PK_KhachHang] PRIMARY KEY ([MaKH])
);
CREATE TABLE [dbo].[LoaiSanPham] (
    [MaLoaiSP] int IDENTITY(1,1) NOT NULL,
    [TenLoai] nvarchar(150) NULL,
    [Icon] nvarchar(max) NULL,
    [BiDanh] nvarchar(50) NULL,
    CONSTRAINT [PK_LoaiSanPham] PRIMARY KEY ([MaLoaiSP])
);
CREATE TABLE [dbo].[LoaiThanhVien] (
    [MaLoaiTV] int IDENTITY(1,1) NOT NULL,
    [TenLoai] nvarchar(50) NULL,
    [UuDai] int NULL,
    CONSTRAINT [PK_LoaiThanhVien] PRIMARY KEY ([MaLoaiTV])
);
CREATE TABLE [dbo].[LoaiThanhVien_Quyen] (
    [MaLoaiTV] int NOT NULL,
    [MaQuyen] nvarchar(50) NOT NULL,
    [GhiChu] nvarchar(max) NULL,
    CONSTRAINT [PK_LoaiThanhVien_Quyen] PRIMARY KEY ([MaLoaiTV], [MaQuyen])
);
CREATE TABLE [dbo].[NhaCungCap] (
    [MaNCC] int IDENTITY(1,1) NOT NULL,
    [TenNCC] nvarchar(150) NULL,
    [DiaChi] nvarchar(max) NULL,
    [Email] nvarchar(250) NULL,
    [SoDienThoai] varchar(20) NULL,
    [Fax] nvarchar(50) NULL,
    CONSTRAINT [PK_NhaCungCap] PRIMARY KEY ([MaNCC])
);
CREATE TABLE [dbo].[NhaSanXuat] (
    [MaNSX] int IDENTITY(1,1) NOT NULL,
    [TenNSX] nvarchar(100) NULL,
    [ThongTin] nvarchar(250) NULL,
    CONSTRAINT [PK_NhaSanXuat] PRIMARY KEY ([MaNSX])
);
CREATE TABLE [dbo].[PhieuNhap] (
    [MaPN] int IDENTITY(1,1) NOT NULL,
    [MaNCC] int NULL,
    [NgayNhap] datetime NULL,
    [DaXoa] bit NULL,
    CONSTRAINT [PK_PhieuNhap] PRIMARY KEY ([MaPN])
);
CREATE TABLE [dbo].[Quyen] (
    [MaQuyen] nvarchar(50) NOT NULL,
    [TenQuyen] nvarchar(100) NULL,
    CONSTRAINT [PK_Quyen] PRIMARY KEY ([MaQuyen])
);
CREATE TABLE [dbo].[SanPham] (
    [MaSP] int IDENTITY(1,1) NOT NULL,
    [TenSP] nvarchar(250) NULL,
    [DonGia] decimal(18,0) NULL,
    [NgayCapNhat] datetime NULL,
    [DongCo] nvarchar(max) NULL,
    [MoTa] nvarchar(max) NULL,
    [HinhAnh] nvarchar(max) NULL,
    [SoLuongTon] int NULL,
    [LuotXem] int NULL,
    [LuotBinhChon] int NULL,
    [LuotBinhLuan] int NULL,
    [SoLuotMua] int NULL,
    [Moi] int NULL,
    [MaNCC] int NULL,
    [MaNSX] int NULL,
    [MaLoaiSP] int NULL,
    [DaXoa] bit NULL,
    [HinhAnh1] nvarchar(max) NULL,
    [HinhAnh2] nvarchar(max) NULL,
    [HinhAnh3] nvarchar(max) NULL,
    [HinhAnh4] nvarchar(max) NULL,
    CONSTRAINT [PK_SanPham] PRIMARY KEY ([MaSP])
);
CREATE TABLE [dbo].[sysdiagrams] (
    [name] nvarchar(128) NOT NULL,
    [principal_id] int NOT NULL,
    [diagram_id] int IDENTITY(1,1) NOT NULL,
    [version] int NULL,
    [definition] varbinary(max) NULL,
    CONSTRAINT [PK_sysdiagrams] PRIMARY KEY ([diagram_id])
);
CREATE TABLE [dbo].[ThanhVien] (
    [MaThanhVien] int IDENTITY(1,1) NOT NULL,
    [TaiKhoan] nvarchar(150) NULL,
    [MatKhau] nvarchar(150) NULL,
    [HoTen] nvarchar(50) NULL,
    [DiaChi] nvarchar(250) NULL,
    [Email] nvarchar(250) NULL,
    [SoDienThoai] varchar(50) NULL,
    [CauHoi] nvarchar(max) NULL,
    [CauTraLoi] nvarchar(max) NULL,
    [MaLoaiTV] int NULL,
    CONSTRAINT [PK_ThanhVien] PRIMARY KEY ([MaThanhVien])
);
ALTER TABLE [dbo].[BinhLuan] WITH CHECK ADD CONSTRAINT [FK_BinhLuan_SanPham] FOREIGN KEY ([MaSP]) REFERENCES [dbo].[SanPham] ([MaSP]);
ALTER TABLE [dbo].[BinhLuan] WITH CHECK ADD CONSTRAINT [FK_BinhLuan_ThanhVien] FOREIGN KEY ([MaThanhVien]) REFERENCES [dbo].[ThanhVien] ([MaThanhVien]);
ALTER TABLE [dbo].[ChiTietDonDatHang] WITH CHECK ADD CONSTRAINT [FK_ChiTietDonDatHang_DonDatHang] FOREIGN KEY ([MaDDH]) REFERENCES [dbo].[DonDatHang] ([MaDDH]);
ALTER TABLE [dbo].[ChiTietDonDatHang] WITH CHECK ADD CONSTRAINT [FK_ChiTietDonDatHang_SanPham] FOREIGN KEY ([MaSP]) REFERENCES [dbo].[SanPham] ([MaSP]);
ALTER TABLE [dbo].[ChiTietPhieuNhap] WITH CHECK ADD CONSTRAINT [FK_ChiTietPhieuNhap_PhieuNhap] FOREIGN KEY ([MaPN]) REFERENCES [dbo].[PhieuNhap] ([MaPN]);
ALTER TABLE [dbo].[ChiTietPhieuNhap] WITH CHECK ADD CONSTRAINT [FK_ChiTietPhieuNhap_SanPham] FOREIGN KEY ([MaSP]) REFERENCES [dbo].[SanPham] ([MaSP]);
ALTER TABLE [dbo].[DonDatHang] WITH CHECK ADD CONSTRAINT [FK_DonDatHang_KhachHang] FOREIGN KEY ([MaKH]) REFERENCES [dbo].[KhachHang] ([MaKH]) ON DELETE CASCADE;
ALTER TABLE [dbo].[KhachHang] WITH CHECK ADD CONSTRAINT [FK_KhachHang_ToTable] FOREIGN KEY ([MaThanhVien]) REFERENCES [dbo].[ThanhVien] ([MaThanhVien]) ON DELETE CASCADE;
ALTER TABLE [dbo].[LoaiThanhVien_Quyen] WITH CHECK ADD CONSTRAINT [FK_LoaiThanhVien_Quyen_LoaiThanhVien] FOREIGN KEY ([MaLoaiTV]) REFERENCES [dbo].[LoaiThanhVien] ([MaLoaiTV]);
ALTER TABLE [dbo].[LoaiThanhVien_Quyen] WITH CHECK ADD CONSTRAINT [FK_LoaiThanhVien_Quyen_Quyen] FOREIGN KEY ([MaQuyen]) REFERENCES [dbo].[Quyen] ([MaQuyen]);
ALTER TABLE [dbo].[PhieuNhap] WITH CHECK ADD CONSTRAINT [FK_PhieuNhap_ToTable] FOREIGN KEY ([MaNCC]) REFERENCES [dbo].[NhaCungCap] ([MaNCC]) ON DELETE CASCADE;
ALTER TABLE [dbo].[SanPham] WITH CHECK ADD CONSTRAINT [FK_SanPham_LoaiSP] FOREIGN KEY ([MaLoaiSP]) REFERENCES [dbo].[LoaiSanPham] ([MaLoaiSP]);
ALTER TABLE [dbo].[SanPham] WITH CHECK ADD CONSTRAINT [FK_SanPham_NhaCungCap] FOREIGN KEY ([MaNCC]) REFERENCES [dbo].[NhaCungCap] ([MaNCC]);
ALTER TABLE [dbo].[SanPham] WITH CHECK ADD CONSTRAINT [FK_SanPham_NhaSanXuat] FOREIGN KEY ([MaNSX]) REFERENCES [dbo].[NhaSanXuat] ([MaNSX]);
ALTER TABLE [dbo].[ThanhVien] WITH CHECK ADD CONSTRAINT [FK_ThanhVien_ToTable] FOREIGN KEY ([MaLoaiTV]) REFERENCES [dbo].[LoaiThanhVien] ([MaLoaiTV]) ON DELETE CASCADE;
COMMIT TRANSACTION;
END TRY
BEGIN CATCH
IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
THROW;
END CATCH;
