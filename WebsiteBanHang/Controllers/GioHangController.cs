using System;
using System.Collections.Generic;
using System.Data.Entity.Infrastructure;
using System.Linq;
using System.Web.Mvc;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    public class GioHangController : Controller
    {
        private readonly QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        [ChildActionOnly]
        public ActionResult GioHangPartial()
        {
            var cart = LayGioHang();
            ViewBag.TongSoLuong = cart.Sum(item => item.SoLuong);
            ViewBag.TongTien = cart.Sum(item => item.ThanhTien);
            return PartialView();
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult ThemGioHang(int MaSP, string strURL)
        {
            var message = AddProduct(MaSP);
            if (message != null)
                return CartError(message);
            TempData["SuccessMessage"] = "Thêm vào giỏ hàng thành công!";
            return Url.IsLocalUrl(strURL) ? (ActionResult)Redirect(strURL) : RedirectToAction("XemGioHang");
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public JsonResult ThemGioHangAjax(int MaSP)
        {
            var message = AddProduct(MaSP);
            if (message != null)
            {
                Response.StatusCode = 409;
                Response.TrySkipIisCustomErrors = true;
                return Json(new { success = false, message });
            }
            return Json(new { success = true, total = LayGioHang().Sum(item => item.SoLuong) });
        }

        [HttpGet]
        public ActionResult XemGioHang()
        {
            var cart = LayGioHang();
            ViewBag.TongSoLuong = cart.Sum(item => item.SoLuong);
            ViewBag.TongTien = cart.Sum(item => item.ThanhTien);
            return View(cart);
        }

        [HttpGet]
        public ActionResult SuaGioHang(int MaSP)
        {
            var cart = LayGioHang();
            var item = cart.SingleOrDefault(product => product.MaSP == MaSP);
            if (item == null)
                return HttpNotFound();
            ViewBag.GioHang = cart;
            return View(item);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult CapNhatGioHang(ItemGioHang itemGH)
        {
            if (!ModelState.IsValid || itemGH == null || itemGH.SoLuong < 1)
                return CartError("Số lượng sản phẩm phải là số nguyên lớn hơn 0.");
            var item = LayGioHang().SingleOrDefault(product => product.MaSP == itemGH.MaSP);
            if (item == null)
                return HttpNotFound();
            var productInStore = db.SanPham.SingleOrDefault(product => product.MaSP == itemGH.MaSP && product.DaXoa != true);
            if (!CanOrder(productInStore, itemGH.SoLuong))
                return CartError("Sản phẩm không còn bán hoặc số lượng yêu cầu vượt quá tồn kho.");
            UpdateItem(item, productInStore, itemGH.SoLuong);
            return RedirectToAction("XemGioHang");
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult XoaGioHang(int MaSP)
        {
            var cart = LayGioHang();
            var item = cart.SingleOrDefault(product => product.MaSP == MaSP);
            if (item != null)
                cart.Remove(item);
            return RedirectToAction("XemGioHang");
        }

        [Authorize]
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult DatHang()
        {
            var sessionMember = Session["TaiKhoan"] as ThanhVien;
            if (sessionMember == null || !User.Identity.IsAuthenticated
                || !string.Equals(User.Identity.Name, sessionMember.TaiKhoan, StringComparison.OrdinalIgnoreCase))
                return RedirectToAction("Index", "Home");
            var cart = LayGioHang();
            if (cart.Count == 0 || cart.Any(item => item == null || item.SoLuong < 1)
                || cart.Select(item => item.MaSP).Distinct().Count() != cart.Count)
                return CartError("Giỏ hàng trống hoặc không hợp lệ. Vui lòng chọn lại sản phẩm.");
            var member = db.ThanhVien.SingleOrDefault(item => item.MaThanhVien == sessionMember.MaThanhVien
                                                            && item.TaiKhoan == sessionMember.TaiKhoan);
            if (member == null)
            {
                Session["TaiKhoan"] = null;
                return RedirectToAction("Index", "Home");
            }
            var ids = cart.Select(item => item.MaSP).ToList();
            var products = db.SanPham.Where(item => ids.Contains(item.MaSP) && item.DaXoa != true)
                .ToDictionary(item => item.MaSP);
            foreach (var item in cart)
            {
                SanPham product;
                if (!products.TryGetValue(item.MaSP, out product) || !CanOrder(product, item.SoLuong))
                    return CartError("Một sản phẩm không còn bán hoặc không đủ tồn kho. Vui lòng cập nhật giỏ hàng.");
                UpdateItem(item, product, item.SoLuong);
            }
            using (var transaction = db.Database.BeginTransaction())
            {
                try
                {
                    var customer = db.KhachHang.FirstOrDefault(item => item.MaThanhVien == member.MaThanhVien);
                    if (customer == null)
                    {
                        customer = new KhachHang
                        {
                            TenKH = member.HoTen,
                            Email = member.Email,
                            SoDienThoai = member.SoDienThoai,
                            DiaChi = member.DiaChi,
                            MaThanhVien = member.MaThanhVien
                        };
                        db.KhachHang.Add(customer);
                    }
                    var order = new DonDatHang
                    {
                        KhachHang = customer,
                        NgayDat = DateTime.Now,
                        TinhTrangGiaoHang = false,
                        DaThanhToan = false,
                        UuDai = 0,
                        DaHuy = false,
                        DaXoa = false
                    };
                    foreach (var item in cart)
                    {
                        order.ChiTietDonDatHang.Add(new ChiTietDonDatHang
                        {
                            MaSP = item.MaSP,
                            TenSP = item.TenSP,
                            SoLuong = item.SoLuong,
                            Dongia = item.DonGia
                        });
                    }
                    db.DonDatHang.Add(order);
                    db.SaveChanges();
                    transaction.Commit();
                }
                catch (DbUpdateException)
                {
                    transaction.Rollback();
                    return CartError("Chưa lưu được đơn hàng. Giỏ hàng của bạn vẫn được giữ lại để thử lại.");
                }
            }
            Session["GioHang"] = null;
            return RedirectToAction("Index", "DonHang");
        }

        private string AddProduct(int productId)
        {
            var product = db.SanPham.SingleOrDefault(item => item.MaSP == productId && item.DaXoa != true);
            if (!CanOrder(product, 1))
                return "Sản phẩm không còn bán hoặc đã hết hàng.";
            var cart = LayGioHang();
            var itemInCart = cart.SingleOrDefault(item => item.MaSP == productId);
            if (itemInCart != null)
            {
                if (itemInCart.SoLuong < 1 || itemInCart.SoLuong >= product.SoLuongTon.GetValueOrDefault())
                    return "Số lượng trong giỏ hàng đã đạt số lượng tồn kho.";
                UpdateItem(itemInCart, product, itemInCart.SoLuong + 1);
            }
            else
            {
                itemInCart = new ItemGioHang { MaSP = product.MaSP };
                UpdateItem(itemInCart, product, 1);
                cart.Add(itemInCart);
            }
            return null;
        }

        private static bool CanOrder(SanPham product, int quantity)
        {
            return quantity > 0 && product != null && product.DaXoa != true
                   && product.DonGia.HasValue && product.DonGia.Value >= 0
                   && product.SoLuongTon.GetValueOrDefault() >= quantity;
        }

        private static void UpdateItem(ItemGioHang item, SanPham product, int quantity)
        {
            item.TenSP = product.TenSP;
            item.HinhAnh = product.HinhAnh;
            item.DonGia = product.DonGia.Value;
            item.SoLuong = quantity;
            item.ThanhTien = item.DonGia * quantity;
        }

        private List<ItemGioHang> LayGioHang()
        {
            var cart = Session["GioHang"] as List<ItemGioHang>;
            if (cart == null)
            {
                cart = new List<ItemGioHang>();
                Session["GioHang"] = cart;
            }
            return cart;
        }

        private ActionResult CartError(string message)
        {
            TempData["ErrorMessage"] = message;
            return RedirectToAction("XemGioHang");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}
