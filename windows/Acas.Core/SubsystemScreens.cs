using System.Reflection;
using Acas.Core.Engine;

namespace Acas.Core;

public interface ISubsystemScreens
{
    MenuItem CreateNavigation(Db database);
}

[AttributeUsage(AttributeTargets.Assembly, AllowMultiple = true)]
public abstract class SubsystemScreensAttribute(int order) : Attribute
{
    public int Order { get; } = order;
    internal abstract ISubsystemScreens Create();
}

public sealed class SubsystemScreensAttribute<T>(int order) : SubsystemScreensAttribute(order)
    where T : ISubsystemScreens, new()
{
    internal override ISubsystemScreens Create() => new T();
}

public static class SubsystemScreens
{
    public static IReadOnlyList<MenuItem> Load(Assembly assembly, Db database) => assembly
        .GetCustomAttributes<SubsystemScreensAttribute>()
        .OrderBy(registration => registration.Order)
        .ThenBy(registration => registration.GetType().FullName, StringComparer.Ordinal)
        .Select(registration => registration.Create().CreateNavigation(database))
        .ToArray();
}
