using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using WebsiteBanHang.Models;
using PagedList;

namespace WebsiteBanHang.Controllers
{
    public class TimKiemController : Controller
    {

        QuanLyBanHangEntities db = new QuanLyBanHangEntities();
        // GET: TimKiem
        [HttpGet]
        public ActionResult KQTimKiem(string sTuKhoa, int? page)
        {
            int PageSize = 6;
            int PageNumber = page ?? 1;

            // Nếu không nhập gì
            if (string.IsNullOrWhiteSpace(sTuKhoa))
            {
                ViewBag.TuKhoa = "";
                ViewBag.ThongBao = "Vui lòng nhập từ khóa tìm kiếm!";
                return View(new List<SanPham>().ToPagedList(1, PageSize));
            }

            var lstSP = db.SanPham
                          .Where(n => n.TenSP.Contains(sTuKhoa))
                          .OrderBy(n => n.TenSP);

            ViewBag.TuKhoa = sTuKhoa;

            return View(lstSP.ToPagedList(PageNumber, PageSize));
        }
    }
}