using System.IO.Compression;
using Leemon.Updater;
using System.Diagnostics;

// Disposable stand-in for the POS during subprocess integration checks.
var healthIndex = Array.IndexOf(args, "--leemon-update-token");
if (healthIndex >= 0)
{
    var control = Path.Combine(Path.GetTempPath(), "leemon_updater_" + args[healthIndex + 1]);
    if (!args.Contains("--leemon-update-recovered") &&
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "mode.dll")) == "crash") return 42;
    File.WriteAllText(Path.Combine(control, "app.pid"), Environment.ProcessId.ToString());
    if (args.Contains("--leemon-update-recovered"))
        File.WriteAllText(Path.Combine(control, "recovered"), "ok");
    else if (File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "mode.dll")) != "hang")
        File.WriteAllText(Path.Combine(control, "healthy"),
            File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "mode.dll")) == "wrong"
                ? "{\"version\":\"1.0.0\"}" : "{\"version\":\"2.0.0\"}");
    Thread.Sleep(TimeSpan.FromMinutes(2));
    return 0;
}

var root = Path.Combine(Path.GetTempPath(), "leemon_updater_tests_" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
var passed = 0;
try
{
    Check("apply, recover after interruption, preserve user data", () =>
    {
        var (target, zip) = Fixture();
        File.WriteAllText(Path.Combine(target, "sales.sqlite"), "financial data");
        var update = new UpdateTransaction(target);
        update.Prepare(zip, "Leemon.exe");
        update.Apply("2.0.0");
        Assert(File.ReadAllText(Path.Combine(target, "Leemon.exe")) == "new exe");
        Assert(File.Exists(Path.Combine(target, "added.dll")));
        new UpdateTransaction(target).Rollback();
        Assert(File.ReadAllText(Path.Combine(target, "Leemon.exe")) == "old exe");
        Assert(!File.Exists(Path.Combine(target, "added.dll")));
        Assert(File.ReadAllText(Path.Combine(target, "sales.sqlite")) == "financial data");
        Assert(!File.Exists(update.JournalPath));
    });
    Check("commit preserves the new files and removes the recovery marker", () =>
    {
        var (target, zip) = Fixture();
        var update = new UpdateTransaction(target);
        update.Prepare(zip, "Leemon.exe"); update.Apply("2.0.0"); update.Commit();
        new UpdateTransaction(target).Rollback();
        Assert(File.ReadAllText(Path.Combine(target, "Leemon.exe")) == "new exe");
        Assert(!File.Exists(update.JournalPath));
    });
    Check("locked live DLL fails installation and permits complete rollback", () =>
    {
        var (target, zip) = Fixture();
        var update = new UpdateTransaction(target);
        update.Prepare(zip, "Leemon.exe");
        using (var locked = new FileStream(Path.Combine(target, "flutter_windows.dll"), FileMode.Open, FileAccess.Read, FileShare.Read))
            ExpectFailure(() => update.Apply("2.0.0"));
        update.Rollback();
        Assert(File.ReadAllText(Path.Combine(target, "Leemon.exe")) == "old exe");
        Assert(File.ReadAllText(Path.Combine(target, "flutter_windows.dll")) == "old dll");
    });
    Check("backup failure never changes the live application", () =>
    {
        var (target, zip) = Fixture();
        var update = new UpdateTransaction(target);
        update.Prepare(zip, "Leemon.exe");
        using (var locked = new FileStream(Path.Combine(target, "flutter_windows.dll"), FileMode.Open, FileAccess.Read, FileShare.None))
            ExpectFailure(() => update.Apply("2.0.0"));
        Assert(!File.Exists(update.JournalPath));
        Assert(File.ReadAllText(Path.Combine(target, "Leemon.exe")) == "old exe");
    });
    Check("incomplete archive cannot touch the installed application", () =>
    {
        var (target, zip) = Fixture(incomplete: true);
        ExpectFailure(() => new UpdateTransaction(target).Prepare(zip, "Leemon.exe"));
        Assert(File.ReadAllText(Path.Combine(target, "Leemon.exe")) == "old exe");
    });
    Check("financial files in a release archive are rejected", () =>
    {
        var (target, zip) = Fixture(extra: "sales.sqlite");
        ExpectFailure(() => new UpdateTransaction(target).Prepare(zip, "Leemon.exe"));
        Assert(File.ReadAllText(Path.Combine(target, "Leemon.exe")) == "old exe");
    });
    Check("zip traversal is rejected", () =>
    {
        var (target, zip) = Fixture(extra: "../outside.dll");
        ExpectFailure(() => new UpdateTransaction(target).Prepare(zip, "Leemon.exe"));
        Assert(!File.Exists(Path.Combine(target, ".leemon-update", "outside.dll")));
    });
    if (args.Length >= 2)
    {
        foreach (var mode in args.Length > 2 ? args[2].Split(',') : new[] { "healthy", "crash", "hang", "wrong" })
            Check("subprocess handoff and " + (mode == "healthy" ? "startup commit" : mode == "crash" ? "early-crash rollback" : mode == "hang" ? "startup-hang rollback" : "version-mismatch rollback"), () =>
            {
                var (target, zip) = Fixture();
                File.Copy(args[1], Path.Combine(target, "Leemon.exe"), true);
                File.WriteAllText(Path.Combine(target, "mode.dll"), "old");
                using (var archive = ZipFile.Open(zip, ZipArchiveMode.Update))
                {
                    archive.GetEntry("Leemon.exe")!.Delete();
                    archive.CreateEntryFromFile(args[1], "Leemon.exe", CompressionLevel.Fastest);
                    using var writer = new StreamWriter(archive.CreateEntry("mode.dll").Open()); writer.Write(mode);
                }
                var token = Guid.NewGuid().ToString("N");
                var control = Path.Combine(Path.GetTempPath(), "leemon_updater_" + token);
                var oldToken = Guid.NewGuid().ToString("N");
                var oldControl = Path.Combine(Path.GetTempPath(), "leemon_updater_" + oldToken);
                Directory.CreateDirectory(control); Directory.CreateDirectory(oldControl);
                Process? original = null;
                Process? helper = null;
                try
                {
                    var app = new ProcessStartInfo(Path.Combine(target, "Leemon.exe")) { UseShellExecute = false, CreateNoWindow = true };
                    foreach (var arg in new[] { "--leemon-update-token", oldToken, "--leemon-update-recovered" }) app.ArgumentList.Add(arg);
                    original = Process.Start(app)!;
                    WaitUntil(() => File.Exists(Path.Combine(oldControl, "app.pid")), TimeSpan.FromSeconds(20));
                    var start = new ProcessStartInfo(Path.GetFullPath(args[0])) { UseShellExecute = false, CreateNoWindow = true };
                    foreach (var arg in new[] { "--zip", zip, "--target-dir", target, "--app-exe", "Leemon.exe", "--version", "2.0.0", "--token", token }) start.ArgumentList.Add(arg);
                    helper = Process.Start(start)!;
                    WaitUntil(() => File.Exists(Path.Combine(control, "ready")), TimeSpan.FromSeconds(20));
                    Assert(File.ReadAllText(Path.Combine(target, "mode.dll")) == "old");
                    Assert(!original.HasExited);
                    original.Kill(true); original.WaitForExit();
                    Assert(helper.WaitForExit(mode == "hang" ? 110000 : 30000));
                    Assert(helper.ExitCode == (mode == "healthy" ? 0 : 4));
                    Assert(!File.Exists(Path.Combine(target, ".leemon-update", "pending.json")));
                    Assert(File.ReadAllText(Path.Combine(target, "mode.dll")) == (mode == "healthy" ? "healthy" : "old"));
                    if (mode != "healthy") WaitUntil(() => File.Exists(Path.Combine(control, "recovered")), TimeSpan.FromSeconds(20));
                }
                finally
                {
                    if (original is { HasExited: false }) { original.Kill(true); original.WaitForExit(); }
                    if (helper is { HasExited: false }) { helper.Kill(true); helper.WaitForExit(); }
                    var pidFile = Path.Combine(control, "app.pid");
                    if (File.Exists(pidFile))
                    {
                        try
                        {
                            using var app = Process.GetProcessById(int.Parse(File.ReadAllText(pidFile)));
                            if (string.Equals(app.MainModule?.FileName, Path.Combine(target, "Leemon.exe"), StringComparison.OrdinalIgnoreCase))
                            { app.Kill(true); app.WaitForExit(); }
                        }
                        catch (ArgumentException) { }
                    }
                    original?.Dispose(); helper?.Dispose();
                    Directory.Delete(control, true); Directory.Delete(oldControl, true);
                }
            });
    }
    Console.WriteLine($"{passed} updater recovery tests passed.");
    return 0;
}
finally
{
    var full = Path.GetFullPath(root);
    if (full.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase) &&
        Path.GetFileName(full).StartsWith("leemon_updater_tests_")) Directory.Delete(full, true);
}

