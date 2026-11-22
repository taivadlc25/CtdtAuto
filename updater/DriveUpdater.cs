using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Win32.SafeHandles;

internal static class DriveUpdater
{
    private const int ManifestLimit = 8192;
    private const int HtmlLimit = 262144;
    private const int PackageLimit = 128 * 1024 * 1024;
    private static readonly UTF8Encoding StrictUtf8 = new UTF8Encoding(false, true);
    private static readonly UTF8Encoding StatusUtf8 = new UTF8Encoding(true);
    private static readonly Regex DriveId = new Regex(@"^[A-Za-z0-9_-]{1,200}\z");

    private sealed class Release
    {
        internal Version Version;
        internal string FileId, Hash;
        internal long Size;
    }

    private sealed class Install
    {
        internal string Target, State;
        internal Version Reported;
        internal string Pending { get { return Path.Combine(State, "pending"); } }
        internal string Download { get { return Path.Combine(State, "download"); } }

        internal Version InstalledVersion()
        {
            Version onDisk = ResourceVersion(Target);
            return onDisk != null && onDisk > Reported ? onDisk : Reported;
        }

        internal void Status(string text)
        {
            WriteAtomic(Path.Combine(State, "status.txt"), text + "\r\n", StatusUtf8);
        }

        internal bool Throttled()
        {
            string path = Path.Combine(State, "check.txt");
            if (!File.Exists(path)) return false;
            string[] fields = File.ReadAllText(path).Trim().Split('|');
            long ticks;
            if (fields.Length != 2 || !long.TryParse(fields[1], out ticks)) return false;
            long age = DateTime.UtcNow.Ticks - ticks;
            TimeSpan limit = fields[0] == "ok" ? TimeSpan.FromHours(6) : TimeSpan.FromMinutes(10);
            return ticks > 0 && age >= 0 && age < limit.Ticks;
        }

