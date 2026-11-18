using System.Data.Entity;
using System.Data.Entity.Infrastructure;
using System.Linq;
using System.Web.Mvc;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanLy,QuanTriWeb")]
    public class QuanLyNhaSXController : Controller
    {
        private readonly QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        public ActionResult Index()
        {
            return View(db.NhaSanXuat.AsNoTracking().OrderBy(n => n.MaNSX).ToList());
        }

        [HttpGet]
        public ActionResult TaoMoi()
        {
            return View();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult TaoMoi([Bind(Include = "TenNSX,ThongTin")] NhaSanXuat entity)
        {
            entity = entity ?? new NhaSanXuat();
            ValidateFields(entity);
            if (!ModelState.IsValid)
                return View(entity);

            db.NhaSanXuat.Add(entity);
            db.SaveChanges();
            return RedirectToAction("Index");
        }

        [HttpGet]
        public ActionResult ChinhSua(int? id)
        {
            if (!id.HasValue || id.Value <= 0)
                return HttpNotFound();

            var entity = db.NhaSanXuat.Find(id.Value);
            return entity == null ? (ActionResult)HttpNotFound() : View(entity);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult ChinhSua(int? id, [Bind(Include = "MaNSX,TenNSX,ThongTin")] NhaSanXuat entity)
        {
            if (entity == null || entity.MaNSX <= 0 || (id.HasValue && id.Value != entity.MaNSX))
                return HttpNotFound();

            var current = db.NhaSanXuat.Find(entity.MaNSX);
            if (current == null)
                return HttpNotFound();

            ValidateFields(entity);
            if (!ModelState.IsValid)
                return View(entity);

            current.TenNSX = entity.TenNSX;
            current.ThongTin = entity.ThongTin;
            db.SaveChanges();
            return RedirectToAction("Index");
        }

        [HttpGet]
        public ActionResult Xoa(int? id)
        {
            if (!id.HasValue || id.Value <= 0)
                return HttpNotFound();

            var entity = db.NhaSanXuat.Find(id.Value);
            return entity == null ? (ActionResult)HttpNotFound() : View(entity);
        }

        [HttpPost, ActionName("Xoa")]
        [ValidateAntiForgeryToken]
        public ActionResult XacNhanXoa(int? id)
        {
            if (!id.HasValue || id.Value <= 0)
                return HttpNotFound();

            var entity = db.NhaSanXuat.Find(id.Value);
            if (entity == null)
                return HttpNotFound();

            if (db.SanPham.Any(n => n.MaNSX == id.Value))
            {
                ModelState.AddModelError("", "Không thể xóa nhà sản xuất đang có sản phẩm sử dụng.");
                return View("Xoa", entity);
            }

            db.NhaSanXuat.Remove(entity);
            try
            {
                db.SaveChanges();
                return RedirectToAction("Index");
            }
            catch (DbUpdateException)
            {
                db.Entry(entity).State = EntityState.Unchanged;
                ModelState.AddModelError("", "Không thể xóa nhà sản xuất đang được sử dụng. Vui lòng tải lại trang và thử lại.");
                return View("Xoa", entity);
            }
        }

        private void ValidateFields(NhaSanXuat entity)
        {
            entity.TenNSX = (entity.TenNSX ?? string.Empty).Trim();
            if (entity.TenNSX.Length == 0)
                ModelState.AddModelError("TenNSX", "Vui lòng nhập tên nhà sản xuất.");
            else if (entity.TenNSX.Length > 100)
                ModelState.AddModelError("TenNSX", "Tên nhà sản xuất không được vượt quá 100 ký tự.");
            entity.ThongTin = string.IsNullOrWhiteSpace(entity.ThongTin) ? null : entity.ThongTin.Trim();
            if (entity.ThongTin != null && entity.ThongTin.Length > 250)
                ModelState.AddModelError("ThongTin", "Thông tin không được vượt quá 250 ký tự.");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}