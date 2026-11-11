using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using WebsiteBanHang.Models;

namespace WebsiteBanHang.Controllers
{
    public class GioHangController : Controller
    {
        QuanLyBanHangEntities db = new QuanLyBanHangEntities();

        //Hiển thị icon giỏ hàng lên phần header
        public ActionResult GioHangPartial()
        {
            if (TinhTongSoLuong() == 0) //ktra soluong giỏ hàng
            {
                ViewBag.TongSoLuong = 0;
                ViewBag.TongTien = 0;
                return PartialView();
            }
            //Hiển thị tổng tiền và sl sp lên trên icon giỏ hàng
            ViewBag.TongSoLuong = TinhTongSoLuong();
            ViewBag.TongTien = TinhTongTien();

            return PartialView();
        }

        //Thêm giỏ hàng thông thường ko ajax
        public ActionResult ThemGioHang(int MaSP, string strURL)
        {
            //ktra sp có tồn tại trong csdl ko
            SanPham sp = db.SanPham.SingleOrDefault(n => n.MaSP == MaSP);  //lấy sp với masp tương ứng
            if(sp == null)  //nếu lấy sai masp
            {
                //Trang đường dẫn ko hợp lệ
                Response.StatusCode = 404;
                return null;
            }

            //Lấy giỏ hàng
            List<ItemGioHang> lstGioHang = LayGioHang();

            //trường hợp nếu 1 sp đã tồn tại trong giỏ hàng
            ItemGioHang spCheck = lstGioHang.SingleOrDefault(n => n.MaSP == MaSP);  //ktra sp có trong lst đã tạo hay ko
            if(spCheck != null)
            {
                //ktra số lg tồn trc khi cho kh mua hàng
                if (sp.SoLuongTon < spCheck.SoLuong)
                    return View("ThongBao");
                //nếu sp đã có trong list thì khi thêm vào giỏ hàng sẽ tăng số lượng lên
                spCheck.SoLuong++;
                //và đơn giá sẽ tăng theo giá sp * sl tương ứng
                spCheck.ThanhTien = spCheck.SoLuong * spCheck.DonGia;
                TempData["SuccessMessage"] = "Thêm vào giỏ hàng thành công!";
                return Redirect(strURL);
            }
            
            //nếu chưa tồn tại thì thêm vào list
            ItemGioHang itemGH = new ItemGioHang(MaSP);
            if (sp.SoLuongTon < itemGH.SoLuong) //ktra số lg tồn trc khi cho kh mua hàng
                return View("ThongBao");
            lstGioHang.Add(itemGH);
            TempData["SuccessMessage"] = "Thêm vào giỏ hàng thành công!";
            return Redirect(strURL);
        }

        [HttpPost]
public JsonResult ThemGioHangAjax(int MaSP)
{
    SanPham sp = db.SanPham.SingleOrDefault(n => n.MaSP == MaSP);
    if (sp == null)
        return Json(new { success = false });

    List<ItemGioHang> lstGioHang = LayGioHang();

    ItemGioHang spCheck = lstGioHang.SingleOrDefault(n => n.MaSP == MaSP);

    if (spCheck != null)
    {
        spCheck.SoLuong++;
        spCheck.ThanhTien = spCheck.SoLuong * spCheck.DonGia;
    }
    else
    {
        ItemGioHang itemGH = new ItemGioHang(MaSP);
        lstGioHang.Add(itemGH);
    }

    // 🔥 Tính tổng số lượng
    int tongSoLuong = lstGioHang.Sum(x => x.SoLuong);

    return Json(new { success = true, total = tongSoLuong });
}

        // GET: GioHang
        //Trang xem giỏ hàng
        public ActionResult XemGioHang()
        {
            //lấy giỏ hàng đã đc tạo
            List<ItemGioHang> lstGioHang = LayGioHang();
            ViewBag.TongSoLuong = TinhTongSoLuong();
            ViewBag.TongTien = TinhTongTien();

            return View(lstGioHang);    //đưa list vào view
        }

        //chỉnh sửa giỏ hàng
        [HttpGet]
        public ActionResult SuaGioHang(int MaSP)
        {
            //ktra session giỏ hàng có tồn tại ko
            if(Session["GioHang"] == null)
            {
                return RedirectToAction("Index", "Home");   //quay về trang chủ
            }
            //ktra sp có tồn tại trong csdl ko
            SanPham sp = db.SanPham.SingleOrDefault(n => n.MaSP == MaSP);
            if (sp == null)
            {
                //Trang đường dẫn ko hợp lệ
                Response.StatusCode = 404;
                return null;
            }

            //Lấy list giỏ hàng từ session
            List<ItemGioHang> lstGioHang = LayGioHang();

            //ktra xem sp đó có tồn tại trong giỏ hàng hay ko
            ItemGioHang spCheck = lstGioHang.SingleOrDefault(n => n.MaSP == MaSP);
            if(spCheck == null)
            {
                return RedirectToAction("Index", "Home");
            }

            //Lấy list giỏ hàng tạo giao diện
            ViewBag.GioHang = lstGioHang;

            //nếu tồn tại thì
            return View(spCheck);
        }

