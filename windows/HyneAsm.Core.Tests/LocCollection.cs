namespace HyneAsm.Core.Tests;

/// <summary><c>Loc.Language</c> is one global value (the app needs it that way). Test classes that set it belong to this
/// collection: xUnit runs a collection with parallelization disabled on its own, after the parallel ones, so a test
/// that reads localized text never sees another test's language.</summary>
[CollectionDefinition(Name, DisableParallelization = true)]
public sealed class LocCollection
{
    public const string Name = "Loc";
}
