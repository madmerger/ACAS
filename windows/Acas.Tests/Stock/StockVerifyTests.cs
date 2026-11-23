using System.Text.Encodings.Web;
using System.Text.Json;

namespace Acas.Tests.Stock;

public class StockVerifyTests
{
    /// <summary>証跡（既定 %USERPROFILE%\acas_evidence、環境変数 ACAS_EVIDENCE で変更）がある場合に ST- 全件を判定し JSON を出力する。</summary>
    [Fact]
    public void 在庫の同一性確認ケースがレガシー証跡と一致する()
    {
        string? explicitRoot = Environment.GetEnvironmentVariable("ACAS_EVIDENCE");
        string root = explicitRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "acas_evidence");
        string ledger = Path.Combine(root, "入力", "シナリオ台帳.json");
        if (!File.Exists(ledger))
        {
            Assert.True(explicitRoot == null, "ACAS_EVIDENCE が指す証跡に台帳がありません: " + ledger);
            return;
        }
        var results = StockVerify.Run(ledger, root);
        string output = Environment.GetEnvironmentVariable("ACAS_VERIFY_OUT")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "acas-verify-st.json");
        File.WriteAllText(output, JsonSerializer.Serialize(new
        {
            一致 = results.Count(x => x.Verdict == "一致"),
            不一致 = results.Count(x => x.Verdict == "不一致"),
            対象外 = results.Count(x => x.Verdict == "対象外"),
            cases = results,
        }, new JsonSerializerOptions { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
        Assert.NotEmpty(results);
        Assert.All(results.Where(x => x.Verdict == "不一致"), x => Assert.Fail(x.Id + ": " + string.Join(" / ", x.Diffs.Concat(x.Untranslated))));
    }
}
