using System.Data.Entity;
using System.Data.Entity.Infrastructure;
using System.Linq;
using System.Web.Mvc;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanLy,QuanTriWeb")]
    public class QuanLyLoaiController : Controller
    {
        private readonly QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        public ActionResult Index()
        {
            return View(db.LoaiSanPham.AsNoTracking().OrderBy(n => n.MaLoaiSP).ToList());
        }

        [HttpGet]
        public ActionResult TaoMoi()
        {
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult TaoMoi([Bind(Include = "TenLoai,Icon,BiDanh")] LoaiSanPham entity)
        {
            entity = entity ?? new LoaiSanPham();
            ValidateFields(entity);
            if (!ModelState.IsValid)
                return View(entity);

            db.LoaiSanPham.Add(entity);
            db.SaveChanges();
            return RedirectToAction("Index");
        }

        [HttpGet]
        public ActionResult ChinhSua(int? id)
        {
            if (!id.HasValue || id.Value <= 0)
                return HttpNotFound();

            var entity = db.LoaiSanPham.Find(id.Value);
            return entity == null ? (ActionResult)HttpNotFound() : View(entity);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult ChinhSua(int? id, [Bind(Include = "MaLoaiSP,TenLoai,Icon,BiDanh")] LoaiSanPham entity)
        {
            if (entity == null || entity.MaLoaiSP <= 0 || (id.HasValue && id.Value != entity.MaLoaiSP))
                return HttpNotFound();

            var current = db.LoaiSanPham.Find(entity.MaLoaiSP);
            if (current == null)
                return HttpNotFound();

            ValidateFields(entity);
            if (!ModelState.IsValid)
                return View(entity);

            current.TenLoai = entity.TenLoai;
            current.Icon = entity.Icon;
            current.BiDanh = entity.BiDanh;
            db.SaveChanges();
            return RedirectToAction("Index");
        }

        [HttpGet]
        public ActionResult Xoa(int? id)
        {
            if (!id.HasValue || id.Value <= 0)
                return HttpNotFound();

            var entity = db.LoaiSanPham.Find(id.Value);
            return entity == null ? (ActionResult)HttpNotFound() : View(entity);
        }

        [HttpPost, ActionName("Xoa")]
        [ValidateAntiForgeryToken]
        public ActionResult XacNhanXoa(int? id)
        {
            if (!id.HasValue || id.Value <= 0)
                return HttpNotFound();

            var entity = db.LoaiSanPham.Find(id.Value);
            if (entity == null)
                return HttpNotFound();

            if (db.SanPham.Any(n => n.MaLoaiSP == id.Value))
            {
                ModelState.AddModelError("", "Không thể xóa loại sản phẩm đang có sản phẩm sử dụng.");
                return View("Xoa", entity);
            }

            db.LoaiSanPham.Remove(entity);
            try
            {
                db.SaveChanges();
                return RedirectToAction("Index");
            }
            catch (DbUpdateException)
            {
                db.Entry(entity).State = EntityState.Unchanged;
                ModelState.AddModelError("", "Không thể xóa loại sản phẩm đang được sử dụng. Vui lòng tải lại trang và thử lại.");
                return View("Xoa", entity);
            }
        }

        private void ValidateFields(LoaiSanPham entity)
        {
            entity.TenLoai = (entity.TenLoai ?? string.Empty).Trim();
            if (entity.TenLoai.Length == 0)
                ModelState.AddModelError("TenLoai", "Vui lòng nhập tên loại sản phẩm.");
            else if (entity.TenLoai.Length > 150)
                ModelState.AddModelError("TenLoai", "Tên loại sản phẩm không được vượt quá 150 ký tự.");
            entity.BiDanh = string.IsNullOrWhiteSpace(entity.BiDanh) ? null : entity.BiDanh.Trim();
            if (entity.BiDanh != null && entity.BiDanh.Length > 50)
                ModelState.AddModelError("BiDanh", "Bí danh không được vượt quá 50 ký tự.");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}