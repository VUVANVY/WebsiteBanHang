using System;
using System.Collections.Generic;
using System.Linq;
using System.Data.Entity;
using System.Net;
using System.Web;
using System.Web.Mvc;
using WebsiteBanHang.Models;
using PagedList;    

namespace WebsiteBanHang.Controllers
{

    
    public class SanPhamController : Controller
    {
        QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        //tao 2 partial view san pham 1 va 2 de hien thi san pham theo 2 style khac nhau
        [ChildActionOnly]
        public ActionResult SanPhamStyle1Partial()
        {
            

            return PartialView();
        }
        [ChildActionOnly]
        public ActionResult SanPhamStyle2Partial()
        {
            return PartialView();
        }

        //xây dựng trang xem chi tiết
        // GET: SanPham/XemChiTiet/1
        public ActionResult XemChiTiet(int? id,string tensp)
        {
            //check tham số truyền vào có null ko
            if(id == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }

            //nếu ko thì truy xuất csdl lấy ra sp với id tương ứng
            SanPham sp = db.SanPham
                .Include(n => n.LoaiSanPham)
                .Include(n => n.NhaSanXuat)
                .SingleOrDefault(n => n.MaSP == id && n.DaXoa == false);
            if(sp == null)
            {
                //thông báo nếu ko thấy sp này
                return HttpNotFound();
            }

            return View(sp);
        }
  
        //xây dựng action load sp theo mã loại sp và mã nsx
        public ActionResult SanPham(int? MaLoaiSP, int? MaNSX, int? page)
        {
            // Kiểm tra tham số: ít nhất phải có 1 trong 2 mã để lọc
            if (MaLoaiSP == null && MaNSX == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }

            // Truy vấn cơ bản
            var lstSP = db.SanPham
                .Include(n => n.LoaiSanPham)
                .Include(n => n.NhaSanXuat)
                .Where(n => n.DaXoa == false);

            // Lọc theo Loại SP nếu có
            if (MaLoaiSP != null)
            {
                lstSP = lstSP.Where(n => n.MaLoaiSP == MaLoaiSP);
                var loai = db.LoaiSanPham.SingleOrDefault(n => n.MaLoaiSP == MaLoaiSP);
                ViewBag.TenLoai = (loai != null) ? loai.TenLoai : null;
            }

            // Lọc theo NSX nếu có
            if (MaNSX != null)
            {
                lstSP = lstSP.Where(n => n.MaNSX == MaNSX);
                var nsx = db.NhaSanXuat.SingleOrDefault(n => n.MaNSX == MaNSX);
                ViewBag.TenNSX = (nsx != null) ? nsx.TenNSX : null;
            }

            // Lưu tham số cho phân trang
            ViewBag.MaLoaiSP = MaLoaiSP;
            ViewBag.MaNSX = MaNSX;

            return View(PageProducts(lstSP.OrderBy(n => n.MaSP), page));
        }

        // Action phục vụ sidebar hãng xe
        [ChildActionOnly]
        public ActionResult HangPartial(int? MaLoaiSP)
        {
            ViewBag.MaLoaiSP = MaLoaiSP;
            List<int?> lstMaNSX;
            if (MaLoaiSP != null)
            {
                // Lấy danh sách các MaNSX có sản phẩm thuộc loại này và chưa bị xóa
                lstMaNSX = db.SanPham.Where(n => n.MaLoaiSP == MaLoaiSP && n.DaXoa == false).Select(n => n.MaNSX).Distinct().ToList();
            }
            else
            {
                // Nếu không lọc theo loại, lấy tất cả MaNSX có sản phẩm đang kinh doanh
                lstMaNSX = db.SanPham.Where(n => n.DaXoa == false).Select(n => n.MaNSX).Distinct().ToList();
            }

            var lstNSX = db.NhaSanXuat.Where(n => lstMaNSX.Contains(n.MaNSX)).OrderBy(n => n.TenNSX).ToList();
            return PartialView(lstNSX);
        }

        //xây dựng action load sp theo mã loại sp
        public ActionResult LoaiSanPham(int? MaLoaiSP, int? page)
        {
            //check tham số truyền vào có null ko
            if (MaLoaiSP == null)
            {
                return new HttpStatusCodeResult(HttpStatusCode.BadRequest);
            }
            //load sp theo mã loại sp
            var lstSP = db.SanPham
                .Include(n => n.LoaiSanPham)
                .Include(n => n.NhaSanXuat)
                .Where(n => n.MaLoaiSP == MaLoaiSP && n.DaXoa == false);
            
            // Lấy tên loại để hiển thị tiêu đề
            var loai = db.LoaiSanPham.SingleOrDefault(n => n.MaLoaiSP == MaLoaiSP);
            ViewBag.TenLoai = (loai != null) ? loai.TenLoai : "Sản phẩm";
            
            ViewBag.MaLoaiSP = MaLoaiSP;

            return View(PageProducts(lstSP.OrderBy(n => n.MaSP), page));
        }

        private static IPagedList<SanPham> PageProducts(IOrderedQueryable<SanPham> products, int? page)
        {
            const int pageSize = 6;
            int totalItemCount = products.Count();
            int pageCount = Math.Max(1, (int)Math.Ceiling(totalItemCount / (double)pageSize));
            int pageNumber = Math.Min(Math.Max(page ?? 1, 1), pageCount);
            var items = totalItemCount == 0
                ? new List<SanPham>()
                : products.Skip((pageNumber - 1) * pageSize).Take(pageSize).ToList();

            return new StaticPagedList<SanPham>(items, pageNumber, pageSize, totalItemCount);
        }

        //Giải phóng dung lượng biến db, để ở cuối controller
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (db != null)
                {
                    db.Dispose();
                    db = null;
                }
            }
            base.Dispose(disposing);
        }
    }
}
