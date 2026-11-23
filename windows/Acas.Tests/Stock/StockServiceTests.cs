using Acas.Core;
using Acas.Core.Engine;
using Acas.Core.Programs.Stock;

namespace Acas.Tests.Stock;

public class StockServiceTests
{
    private static readonly DateTime Today = new(2026, 11, 23, 4, 15, 0);

    private static (Db Db, StockScreenModel Model) Open()
    {
        var db = new Db();
        db.LoadBaseline("biz");
        return (db, new StockScreenModel(db, () => Today));
    }

    private static Screen Submit(Screen s, params (string Id, object? Value)[] values)
    {
        var form = Assert.IsType<FormScreen>(s);
        var map = form.Fields.ToDictionary(f => f.Id, f => f switch { TextField t => t.Value, DateField d => d.Value, ChoiceField c => c.Value, _ => (object?)null });
        foreach (var (id, v) in values) map[id] = v;
        return form.Submit(new FormValues(map));
    }

    private static Screen Open(Screen s, string id) => Assert.IsType<MenuScreen>(s).Items.Single(i => i.Id == id).Open!();

    [Fact]
    public void 在庫レコードは400バイトで監査レコードは104バイト()
    {
        Assert.Equal(400, Layouts.Stock.Size);
        Assert.Equal(104, Layouts.StockAudit.Size);
    }

    [Fact]
    public void 入庫はレガシーと同じバイトを更新し入庫明細表を出力する()
    {
        var (db, m) = Open();
        var before = db.Read(StockService.StockFile, "ITEM001      ")!;
        var menu = Submit(m.Start());
        var entry = Open(Open(menu, "StockMovements"), "StockAdditions");
        var qty = Submit(entry, ("StockMovementNumber", "ITM001"));
        var next = Submit(qty, ("StockMovementQuantity", "000002 "), ("StockMovementPrice", "000005.00"));
        Assert.Equal("在庫入庫入力", next.Title);
        Assert.Equal(StockScreenModel.MovementsTitle, Submit(next).Title);

        var after = db.Read(StockService.StockFile, "ITEM001      ")!;
        var changed = Enumerable.Range(0, 400).Where(i => before[i] != after[i]).ToArray();
        Assert.Equal([106, 147, 166, 180, 356], changed);
        var r = Layouts.Stock.From(after);
        Assert.Equal(12, r.N("Stock-Held"));
        Assert.Equal(60m, r.N("Stock-Value"));
        Assert.Equal(5m, r.N("Stock-Last-Actual-Cost"));
        Assert.Contains(m.LastReport!.Legacy, l => l.StartsWith("23/11/2026 ITEM001       ALPHA WIDGET                          2       5.00        10.00"));
        Assert.Single(db.Spool());
    }

    [Fact]
    public void 出庫は在庫数と評価額を減らす()
    {
        var (db, m) = Open();
        var entry = Open(Open(Submit(m.Start()), "StockMovements"), "StockDeductions");
        var next = Submit(Submit(entry, ("StockMovementNumber", "ITM001")), ("StockMovementQuantity", "000001 "));
        Submit(next);
        var r = Layouts.Stock.From(db.Read(StockService.StockFile, "ITEM001      ")!);
        Assert.Equal(9, r.N("Stock-Held"));
        Assert.Equal(45m, r.N("Stock-Value"));
        Assert.Equal(1, r.N("Stock-TD-Deds-11"));
        Assert.EndsWith("5.00-", m.LastReport!.Legacy.Last());
    }

    [Fact]
    public void 不存在品目と在庫不足はエラーで更新しない()
    {
        var (db, m) = Open();
        var snap = db.Snapshot();
        var movements = Open(Submit(m.Start()), "StockMovements");
        var err = Assert.IsType<ConfirmationScreen>(Submit(Open(movements, "StockAdditions"), ("StockMovementNumber", "MISSING")));
        Assert.Equal(StockMessages.ST203, err.Message);
        var qty = Submit(Open(movements, "StockDeductions"), ("StockMovementNumber", "ITM001"));
        var shortage = Assert.IsType<ConfirmationScreen>(Submit(qty, ("StockMovementQuantity", "11")));
        Assert.Equal(StockMessages.ST206, shortage.Message);
        Assert.Equal(StockMessages.ST207, Assert.IsType<ConfirmationScreen>(Submit(Submit(Open(movements, "StockDeductions"), ("StockMovementNumber", "ITM001")), ("StockMovementQuantity", "1+"))).Message);
        Assert.Equal(snap, db.Snapshot());
    }

    [Fact]
    public void 品目の登録削除と期間締め()
    {
        var (db, m) = Open();
        var maint = Open(Submit(m.Start()), "StockMaintenance");
        var done = Submit(Open(maint, "StockItemCreate"), ("StockKey", "item003"), ("StockAbrev", "itm003"), ("StockDesc", "GAMMA"), ("StockCost", "2.5"));
        Assert.IsType<ConfirmationScreen>(done);
        var created = Layouts.Stock.From(db.Read(StockService.StockFile, "ITEM003      ")!);
        Assert.Equal("ITM003", created.St("Stock-Abrev-Key"));
        Assert.Equal(StockMessages.ST116, Assert.IsType<ConfirmationScreen>(Submit(Open(maint, "StockItemCreate"), ("StockKey", "ITEM001"), ("StockAbrev", "X1"))).Message);
        var confirm = Assert.IsType<ConfirmationScreen>(Submit(Open(maint, "StockItemDelete"), ("StockDeleteKey", "ITM003")));
        confirm.Confirm();
        Assert.Null(db.Read(StockService.StockFile, "ITEM003      "));
        Assert.Equal(StockMessages.ST107, Assert.IsType<ConfirmationScreen>(
            Assert.IsType<ConfirmationScreen>(Submit(Open(maint, "StockItemDelete"), ("StockDeleteKey", "ITM001"))).Confirm()).Message);

        var reset = Submit(Open(Submit(m.Start()), "StockEndOfCycle"), ("StockResetPeriod", "Y"));
        Assert.Equal(StockMessages.NotReported, Assert.IsType<InformationScreen>(reset).Message);
    }

    [Fact]
    public void 変更は分析ファイルが使えなければ中止する()
    {
        var (_, m) = Open();
        var info = Assert.IsType<InformationScreen>(Open(Open(Submit(m.Start()), "StockMaintenance"), "StockItemAmend"));
        Assert.Equal(StockMessages.ST112, info.Message);
    }

    [Fact]
    public void 全メニューと初期画面に英字の画面文言がない()
    {
        var (db, m) = Open();
        var r = new StockVerify.Result();
        var seen = new HashSet<string>();
        var queue = new Queue<Screen>([m.Start(), m.MainMenu()]);
        while (queue.Count > 0)
        {
            var s = queue.Dequeue();
            StockVerify.Audit(r, s, db);
            if (s is not MenuScreen menu) continue;
            foreach (var item in menu.Items.Where(i => i.Open != null && i.Id is not ("StockExit" or "StockSystemSetUp") && seen.Add(i.Id)))
                queue.Enqueue(item.Open!());
        }
        Assert.True(seen.Count >= 25, seen.Count.ToString());
        Assert.Empty(r.Untranslated);
    }

    [Theory]
    [InlineData("23/11/2026", 155840)]
    [InlineData("31/02/2026", 0)]
    public void 日付は通算日へ変換する(string uk, int expected)
    {
        int bin = StockDates.UkToBin(uk);
        if (expected == 0) Assert.Equal(0, bin);
        else Assert.Equal(uk, StockDates.ToUk(StockDates.FromBin(bin)));
    }
}
