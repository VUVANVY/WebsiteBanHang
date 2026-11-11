using System;
using System.Collections.Generic;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using WebsiteBanHang.Models;
using System.Web.Security;
using CaptchaMvc.HtmlHelpers;
using CaptchaMvc;
using WebsiteBanHang.Security;

namespace WebsiteBanHang.Controllers
{

    public class HomeController : Controller
    {
        QuanLyBanHangEntities db = new QuanLyBanHangEntities();
        
        // GET: Home/Index
        public ActionResult Index()
        {
            //Lần lượt tạo các viewbag để lấy list sp từ csdl
            //List laptop mới
            var lstLTM = db.SanPham.Where(n => n.MaLoaiSP == 1 && n.Moi == 1 && n.DaXoa == false).ToList();
            //Gán vào viewbag
            ViewBag.ListLTM = lstLTM;

            //List PC mới
            var lstPCM = db.SanPham.Where(n => n.MaLoaiSP == 2 && n.Moi == 1 && n.DaXoa == false).ToList();
            //Gán vào viewbag
            ViewBag.ListPCM = lstPCM;

            //List dt mới
            var lstDTM = db.SanPham.Where(n => n.MaLoaiSP == 7 && n.Moi == 1 && n.DaXoa == false).ToList();
            //Gán vào viewbag
            ViewBag.ListDTM = lstDTM;

            return View();
        }

        public ActionResult MenuPartial()
        {
            //Lấy ra 1 lst sanpham và truyền trực tiếp vào partial
            var lstSP = db.SanPham.ToList();

            return PartialView(lstSP);
        }

        [HttpGet]
        public ActionResult DangKy()
        {
            //đặt trùng tên viewbag giống trong bảng
            ViewBag.CauHoi = new SelectList(LoadCauHoi());  //gắn các câu hỏi vào viewbag để hiển thị lên view

            return View();
        }
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult DangKy([Bind(Include = "TaiKhoan,MatKhau,HoTen,DiaChi,Email,SoDienThoai,CauHoi,CauTraLoi")] ThanhVien tv)
        {
            ViewBag.CauHoi = new SelectList(LoadCauHoi());  //lưu câu hỏi đã chọn trong dropdownlist vào csdl
            //Kiểm tra captcha hợp lệ
            if (this.IsCaptchaValid("Captcha không hợp lệ!"))   //nếu captcha hợp lệ
            {
                if (ModelState.IsValid)
                {
                    if (db.ThanhVien.Any(n => n.TaiKhoan == tv.TaiKhoan))
                    {
                        ModelState.AddModelError("TaiKhoan", "Tài khoản đã tồn tại.");
                        return View(tv);
                    }
                    tv.MaThanhVien = 0;
                    tv.MaLoaiTV = 3;
                    tv.MatKhau = PasswordService.Hash(tv.MatKhau);
                    ViewBag.ThongBao = "Thêm thành công";
                    //Thêm khách hàng vào csdl
                    db.ThanhVien.Add(tv);  //sau khi lấy được các thuộc tính trong biến tv qua các textbox thì truyền tv vào dbset ThanhViens
                    //Lưu thay đổi
                    db.SaveChanges();   //lấy data từ dbset chuyển vào csdl
                }
                return View();
            }
            ViewBag.ThongBao = "Sai mã Captcha";
            return View();
        }

        //Load câu hỏi để đưa vào dropdownlist
        private List<string> LoadCauHoi()
        {
            List<string> lstCauHoi = new List<string>();    //tạo list câu hỏi chứa câu hỏi
            lstCauHoi.Add("Họ tên người cha bạn là gì?");
            lstCauHoi.Add("Ca sĩ mà bạn yêu thích là ai?");
            lstCauHoi.Add("Vật nuôi mà bạn yêu thích là gì?");
            lstCauHoi.Add("Sở thích của bạn là gì");
            lstCauHoi.Add("Hiện tại bạn đang làm công việc gì?");
            lstCauHoi.Add("Trường cấp ba bạn học là gì?");
            lstCauHoi.Add("Năm sinh của mẹ bạn là gì?");
            lstCauHoi.Add("Bộ phim mà bạn yêu thích là gì?");
            lstCauHoi.Add("Bài nhạc mà bạn yêu thích là gì?");

            return lstCauHoi;
        }

        //xd action dang nhap
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult DangNhap(FormCollection f)
        {
            string taikhoan = f["txtTenDangNhap"];
            string matKhau = f["txtMatKhau"];
            if (string.IsNullOrWhiteSpace(taikhoan) || string.IsNullOrEmpty(matKhau))
                return Content("Tài khoản hoặc mật khẩu không chính xác.");

            ThanhVien tv = db.ThanhVien.SingleOrDefault(n => n.TaiKhoan == taikhoan);
            bool needsUpgrade;
            if (tv != null && PasswordService.Verify(matKhau, tv.MatKhau, out needsUpgrade))
            {
                var lstQuyen = db.LoaiThanhVien_Quyen.Where(n => n.MaLoaiTV == tv.MaLoaiTV).ToList();   //lấy ra list quyền tương ứng loaitv
                string Quyen = "";
                if (lstQuyen.Count() != 0)
                {
                    if (needsUpgrade)
                    {
                        tv.MatKhau = PasswordService.Hash(matKhau);
                        db.SaveChanges();
                    }
                    foreach (var item in lstQuyen)   //duyệt list quyền
                    {
                        Quyen += item.Quyen.MaQuyen + ",";
                    }
                    Quyen = Quyen.Substring(0, Quyen.Length - 1); //Cắt dấu ,
                    PhanQuyen(tv.TaiKhoan.ToString(), Quyen);

                    Session["TaiKhoan"] = tv;
                    return Content(@"<script>window.location.reload()</script>");   //đoạn script dùng để reload lại trang khi đăng nhập thành công
                }
            }
            return Content("Tài khoản hoặc mật khẩu không chính xác.");
        }

        


        public ActionResult DangXuat()
        {
            Session["TaiKhoan"] = null; //thiết lập session là null

            FormsAuthentication.SignOut();  //xóa bộ nhớ cookie

            return RedirectToAction("Index");
        }

        public ActionResult LoiPhanquyen()
        {
            return View();
        }

        private void PhanQuyen(string Taikhoan, string Quyen)
        {
            FormsAuthentication.Initialize();

            var ticket = new FormsAuthenticationTicket(1,
                                            Taikhoan,   //đặt tên ticket theo tên tk 
                                            DateTime.Now,   //lấy tgian bắt đầu
                                            DateTime.Now.AddHours(3),   //thời gian 3 tiếng out ra
                                            false,  //ko lưu
                                            Quyen,  //Lấy chuỗi phân quyền
                                            FormsAuthentication.FormsCookiePath);   //Lấy đg dẫn cookie thay vì name
            var cookie = new HttpCookie(FormsAuthentication.FormsCookieName, FormsAuthentication.Encrypt(ticket))
            {
                HttpOnly = true,
                Secure = Request.IsSecureConnection,
                Path = FormsAuthentication.FormsCookiePath
            };
            if (ticket.IsPersistent) cookie.Expires = ticket.Expiration;    //ktra cookie có chưa
            Response.Cookies.Add(cookie);     //
        }

        //Giải phóng dung lượng biến db, để ở cuối controller
        protected override void Dispose(bool disposing)
        {
            if (disposing && db != null)
                db.Dispose();
            base.Dispose(disposing);
        }
    }
}
