using Acas.Core.Engine;

namespace Acas.Core.Programs;

public static partial class Sys002 { public static Task<int> Run(Ctx c, string caller) => Task.FromResult(0); }
public static partial class Sales { public static Task<int> Menu(Ctx c) => Task.FromResult(0); }
public static partial class Purchase { public static Task<int> Menu(Ctx c) => Task.FromResult(0); }
public static partial class Stock { public static Task<int> Menu(Ctx c) => Task.FromResult(0); }
public static partial class Irs { public static Task<int> Menu(Ctx c) => Task.FromResult(0); }
public static partial class Gl020 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl050 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl051 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl060 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl070 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl071 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl072 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl080 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl090 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl120 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl100 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl105 { public static Task<int> Run(Ctx c, string toDay) => Task.FromResult(0); }
public static partial class Gl030
{
    private static Task SetupPc(Ctx c, string toDay) => Task.CompletedTask;
    private static Task Amend(Ctx c, string toDay) => Task.CompletedTask;
    private static Task Alpha(Ctx c, string toDay) => Task.CompletedTask;
    private static Task Chart(Ctx c, string toDay, int menu) => Task.CompletedTask;
    private static Task PcReport(Ctx c, string toDay) => Task.CompletedTask;
}
