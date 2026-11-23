using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Sales { public static Task<int> Menu(Ctx c) => Task.FromResult(0); }
public static partial class Purchase { public static Task<int> Menu(Ctx c) => Task.FromResult(0); }
public static partial class Stock { public static Task<int> Menu(Ctx c) => Task.FromResult(0); }
public static partial class Irs { public static Task<int> Menu(Ctx c) => Task.FromResult(0); }
public static partial class Gl071 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl072 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl105 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl030
{
    private static Task SetupPc(Ctx c, string toDay) => Task.CompletedTask;
    private static Task Alpha(Ctx c, string toDay) => Task.CompletedTask;
    private static Task PcReport(Ctx c, string toDay) => Task.CompletedTask;
}
public static class Maps01 { public static string Pass(string pw) => pw; /* TODO: port common/maps01.cbl */ }
