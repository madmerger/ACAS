using System.Globalization;
using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace Acas.Core.Engine;

/// <summary>
/// ローカル DB (SQLite)。レガシー ISAM/相対ファイルを (file, key) → レコードバイト列として保持する。
/// レコードのバイト配置はレガシー copybook と同一で、論理レコード差分をそのまま比較できる。
/// </summary>
public sealed class Db : IDisposable
{
    private readonly SqliteConnection _c;

    public Db(string path = ":memory:")
    {
        _c = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path }.ToString());
        _c.Open();
        Exec("CREATE TABLE IF NOT EXISTS files(name TEXT PRIMARY KEY)");
        Exec("CREATE TABLE IF NOT EXISTS rec(file TEXT NOT NULL, key TEXT NOT NULL, data BLOB NOT NULL, PRIMARY KEY(file,key)) WITHOUT ROWID");
        Exec("CREATE TABLE IF NOT EXISTS spool(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created TEXT NOT NULL, body TEXT NOT NULL)");
    }

    private void Exec(string sql, params (string, object)[] ps)
    {
        using var cmd = _c.CreateCommand();
        cmd.CommandText = sql;
        foreach (var (n, v) in ps) cmd.Parameters.AddWithValue(n, v);
        cmd.ExecuteNonQuery();
    }

    public bool Exists(string file)
    {
        using var cmd = _c.CreateCommand();
        cmd.CommandText = "SELECT 1 FROM files WHERE name=$f";
        cmd.Parameters.AddWithValue("$f", file);
        return cmd.ExecuteScalar() != null;
    }
    public void Create(string file) => Exec("INSERT OR IGNORE INTO files(name) VALUES($f)", ("$f", file));
    /// <summary>OPEN OUTPUT 相当: ファイルを空で作り直す。</summary>
    public void Recreate(string file) { Exec("DELETE FROM rec WHERE file=$f", ("$f", file)); Create(file); }
    public void Remove(string file) { Exec("DELETE FROM rec WHERE file=$f", ("$f", file)); Exec("DELETE FROM files WHERE name=$f", ("$f", file)); }

    public byte[]? Read(string file, string key)
    {
        using var cmd = _c.CreateCommand();
        cmd.CommandText = "SELECT data FROM rec WHERE file=$f AND key=$k";
        cmd.Parameters.AddWithValue("$f", file); cmd.Parameters.AddWithValue("$k", key);
        return cmd.ExecuteScalar() as byte[];
    }
    /// <summary>WRITE: 重複キーなら false (status 22)。</summary>
    public bool Write(string file, string key, byte[] data)
    {
        if (Read(file, key) != null) return false;
        Create(file);
        Exec("INSERT INTO rec(file,key,data) VALUES($f,$k,$d)", ("$f", file), ("$k", key), ("$d", data));
        return true;
    }
    /// <summary>REWRITE: 無ければ false (status 23)。</summary>
    public bool Rewrite(string file, string key, byte[] data)
    {
        if (Read(file, key) == null) return false;
        Exec("UPDATE rec SET data=$d WHERE file=$f AND key=$k", ("$f", file), ("$k", key), ("$d", data));
        return true;
    }
    public void Put(string file, string key, byte[] data)
    {
        Create(file);
        Exec("INSERT INTO rec(file,key,data) VALUES($f,$k,$d) ON CONFLICT(file,key) DO UPDATE SET data=$d", ("$f", file), ("$k", key), ("$d", data));
    }
    public bool Delete(string file, string key)
    {
        if (Read(file, key) == null) return false;
        Exec("DELETE FROM rec WHERE file=$f AND key=$k", ("$f", file), ("$k", key));
        return true;
    }
    /// <summary>キー順の走査 (START key >= from; READ NEXT)。</summary>
    public List<(string Key, byte[] Data)> Scan(string file, string? from = null)
    {
        var r = new List<(string, byte[])>();
        using var cmd = _c.CreateCommand();
        cmd.CommandText = "SELECT key,data FROM rec WHERE file=$f AND key>=$k ORDER BY key";
        cmd.Parameters.AddWithValue("$f", file); cmd.Parameters.AddWithValue("$k", from ?? "");
        using var rd = cmd.ExecuteReader();
        while (rd.Read()) r.Add((rd.GetString(0), (byte[])rd[1]));
        r.Sort((a, b) => string.CompareOrdinal(a.Item1, b.Item1));
        return r;
    }
    public int Count(string file) => Scan(file).Count;

    public void AddSpool(string name, string body) =>
        Exec("INSERT INTO spool(name,created,body) VALUES($n,$c,$b)", ("$n", name), ("$c", DateTime.UtcNow.ToString("o")), ("$b", body));

    internal void Atomic(Action write)
    {
        using var tx = _c.BeginTransaction();
        write();
        tx.Commit();
    }
    public List<(long Id, string Name, DateTimeOffset Created, string Body)> Spool()
    {
        var r = new List<(long, string, DateTimeOffset, string)>();
        using var cmd = _c.CreateCommand();
        cmd.CommandText = "SELECT id,name,created,body FROM spool ORDER BY id";
        using var rd = cmd.ExecuteReader();
        while (rd.Read())
        {
            var created = DateTimeOffset.TryParse(rd.GetString(2), CultureInfo.InvariantCulture, DateTimeStyles.None, out var timestamp)
                ? timestamp : DateTimeOffset.MinValue;
            r.Add((rd.GetInt64(0), rd.GetString(1), created, rd.GetString(3)));
        }
        return r;
    }

    /// <summary>全データを消去し、同梱ベースライン(レガシーの初期データ)を読み込む。</summary>
    public void LoadBaseline(string name)
    {
        using var s = typeof(Db).Assembly.GetManifestResourceStream("Acas.Core.Baselines." + name + ".json");
        if (s == null) throw new ArgumentException("初期データ「" + name + "」は同梱されていません。", nameof(name));
        using var doc = JsonDocument.Parse(s);
        using var tx = _c.BeginTransaction();
        Exec("DELETE FROM rec"); Exec("DELETE FROM files"); Exec("DELETE FROM spool");
        foreach (var f in doc.RootElement.GetProperty("files").EnumerateArray()) Create(f.GetString()!);
        foreach (var f in doc.RootElement.GetProperty("records").EnumerateObject())
            foreach (var r in f.Value.EnumerateObject())
                Put(f.Name, r.Name, Convert.FromHexString(r.Value.GetString()!));
        tx.Commit();
    }

    /// <summary>論理レコードのスナップショット (file → key → hex)。</summary>
    public SortedDictionary<string, SortedDictionary<string, string>> Snapshot()
    {
        var r = new SortedDictionary<string, SortedDictionary<string, string>>(StringComparer.Ordinal);
        using var cmd = _c.CreateCommand();
        cmd.CommandText = "SELECT file,key,data FROM rec";
        using var rd = cmd.ExecuteReader();
        while (rd.Read())
        {
            if (!r.TryGetValue(rd.GetString(0), out var m)) r[rd.GetString(0)] = m = new(StringComparer.Ordinal);
            m[rd.GetString(1)] = Convert.ToHexString((byte[])rd[2]).ToLowerInvariant();
        }
        return r;
    }

    public void Dispose() => _c.Dispose();
}
