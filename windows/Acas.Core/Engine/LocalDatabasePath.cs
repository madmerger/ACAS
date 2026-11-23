namespace Acas.Core.Engine;

public static class LocalDatabasePath
{
    public static string Resolve(string path)
    {
        ArgumentNullException.ThrowIfNull(path);
        if (path.Length >= 2 && IsSeparator(path[0]) &&
            (IsSeparator(path[1]) || (path.Length >= 4 && path[1] == '?' && path[2] == '?' && IsSeparator(path[3]))))
            throw NotLocal();

        var fullPath = Path.GetFullPath(path);
        var root = Path.GetPathRoot(fullPath);
        if (root is not { Length: 3 } || !char.IsAsciiLetter(root[0]) || root[1] != ':' || root[2] != '\\' ||
            new DriveInfo(root).DriveType is not (DriveType.Fixed or DriveType.Removable or DriveType.Ram))
            throw NotLocal();

        string current = root;
        foreach (var part in fullPath[root.Length..].Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, part);
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
            catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException) { break; }
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw NotLocal();
        }
        return fullPath;
    }

    private static bool IsSeparator(char value) => value is '\\' or '/';

    private static ArgumentException NotLocal() => new("データベースにはローカルドライブ上のパスを指定してください。");
}
