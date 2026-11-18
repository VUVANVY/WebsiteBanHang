using System;
using System.Collections.Generic;
using System.Linq;
using System.Data.Entity;
using System.Web;
using System.Web.Mvc;
using WebsiteBanHang.Models;
using PagedList;

namespace WebsiteBanHang.Controllers
{
    public class TimKiemController : Controller
    {

        private readonly QuanLyBanHangEntities db = new QuanLyBanHangEntities();
        // GET: TimKiem
        [HttpGet]
        public ActionResult KQTimKiem(string sTuKhoa, int? page)
        {
            const int pageSize = 6;

            // Nếu không nhập gì
            if (string.IsNullOrWhiteSpace(sTuKhoa))
            {
                ViewBag.TuKhoa = "";
                ViewBag.ThongBao = "Vui lòng nhập từ khóa tìm kiếm!";
                return View(new StaticPagedList<SanPham>(new List<SanPham>(), 1, pageSize, 0));
            }

            var lstSP = db.SanPham
                          .Include(n => n.LoaiSanPham)
                          .Include(n => n.NhaSanXuat)
                          .Where(n => n.DaXoa == false && n.TenSP.Contains(sTuKhoa))
                          .OrderBy(n => n.TenSP);

            ViewBag.TuKhoa = sTuKhoa;

            int totalItemCount = lstSP.Count();
            int pageCount = Math.Max(1, (int)Math.Ceiling(totalItemCount / (double)pageSize));
            int pageNumber = Math.Min(Math.Max(page ?? 1, 1), pageCount);
            var items = totalItemCount == 0
                ? new List<SanPham>()
                : lstSP.Skip((pageNumber - 1) * pageSize).Take(pageSize).ToList();

            return View(new StaticPagedList<SanPham>(items, pageNumber, pageSize, totalItemCount));
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}
