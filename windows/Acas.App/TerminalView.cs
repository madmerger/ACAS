using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Acas.Core.Engine;

namespace Acas.App;

/// <summary>80×24 の業務画面を WPF で直接描画するネイティブコントロール (全角は 2 桁幅)。</summary>
public sealed class TerminalView : FrameworkElement
{
    public const double CellW = 11, CellH = 24, Pad = 8;
    private static readonly Typeface Face = new(new FontFamily("MS Gothic, BIZ UDGothic, Yu Gothic UI, Consolas"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
    private static readonly Brush Back = Frozen(Color.FromRgb(0x10, 0x18, 0x20));
    private static readonly Brush FieldBack = Frozen(Color.FromRgb(0x2a, 0x3b, 0x55));
    private static readonly Brush[] Fg =
    {
        Frozen(Colors.Gainsboro), Frozen(Color.FromRgb(0x6c, 0xa8, 0xff)), Frozen(Color.FromRgb(0x7c, 0xe3, 0x8b)), Frozen(Color.FromRgb(0x66, 0xd9, 0xef)),
        Frozen(Color.FromRgb(0xff, 0x6b, 0x6b)), Frozen(Color.FromRgb(0xd6, 0x8f, 0xff)), Frozen(Color.FromRgb(0xff, 0xd8, 0x66)), Frozen(Colors.White),
    };
    private static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }

    private Crt? _crt;
    public Crt? Crt
    {
        get => _crt;
        set
        {
            if (_crt != null) _crt.Changed -= OnChanged;
            _crt = value;
            if (_crt != null) _crt.Changed += OnChanged;
            InvalidateVisual();
        }
    }

    public TerminalView()
    {
        Focusable = true;
        Width = Crt.Cols * CellW + Pad * 2; Height = Crt.Rows * CellH + Pad * 2;
        SnapsToDevicePixels = true;
    }

    private void OnChanged() => Dispatcher.BeginInvoke(new Action(InvalidateVisual));
    public void Refresh() => Dispatcher.BeginInvoke(new Action(InvalidateVisual));

    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawRectangle(Back, null, new Rect(0, 0, ActualWidth, ActualHeight));
        var t = _crt; if (t == null) return;
        double dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        if (t.FieldLen > 0)
            dc.DrawRectangle(FieldBack, null, new Rect(Pad + (t.FieldCol - 1) * CellW, Pad + (t.FieldRow - 1) * CellH, t.FieldLen * CellW, CellH));
        for (int r = 0; r < Crt.Rows; r++)
            for (int c = 0; c < Crt.Cols; c++)
            {
                char ch = t.Visible[r * Crt.Cols + c];
                if (ch == ' ' || ch == '\0') continue;
                var ft = new FormattedText(ch.ToString(), CultureInfo.InvariantCulture, FlowDirection.LeftToRight, Face, 20, Fg[t.Color[r * Crt.Cols + c] & 7], dpi);
                dc.DrawText(ft, new Point(Pad + c * CellW, Pad + r * CellH + 1));
            }
        if (t.CursorOn)
            dc.DrawRectangle(Fg[6], null, new Rect(Pad + (t.CurCol - 1) * CellW, Pad + t.CurRow * CellH - 4, CellW, 3));
    }
}
