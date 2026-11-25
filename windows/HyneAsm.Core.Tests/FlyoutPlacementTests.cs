namespace HyneAsm.Core.Tests;

/// <summary>Same cases as Tests/HMLauncherCoreTests/FlyoutPlacementTests.swift.</summary>
public class FlyoutPlacementTests
{
    // Panel 1000…1400 with two columns: left pad 1010…1200, right pad 1210…1390. List 280 wide, screen 0…3000.
    static double X(double padMin, double padMax, double screenMin = 0, double screenMax = 3000) =>
        FlyoutPlacement.X(padMin, padMax, 1000, 1400, 280, screenMin, screenMax);

    [Fact]
    public void Left_column_opens_left_right_column_opens_right()
    {
        Assert.Equal(1010 - 2 - 280, X(1010, 1200));
        Assert.Equal(1392, X(1210, 1390));
    }

    [Fact]
    public void Centred_pad_opens_right() => Assert.Equal(1392, X(1010, 1390));

    [Fact]
    public void No_room_uses_the_other_side()
    {
        Assert.Equal(1202, X(1010, 1200, screenMin: 900));
        Assert.Equal(1210 - 2 - 280, X(1210, 1390, screenMax: 1500));
    }

    [Fact]
    public void No_room_either_side_stays_on_screen()
    {
        Assert.Equal(1500 - 280, X(1010, 1390, 900, 1500));
        Assert.Equal(1000, X(1010, 1200, 1000, 1250));
    }
}
