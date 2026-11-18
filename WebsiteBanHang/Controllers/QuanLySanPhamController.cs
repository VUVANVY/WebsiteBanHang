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
        public ActionResult TaoMoi([Bind(Include = "TenSP,DonGia,DongCo,MoTa,SoLuongTon,LuotXem,MaNCC,MaLoaiSP,MaNSX,Moi")] SanPham sp,
            HttpPostedFileBase HinhAnh,
            HttpPostedFileBase HinhAnh1,
            HttpPostedFileBase HinhAnh2,
            HttpPostedFileBase HinhAnh3,
            HttpPostedFileBase HinhAnh4)
        {
            sp = sp ?? new SanPham();
            LoadDropdown(sp);
            ValidateProduct(sp);
            if (!ModelState.IsValid)
                return View(sp);

            try
            {
                sp.DaXoa = false;
                sp.NgayCapNhat = DateTime.Now;
                sp.Moi = sp.Moi == 1 ? 1 : 0;
                sp.LuotXem = sp.LuotXem ?? 0;
                sp.LuotBinhChon = 0;
                sp.LuotBinhLuan = 0;
                sp.SoLuotMua = 0;

                SaveImages(sp, HinhAnh, HinhAnh1, HinhAnh2, HinhAnh3, HinhAnh4);

                db.SanPham.Add(sp);
                db.SaveChanges();

                TempData["Success"] = "Thêm sản phẩm thành công!";
                return RedirectToAction("Index");
            }
            catch (Exception)
            {
                ModelState.AddModelError("", "Chưa lưu được sản phẩm. Vui lòng kiểm tra thông tin và quyền ghi thư mục hình ảnh rồi thử lại.");
                return View(sp);
            }
        }

        // ================= CHỈNH SỬA (GET) =================
        [HttpGet]
        public ActionResult ChinhSua(int? id)
        {
            if (id == null)
                return HttpNotFound();

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
        public ActionResult ChinhSua([Bind(Include = "MaSP,TenSP,DonGia,DongCo,MoTa,SoLuongTon,LuotXem,MaNCC,MaLoaiSP,MaNSX,Moi")] SanPham sp)
        {
            if (sp == null || sp.MaSP <= 0)
                return HttpNotFound();

            SanPham sanPham = db.SanPham.Find(sp.MaSP);
            if (sanPham == null)
                return HttpNotFound();

            LoadDropdown(sp);
            ValidateProduct(sp);
            if (!ModelState.IsValid)
                return View(sanPham);

            try
            {
                sanPham.TenSP = sp.TenSP;
                sanPham.DonGia = sp.DonGia;
                sanPham.DongCo = sp.DongCo;
                sanPham.MoTa = sp.MoTa;
                sanPham.SoLuongTon = sp.SoLuongTon;
                sanPham.LuotXem = sp.LuotXem ?? 0;
                sanPham.MaNCC = sp.MaNCC;
                sanPham.MaLoaiSP = sp.MaLoaiSP;
                sanPham.MaNSX = sp.MaNSX;
                sanPham.Moi = sp.Moi == 1 ? 1 : 0;
                sanPham.NgayCapNhat = DateTime.Now;

                db.SaveChanges();

                TempData["Success"] = "Cập nhật thành công!";
                return RedirectToAction("Index");
            }
            catch (Exception)
            {
                ModelState.AddModelError("", "Chưa cập nhật được sản phẩm. Vui lòng kiểm tra thông tin và thử lại.");
                return View(sanPham);
            }
        }

        // ================= UPLOAD HÌNH (GET) =================
        [HttpGet]
        public ActionResult UploadHinh(int? id)
        {
            if (id == null)
                return HttpNotFound();

            SanPham sp = db.SanPham.Find(id);

            if (sp == null)
                return HttpNotFound();

            return View(sp);
        }

        // ================= UPLOAD HÌNH (POST) =================
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult UploadHinh(int? id,
            HttpPostedFileBase HinhAnh,
            HttpPostedFileBase HinhAnh1,
            HttpPostedFileBase HinhAnh2,
            HttpPostedFileBase HinhAnh3,
            HttpPostedFileBase HinhAnh4)
        {
            if (!id.HasValue || id.Value <= 0)
                return HttpNotFound();

            SanPham sp = db.SanPham.Find(id.Value);
            if (sp == null)
                return HttpNotFound();

            try
            {
                SaveImages(sp, HinhAnh, HinhAnh1, HinhAnh2, HinhAnh3, HinhAnh4);

                db.SaveChanges();

                TempData["Success"] = "Cập nhật hình ảnh thành công!";
                return RedirectToAction("Index");
            }
            catch (Exception)
            {
                ModelState.AddModelError("", "Chưa lưu được hình ảnh. Vui lòng kiểm tra quyền ghi thư mục hình ảnh rồi thử lại.");
                return View(sp);
            }
        }

        // ================= XÓA (SOFT DELETE) =================
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Xoa(int? id)
        {
            if (!id.HasValue || id.Value <= 0)
                return HttpNotFound();

            try
            {
                SanPham sp = db.SanPham.Find(id.Value);
                if (sp == null)
                    return HttpNotFound();

                sp.DaXoa = true;
                db.SaveChanges();

                TempData["Success"] = "Xóa sản phẩm thành công!";
            }
            catch (Exception)
            {
                TempData["Error"] = "Chưa xóa được sản phẩm. Vui lòng thử lại.";
            }

            return RedirectToAction("Index");
        }

        private void ValidateProduct(SanPham sp)
        {
            sp.TenSP = (sp.TenSP ?? string.Empty).Trim();
            if (sp.TenSP.Length == 0)
                ModelState.AddModelError("TenSP", "Vui lòng nhập tên sản phẩm.");
            else if (sp.TenSP.Length > 250)
                ModelState.AddModelError("TenSP", "Tên sản phẩm không được vượt quá 250 ký tự.");

            if (!sp.DonGia.HasValue)
                ModelState.AddModelError("DonGia", "Vui lòng nhập đơn giá.");
            else if (sp.DonGia.Value < 0 || sp.DonGia.Value > 999999999999999999m || decimal.Truncate(sp.DonGia.Value) != sp.DonGia.Value)
                ModelState.AddModelError("DonGia", "Đơn giá phải là số nguyên VNĐ không âm và không vượt quá 18 chữ số.");

            if (!sp.SoLuongTon.HasValue || sp.SoLuongTon.Value < 0)
                ModelState.AddModelError("SoLuongTon", "Số lượng tồn phải là số nguyên không âm.");
            if (sp.LuotXem.HasValue && sp.LuotXem.Value < 0)
                ModelState.AddModelError("LuotXem", "Lượt xem phải là số nguyên không âm.");

            if (!sp.MaNCC.HasValue || !db.NhaCungCap.Any(n => n.MaNCC == sp.MaNCC.Value))
                ModelState.AddModelError("MaNCC", "Vui lòng chọn nhà cung cấp hợp lệ.");
            if (!sp.MaLoaiSP.HasValue || !db.LoaiSanPham.Any(n => n.MaLoaiSP == sp.MaLoaiSP.Value))
                ModelState.AddModelError("MaLoaiSP", "Vui lòng chọn loại sản phẩm hợp lệ.");
            if (!sp.MaNSX.HasValue || !db.NhaSanXuat.Any(n => n.MaNSX == sp.MaNSX.Value))
                ModelState.AddModelError("MaNSX", "Vui lòng chọn nhà sản xuất hợp lệ.");
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
            Directory.CreateDirectory(path);

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
