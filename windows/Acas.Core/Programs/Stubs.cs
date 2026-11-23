using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Gl071 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl072 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl105 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl030
{
    private static Task SetupPc(Ctx c, string toDay) => Task.CompletedTask;
    private static Task Alpha(Ctx c, string toDay) => Task.CompletedTask;
    private static Task PcReport(Ctx c, string toDay) => Task.CompletedTask;
}
