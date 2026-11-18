using System;
using System.Data.Entity.Infrastructure;
using System.Linq;
using System.Text.RegularExpressions;
using System.Web.Mvc;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanTriWeb")]
    public class QuanLyQuyenController : Controller
    {
        private readonly QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        public ActionResult Index()
        {
            return View(db.Quyen.OrderBy(role => role.TenQuyen).ToList());
        }

        [HttpGet]
        public ActionResult TaoMoi()
        {
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult TaoMoi([Bind(Include = "MaQuyen,TenQuyen")] Quyen quyen)
        {
            quyen = quyen ?? new Quyen();
            ValidateRole(quyen);
            if (ModelState.IsValid && db.Quyen.Any(role => role.MaQuyen == quyen.MaQuyen))
                ModelState.AddModelError("MaQuyen", "Mã quyền đã tồn tại.");
            if (!ModelState.IsValid)
                return View(quyen);

            db.Quyen.Add(quyen);
            if (!SaveRole())
                return View(quyen);
            return RedirectToAction("Index");
        }

        [HttpGet]
        public ActionResult ChinhSua(string id)
        {
            var role = FindRole(id);
            if (role == null)
                return HttpNotFound();
            return View(role);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult ChinhSua([Bind(Include = "MaQuyen,TenQuyen")] Quyen quyen, string id)
        {
            quyen = quyen ?? new Quyen();
            var current = FindRole(string.IsNullOrWhiteSpace(id) ? quyen.MaQuyen : id);
            if (current == null)
                return HttpNotFound();

            ValidateRole(quyen);
            if (!string.Equals(current.MaQuyen, quyen.MaQuyen, StringComparison.Ordinal))
            {
                ModelState.Remove("MaQuyen");
                ModelState.AddModelError("", "Không thể thay đổi mã quyền khi chỉnh sửa.");
                quyen.MaQuyen = current.MaQuyen;
            }
            if (!ModelState.IsValid)
                return View(quyen);

            current.TenQuyen = quyen.TenQuyen;
            if (!SaveRole())
                return View(quyen);
            return RedirectToAction("Index");
        }

        [HttpGet]
        public ActionResult Xoa(string id)
        {
            var role = FindRole(id);
            if (role == null)
                return HttpNotFound();
            return View(role);
        }

        [HttpPost, ActionName("Xoa")]
        [ValidateAntiForgeryToken]
        public ActionResult XacNhanXoa(string id)
        {
            var role = FindRole(id);
            if (role == null)
                return HttpNotFound();
            if (db.LoaiThanhVien_Quyen.Any(assignment => assignment.MaQuyen == role.MaQuyen))
            {
                ModelState.AddModelError("", "Quyền đang được gán cho loại thành viên. Hãy bỏ phân quyền trước khi xóa.");
                return View("Xoa", role);
            }

            db.Quyen.Remove(role);
            if (!SaveRole())
                return View("Xoa", role);
            return RedirectToAction("Index");
        }

        private Quyen FindRole(string id)
        {
            return string.IsNullOrWhiteSpace(id)
                ? null
                : db.Quyen.SingleOrDefault(role => role.MaQuyen == id);
        }

        private void ValidateRole(Quyen role)
        {
            role.MaQuyen = role.MaQuyen == null ? null : role.MaQuyen.Trim();
            role.TenQuyen = role.TenQuyen == null ? null : role.TenQuyen.Trim();
            if (string.IsNullOrWhiteSpace(role.MaQuyen) ||
                !Regex.IsMatch(role.MaQuyen, "^[A-Za-z0-9_-]{1,50}$"))
            {
                ModelState.AddModelError("MaQuyen", "Mã quyền từ 1 đến 50 ký tự, chỉ gồm chữ không dấu, số, dấu gạch ngang hoặc gạch dưới.");
            }
            if (string.IsNullOrWhiteSpace(role.TenQuyen) || role.TenQuyen.Length > 100)
                ModelState.AddModelError("TenQuyen", "Tên quyền không được trống và không vượt quá 100 ký tự.");
        }

        private bool SaveRole()
        {
            try
            {
                db.SaveChanges();
                return true;
            }
            catch (DbUpdateException)
            {
                ModelState.AddModelError("", "Không thể lưu quyền. Dữ liệu có thể đã thay đổi hoặc đang được sử dụng; vui lòng tải lại trang.");
                return false;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}