void Check(string name, Action test) { test(); passed++; Console.WriteLine("PASS " + name); }
void Assert(bool condition) { if (!condition) throw new Exception("Assertion failed"); }
void WaitUntil(Func<bool> condition, TimeSpan timeout)
{
    var clock = Stopwatch.StartNew();
    while (!condition()) { if (clock.Elapsed > timeout) throw new TimeoutException(); Thread.Sleep(100); }
}
void ExpectFailure(Action action)
{
    try { action(); } catch (IOException) { return; } catch (InvalidDataException) { return; }
    catch (UnauthorizedAccessException) { return; }
    throw new Exception("Expected installation to fail safely");
}
(string Target, string Zip) Fixture(bool incomplete = false, string? extra = null)
{
    var test = Path.Combine(root, Guid.NewGuid().ToString("N"));
    var target = Path.Combine(test, "installed");
    Directory.CreateDirectory(target);
    File.WriteAllText(Path.Combine(target, "Leemon.exe"), "old exe");
    File.WriteAllText(Path.Combine(target, "flutter_windows.dll"), "old dll");
    var zip = Path.Combine(test, "release.zip");
    using var archive = ZipFile.Open(zip, ZipArchiveMode.Create);
    foreach (var (name, content) in new[] {
        ("Leemon.exe", "new exe"), ("flutter_windows.dll", "new dll"),
        ("data/app.so", "new app"), ("data/icudtl.dat", "new icu"),
        ("data/flutter_assets/AssetManifest.bin", "assets"), ("added.dll", "new plugin"), ("native_assets.json", "{}"), ("Leemon.Updater.exe", "new helper") })
    {
        if (incomplete && name == "data/app.so") continue;
        using var writer = new StreamWriter(archive.CreateEntry(name).Open()); writer.Write(content);
    }
    if (extra != null) { using var writer = new StreamWriter(archive.CreateEntry(extra).Open()); writer.Write("unexpected"); }
    return (target, zip);
}