        //Cập nhật giỏ hàng
        [HttpPost]
        public ActionResult CapNhatGioHang(ItemGioHang itemGH)
        {
            //ktra số lượng tồn sau khi sửa
            SanPham spCheck = db.SanPham.Single(n => n.MaSP == itemGH.MaSP);
            if(spCheck.SoLuongTon < itemGH.SoLuong)
            {
                return View("ThongBao");
            }

            //update số lg trong session giỏ hàng
            //bc1: Lấy list giỏ hàng từ sesssion giỏ hàng
            List<ItemGioHang> lstGH = LayGioHang();
            //bc2: lấy sp cần update từ trong list giỏ hàng
            ItemGioHang itemGHUpdate = lstGH.Find(n => n.MaSP == itemGH.MaSP);  //pt find dùng để tìm các trường mong muốn
            //bc3: update lại số lg và thành tiền
            itemGHUpdate.SoLuong = itemGH.SoLuong;
            itemGHUpdate.ThanhTien = itemGHUpdate.SoLuong * itemGHUpdate.DonGia;

            return RedirectToAction("XemGioHang");
        }

        //Xóa giỏ hàng
        public ActionResult XoaGioHang(int MaSP)
        {
            //ktra session giỏ hàng có tồn tại ko
            if (Session["GioHang"] == null)
            {
                return RedirectToAction("Index", "Home");
            }
            //ktra sp có tồn tại trong csdl ko
            SanPham sp = db.SanPham.SingleOrDefault(n => n.MaSP == MaSP);
            if (sp == null)
            {
                //Trang đường dẫn ko hợp lệ
                Response.StatusCode = 404;
                return null;
            }
            //Lấy list giỏ hàng từ session
            List<ItemGioHang> lstGioHang = LayGioHang();
            //ktra xem sp đó có tồn tại trong giỏ hàng hay ko
            ItemGioHang spCheck = lstGioHang.SingleOrDefault(n => n.MaSP == MaSP);
            if (spCheck == null)
            {
                return RedirectToAction("Index", "Home");
            }
            //Xóa item trong giỏ hàng
            lstGioHang.Remove(spCheck);

            return RedirectToAction("XemGioHang");
        }

        //chức năng đặt hàng
        public ActionResult DatHang()
        {
            if (Session["TaiKhoan"] == null)
                return RedirectToAction("DangNhap", "ThanhVien");

            ThanhVien tv = (ThanhVien)Session["TaiKhoan"];

            // 🔥 TÌM KHÁCH HÀNG TƯƠNG ỨNG
            KhachHang khach = db.KhachHang
                .FirstOrDefault(x => x.MaThanhVien == tv.MaThanhVien);

            // Nếu chưa có → tạo mới
            if (khach == null)
            {
                khach = new KhachHang();
                khach.TenKH = tv.HoTen;
                khach.Email = tv.Email;
                khach.SoDienThoai = tv.SoDienThoai;
                khach.DiaChi = tv.DiaChi;
                khach.MaThanhVien = tv.MaThanhVien;

                db.KhachHang.Add(khach);
                db.SaveChanges();
            }

            // ===== TẠO ĐƠN HÀNG =====
            DonDatHang ddh = new DonDatHang();
            ddh.MaKH = khach.MaKH;   // 🔥 QUAN TRỌNG
            ddh.NgayDat = DateTime.Now;
            ddh.TinhTrangGiaoHang = false;
            ddh.DaThanhToan = false;
            ddh.UuDai = 0;
            ddh.DaHuy = false;
            ddh.DaXoa = false;

            db.DonDatHang.Add(ddh);
            db.SaveChanges();

            // ===== THÊM CHI TIẾT =====
            List<ItemGioHang> lstGH = LayGioHang();

            foreach (var item in lstGH)
            {
                ChiTietDonDatHang ctdh = new ChiTietDonDatHang();
                ctdh.MaDDH = ddh.MaDDH;
                ctdh.MaSP = item.MaSP;
                ctdh.TenSP = item.TenSP;
                ctdh.SoLuong = item.SoLuong;
                ctdh.Dongia = item.DonGia;

                db.ChiTietDonDatHang.Add(ctdh);
            }

            db.SaveChanges();

            Session["GioHang"] = null;

            return RedirectToAction("Index", "DonHang");
        }


        #region Methods
        //Lấy giỏ hàng
        public List<ItemGioHang> LayGioHang()
        {
            //nếu giỏ hàng đã tồn tại
            List<ItemGioHang> lstGioHang = Session["GioHang"] as List<ItemGioHang>; //lưu giỏ hàng vào session giohang để quản lý
            if (lstGioHang == null)
            {
                //Nếu session giỏ hàng ko tồn tại thì khởi tạo giỏ hàng
                lstGioHang = new List<ItemGioHang>();
                Session["GioHang"] = lstGioHang;
            }
            return lstGioHang;
        }

        // tính tổng số lg
        public double TinhTongSoLuong()
        {
            //lấy giỏ hàng
            List<ItemGioHang> lstGioHang = Session["GioHang"] as List<ItemGioHang>;
            if(lstGioHang == null)  //nếu chưa có list giỏ hàng thì trả về gtri = 0
            {
                return 0;
            }
            return lstGioHang.Sum(n => n.SoLuong); //trả về tổng số lượng của list giỏ hàng
        }

        //tính tổng tiền
        public decimal TinhTongTien()
        {
            //lấy giỏ hàng
            List<ItemGioHang> lstGioHang = Session["GioHang"] as List<ItemGioHang>;
            if (lstGioHang == null) //nếu chưa có list giỏ hàng thì trả về gtri = 0
            {
                return 0;
            }
            return lstGioHang.Sum(n => n.ThanhTien);    //trả về tổng tiền của list giỏ hàng
        }
        #endregion

        //Giải phóng dung lượng biến db, để ở cuối controller
        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (db != null)
                    db.Dispose();
                db.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}