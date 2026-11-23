using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Acas.Verify;

Console.OutputEncoding = Encoding.UTF8;
try
{
    var options = RunOptions.Parse(args, "--reference");
    var scenarios = options.Scenarios();
    var reference = options.Extra is { } harness && scenarios.Any(s => s.Group != 5 && !s.Excluded)
        ? await RunReference(harness, options) : [];
    var outcomes = scenarios.Select(scenario =>
    {
        if (scenario.Excluded) return Outcome.Exclude(scenario);
        if (scenario.Group == 5) return scenario.CompareCalculation(options.Evidence);
        if (reference.TryGetValue(scenario.Id, out var comparison) &&
            comparison.TryGetProperty("match", out var match) && match.ValueKind is JsonValueKind.True or JsonValueKind.False)
        {
            var reason = new List<string>();
            if (comparison.TryGetProperty("error", out var error) && error.GetString() is { } errorText) reason.Add(errorText);
            if (comparison.TryGetProperty("diffs", out var diffs)) reason.AddRange(diffs.EnumerateArray().Select(d => d.GetString()!));
            if (comparison.TryGetProperty("untranslated", out var untranslated))
                reason.AddRange(untranslated.EnumerateArray().Select(d => "未翻訳：" + d.GetString()));
            return Outcome.Compare(scenario, match.GetBoolean(), "旧移植版の端末再生結果", string.Join("\n", reason), "旧移植版・参考");
        }
        if (scenario.Group == 1 && GroupOnePlan.For(scenario) is { } plan)
            return GroupOneVerification.Run(scenario, options.Evidence, plan);
        return Outcome.Missing(scenario, "このケースの新アプリ用のヘッドレス手順は未登録です。");
    }).ToArray();
    Outcome.Write(options.Output, outcomes);
    foreach (var group in outcomes.GroupBy(r => r.Group).OrderBy(g => g.Key))
    {
        var counts = new[] { "一致", "不一致", "対象外", "未検証" }.Select(v => $"{v} {group.Count(r => r.Verdict == v)}");
        Console.WriteLine($"グループ{group.Key}：{string.Join(" / ", counts)}");
    }
    if (reference.Count > 0) Console.WriteLine("グループ①〜④の比較は旧移植版の参考値であり、新アプリの結果ではありません。");
    return outcomes.All(r => r.Verdict is "一致" or "対象外" && r.Source != "旧移植版・参考") ? 0 : 1;
}
catch (Exception e) when (e is ArgumentException or IOException or InvalidDataException or JsonException or InvalidOperationException)
{
    Console.Error.WriteLine(e.Message);
    Console.Error.WriteLine("使い方：Acas.Verify <台帳> <証跡ルート> --out <結果> [--group <①〜⑤>] [--case <ケース識別子>] [--reference <旧 Acas.Verify.dll>]");
    return 2;
}

static async Task<Dictionary<string, JsonElement>> RunReference(string harness, RunOptions options)
{
    string temp = Path.GetTempFileName();
    try
    {
        var start = new ProcessStartInfo(Environment.ProcessPath is { } host &&
            Path.GetFileNameWithoutExtension(host).Equals("dotnet", StringComparison.OrdinalIgnoreCase) ? host : "dotnet")
        {
            UseShellExecute = false, RedirectStandardOutput = true, StandardOutputEncoding = Encoding.UTF8
        };
        foreach (string arg in new[] { Path.GetFullPath(harness), options.Ledger, options.Evidence, "--out", temp })
            start.ArgumentList.Add(arg);
        var prefixes = options.Group switch
        {
            1 => new[] { "SYS-", "GL-" }, 2 => ["SL-"], 3 => ["PL-"], 4 => ["ST-", "IRS-", "INT-"], _ => []
        };
        foreach (string prefix in prefixes) start.ArgumentList.Add(prefix);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("参考用ハーネスを起動できません。");
        await process.StandardOutput.BaseStream.CopyToAsync(Stream.Null);
        await process.WaitForExitAsync();
        if (process.ExitCode != 0) throw new InvalidOperationException($"参考用ハーネスが終了コード {process.ExitCode} を返しました。");
        using var document = JsonDocument.Parse(await File.ReadAllTextAsync(temp));
        return document.RootElement.EnumerateArray().Where(r => r.TryGetProperty("screens", out _))
            .ToDictionary(r => r.GetProperty("id").GetString()!, r => r.Clone(), StringComparer.Ordinal);
    }
    finally
    {
        File.Delete(temp);
    }
}
