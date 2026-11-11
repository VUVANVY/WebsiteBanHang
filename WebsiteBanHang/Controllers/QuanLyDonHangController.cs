using System;
using System.Linq;
using System.Web.Mvc;
using WebsiteBanHang.Models;
using System.Data.Entity;

namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanLy,QuanTriWeb")]
    public class QuanLyDonHangController : Controller
    {
        QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        // 1️⃣ CHƯA THANH TOÁN
        public ActionResult ChuaThanhToan()
        {
            var lst = db.DonDatHang
                .Include(d => d.KhachHang)
                .Where(n => n.DaThanhToan == false && n.DaHuy == false)
                .OrderByDescending(n => n.NgayDat)
                .ToList();

            return View(lst);
        }

        // 2️⃣ CHƯA GIAO & ĐÃ THANH TOÁN
        public ActionResult ChuaGiao()
        {
            var lst = db.DonDatHang
                .Include(d => d.KhachHang)
                .Where(n => n.TinhTrangGiaoHang == false
                         && n.DaThanhToan == true
                         && n.DaHuy == false)
                .OrderByDescending(n => n.NgayDat)
                .ToList();

            return View(lst);
        }

        // 3️⃣ ĐÃ GIAO & ĐÃ THANH TOÁN


public ActionResult DaGiaoDaThanhToan()
    {
        var lst = db.DonDatHang
            .Include(x => x.KhachHang)
            .Where(x => x.TinhTrangGiaoHang == true
                     && x.DaThanhToan == true)
            .OrderByDescending(x => x.NgayDat)
            .ToList();

        return View(lst);
    }

        // Duyệt đơn
        public ActionResult DuyetDonHang(int? id)
        {
            if (id == null)
                return HttpNotFound();

            var don = db.DonDatHang
                .Include(d => d.KhachHang)
                .Include(d => d.ChiTietDonDatHang)
                .SingleOrDefault(d => d.MaDDH == id);

            if (don == null)
                return HttpNotFound();

            return View(don);
        }

        // Giao hàng
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult GiaoHang(int id)
        {
            var don = db.DonDatHang.Find(id);
            if (don == null) return HttpNotFound();

            if (don.DaHuy == true || don.DaXoa == true || don.DaThanhToan != true)
                return new HttpStatusCodeResult(409, "Chi giao don hop le da thanh toan.");
            if (don.TinhTrangGiaoHang != true)
            {
                don.TinhTrangGiaoHang = true;
                don.NgayGiao = DateTime.Now;
                db.SaveChanges();
            }

            return RedirectToAction("ChuaGiao");
        }

        // Hủy đơn
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult HuyDon(int id)
        {
            var don = db.DonDatHang.Find(id);
            if (don == null) return HttpNotFound();

            if (don.TinhTrangGiaoHang == true)
                return new HttpStatusCodeResult(409, "Khong huy don da giao.");
            if (don.DaHuy != true)
            {
                don.DaHuy = true;
                db.SaveChanges();
            }

            return RedirectToAction("ChuaThanhToan");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}
