using Acas.Core.Engine;

namespace Acas.Core.Programs;

/// <summary>maps99: エラー番号表示 (error.txt が無い環境の実測動作: 23行目に番号と既定文言を表示しキー待ち)。</summary>
public static class Maps99
{
    public static async Task<int> Show(Ctx c, int err)
    {
        c.Crt.V("T-" + err.ToString("000") + " ", 2301, fg: 4);
        c.Crt.D("Error not in error.txt. Hit return to close", 2307, fg: 4);
        await c.Crt.A(2479, 1);
        return 0;
    }
}
