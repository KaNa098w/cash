using System.IO.Compression;
using System.Text.Json;

namespace Leemon.Updater;

public sealed record UpdateFile(string RelativePath, bool Existed);
public sealed record UpdateJournal(string Version, List<UpdateFile> Files);

public sealed class UpdateTransaction
{
    public string Target { get; }
    public string Work { get; }
    public string Stage => Path.Combine(Work, "stage");
    public string Backup => Path.Combine(Work, "backup");
    public string JournalPath => Path.Combine(Work, "pending.json");
    public string Source { get; private set; } = "";
    public UpdateTransaction(string target)
    {
        Target = Path.GetFullPath(target);
        Work = SafePath(Target, ".leemon-update");
    }

    public void Prepare(string zip, string appExe)
    {
        if (File.Exists(JournalPath)) throw new IOException("An interrupted update needs recovery first.");
        Directory.CreateDirectory(Work);
        if (Directory.Exists(Stage)) Directory.Delete(Stage, true);
        Directory.CreateDirectory(Stage);
        ZipFile.ExtractToDirectory(zip, Stage);
        Source = File.Exists(Path.Combine(Stage, appExe)) ? Stage :
            Directory.GetDirectories(Stage).SingleOrDefault(d => File.Exists(Path.Combine(d, appExe)))
            ?? throw new InvalidDataException("The update does not contain the application.");
        foreach (var required in new[] { appExe, "flutter_windows.dll", "data/app.so", "data/icudtl.dat" })
        {
            var file = Path.Combine(Source, required);
            if (!File.Exists(file) || new FileInfo(file).Length == 0)
                throw new InvalidDataException($"Incomplete update: {required}");
        }
        if (!Directory.Exists(Path.Combine(Source, "data", "flutter_assets")))
            throw new InvalidDataException("The update has no Flutter assets.");
        foreach (var file in Directory.GetFiles(Source, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(Source, file);
            if (!IsApplicationFile(relative, appExe))
                throw new InvalidDataException($"Unexpected file in update: {relative}");
            SafePath(Target, relative);
        }
    }

    public void Apply(string version)
    {
        if (Source.Length == 0) throw new InvalidOperationException("Prepare the update first.");
        if (Directory.Exists(Backup)) Directory.Delete(Backup, true);
        Directory.CreateDirectory(Backup);
        var files = Directory.GetFiles(Source, "*", SearchOption.AllDirectories)
            .Select(f => new UpdateFile(Path.GetRelativePath(Source, f),
                File.Exists(SafePath(Target, Path.GetRelativePath(Source, f)))))
            .ToList();
        // Back up everything before changing even the first live file.
        foreach (var item in files.Where(f => f.Existed))
            CopyDurable(SafePath(Target, item.RelativePath), SafePath(Backup, item.RelativePath));
        WriteJson(JournalPath, new UpdateJournal(version, files));
        foreach (var item in files)
            CopyDurable(SafePath(Source, item.RelativePath), SafePath(Target, item.RelativePath));
    }

    public void Rollback()
    {
        if (!File.Exists(JournalPath)) return;
        var journal = JsonSerializer.Deserialize<UpdateJournal>(File.ReadAllText(JournalPath))
            ?? throw new InvalidDataException("Invalid recovery journal.");
        foreach (var item in journal.Files)
        {
            var destination = SafePath(Target, item.RelativePath);
            if (item.Existed)
                CopyDurable(SafePath(Backup, item.RelativePath), destination);
            else if (File.Exists(destination)) File.Delete(destination);
        }
        File.Delete(JournalPath); // Keep backups if any restore failed.
    }

    public void Commit()
    {
        File.Delete(JournalPath);
        // Keep the last backup for diagnostics; the next update replaces it.
        try { if (Directory.Exists(Stage)) Directory.Delete(Stage, true); } catch { }
    }

    public static void WriteJson(string path, object value)
    {
        var temporary = path + ".tmp";
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            JsonSerializer.Serialize(stream, value);
            stream.Flush(true);
        }
        File.Move(temporary, path, true);
    }

    static bool IsApplicationFile(string relative, string appExe)
    {
        var parts = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (parts[0].Equals("data", StringComparison.OrdinalIgnoreCase)) return true;
        if (parts[0].Equals("updater", StringComparison.OrdinalIgnoreCase))
            return Path.GetExtension(relative).ToLowerInvariant() is ".exe" or ".dll" or ".json" or ".pdb";
        return parts.Length == 1 && (relative.Equals(appExe, StringComparison.OrdinalIgnoreCase) ||
            relative.Equals("Leemon.Updater.exe", StringComparison.OrdinalIgnoreCase) ||
            relative.Equals("native_assets.json", StringComparison.OrdinalIgnoreCase) ||
            Path.GetExtension(relative).ToLowerInvariant() is ".dll" or ".pdb");
    }

    static string SafePath(string root, string relative)
    {
        var prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var full = Path.GetFullPath(Path.Combine(prefix, relative));
        if (!full.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Update path is outside the application.");
        if (Directory.Exists(full) && (File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException("An update path is a directory link.");
        for (var current = Path.GetDirectoryName(full); current != null &&
            current.Length >= prefix.TrimEnd(Path.DirectorySeparatorChar).Length;
            current = Path.GetDirectoryName(current))
        {
            if (Directory.Exists(current) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("An update path contains a directory link.");
        }
        return full;
    }

    static void CopyDurable(string source, string destination)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        var temporary = destination + ".leemon-new";
        try
        {
            using (var input = File.OpenRead(source))
            using (var output = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                input.CopyTo(output);
                output.Flush(true);
            }
            File.Move(temporary, destination, true);
        }
        finally
        {
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }
}
