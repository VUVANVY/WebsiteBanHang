using System;
using System.IO;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanLy,QuanTriWeb")]
    public class QuanLySanPhamController : Controller
    {
        QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        // ================= INDEX =================
        public ActionResult Index()
        {
            var ds = db.SanPham
                       .Where(n => n.DaXoa == false || n.DaXoa == null)
                       .OrderBy(n => n.MaSP)   // bỏ Descending
                       .ToList();

            return View(ds);
        }

        // ================= TẠO MỚI (GET) =================
        [HttpGet]
        public ActionResult TaoMoi()
        {
            LoadDropdown();
            return View();
        }

        // ================= TẠO MỚI (POST) =================
        [HttpPost]
        [ValidateInput(false)]
        [ValidateAntiForgeryToken]
        public ActionResult TaoMoi(SanPham sp,
            HttpPostedFileBase HinhAnh,
            HttpPostedFileBase HinhAnh1,
            HttpPostedFileBase HinhAnh2,
            HttpPostedFileBase HinhAnh3,
            HttpPostedFileBase HinhAnh4)
        {
            LoadDropdown(sp);

            try
            {
                sp.DaXoa = false;
                sp.NgayCapNhat = DateTime.Now;

                SaveImages(sp, HinhAnh, HinhAnh1, HinhAnh2, HinhAnh3, HinhAnh4);

                db.SanPham.Add(sp);
                db.SaveChanges();

                TempData["Success"] = "Thêm sản phẩm thành công!";
                return RedirectToAction("Index");
            }
            catch (Exception ex)
            {
                TempData["Error"] = "Thêm sản phẩm thất bại! " + ex.Message;
                return View(sp);
            }
        }

        // ================= CHỈNH SỬA (GET) =================
        [HttpGet]
        public ActionResult ChinhSua(int? id)
        {
            if (id == null)
                return new HttpStatusCodeResult(400);

            SanPham sp = db.SanPham.Find(id);

            if (sp == null)
                return HttpNotFound();

            LoadDropdown(sp);
            return View(sp);
        }

        // ================= CHỈNH SỬA (POST) =================
        [HttpPost]
        [ValidateInput(false)]
        [ValidateAntiForgeryToken]
        public ActionResult ChinhSua(SanPham sp)
        {
            try
            {
                SanPham sanPham = db.SanPham.Find(sp.MaSP);
                if (sanPham == null)
                    return HttpNotFound();

                sanPham.TenSP = sp.TenSP;
                sanPham.DonGia = sp.DonGia;
                sanPham.DongCo = sp.DongCo;
                sanPham.MoTa = sp.MoTa;
                sanPham.SoLuongTon = sp.SoLuongTon;
                sanPham.LuotXem = sp.LuotXem;
                sanPham.MaNCC = sp.MaNCC;
                sanPham.MaLoaiSP = sp.MaLoaiSP;
                sanPham.MaNSX = sp.MaNSX;
                sanPham.Moi = sp.Moi;
                sanPham.NgayCapNhat = DateTime.Now;

                db.SaveChanges();

                TempData["Success"] = "Cập nhật thành công!";
                return RedirectToAction("Index");
            }
            catch (Exception ex)
            {
                TempData["Error"] = "Cập nhật thất bại! " + ex.Message;
                LoadDropdown(sp);
                return View(sp);
            }
        }

        // ================= UPLOAD HÌNH (GET) =================
        [HttpGet]
        public ActionResult UploadHinh(int? id)
        {
            if (id == null)
                return new HttpStatusCodeResult(400);

            SanPham sp = db.SanPham.Find(id);

            if (sp == null)
                return HttpNotFound();

            return View(sp);
        }

        // ================= UPLOAD HÌNH (POST) =================
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult UploadHinh(int id,
            HttpPostedFileBase HinhAnh,
            HttpPostedFileBase HinhAnh1,
            HttpPostedFileBase HinhAnh2,
            HttpPostedFileBase HinhAnh3,
            HttpPostedFileBase HinhAnh4)
        {
            try
            {
                SanPham sp = db.SanPham.Find(id);
                if (sp == null)
                    return HttpNotFound();

                SaveImages(sp, HinhAnh, HinhAnh1, HinhAnh2, HinhAnh3, HinhAnh4);

                db.SaveChanges();

                TempData["Success"] = "Cập nhật hình ảnh thành công!";
                return RedirectToAction("Index");
            }
            catch (Exception ex)
            {
                TempData["Error"] = "Upload hình thất bại! " + ex.Message;
                return RedirectToAction("Index");
            }
        }

        // ================= XÓA (SOFT DELETE) =================
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Xoa(int id)
        {
            try
            {
                SanPham sp = db.SanPham.Find(id);
                if (sp == null)
                    return HttpNotFound();

                sp.DaXoa = true;
                db.SaveChanges();

                TempData["Success"] = "Xóa sản phẩm thành công!";
            }
            catch (Exception ex)
            {
                TempData["Error"] = "Xóa thất bại! " + ex.Message;
            }

            return RedirectToAction("Index");
        }

        // ================= HÀM LƯU HÌNH =================
        private void SaveImages(SanPham sp,
            HttpPostedFileBase HinhAnh,
            HttpPostedFileBase HinhAnh1,
            HttpPostedFileBase HinhAnh2,
            HttpPostedFileBase HinhAnh3,
            HttpPostedFileBase HinhAnh4)
        {
            string path = Server.MapPath("~/Content/HinhAnhSP/");

            if (HinhAnh != null && HinhAnh.ContentLength > 0)
            {
                string fileName = Path.GetFileName(HinhAnh.FileName);
                HinhAnh.SaveAs(path + fileName);
                sp.HinhAnh = fileName;
            }

            if (HinhAnh1 != null && HinhAnh1.ContentLength > 0)
            {
                string fileName = Path.GetFileName(HinhAnh1.FileName);
                HinhAnh1.SaveAs(path + fileName);
                sp.HinhAnh1 = fileName;
            }

            if (HinhAnh2 != null && HinhAnh2.ContentLength > 0)
            {
                string fileName = Path.GetFileName(HinhAnh2.FileName);
                HinhAnh2.SaveAs(path + fileName);
                sp.HinhAnh2 = fileName;
            }

            if (HinhAnh3 != null && HinhAnh3.ContentLength > 0)
            {
                string fileName = Path.GetFileName(HinhAnh3.FileName);
                HinhAnh3.SaveAs(path + fileName);
                sp.HinhAnh3 = fileName;
            }

            if (HinhAnh4 != null && HinhAnh4.ContentLength > 0)
            {
                string fileName = Path.GetFileName(HinhAnh4.FileName);
                HinhAnh4.SaveAs(path + fileName);
                sp.HinhAnh4 = fileName;
            }
        }

        // ================= LOAD DROPDOWN =================
        private void LoadDropdown(SanPham sp = null)
        {
            ViewBag.MaNCC = new SelectList(db.NhaCungCap, "MaNCC", "TenNCC", sp?.MaNCC);
            ViewBag.MaLoaiSP = new SelectList(db.LoaiSanPham, "MaLoaiSP", "TenLoai", sp?.MaLoaiSP);
            ViewBag.MaNSX = new SelectList(db.NhaSanXuat, "MaNSX", "TenNSX", sp?.MaNSX);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && db != null)
                db.Dispose();

            base.Dispose(disposing);
        }
    }
}