using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Principal;
using System.Web;
using System.Web.Mvc;
using System.Web.Optimization;
using System.Web.Routing;
using System.Web.Security;
using System.Security.Cryptography;
using System.Threading;

namespace WebsiteBanHang
{
    public class MvcApplication : System.Web.HttpApplication
    {
        protected void Application_Start()
        {
            AreaRegistration.RegisterAllAreas();
            FilterConfig.RegisterGlobalFilters(GlobalFilters.Filters);
            RouteConfig.RegisterRoutes(RouteTable.Routes);
            BundleConfig.RegisterBundles(BundleTable.Bundles);

            Application["SoNguoiTruyCap"] = 0;
            Application["SoNguoiDangOnline"] = 0;
        }
        protected void Session_Start()
        {
            Application.Lock();     //dùng đồng bộ hóa
            Application["SoNguoiTruyCap"] = (int)Application["SoNguoiTruyCap"] + 1;
            Application["SoNguoiDangOnline"] = (int)Application["SoNguoiDangOnline"] + 1;
            Application.UnLock();       ////dùng ngắt bộ hóa
        }

        protected void Session_End()
        {
            Application.Lock();
            Application["SoNguoiDangOnline"] = (int)Application["SoNguoiDangOnline"] - 1;
            Application.UnLock();
        }

        public void Application_End()
        {
            Application.Lock();
            Application["SoNguoiDangOnline"] = (int)Application["SoNguoiDangOnline"] - 1;
            Application.UnLock();
        }

        protected void Application_AuthenticateRequest(Object sender, EventArgs e)
        {
            var cookie = Context.Request.Cookies[FormsAuthentication.FormsCookieName];
            if (cookie == null || string.IsNullOrEmpty(cookie.Value))
                return;

            FormsAuthenticationTicket ticket;
            try
            {
                ticket = FormsAuthentication.Decrypt(cookie.Value);
            }
            catch (Exception ex) when (ex is ArgumentException || ex is CryptographicException || ex is HttpException)
            {
                RejectAuthenticationCookie();
                return;
            }

            if (ticket == null || ticket.Expired || string.IsNullOrWhiteSpace(ticket.Name))
            {
                RejectAuthenticationCookie();
                return;
            }

            var roles = (ticket.UserData ?? string.Empty).Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
            var principal = new GenericPrincipal(new GenericIdentity(ticket.Name, "Forms"), roles);
            Context.User = principal;
            Thread.CurrentPrincipal = principal;
        }

        private void RejectAuthenticationCookie()
        {
            FormsAuthentication.SignOut();
            var anonymous = new GenericPrincipal(new GenericIdentity(string.Empty), new string[0]);
            Context.User = anonymous;
            Thread.CurrentPrincipal = anonymous;
        }
    }
}
