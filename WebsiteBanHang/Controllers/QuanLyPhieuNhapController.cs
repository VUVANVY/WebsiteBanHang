using System;
using System.Collections.Generic;
using System.Data.Entity;
using System.Linq;
using System.Web.Mvc;
using PagedList;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    [Authorize(Roles = "QuanLy,QuanTriWeb")]
    public class QuanLyPhieuNhapController : Controller
    {
        private readonly QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        [HttpGet]
        public ActionResult NhapHang()
        {
            LoadImportForm(null, null);
            return View(new PhieuNhap());
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult NhapHang([Bind(Include = "MaNCC")] PhieuNhap model, List<ChiTietPhieuNhap> lstModel)
        {
            model = model ?? new PhieuNhap();
            Dictionary<int, SanPham> products;
            if (!ValidateImport(model.MaNCC, lstModel, out products))
            {
                LoadImportForm(model.MaNCC, lstModel);
                return View(model);
            }

            SaveImport(model.MaNCC.Value, lstModel, products);
            TempData["Success"] = "Đã lưu phiếu nhập và cập nhật tồn kho.";
            return RedirectToAction("DSSPHetHang");
        }

        [HttpGet]
        public ActionResult DSSPHetHang(int? page)
        {
            const int pageSize = 6;
            var query = db.SanPham.Include(n => n.NhaSanXuat).Include(n => n.LoaiSanPham)
                .Where(n => n.DaXoa != true && (n.SoLuongTon ?? 0) <= 5);
            int total = query.Count();
            int lastPage = Math.Max(1, (int)Math.Ceiling(total / (double)pageSize));
            int pageNumber = Math.Min(Math.Max(page ?? 1, 1), lastPage);
            var products = query.OrderBy(n => n.MaSP).Skip((pageNumber - 1) * pageSize).Take(pageSize).ToList();
            return View(new StaticPagedList<SanPham>(products, pageNumber, pageSize, total));
        }

        [HttpGet]
        public ActionResult NhapHangDon(int? id)
        {
            var product = FindProduct(id);
            if (product == null) return HttpNotFound();
            LoadSuppliers(null);
            return View(product);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult NhapHangDon([Bind(Include = "MaNCC")] PhieuNhap model,
            [Bind(Include = "MaSP,DonGiaNhap,SoLuongNhap")] ChiTietPhieuNhap ctpn)
        {
            model = model ?? new PhieuNhap();
            var product = FindProduct(ctpn == null ? null : ctpn.MaSP);
            if (product == null) return HttpNotFound();
            var lines = new List<ChiTietPhieuNhap> { ctpn };
            Dictionary<int, SanPham> products;
            if (!ValidateImport(model.MaNCC, lines, out products))
            {
                LoadSuppliers(model.MaNCC);
                return View(product);
            }

            SaveImport(model.MaNCC.Value, lines, products);
            TempData["Success"] = "Đã lưu phiếu nhập và cập nhật tồn kho.";
            return RedirectToAction("DSSPHetHang");
        }

        private SanPham FindProduct(int? id)
        {
            return id.HasValue
                ? db.SanPham.Include(n => n.NhaSanXuat).Include(n => n.LoaiSanPham)
                    .SingleOrDefault(n => n.MaSP == id.Value && n.DaXoa != true)
                : null;
        }

        private void LoadSuppliers(int? selectedSupplier)
        {
            ViewBag.MaNCC = new SelectList(db.NhaCungCap.OrderBy(n => n.TenNCC), "MaNCC", "TenNCC", selectedSupplier);
        }

        private void LoadImportForm(int? selectedSupplier, IList<ChiTietPhieuNhap> lines)
        {
            LoadSuppliers(selectedSupplier);
            ViewBag.ListSanPham = db.SanPham.Where(n => n.DaXoa != true).OrderBy(n => n.TenSP).ToList();
            ViewBag.ChiTietNhap = lines != null && lines.Count > 0
                ? lines.Select(line => line ?? new ChiTietPhieuNhap()).ToList()
                : new List<ChiTietPhieuNhap> { new ChiTietPhieuNhap { SoLuongNhap = 1, DonGiaNhap = 0 } };
        }

        private bool ValidateImport(int? supplierId, IList<ChiTietPhieuNhap> lines, out Dictionary<int, SanPham> products)
        {
            products = new Dictionary<int, SanPham>();
            if (!supplierId.HasValue || !db.NhaCungCap.Any(n => n.MaNCC == supplierId.Value))
                ModelState.AddModelError("MaNCC", "Vui lòng chọn nhà cung cấp hợp lệ.");
            if (lines == null || lines.Count == 0)
            {
                ModelState.AddModelError("", "Phiếu nhập cần ít nhất một sản phẩm.");
                return false;
            }

            foreach (var line in lines)
            {
                if (line == null || !line.MaSP.HasValue || line.MaSP.Value <= 0)
                    ModelState.AddModelError("", "Có sản phẩm không hợp lệ trong phiếu nhập.");
                if (line == null || !line.SoLuongNhap.HasValue || line.SoLuongNhap.Value <= 0)
                    ModelState.AddModelError("", "Số lượng nhập phải là số nguyên lớn hơn 0.");
                if (line == null || !line.DonGiaNhap.HasValue || line.DonGiaNhap.Value < 0
                    || line.DonGiaNhap.Value > 999999999999999999m
                    || decimal.Truncate(line.DonGiaNhap.Value) != line.DonGiaNhap.Value)
                    ModelState.AddModelError("", "Đơn giá nhập phải là số tiền hợp lệ, không âm.");
            }
            if (!ModelState.IsValid) return false;

            var productIds = lines.Select(n => n.MaSP.Value).Distinct().ToList();
            products = db.SanPham.Where(n => productIds.Contains(n.MaSP) && n.DaXoa != true).ToDictionary(n => n.MaSP);
            if (products.Count != productIds.Count)
                ModelState.AddModelError("", "Có sản phẩm không tồn tại hoặc đã ngừng bán.");
            foreach (var group in lines.GroupBy(n => n.MaSP.Value))
            {
                SanPham product;
                if (products.TryGetValue(group.Key, out product)
                    && (long)(product.SoLuongTon ?? 0) + group.Sum(n => (long)n.SoLuongNhap.Value) > int.MaxValue)
                    ModelState.AddModelError("", "Số lượng nhập vượt giới hạn tồn kho.");
            }
            return ModelState.IsValid;
        }

        private void SaveImport(int supplierId, IEnumerable<ChiTietPhieuNhap> lines, IDictionary<int, SanPham> products)
        {
            using (var transaction = db.Database.BeginTransaction())
            {
                var receipt = new PhieuNhap { MaNCC = supplierId, NgayNhap = DateTime.Now, DaXoa = false };
                foreach (var line in lines)
                {
                    receipt.ChiTietPhieuNhap.Add(new ChiTietPhieuNhap
                    {
                        MaSP = line.MaSP,
                        SoLuongNhap = line.SoLuongNhap,
                        DonGiaNhap = line.DonGiaNhap
                    });
                    var product = products[line.MaSP.Value];
                    product.SoLuongTon = (product.SoLuongTon ?? 0) + line.SoLuongNhap.Value;
                }
                db.PhieuNhap.Add(receipt);
                db.SaveChanges();
                transaction.Commit();
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing) db.Dispose();
            base.Dispose(disposing);
        }
    }
}
