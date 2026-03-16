using System.Diagnostics;
using System.IO.Compression;

const int waitTimeoutSeconds = 60;
const int pollDelayMilliseconds = 500;

var options = ParseArgs(args);

if (!options.TryGetValue("zip", out var zipPath) ||
    !options.TryGetValue("target-dir", out var targetDir) ||
    !options.TryGetValue("app-exe", out var appExeName))
{
    return 1;
}

var fullZipPath = Path.GetFullPath(zipPath);
var fullTargetDir = Path.GetFullPath(targetDir);
var fullAppExePath = Path.Combine(fullTargetDir, appExeName);

if (!File.Exists(fullZipPath))
{
    return 2;
}

Directory.CreateDirectory(fullTargetDir);

if (!WaitForAppShutdown(fullAppExePath, TimeSpan.FromSeconds(waitTimeoutSeconds)))
{
    return 3;
}

var extractDir = Path.Combine(
    Path.GetTempPath(),
    $"leemon_update_{Guid.NewGuid():N}"
);

try
{
    ZipFile.ExtractToDirectory(fullZipPath, extractDir);

    var sourceRoot = ResolveExtractRoot(extractDir, appExeName);
    CopyDirectory(sourceRoot, fullTargetDir);

    if (File.Exists(fullAppExePath))
    {
        Process.Start(new ProcessStartInfo
        {
            FileName = fullAppExePath,
            WorkingDirectory = fullTargetDir,
            UseShellExecute = true,
        });
    }

    return 0;
}
catch
{
    return 4;
}
finally
{
    TryDeleteDirectory(extractDir);
    TryDeleteFile(fullZipPath);
}

static Dictionary<string, string> ParseArgs(string[] args)
{
    var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    for (var i = 0; i < args.Length; i++)
    {
        var arg = args[i];
        if (!arg.StartsWith("--", StringComparison.Ordinal))
        {
            continue;
        }

        var key = arg[2..];
        if (i + 1 >= args.Length)
        {
            break;
        }

        result[key] = args[++i];
    }

    return result;
}

static bool WaitForAppShutdown(string appExePath, TimeSpan timeout)
{
    var deadline = DateTime.UtcNow + timeout;
    var processName = Path.GetFileNameWithoutExtension(appExePath);

    while (DateTime.UtcNow < deadline)
    {
        var matchingProcessFound = false;

        foreach (var process in Process.GetProcessesByName(processName))
        {
            try
            {
                var processPath = process.MainModule?.FileName;
                if (string.Equals(processPath, appExePath, StringComparison.OrdinalIgnoreCase))
                {
                    matchingProcessFound = true;
                    break;
                }
            }
            catch
            {
                matchingProcessFound = true;
                break;
            }
        }

        if (!matchingProcessFound && CanOpenForWrite(fullAppExePath: appExePath))
        {
            return true;
        }

        Thread.Sleep(pollDelayMilliseconds);
    }

    return false;
}

static bool CanOpenForWrite(string fullAppExePath)
{
    if (!File.Exists(fullAppExePath))
    {
        return true;
    }

    try
    {
        using var stream = new FileStream(
            fullAppExePath,
            FileMode.Open,
            FileAccess.ReadWrite,
            FileShare.None
        );
        return true;
    }
    catch
    {
        return false;
    }
}

static string ResolveExtractRoot(string extractDir, string appExeName)
{
    var rootExePath = Path.Combine(extractDir, appExeName);
    if (File.Exists(rootExePath))
    {
        return extractDir;
    }

    var directories = Directory.GetDirectories(extractDir);
    if (directories.Length == 1)
    {
        var nestedExePath = Path.Combine(directories[0], appExeName);
        if (File.Exists(nestedExePath))
        {
            return directories[0];
        }
    }

    throw new InvalidOperationException("Unable to locate extracted app payload.");
}

static void CopyDirectory(string sourceDir, string targetDir)
{
    foreach (var directory in Directory.GetDirectories(sourceDir, "*", SearchOption.AllDirectories))
    {
        var relativePath = Path.GetRelativePath(sourceDir, directory);
        if (relativePath.StartsWith("updater", StringComparison.OrdinalIgnoreCase))
        {
            continue;
        }

        Directory.CreateDirectory(Path.Combine(targetDir, relativePath));
    }

    foreach (var file in Directory.GetFiles(sourceDir, "*", SearchOption.AllDirectories))
    {
        var relativePath = Path.GetRelativePath(sourceDir, file);
        if (relativePath.StartsWith("updater", StringComparison.OrdinalIgnoreCase))
        {
            continue;
        }

        var destinationPath = Path.Combine(targetDir, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
        File.Copy(file, destinationPath, overwrite: true);
    }
}

static void TryDeleteDirectory(string path)
{
    try
    {
        if (Directory.Exists(path))
        {
            Directory.Delete(path, recursive: true);
        }
    }
    catch
    {
    }
}

static void TryDeleteFile(string path)
{
    try
    {
        if (File.Exists(path))
        {
            File.Delete(path);
        }
    }
    catch
    {
    }
}
