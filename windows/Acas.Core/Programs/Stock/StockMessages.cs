namespace Acas.Core.Programs.Stock;

/// <summary>st0x0.cbl のエラー・警告メッセージ（日本語化。末尾の番号はレガシーのメッセージ番号に対応）。</summary>
public static class StockMessages
{
    public const string ST005 = "日付が正しくありません。";
    public const string ST101 = "仕入先が見つかりません。";
    public const string ST102 = "略号は必ず入力してください。";
    public const string ST107 = "数量・金額が残っているため削除できません。";
    public const string ST109 = "発注情報が残っているため付番を変更できません。";
    public const string ST112 = "分析コードファイルを開けないため処理を中止しました。";
    public const string ST113 = "この略号は既に登録されています。";
    public const string ST114 = "品目番号が見つかりません。";
    public const string ST116 = "この品目番号は既に登録されています。";
    public const string ST203 = "略号に該当する品目がありません。";
    public const string ST204 = "数量は 999,999 未満で入力してください。";
    public const string ST205 = "在庫数は 999,999 を超えられません。";
    public const string ST206 = "在庫数がマイナスになります。";
    public const string ST207 = "数量の末尾は空白またはマイナス記号のみ指定できます。";
    public const string ST208 = "注意: 在庫数がゼロになります。";
    public const string ST209 = "在庫金額を最小値（ゼロ）にしました。";
    public const string ST212 = "在庫金額を最大値（99,999,999.99）にしました。";
    public const string ST214 = "品目番号が見つかりません。";
    public const string ST217 = "役務専用の品目です。";
    public const string ST219 = "在庫ファイルがまだ作成されていません。";
    public const string ST250 = "注文日を確認してください。";
    public const string ST251 = "納期を確認してください。";
    public const string ST302 = "指定範囲に該当する品目番号がありません。";
    public const string ST304 = "品目番号と略号の範囲は同時に指定できません。";
    public const string ST307 = "品目番号の開始は終了より小さくしてください。";
    public const string ST308 = "略号の開始は終了より小さくしてください。";
    public const string NotReported = "監査帳票が未出力のため、期間締めは実行できません。";
    public const string InvalidAmount = "金額が正しくありません。";
    public const string SingleByteOnly = "品名・保管場所などの文字項目は半角英数字・記号で入力してください（固定長レコードは 1 バイト文字のみ保存できます）。";
    public const string PriceRequired = "単価を入力してください。";
    public const string AuditNotUsed = "在庫監査を使用していないため、月末監査帳票は出力できません。";
}
