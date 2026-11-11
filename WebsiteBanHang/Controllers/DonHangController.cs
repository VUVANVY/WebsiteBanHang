using System;
using System.Data.Entity;
using System.IO;
using System.Linq;
using System.Web.Mvc;
using iTextSharp.text;
using iTextSharp.text.pdf;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    [Authorize]
    public class DonHangController : Controller
    {
        private readonly QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        [HttpGet]
        public ActionResult Index(string trangThai)
        {
            var member = CurrentMember();
            if (member == null)
                return RedirectToAction("Index", "Home");
            var query = db.DonDatHang.Where(d => d.KhachHang.MaThanhVien == member.MaThanhVien && d.DaXoa != true);
            if (trangThai == "chuatt")
                query = query.Where(d => d.DaThanhToan != true);
            if (trangThai == "hoanthanh")
                query = query.Where(d => d.TinhTrangGiaoHang == true);
            return View(query.OrderByDescending(d => d.NgayDat).ToList());
        }

        [HttpGet]
        public ActionResult ChiTiet(int id)
        {
            var member = CurrentMember();
            if (member == null)
                return RedirectToAction("Index", "Home");
            var order = OwnedOrders(member.MaThanhVien).SingleOrDefault(d => d.MaDDH == id && d.DaXoa != true);
            return order == null ? (ActionResult)HttpNotFound() : View(order);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult HuyDon(int id)
        {
            var member = CurrentMember();
            if (member == null)
                return RedirectToAction("Index", "Home");
            var order = OwnedOrders(member.MaThanhVien).SingleOrDefault(d => d.MaDDH == id);
            if (order == null)
                return HttpNotFound();
            if (order.DaHuy == true)
                return RedirectToAction("Index");
            if (order.DaXoa == true)
                return HttpNotFound();
            if (order.DaThanhToan == true || order.TinhTrangGiaoHang == true)
                return new HttpStatusCodeResult(409, "Khong the huy don da thanh toan hoac da giao.");
            // Checkout does not reserve stock, so cancellation must not add stock.
            order.DaHuy = true;
            order.DaXoa = true;
            db.SaveChanges();
            return RedirectToAction("Index");
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult ThanhToan(int id)
        {
            var member = CurrentMember();
            if (member == null)
                return RedirectToAction("Index", "Home");
            var order = OwnedOrders(member.MaThanhVien).SingleOrDefault(d => d.MaDDH == id && d.DaXoa != true);
            if (order == null)
                return HttpNotFound();
            if (order.DaHuy == true)
                return new HttpStatusCodeResult(409, "Khong the thanh toan don da huy.");
            if (order.DaThanhToan != true)
            {
                // Preserve the existing demo status update, not a payment gateway.
                order.DaThanhToan = true;
                db.SaveChanges();
            }
            return RedirectToAction("ChiTiet", new { id });
        }

        [HttpGet]
        public ActionResult XuatHoaDon(int id)
        {
            var member = CurrentMember();
            if (member == null)
                return RedirectToAction("Index", "Home");
            var order = OwnedOrders(member.MaThanhVien).SingleOrDefault(d => d.MaDDH == id && d.DaXoa != true);
            if (order == null)
                return HttpNotFound();
            using (var stream = new MemoryStream())
            using (var document = new Document(PageSize.A4))
            {
                var writer = PdfWriter.GetInstance(document, stream);
                writer.CloseStream = false;
                document.Open();
                document.Add(new Paragraph("HOA DON BAN HANG"));
                document.Add(new Paragraph("Ma don: " + order.MaDDH));
                document.Add(new Paragraph("Khach hang: " + order.KhachHang.TenKH));
                document.Add(new Paragraph("Ngay dat: " + order.NgayDat));
                document.Add(new Paragraph(" "));
                var table = new PdfPTable(4);
                table.AddCell("San pham");
                table.AddCell("So luong");
                table.AddCell("Don gia");
                table.AddCell("Thanh tien");
                foreach (var item in order.ChiTietDonDatHang)
                {
                    table.AddCell(item.TenSP ?? "");
                    table.AddCell((item.SoLuong ?? 0).ToString());
                    table.AddCell((item.Dongia ?? 0).ToString("N0"));
                    table.AddCell(((item.SoLuong ?? 0) * (item.Dongia ?? 0)).ToString("N0"));
                }
                document.Add(table);
                document.Close();
                return File(stream.ToArray(), "application/pdf", "HoaDon_" + order.MaDDH + ".pdf");
            }
        }

        private ThanhVien CurrentMember()
        {
            var member = Session["TaiKhoan"] as ThanhVien;
            return User.Identity.IsAuthenticated && member != null
                   && string.Equals(User.Identity.Name, member.TaiKhoan, StringComparison.OrdinalIgnoreCase)
                ? member : null;
        }

        private IQueryable<DonDatHang> OwnedOrders(int memberId)
        {
            return db.DonDatHang.Include(d => d.ChiTietDonDatHang).Include(d => d.KhachHang)
                .Where(d => d.KhachHang.MaThanhVien == memberId);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}
