using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using WebsiteBanHang.Models;
using PagedList;
namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanLy,QuanTriWeb")]
    public class QuanLyPhieuNhapController : Controller
    {
        QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        // GET: QuanLyPhieuNhap
        [HttpGet]
        public ActionResult NhapHang()
        {
            ViewBag.MaNCC = db.NhaCungCap;
            ViewBag.ListSanPham = db.SanPham;
            ViewBag.NgayNhap = DateTime.Today;

            return View();
        }
        [HttpPost]
        public ActionResult NhapHang(PhieuNhap model, List<ChiTietPhieuNhap> lstModel)
        {
            if (lstModel == null || !lstModel.Any())
            {
                ModelState.AddModelError("", "Danh sách sản phẩm rỗng");
                return View(model);
            }

            db.PhieuNhap.Add(model);
            db.SaveChanges();

            foreach (var item in lstModel)
            {
                var sp = db.SanPham.SingleOrDefault(n => n.MaSP == item.MaSP);
                if (sp == null) continue;
            }

            db.SaveChanges();
            return RedirectToAction("Index");
        }

        [HttpGet]
        public ActionResult DSSPHetHang(int? page)
        {
            int pageSize = 6;
            int pageNumber = page ?? 1;

            var lstSP = db.SanPham
                          .Where(n => (n.DaXoa == false || n.DaXoa == null)
                                   && n.SoLuongTon <= 5)
                          .OrderBy(n => n.MaSP)
                          .ToPagedList(pageNumber, pageSize);

            return View(lstSP);
        }

        [HttpGet]
        public ActionResult NhapHangDon(int? id)
        {
            ViewBag.MaNCC = new SelectList(db.NhaCungCap.OrderBy(n => n.TenNCC), "MaNCC", "TenNCC");

            if(id == null)
            {
                Response.StatusCode = 404;
                return null;
            }
            SanPham sp = db.SanPham.SingleOrDefault(n => n.MaSP == id);
            if (sp == null)
                return HttpNotFound();
            return View(sp);
        }

        [HttpPost]
        public ActionResult NhapHangDon(PhieuNhap model, ChiTietPhieuNhap ctpn)
        {
            ViewBag.MaNCC = new SelectList(db.NhaCungCap.OrderBy(n => n.TenNCC), "MaNCC", "TenNCC", model.MaNCC);

            model.NgayNhap = DateTime.Now;
            model.DaXoa = false;
            db.PhieuNhap.Add(model);
            db.SaveChanges();   //save để lấy MaPN gán cho lst chitietpn

            ctpn.MaPN = model.MaPN;
            SanPham sp = db.SanPham.Single(n => n.MaSP == ctpn.MaSP);
            sp.SoLuongTon += ctpn.SoLuongNhap;
            db.ChiTietPhieuNhap.Add(ctpn);
            db.SaveChanges();

            return View(sp);
        }

        //Giải phóng dung lượng biến db, để ở cuối controller
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (db != null)
                    db.Dispose();
                db.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
