using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using Leemon.Updater;

var options = ParseArgs(args);
if (!options.TryGetValue("target-dir", out var target) ||
    !options.TryGetValue("app-exe", out var appExe) || Path.GetFileName(appExe) != appExe) return 1;
var token = options.GetValueOrDefault("token", Guid.NewGuid().ToString("N"));
if (!Regex.IsMatch(token, "^[a-fA-F0-9]{32}$")) return 1;
var control = Path.Combine(Path.GetTempPath(), "leemon_updater_" + token);
Directory.CreateDirectory(control);
var transaction = new UpdateTransaction(target);
var appPath = Path.Combine(transaction.Target, appExe);
var logPath = Path.Combine(transaction.Work, "update.log");
var version = options.GetValueOrDefault("version", "");
Process? trial = null;
var changed = false;
FileStream? updateLock = null;
try
{
    // Never overwrite the helper that is currently executing, including recovery.
    var ownPath = Environment.ProcessPath!;
    if (ownPath.StartsWith(transaction.Target.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar,
        StringComparison.OrdinalIgnoreCase))
    {
        var shadow = Path.Combine(control, "Leemon.Updater.exe");
        File.Copy(ownPath, shadow, true);
        var start = new ProcessStartInfo(shadow) { UseShellExecute = false, CreateNoWindow = true };
        foreach (var argument in args) start.ArgumentList.Add(argument);
        if (!options.ContainsKey("token")) { start.ArgumentList.Add("--token"); start.ArgumentList.Add(token); }
        Process.Start(start);
        return 0;
    }
    Directory.CreateDirectory(transaction.Work);
    updateLock = new FileStream(Path.Combine(transaction.Work, "active.lock"),
        FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    Log("Updater started.");
    if (File.Exists(transaction.JournalPath))
    {
        if (!WaitForShutdown(appPath, TimeSpan.FromSeconds(60)))
            throw new IOException("Close the cash register before restoring the interrupted update.");
        var interrupted = JsonSerializer.Deserialize<UpdateJournal>(File.ReadAllText(transaction.JournalPath));
        transaction.Rollback();
        RecordFailure(interrupted?.Version ?? "", "Interrupted update restored.");
        Log("Interrupted update restored.");
    }
    if (options.ContainsKey("recover-only"))
    {
        StartApp(false);
        return 0;
    }
    if (!options.TryGetValue("zip", out var zip) || !File.Exists(zip))
        throw new FileNotFoundException("Update archive not found.");
    transaction.Prepare(zip, appExe);
    File.WriteAllText(Path.Combine(control, "ready"), "ready");
    Log("Archive validated; waiting for cash register shutdown.");
    if (!WaitForShutdown(appPath, TimeSpan.FromSeconds(60)))
        throw new TimeoutException("Cash register did not shut down; application files were not changed.");
    changed = true;
    transaction.Apply(version);
    Log("Files installed; waiting for first usable application frame.");
    trial = StartApp(true);
    var timer = Stopwatch.StartNew();
    while (timer.Elapsed < TimeSpan.FromSeconds(90))
    {
        if (trial.HasExited) throw new IOException($"Updated application exited with code {trial.ExitCode} before startup confirmation.");
        if (File.Exists(Path.Combine(control, "healthy")) && timer.Elapsed > TimeSpan.FromSeconds(5))
        {
            using var health = JsonDocument.Parse(File.ReadAllText(Path.Combine(control, "healthy")));
            var launchedVersion = health.RootElement.GetProperty("version").GetString() ?? "";
            if (launchedVersion.Split('+')[0].TrimStart('v', 'V') != version.Split('+')[0].TrimStart('v', 'V'))
                throw new InvalidDataException("The launched application version does not match the requested update.");
            transaction.Commit();
            Log("Update committed after startup confirmation.");
            try { if (File.Exists(zip)) File.Delete(zip); } catch { }
            return 0;
        }
        Thread.Sleep(250);
    }
    throw new TimeoutException("Updated application did not confirm successful startup within 90 seconds.");
}
catch (Exception error)
{
    Log(error.ToString());
    try { File.WriteAllText(Path.Combine(control, "error"), error.Message); } catch { }
    if (changed)
    {
        try
        {
            if (trial is { HasExited: false }) { trial.Kill(true); trial.WaitForExit(10000); }
            if (!WaitForShutdown(appPath, TimeSpan.FromSeconds(30)))
                throw new IOException("Application is still running. Backup retained for recovery.");
            transaction.Rollback();
            RecordFailure(version, error.Message);
            Log("Previous application files restored.");
            StartApp(false);
        }
        catch (Exception restoreError) { Log("RESTORE REQUIRED: " + restoreError); }
    }
    return 4;
}
finally { trial?.Dispose(); updateLock?.Dispose(); }

Process StartApp(bool checkHealth)
{
    var start = new ProcessStartInfo(appPath) { WorkingDirectory = transaction.Target, UseShellExecute = false };
    // Recovery process is permitted through the native startup update guard.
    start.ArgumentList.Add("--leemon-update-token");
    start.ArgumentList.Add(token);
    if (!checkHealth) start.ArgumentList.Add("--leemon-update-recovered");
    return Process.Start(start) ?? throw new IOException("Unable to start the cash register.");
}
void RecordFailure(string failedVersion, string message) => UpdateTransaction.WriteJson(
    Path.Combine(transaction.Work, "last-failure.json"),
    new { version = failedVersion, message, at = DateTime.UtcNow });
void Log(string message)
{
    try
    {
        Directory.CreateDirectory(transaction.Work);
        if (File.Exists(logPath) && new FileInfo(logPath).Length > 1024 * 1024)
            File.Move(logPath, logPath + ".previous", true);
        File.AppendAllText(logPath, $"{DateTime.UtcNow:O} {message}{Environment.NewLine}");
    }
    catch { }
}
static Dictionary<string, string> ParseArgs(string[] arguments)
{
    var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    for (var i = 0; i < arguments.Length; i++)
        if (arguments[i].StartsWith("--", StringComparison.Ordinal))
        {
            var key = arguments[i][2..];
            result[key] = i + 1 < arguments.Length && !arguments[i + 1].StartsWith("--", StringComparison.Ordinal)
                ? arguments[++i] : "true";
        }
    return result;
}
static bool WaitForShutdown(string appPath, TimeSpan timeout)
{
    var timer = Stopwatch.StartNew();
    while (timer.Elapsed < timeout)
    {
        var running = false;
        foreach (var process in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(appPath)))
        {
            using (process)
            {
                try { if (string.Equals(process.MainModule?.FileName, appPath, StringComparison.OrdinalIgnoreCase)) running = true; }
                catch { running = true; }
            }
        }
        if (!running) return true;
        Thread.Sleep(250);
    }
    return false;
}
