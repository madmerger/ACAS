using Acas.Core.Engine;
using Microsoft.Data.Sqlite;

namespace Acas.Tests;

public class DatabaseTests
{
    [Fact]
    public void データと帳票を閉じた後も読み込める()
    {
        var directory = Directory.CreateTempSubdirectory();
        try
        {
            var path = Path.Combine(directory.FullName, "acas.db");
            using (var db = new Db(path))
            {
                db.Put("試験ファイル", "001", [0, 42, 255]);
                db.AddSpool("試験帳票", "合計　４２");
            }
            using (var reopened = new Db(path))
            {
                Assert.Equal(new byte[] { 0, 42, 255 }, reopened.Read("試験ファイル", "001"));
                Assert.Equal("合計　４２", Assert.Single(reopened.Spool()).Body);
            }
        }
        finally
        {
            SqliteConnection.ClearAllPools();
            directory.Delete(true);
        }
    }

    [Fact]
    public void 存在しない初期データを指定してもデータを消さない()
    {
        using var db = new Db();
        db.Put("試験ファイル", "001", [42]);
        db.AddSpool("試験帳票", "合計　４２");

        Assert.Throws<ArgumentException>(() => db.LoadBaseline("未同梱"));

        Assert.Equal(new byte[] { 42 }, db.Read("試験ファイル", "001"));
        Assert.Single(db.Spool());
    }

    [Fact]
    public void 同梱初期データで別のケースへ切り替えられる()
    {
        using var db = new Db();
        db.LoadBaseline("biz");
        Assert.NotEmpty(db.Snapshot());
        db.AddSpool("試験帳票", "合計　４２");

        db.LoadBaseline("empty");

        Assert.Empty(db.Snapshot());
        Assert.Empty(db.Spool());
    }
}
