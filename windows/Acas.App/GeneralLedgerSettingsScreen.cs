using Acas.Core;

namespace Acas.App;

internal sealed partial class AccountingScreens
{
    private Screen GeneralLedgerSettings(GeneralLedgerParameters? draft = null, string? error = null)
    {
        if ((draft ?? _settings.ReadGeneralLedgerParameters()) is not { } parameters)
            return new InformationScreen("総勘定元帳の設定", "総勘定元帳が有効な会社を登録してください。");

        return new FormScreen("総勘定元帳の設定",
        [
            new ChoiceField("LedgerDivisionMode", "部門・拠点区分",
                [new(" ", "使用しない"), new("P", "部門"), new("B", "拠点")],
                parameters.Division is "P" or "B" ? parameters.Division : " "),
            Toggle("LedgerRevenueOnly", "部門・拠点区分を収益勘定のみに適用", parameters.RevenueOnly),
            Toggle("LedgerGrouped", "部門・拠点番号の先頭をグループに使用", parameters.Grouped),
            Toggle("LedgerComparatives", "比較情報", parameters.Comparatives),
            Toggle("LedgerSecondaryIndex", "二次索引", parameters.SecondaryIndex),
            Toggle("LedgerMinimumValidation", "最小限の検証", parameters.MinimumValidation),
            Toggle("LedgerArchive", "締め処理時の仕訳保管", parameters.Archive),
            Toggle("LedgerAutomaticTax", "消費税の自動計算", parameters.AutomaticTax),
            Toggle("LedgerUseIncompleteRecords", "簡易記帳との連携", parameters.UseIncompleteRecords),
            new TextField("LedgerNextBatch", "次回バッチ番号", parameters.NextBatch.ToString(), 5)
        ], "確認へ", values =>
        {
            if (!Number(values.Text("LedgerNextBatch"), out int nextBatch))
                return GeneralLedgerSettings(parameters, "次回バッチ番号を確認してください。");
            var updated = new GeneralLedgerParameters(values.Choice("LedgerDivisionMode") ?? " ",
                Enabled(values, "LedgerRevenueOnly"), Enabled(values, "LedgerGrouped"), Enabled(values, "LedgerComparatives"),
                Enabled(values, "LedgerSecondaryIndex"), Enabled(values, "LedgerMinimumValidation"), Enabled(values, "LedgerArchive"),
                Enabled(values, "LedgerAutomaticTax"), Enabled(values, "LedgerUseIncompleteRecords"), nextBatch);
            return new ConfirmationScreen("総勘定元帳の設定", "入力した設定を保存しますか。", "保存",
                () => _settings.SaveGeneralLedgerParameters(updated)
                    ? new InformationScreen("総勘定元帳の設定", "設定を保存しました。")
                    : GeneralLedgerSettings(updated, "設定内容を確認してください。"),
                () => GeneralLedgerSettings(updated));
        }, Error: error);
    }
}
