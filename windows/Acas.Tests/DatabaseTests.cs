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
    public void 作成日時が不正でも帳票を読み込める()
    {
        var directory = Directory.CreateTempSubdirectory();
        try
        {
            var path = Path.Combine(directory.FullName, "acas.db");
            using var db = new Db(path);
            using var connection = new SqliteConnection(new SqliteConnectionStringBuilder { DataSource = path }.ToString());
            connection.Open();
            using var command = connection.CreateCommand();
            command.CommandText = """
                INSERT INTO spool(name, created, body) VALUES
                    ('期限帳票', 'invalid', '期限の集計'),
                    ('残高帳票', '2025-04-01T12:34:56+09:00', '残高の集計')
                """;
            command.ExecuteNonQuery();

            var entries = db.Spool();
            Assert.Equal("期限の集計", entries[0].Body);
            Assert.Equal(DateTimeOffset.MinValue, entries[0].Created);
            Assert.Equal(new DateTimeOffset(2025, 4, 1, 12, 34, 56, TimeSpan.FromHours(9)), entries[1].Created);
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
