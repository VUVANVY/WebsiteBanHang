using System;
using System.Collections.Generic;
using System.Data.Entity.Infrastructure;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanTriWeb")]
    public class PhanQuyenController : Controller
    {
        private readonly QuanLyBanHangEntities db = new QuanLyBanHangEntities();
        // GET: PhanQuyen
        public ActionResult Index()
        {
            return View(db.LoaiThanhVien.OrderBy(n => n.TenLoai).ToList());
        }

        [HttpGet]
        public ActionResult PhanQuyen(int? id)
        {
            if (id == null)
                return HttpNotFound();
            LoaiThanhVien ltv = db.LoaiThanhVien.SingleOrDefault(n => n.MaLoaiTV == id);
            if (ltv == null)
                return HttpNotFound();
            return PermissionView(ltv);
        }
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult PhanQuyen(int? MaLTV, IEnumerable<LoaiThanhVien_Quyen> lstPhanQuyen, string[] selectedPermissions)
        {
            if (MaLTV == null)
                return HttpNotFound();
            var memberType = db.LoaiThanhVien.Find(MaLTV.Value);
            if (memberType == null)
                return HttpNotFound();

            var requested = selectedPermissions != null
                ? selectedPermissions.ToList()
                : (lstPhanQuyen ?? Enumerable.Empty<LoaiThanhVien_Quyen>())
                    .Select(item => item == null ? null : item.MaQuyen).ToList();
            if (requested.Any(code => string.IsNullOrWhiteSpace(code) || code.Trim().Length > 50))
                ModelState.AddModelError("", "Mã quyền không hợp lệ. Các quyền hiện tại chưa bị thay đổi.");

            var selected = new HashSet<string>(requested.Where(code => !string.IsNullOrWhiteSpace(code))
                .Select(code => code.Trim()), StringComparer.OrdinalIgnoreCase);
            var available = db.Quyen.ToList();
            if (selected.Any(code => !available.Any(role => string.Equals(role.MaQuyen, code, StringComparison.OrdinalIgnoreCase))))
                ModelState.AddModelError("", "Có quyền không tồn tại. Các quyền hiện tại chưa bị thay đổi.");
            if (!ModelState.IsValid)
                return PermissionView(memberType);

            var canonicalCodes = available.Where(role => selected.Contains(role.MaQuyen))
                .Select(role => role.MaQuyen).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            try
            {
                using (var transaction = db.Database.BeginTransaction())
                {
                    var current = db.LoaiThanhVien_Quyen.Where(role => role.MaLoaiTV == memberType.MaLoaiTV).ToList();
                    var currentCodes = new HashSet<string>(current.Select(role => role.MaQuyen), StringComparer.OrdinalIgnoreCase);
                    db.LoaiThanhVien_Quyen.RemoveRange(current.Where(role => !selected.Contains(role.MaQuyen)));
                    foreach (var code in canonicalCodes.Where(code => !currentCodes.Contains(code)))
                    {
                        db.LoaiThanhVien_Quyen.Add(new LoaiThanhVien_Quyen
                        {
                            MaLoaiTV = memberType.MaLoaiTV,
                            MaQuyen = code
                        });
                    }
                    db.SaveChanges();
                    transaction.Commit();
                }
            }
            catch (DbUpdateException)
            {
                ModelState.AddModelError("", "Không thể lưu phân quyền. Vui lòng tải lại trang và thử lại.");
                return PermissionView(memberType);
            }
            return RedirectToAction("Index");
        }

        private ActionResult PermissionView(LoaiThanhVien memberType)
        {
            ViewBag.MaQuyen = db.Quyen.OrderBy(role => role.MaQuyen).ToList();
            ViewBag.LoaiTVQuyen = db.LoaiThanhVien_Quyen.Where(role => role.MaLoaiTV == memberType.MaLoaiTV).ToList();
            return View("PhanQuyen", memberType);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}
