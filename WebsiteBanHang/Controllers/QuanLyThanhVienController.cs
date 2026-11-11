using System;
using System.Collections.Generic;
using System.Linq;
using System.Web.Mvc;
using WebsiteBanHang.Models;
using WebsiteBanHang.Security;

namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanTriWeb")]
    public class QuanLyThanhVienController : Controller
    {
        private QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        // ==============================
        // DANH SÁCH
        // ==============================
        public ActionResult Index()
        {
            var ds = db.ThanhVien
                       .OrderBy(x => x.MaThanhVien)
                       .ToList();

            return View(ds);
        }

        // ==============================
        // TẠO MỚI - GET
        // ==============================
        [HttpGet]
        public ActionResult TaoMoi()
        {
            LoadDropdown();
            return View();
        }

        // ==============================
        // TẠO MỚI - POST
        // ==============================
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult TaoMoi(ThanhVien tv)
        {
            LoadDropdown(tv.MaLoaiTV, tv.CauHoi);

            if (!ModelState.IsValid)
                return View(tv);

            // Kiểm tra bắt buộc
            if (string.IsNullOrWhiteSpace(tv.TaiKhoan) ||
                string.IsNullOrWhiteSpace(tv.MatKhau) ||
                string.IsNullOrWhiteSpace(tv.HoTen) ||
                string.IsNullOrWhiteSpace(tv.CauHoi) ||
                string.IsNullOrWhiteSpace(tv.CauTraLoi) ||
                tv.MaLoaiTV == null)
            {
                TempData["ErrorMessage"] = "Vui lòng nhập đầy đủ thông tin bắt buộc!";
                return View(tv);
            }

            try
            {
                if (db.ThanhVien.Any(n => n.TaiKhoan == tv.TaiKhoan))
                {
                    ModelState.AddModelError("TaiKhoan", "Tài khoản đã tồn tại.");
                    return View(tv);
                }
                tv.MaThanhVien = 0;
                tv.MatKhau = PasswordService.Hash(tv.MatKhau);
                db.ThanhVien.Add(tv);
                db.SaveChanges();

                TempData["SuccessMessage"] = "Thêm thành viên thành công!";
                return RedirectToAction("TaoMoi");
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Lỗi: " + ex.Message;
                return View(tv);
            }
        }

        // ==============================
        // CHỈNH SỬA - GET
        // ==============================
        [HttpGet]
        public ActionResult ChinhSua(int id)
        {
            var tv = db.ThanhVien.Find(id);
            if (tv == null)
                return HttpNotFound();

            LoadDropdown(tv.MaLoaiTV, tv.CauHoi);
            return View(tv);
        }

        // ==============================
        // CHỈNH SỬA - POST
        // ==============================
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult ChinhSua(ThanhVien tv)
        {
            LoadDropdown(tv.MaLoaiTV, tv.CauHoi);

            var changePassword = !string.IsNullOrWhiteSpace(tv.MatKhau);
            if (!changePassword)
                ModelState.Remove("MatKhau");

            if (!ModelState.IsValid)
                return View(tv);

            var thanhVien = db.ThanhVien.Find(tv.MaThanhVien);
            if (thanhVien == null)
                return HttpNotFound();

            try
            {
                if (db.ThanhVien.Any(n => n.TaiKhoan == tv.TaiKhoan && n.MaThanhVien != tv.MaThanhVien))
                {
                    ModelState.AddModelError("TaiKhoan", "Tài khoản đã tồn tại.");
                    return View(tv);
                }
                thanhVien.TaiKhoan = tv.TaiKhoan;
                if (changePassword)
                    thanhVien.MatKhau = PasswordService.Hash(tv.MatKhau);
                thanhVien.HoTen = tv.HoTen;
                thanhVien.DiaChi = tv.DiaChi;
                thanhVien.Email = tv.Email;
                thanhVien.SoDienThoai = tv.SoDienThoai;
                thanhVien.CauHoi = tv.CauHoi;
                thanhVien.CauTraLoi = tv.CauTraLoi;
                thanhVien.MaLoaiTV = tv.MaLoaiTV;

                db.SaveChanges();

                TempData["SuccessMessage"] = "Cập nhật thành viên thành công!";
                return RedirectToAction("Index");
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Lỗi: " + ex.Message;
                return View(tv);
            }
        }

        // ==============================
        // XÓA - GET
        // ==============================
        [HttpGet]
        public ActionResult Xoa(int id)
        {
            var tv = db.ThanhVien.Find(id);
            if (tv == null)
                return HttpNotFound();

            return View(tv);
        }

        // ==============================
        // XÓA - POST
        // ==============================
        [HttpPost, ActionName("Xoa")]
        [ValidateAntiForgeryToken]
        public ActionResult XoaConfirmed(int id)
        {
            var tv = db.ThanhVien.Find(id);
            if (tv == null)
                return HttpNotFound();

            try
            {
                db.ThanhVien.Remove(tv);
                db.SaveChanges();

                TempData["SuccessMessage"] = "Xóa thành viên thành công!";
            }
            catch (Exception ex)
            {
                TempData["ErrorMessage"] = "Lỗi: " + ex.Message;
            }

            return RedirectToAction("Index");
        }

        // ==============================
        // LOAD DROPDOWN
        // ==============================
        private void LoadDropdown(int? maLoaiTV = null, string cauHoi = null)
        {
            ViewBag.MaLoaiTV = new SelectList(
                db.LoaiThanhVien.OrderBy(x => x.MaLoaiTV),
                "MaLoaiTV",
                "TenLoai",
                maLoaiTV
            );

            ViewBag.CauHoi = new SelectList(
                LoadCauHoi(),
                cauHoi
            );
        }

        // ==============================
        // DANH SÁCH CÂU HỎI
        // ==============================
        private List<string> LoadCauHoi()
        {
            return new List<string>
            {
                "Họ tên người cha bạn là gì?",
                "Ca sĩ mà bạn yêu thích là ai?",
                "Vật nuôi mà bạn yêu thích là gì?",
                "Sở thích của bạn là gì?",
                "Hiện tại bạn đang làm công việc gì?",
                "Trường cấp ba bạn học là gì?",
                "Năm sinh của mẹ bạn là gì?",
                "Bộ phim mà bạn yêu thích là gì?",
                "Bài nhạc mà bạn yêu thích là gì?"
            };
        }

        // ==============================
        // DISPOSE
        // ==============================
        protected override void Dispose(bool disposing)
        {
            if (disposing && db != null)
            {
                db.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
