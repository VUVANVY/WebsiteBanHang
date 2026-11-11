using System;
using System.Linq;
using System.Web.Mvc;
using WebsiteBanHang.Models;
using System.Data.Entity;
using iTextSharp.text;
using iTextSharp.text.pdf;
using System.IO;


namespace WebsiteBanHang.Controllers
{

    public class DonHangController : Controller
    {
        QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        // =============================
        // DANH SÁCH ĐƠN
        // =============================
        public ActionResult Index(string trangThai)
        {
            if (Session["TaiKhoan"] == null)
                return RedirectToAction("DangNhap", "ThanhVien");

            ThanhVien tv = (ThanhVien)Session["TaiKhoan"];

            var kh = db.KhachHang
                .FirstOrDefault(x => x.MaThanhVien == tv.MaThanhVien);

            var query = db.DonDatHang
                .Where(d => d.MaKH == kh.MaKH && d.DaXoa == false);

            if (trangThai == "chuatt")
                query = query.Where(d => d.DaThanhToan == false);

            if (trangThai == "hoanthanh")
                query = query.Where(d => d.TinhTrangGiaoHang == true);

            var dsDon = query
                .OrderByDescending(d => d.NgayDat)
                .ToList();

            return View(dsDon);
        }

        // =============================
        // CHI TIẾT ĐƠN
        // =============================
        public ActionResult ChiTiet(int id)
        {
            if (Session["TaiKhoan"] == null)
                return RedirectToAction("DangNhap", "ThanhVien");

            ThanhVien tv = (ThanhVien)Session["TaiKhoan"];

            var kh = db.KhachHang
                .FirstOrDefault(x => x.MaThanhVien == tv.MaThanhVien);

            var don = db.DonDatHang
                .Include(d => d.ChiTietDonDatHang)
                .Include(d => d.KhachHang)
                .SingleOrDefault(d => d.MaDDH == id && d.MaKH == kh.MaKH);

            if (don == null)
                return HttpNotFound();

            return View(don);
        }

        // =============================
        // HỦY ĐƠN
        // =============================
        public ActionResult HuyDon(int id)
        {
            var don = db.DonDatHang
                .Include(d => d.ChiTietDonDatHang)
                .SingleOrDefault(d => d.MaDDH == id);

            if (don == null)
                return HttpNotFound();

            if (don.DaThanhToan == true)
                return RedirectToAction("ChiTiet", new { id });

            // 🔥 HOÀN TRẢ TỒN KHO
            foreach (var item in don.ChiTietDonDatHang)
            {
                var sp = db.SanPham.Find(item.MaSP);
                if (sp != null)
                {
                    sp.SoLuongTon += item.SoLuong;
                }
            }

            don.DaHuy = true;
            don.DaXoa = true;

            db.SaveChanges();

            return RedirectToAction("Index");
        }
        // =============================
        // THANH TOÁN
        // =============================
        public ActionResult ThanhToan(int id)
        {
            var don = db.DonDatHang.Find(id);
            if (don == null)
                return HttpNotFound();

            // Chỉ cập nhật thanh toán
            don.DaThanhToan = true;

            db.SaveChanges();

            return RedirectToAction("ChiTiet", new { id = id });
        }
        public FileResult XuatHoaDon(int id)
        {
            var don = db.DonDatHang
                .Include(d => d.ChiTietDonDatHang)
                .Include(d => d.KhachHang)
                .SingleOrDefault(d => d.MaDDH == id);

            if (don == null)
                return null;

            MemoryStream ms = new MemoryStream();
            Document doc = new Document(PageSize.A4);
            PdfWriter.GetInstance(doc, ms);
            doc.Open();

            doc.Add(new Paragraph("HOA DON BAN HANG"));
            doc.Add(new Paragraph("Ma don: " + don.MaDDH));
            doc.Add(new Paragraph("Khach hang: " + don.KhachHang?.TenKH));
            doc.Add(new Paragraph("Ngay dat: " + don.NgayDat));
            doc.Add(new Paragraph(" "));

            PdfPTable table = new PdfPTable(4);
            table.AddCell("San pham");
            table.AddCell("So luong");
            table.AddCell("Don gia");
            table.AddCell("Thanh tien");

            foreach (var item in don.ChiTietDonDatHang)
            {
                table.AddCell(item.TenSP);
                table.AddCell(item.SoLuong.ToString());
                table.AddCell(item.Dongia.HasValue
        ? item.Dongia.Value.ToString("N0")
        : "0");

                decimal thanhTien = (item.SoLuong ?? 0) * (item.Dongia ?? 0);

                table.AddCell(thanhTien.ToString("N0"));
            }

            doc.Add(table);
            doc.Close();

            byte[] bytes = ms.ToArray();
            ms.Close();

            return File(bytes, "application/pdf", "HoaDon_" + don.MaDDH + ".pdf");
        }
    }

}