        internal void Record(bool success)
        {
            WriteAtomic(Path.Combine(State, "check.txt"), (success ? "ok|" : "fail|") +
                DateTime.UtcNow.Ticks.ToString(CultureInfo.InvariantCulture), StrictUtf8);
        }
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 4 || (args[3] != "auto" && args[3] != "manual")) return 2;
        Install app = new Install();
        try
        {
            string inputName = Path.GetFileName(args[0]);
            if (!Path.IsPathRooted(args[0]) || (!string.Equals(inputName, "CtdtAuto.exe", StringComparison.OrdinalIgnoreCase) && !string.Equals(inputName, "CTDT_auto_custom.exe", StringComparison.OrdinalIgnoreCase))) return 2;
            app.Target = CanonicalFile(args[0]);
            string targetName = Path.GetFileName(app.Target);
            if (!string.Equals(targetName, "CtdtAuto.exe", StringComparison.OrdinalIgnoreCase) && !string.Equals(targetName, "CTDT_auto_custom.exe", StringComparison.OrdinalIgnoreCase)) return 2;
            app.Reported = ParseVersion(args[1]);
            app.State = Path.Combine(Path.GetDirectoryName(app.Target), ".ctdt-update");
            string mutexId;
            using (SHA256 sha = SHA256.Create())
                mutexId = Hex(sha.ComputeHash(StrictUtf8.GetBytes(app.Target.ToUpperInvariant())));
            using (Mutex mutex = new Mutex(false, @"Global\CTDT.DriveUpdate." + mutexId))
            {
                try { if (!mutex.WaitOne(0)) return 0; }
                catch (AbandonedMutexException) { }
                try
                {
                    Directory.CreateDirectory(app.State);
                    RejectLink(app.State);
                    return Check(app, args[2], args[3] == "manual");
                }
                catch (Exception ex)
                {
                    try
                    {
                        if (ex is WebException || ex is TimeoutException)
                            app.Status("Chưa kiểm tra được cập nhật qua Google Drive. Ứng dụng sẽ thử lại sau.");
                        else if (ex is InvalidDataException || ex is CryptographicException || ex is DecoderFallbackException)
                            app.Status("Không thể xác minh bản cập nhật. Vẫn sử dụng phiên bản đang cài.");
                        else
                            app.Status("Không thể hoàn tất cập nhật. Hãy kiểm tra quyền ghi và dung lượng thư mục ứng dụng.");
                        app.Record(false);
                    }
                    catch (IOException) { }
                    catch (UnauthorizedAccessException) { }
                    return 1;
                }
                finally { mutex.ReleaseMutex(); }
            }
        }
        catch (Exception) { return 2; }
    }

    private static int Check(Install app, string manifestId, bool manual)
    {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        if (Directory.Exists(app.Pending))
        {
            RejectLink(app.Pending);
            try
            {
                Release queued = ReadManifest(Path.Combine(app.Pending, "manifest.txt"));
                if (queued.Version > app.InstalledVersion())
                {
                    ApplyWhenClosed(app, queued);
                    return 0;
                }
                ClearStage(app.Pending);
                app.Status("Đang sử dụng phiên bản " + app.InstalledVersion() + ".");
            }
            catch (InvalidDataException)
            {
                ClearStage(app.Pending);
                app.Status("Đã bỏ gói cập nhật chưa hợp lệ. Đang kiểm tra lại.");
            }
        }
        if (!manual && app.Throttled()) return 0;
        if (!DriveId.IsMatch(manifestId))
        {
            app.Status("Chưa cấu hình tệp phát hành Google Drive.");
            return 2;
        }
        app.Status("Đang kiểm tra phiên bản mới trên Google Drive…");
        byte[] manifest;
        using (MemoryStream body = new MemoryStream())
        {
            Fetch(manifestId, body, ManifestLimit);
            manifest = body.ToArray();
        }
        Release release = ParseManifest(manifest);
        if (release.Version <= app.InstalledVersion())
        {
            app.Status("Đang dùng phiên bản " + app.InstalledVersion() + ". Chưa có bản mới hơn.");
            app.Record(true);
            return 0;
        }
        app.Status("Đang tải bản cập nhật " + release.Version + "…");
        ClearStage(app.Download);
        Directory.CreateDirectory(app.Download);
        RejectLink(app.Download);
        try
        {
            string exe = Path.Combine(app.Download, "payload.exe");
            using (FileStream output = new FileStream(exe, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                Fetch(release.FileId, output, release.Size);
                output.Flush(true);
            }
            VerifyPackage(exe, release);
            using (FileStream output = new FileStream(Path.Combine(app.Download, "manifest.txt"), FileMode.CreateNew))
            {
                output.Write(manifest, 0, manifest.Length);
                output.Flush(true);
            }
            Directory.Move(app.Download, app.Pending);
        }
        finally { ClearStage(app.Download); }
        ApplyWhenClosed(app, release);
        return 0;
    }

    private static Version ParseVersion(string value)
    {
        if (!Regex.IsMatch(value, @"^[0-9]{1,5}(?:\.[0-9]{1,5}){3}\z")) throw new InvalidDataException();
        Version version;
        if (!Version.TryParse(value, out version) || version.Major > 65535 || version.Minor > 65535 ||
            version.Build > 65535 || version.Revision > 65535) throw new InvalidDataException();
        return version;
    }

    private static Release ReadManifest(string path)
    {
        if (!File.Exists(path)) throw new InvalidDataException();
        RejectLink(path);
        if (new FileInfo(path).Length > ManifestLimit) throw new InvalidDataException();
        return ParseManifest(File.ReadAllBytes(path));
    }

    private static Release ParseManifest(byte[] bytes)
    {
        if (bytes.Length > ManifestLimit) throw new InvalidDataException();
        string text;
        try { text = StrictUtf8.GetString(bytes); }
        catch (DecoderFallbackException ex) { throw new InvalidDataException("UTF-8", ex); }
        if (text.StartsWith("\uFEFF", StringComparison.Ordinal)) text = text.Substring(1);
        text = text.Replace("\r\n", "\n");
        if (text.EndsWith("\n", StringComparison.Ordinal)) text = text.Substring(0, text.Length - 1);
        string[] lines = text.Split('\n');
        if (lines.Length != 6 || lines[0] != "CTDT-AUTO-1") throw new InvalidDataException();
        Release release = new Release();
        release.Version = ParseVersion(Field(lines[1], "version"));
        release.FileId = Field(lines[2], "file");
        if (!DriveId.IsMatch(release.FileId)) throw new InvalidDataException();
        string size = Field(lines[3], "size");
        if (!Regex.IsMatch(size, @"^[0-9]{1,10}\z") || !long.TryParse(size, NumberStyles.None,
            CultureInfo.InvariantCulture, out release.Size) || release.Size < 64 || release.Size > PackageLimit)
            throw new InvalidDataException();
        release.Hash = Field(lines[4], "sha256");
        if (!Regex.IsMatch(release.Hash, @"^[0-9a-fA-F]{64}\z")) throw new InvalidDataException();
        string sigText = Field(lines[5], "signature");
        if (!Regex.IsMatch(sigText, @"^[A-Za-z0-9+/]{1,1400}={0,2}\z")) throw new InvalidDataException();
        byte[] signature;
        try { signature = Convert.FromBase64String(sigText); }
        catch (FormatException ex) { throw new InvalidDataException("Signature", ex); }
        byte[] signed = StrictUtf8.GetBytes(string.Join("\n", lines, 0, 5) + "\n");
        using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("CTDT.ReleaseKey"))
        {
            if (resource == null) throw new InvalidDataException("Release key");
            using (StreamReader reader = new StreamReader(resource))
            using (RSACryptoServiceProvider key = new RSACryptoServiceProvider(new CspParameters(24)))
            {
                key.PersistKeyInCsp = false;
                key.FromXmlString(reader.ReadToEnd());
                bool valid;
                try { valid = key.VerifyData(signed, CryptoConfig.MapNameToOID("SHA256"), signature); }
                catch (CryptographicException ex) { throw new InvalidDataException("Signature", ex); }
                if (!valid) throw new InvalidDataException("Signature");
            }
        }
        return release;
    }

    private static string Field(string line, string key)
    {
        if (!line.StartsWith(key + "=", StringComparison.Ordinal)) throw new InvalidDataException();
        return line.Substring(key.Length + 1);
    }

    private static Version ResourceVersion(string path)
    {
        FileVersionInfo info = FileVersionInfo.GetVersionInfo(path);
        if (string.IsNullOrWhiteSpace(info.FileVersion)) return null;
        return new Version(info.FileMajorPart, info.FileMinorPart, info.FileBuildPart, info.FilePrivatePart);
    }

    private static void VerifyPackage(string path, Release release)
    {
        if (!File.Exists(path)) throw new InvalidDataException();
        RejectLink(path);
        using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        using (BinaryReader reader = new BinaryReader(stream))
        using (SHA256 sha = SHA256.Create())
        {
            if (stream.Length != release.Size || reader.ReadUInt16() != 0x5a4d) throw new InvalidDataException();
            stream.Position = 0x3c;
            uint pe = reader.ReadUInt32();
            if (pe < 64 || pe > stream.Length - 26) throw new InvalidDataException();
            stream.Position = pe;
            if (reader.ReadUInt32() != 0x4550) throw new InvalidDataException();
            stream.Position = pe + 20;
            ushort optionalSize = reader.ReadUInt16(), flags = reader.ReadUInt16(), magic = reader.ReadUInt16();
            if ((flags & 0x2002) != 2 || (magic != 0x10b && magic != 0x20b) ||
                optionalSize < 96 || pe + 24 + optionalSize > stream.Length) throw new InvalidDataException();
            stream.Position = 0;
            if (!string.Equals(Hex(sha.ComputeHash(stream)), release.Hash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("SHA-256");
        }
        Version version = ResourceVersion(path);
        if (version != release.Version) throw new InvalidDataException("File version");
    }

    private static string Hex(byte[] digest)
    {
        return BitConverter.ToString(digest).Replace("-", "");
    }

    private static void ApplyWhenClosed(Install app, Release release)
    {
        string payload = Path.Combine(app.Pending, "payload.exe");
        VerifyPackage(payload, release);
        app.Status("Đã tải bản " + release.Version + ". Đóng tất cả cửa sổ CTDT Auto để cập nhật.");
        int busyTries = 0;
        while (true)
        {
            if (ApplicationRunning(app.Target))
            {
                Thread.Sleep(1700);
                continue;
            }
            try
            {
                Release final = ReadManifest(Path.Combine(app.Pending, "manifest.txt"));
                if (final.Version != release.Version || !string.Equals(final.Hash, release.Hash, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException();
                if (final.Version <= app.InstalledVersion())
                {
                    ClearStage(app.Pending);
                    app.Status("Đang sử dụng phiên bản " + app.InstalledVersion() + ".");
                    app.Record(true);
                    return;
                }
                // An open write handle prevents another process from mapping this EXE
                // for execution between the last process scan and ReplaceFile.
                using (FileStream guard = new FileStream(app.Target, FileMode.Open, FileAccess.Write,
                    FileShare.ReadWrite | FileShare.Delete))
                {
                    if (ApplicationRunning(app.Target)) continue;
                    VerifyPackage(payload, final);
                    string previous = Path.Combine(app.State, "previous.exe");
                    if (File.Exists(previous)) RejectLink(previous);
                    File.Replace(payload, app.Target, previous, true);
                }
                ClearStage(app.Pending);
                app.Status("Đã cập nhật lên phiên bản " + final.Version + ".");
                app.Record(true);
                return;
            }
            catch (IOException ex)
            {
                int code = ex.HResult & 0xffff;
                if (code != 32 && code != 33 && code != 1224) throw;
                if (++busyTries >= 50)
                {
                    app.Status("Đã tải bản " + release.Version + ". Tệp ứng dụng đang bận, sẽ thử cài lại ở lần mở tới.");
                    return;
                }
                Thread.Sleep(1200);
            }
        }
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder name, uint count, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inherit, int id);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool QueryFullProcessImageName(IntPtr process, uint flags, StringBuilder file, ref int size);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    private static string CanonicalFile(string path)
    {
        using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete))
        {
            StringBuilder name = new StringBuilder(32768);
            uint n = GetFinalPathNameByHandle(stream.SafeFileHandle, name, (uint)name.Capacity, 0);
            if (n == 0 || n >= name.Capacity) throw new IOException("File path", new Win32Exception());
            string final = name.ToString();
            if (final.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) return @"\\" + final.Substring(8);
            if (final.StartsWith(@"\\?\", StringComparison.Ordinal)) return final.Substring(4);
            return final;
        }
    }

    private static bool ApplicationRunning(string path)
    {
        Process[] matches = Process.GetProcessesByName(Path.GetFileNameWithoutExtension(path));
        try
        {
            foreach (Process process in matches)
            {
                IntPtr handle = OpenProcess(0x1000, false, process.Id);
                if (handle == IntPtr.Zero)
                {
                    if (Marshal.GetLastWin32Error() == 5) return true;
                    continue;
                }
                try
                {
                    int length = 32768;
                    StringBuilder image = new StringBuilder(length);
                    if (!QueryFullProcessImageName(handle, 0, image, ref length)) continue;
                    string running = image.ToString();
                    if (string.Equals(running, path, StringComparison.OrdinalIgnoreCase)) return true;
                    try
                    {
                        if (string.Equals(CanonicalFile(running), path, StringComparison.OrdinalIgnoreCase)) return true;
                    }
                    catch (FileNotFoundException) { }
                    catch (DirectoryNotFoundException) { }
                    catch (UnauthorizedAccessException) { }
                }
                finally { CloseHandle(handle); }
            }
            return false;
        }
        finally { foreach (Process process in matches) process.Dispose(); }
    }

    private static void RejectLink(string path)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("Unexpected update path");
    }

    private static void ClearStage(string directory)
    {
        if (!Directory.Exists(directory)) return;
        RejectLink(directory);
        foreach (string name in new string[] { "manifest.txt", "payload.exe" })
        {
            string path = Path.Combine(directory, name);
            if (File.Exists(path)) { RejectLink(path); File.Delete(path); }
        }
        Directory.Delete(directory, false);
    }

    private static void WriteAtomic(string path, string text, Encoding encoding)
    {
        string temporary = path + ".writing";
        if (File.Exists(temporary)) { RejectLink(temporary); File.Delete(temporary); }
        try
        {
            using (FileStream file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write))
            using (StreamWriter writer = new StreamWriter(file, encoding))
            {
                writer.Write(text);
                writer.Flush();
                file.Flush(true);
            }
            for (int attempt = 0; ; attempt++)
            {
                try
                {
                    if (File.Exists(path)) { RejectLink(path); File.Replace(temporary, path, null); }
                    else File.Move(temporary, path);
                    return;
                }
                catch (IOException)
                {
                    if (attempt >= 5) throw;
                    Thread.Sleep(100);
                }
            }
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static bool AllowedAddress(Uri uri)
    {
        if (!uri.IsAbsoluteUri || uri.Scheme != Uri.UriSchemeHttps || uri.Port != 443 ||
            uri.UserInfo.Length != 0 || uri.Fragment.Length != 0) return false;
        string host = uri.IdnHost.ToLowerInvariant();
        return host == "drive.usercontent.google.com" || host == "drive.google.com" ||
            host == "docs.google.com" || host.EndsWith(".googleusercontent.com", StringComparison.Ordinal);
    }

    private static void Fetch(string id, Stream destination, long limit)
    {
        if (!DriveId.IsMatch(id)) throw new InvalidDataException();
        Uri requestUri = new Uri("https://drive.usercontent.google.com/download?export=download&confirm=t&id=" +
            Uri.EscapeDataString(id));
        CookieContainer cookies = new CookieContainer();
        Stopwatch clock = Stopwatch.StartNew();
        bool confirmed = false;
        for (int hop = 0; hop < 7; hop++)
        {
            if (!AllowedAddress(requestUri)) throw new WebException("Download location");
            CheckDeadline(clock);
            HttpWebRequest request = (HttpWebRequest)WebRequest.Create(requestUri);
            request.AllowAutoRedirect = false;
            request.Timeout = 12000;
            request.ReadWriteTimeout = 12000;
            request.CookieContainer = cookies;
            request.UserAgent = "CTDT-Auto-Updater/1";
            request.Credentials = null;
            request.CachePolicy = new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
            using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
            {
                int code = (int)response.StatusCode;
                if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308)
                {
                    Uri redirected;
                    if (!Uri.TryCreate(requestUri, response.Headers["Location"], out redirected) || !AllowedAddress(redirected))
                        throw new WebException("Download redirect");
                    requestUri = redirected;
                    continue;
                }
                if (code != 200) throw new WebException("Download response");
                using (Stream body = response.GetResponseStream())
                {
                    byte[] prefix = new byte[512];
                    int prefixCount = 0;
                    while (prefixCount < prefix.Length)
                    {
                        int n = body.Read(prefix, prefixCount, prefix.Length - prefixCount);
                        if (n == 0) break;
                        prefixCount += n;
                        CheckDeadline(clock);
                    }
                    string leading = Encoding.UTF8.GetString(prefix, 0, prefixCount).TrimStart('\uFEFF', ' ', '\t', '\r', '\n');
                    bool html = response.ContentType.StartsWith("text/html", StringComparison.OrdinalIgnoreCase) ||
                        leading.StartsWith("<", StringComparison.Ordinal);
                    if (html)
                    {
                        if (confirmed || response.ContentLength > HtmlLimit) throw new WebException("Drive returned a web page");
                        using (MemoryStream page = new MemoryStream())
                        {
                            CopyLimited(prefix, prefixCount, body, page, HtmlLimit, clock);
                            requestUri = Confirmation(requestUri, Encoding.UTF8.GetString(page.ToArray()), id);
                        }
                        confirmed = true;
                        continue;
                    }
                    if (response.ContentLength > limit) throw new InvalidDataException("Download size");
                    CopyLimited(prefix, prefixCount, body, destination, limit, clock);
                    return;
                }
            }
        }
        throw new WebException("Too many Drive redirects");
    }

    private static void CopyLimited(byte[] prefix, int count, Stream input, Stream output, long limit, Stopwatch clock)
    {
        if (count > limit) throw new InvalidDataException("Download size");
        output.Write(prefix, 0, count);
        long total = count;
        byte[] buffer = new byte[65536];
        while (true)
        {
            CheckDeadline(clock);
            int n = input.Read(buffer, 0, buffer.Length);
            if (n == 0) return;
            total += n;
            if (total > limit) throw new InvalidDataException("Download size");
            output.Write(buffer, 0, n);
        }
    }

    private static void CheckDeadline(Stopwatch clock)
    {
        if (clock.Elapsed > TimeSpan.FromMinutes(4)) throw new TimeoutException();
    }

    private static Uri Confirmation(Uri baseUri, string html, string id)
    {
        IDictionary<string, string> selected = null;
        foreach (Match match in Regex.Matches(html, @"<form\b(?<head>[^>]*)>(?<body>.*?)</form\s*>",
            RegexOptions.IgnoreCase | RegexOptions.Singleline, TimeSpan.FromSeconds(1)))
        {
            string head = match.Groups["head"].Value;
            if (!string.Equals(Attr(head, "id"), "download-form", StringComparison.OrdinalIgnoreCase)) continue;
            string action = Attr(head, "action");
            string method = Attr(head, "method");
            Uri target;
            if (action == null || (method != null && !method.Equals("get", StringComparison.OrdinalIgnoreCase)) ||
                !Uri.TryCreate(baseUri, action, out target) || !AllowedAddress(target) ||
                (target.AbsolutePath != "/download" && target.AbsolutePath != "/uc")) continue;
            selected = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (Match input in Regex.Matches(match.Groups["body"].Value, @"<input\b[^>]*>", RegexOptions.IgnoreCase))
            {
                string name = Attr(input.Value, "name"), value = Attr(input.Value, "value");
                if (name == null || value == null || value.Length > 2048) continue;
                if (name == "id" || name == "confirm" || name == "export" || name == "uuid" || name == "at")
                    selected[name] = value;
            }
            if (!selected.ContainsKey("id") || selected["id"] != id || !selected.ContainsKey("confirm")) break;
            List<string> fields = new List<string>();
            foreach (KeyValuePair<string, string> field in selected)
                fields.Add(Uri.EscapeDataString(field.Key) + "=" + Uri.EscapeDataString(field.Value));
            UriBuilder url = new UriBuilder(target);
            url.Query = string.Join("&", fields.ToArray());
            return url.Uri;
        }
        throw new WebException("Drive did not provide a public download");
    }

    private static string Attr(string tag, string name)
    {
        string pattern = @"(?:^|\s)" + name + @"\s*=\s*[""'](?<v>[^""']*)[""']";
        Match m = Regex.Match(tag, pattern, RegexOptions.IgnoreCase);
        return m.Success ? WebUtility.HtmlDecode(m.Groups["v"].Value) : null;
    }
}
