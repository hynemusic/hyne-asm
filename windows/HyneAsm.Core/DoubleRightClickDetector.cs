namespace HyneAsm.Core;

public enum ClickVerdict { PassThrough, OpenPanel }

/// <summary>Decides on right-mouse-down: the second press within the interval opens the panel; the press after that starts over.</summary>
public sealed class DoubleRightClickDetector
{
    public TimeSpan Interval { get; }
    DateTime? firstDownAt;

    public DoubleRightClickDetector(TimeSpan interval) { Interval = interval; }

    public ClickVerdict RightMouseDown(DateTime time)
    {
        if (firstDownAt is { } first && time - first <= Interval)
        {
            firstDownAt = null;
            return ClickVerdict.OpenPanel;
        }
        firstDownAt = time;
        return ClickVerdict.PassThrough;
    }
}
