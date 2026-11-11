using System;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace WebsiteBanHang.Security
{
    public static class PasswordService
    {
        private const string Algorithm = "PBKDF2-SHA256";
        private const int Iterations = 600000;
        private const int SaltLength = 16;
        private const int HashLength = 32;

        public static string Hash(string password)
        {
            if (string.IsNullOrEmpty(password))
                throw new ArgumentException("A password is required.", nameof(password));

            var salt = new byte[SaltLength];
            using (var random = RandomNumberGenerator.Create())
                random.GetBytes(salt);

            var hash = Derive(password, salt, Iterations);
            return string.Join("$", Algorithm, Iterations.ToString(CultureInfo.InvariantCulture),
                Convert.ToBase64String(salt), Convert.ToBase64String(hash));
        }

        // Older plaintext credentials are upgraded only after a successful sign-in.
        public static bool Verify(string password, string storedPassword, out bool needsUpgrade)
        {
            needsUpgrade = false;
            if (string.IsNullOrEmpty(password) || string.IsNullOrEmpty(storedPassword))
                return false;

            if (!storedPassword.StartsWith(Algorithm + "$", StringComparison.Ordinal))
            {
                var matches = FixedTimeEquals(Encoding.UTF8.GetBytes(password),
                    Encoding.UTF8.GetBytes(storedPassword));
                needsUpgrade = matches;
                return matches;
            }

            var fields = storedPassword.Split('$');
            int iterations;
            if (fields.Length != 4 || fields[0] != Algorithm ||
                !int.TryParse(fields[1], NumberStyles.None, CultureInfo.InvariantCulture, out iterations) ||
                iterations < 10000 || iterations > 2000000)
                return false;

            try
            {
                var salt = Convert.FromBase64String(fields[2]);
                var expected = Convert.FromBase64String(fields[3]);
                if (salt.Length != SaltLength || expected.Length != HashLength)
                    return false;

                var matches = FixedTimeEquals(Derive(password, salt, iterations), expected);
                needsUpgrade = matches && iterations < Iterations;
                return matches;
            }
            catch (FormatException)
            {
                return false;
            }
        }

        private static byte[] Derive(string password, byte[] salt, int iterations)
        {
            using (var derivation = new Rfc2898DeriveBytes(password, salt, iterations, HashAlgorithmName.SHA256))
                return derivation.GetBytes(HashLength);
        }

        private static bool FixedTimeEquals(byte[] left, byte[] right)
        {
            if (left.Length != right.Length)
                return false;

            var difference = 0;
            for (var i = 0; i < left.Length; i++)
                difference |= left[i] ^ right[i];
            return difference == 0;
        }
    }
}
