using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Yuguang.Core;
using Forms = System.Windows.Forms;
using Drawing = System.Drawing;

namespace Yuguang.App;
public sealed class MainWindow : Window
{
    private readonly LiveSession session;
    private readonly Border sheet = new();
    private readonly Grid root = new();
    private readonly DispatcherTimer hover = new() { Interval = TimeSpan.FromMilliseconds(80) };
    private readonly Forms.NotifyIcon tray;
    private readonly Dictionary<string, string> colors = new();
    private readonly Drawing.Icon trayIcon;
    private bool compact, quitting, menuOpen, settingsOpen, recording, rebuilding, pendingRender;
    private int hotKeyId = 1;
    private IntPtr handle;
    private Brush ink = Brushes.Black, muted = Brushes.Gray, paper = Brushes.White, surface = Brushes.WhiteSmoke;
    private StackPanel? compactControls;
    private ScrollViewer? liveScroll;
    private WindowBounds? expandedFrame, compactFrame;
    private string shortcutError = "";
    private const string Accent = "#C66B42";
    public MainWindow(LiveSession value)
    {
        session = value; Title = "余光 · Yuguang"; Width = 430; Height = 680;
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; FontFamily = new FontFamily("Segoe UI, Microsoft YaHei UI"); FontSize = 13;
        UseLayoutRounding = true; SnapsToDevicePixels = true;
        expandedFrame = session.State.Settings.ExpandedFrame; compactFrame = session.State.Settings.CompactFrame;
        compact = session.State.Settings.SimpleMode;
        using (var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/catalog.json"))!.Stream)
        using (var document = JsonDocument.Parse(resource)) foreach (var team in document.RootElement.EnumerateObject()) colors[team.Name] = "#" + team.Value.GetProperty("dayColor").GetString();
        using (var resource = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AppIcon.ico"))!.Stream) trayIcon = new Drawing.Icon(resource);
        tray = new Forms.NotifyIcon { Icon = trayIcon, Text = "余光 · 使用余光关注比赛", Visible = true };
        tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) Dispatcher.Invoke(ToggleVisibility); };
        tray.ContextMenuStrip = new Forms.ContextMenuStrip();
        tray.ContextMenuStrip.Opening += (_, _) => BuildTray();
        Content = sheet; sheet.Child = root; root.Background = Brushes.Transparent; root.MouseLeftButtonDown += Drag;
        SourceInitialized += (_, _) => { handle = new WindowInteropHelper(this).Handle; HwndSource.FromHwnd(handle)?.AddHook(Hook); var registered = RegisterShortcut(session.State.Settings.ShortcutModifiers, session.State.Settings.ShortcutKey); RestoreFrame(); if (!registered) { settingsOpen = true; compact = false; RestoreFrame(); Render(); } };
        Closing += OnClosing;
        PreviewKeyDown += KeyDownRecorder;
        session.Changed += Render;
        hover.Tick += (_, _) => { if (pendingRender && Mouse.Captured == null) Render(); ApplyHover(); }; hover.Start();
        LocationChanged += (_, _) => { if (!rebuilding && IsLoaded) SaveFrame(); };
        Render();
    }
    private static Brush Color(string hex) => new SolidColorBrush((System.Windows.Media.Color)ColorConverter.ConvertFromString(hex));
    private TextBlock Text(string value, double size = 13, Brush? foreground = null, FontWeight? weight = null) => new() { Text = value, FontSize = size, Foreground = foreground ?? ink, FontWeight = weight ?? FontWeights.Normal, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
    private Button Button(string label, Action action, string? tooltip = null)
    {
        var button = new Button { Content = label, Foreground = ink, Background = surface, BorderThickness = new Thickness(0), Padding = new Thickness(10, 6, 10, 6), Margin = new Thickness(2), Cursor = Cursors.Hand, ToolTip = tooltip, FontFamily = FontFamily };
        button.Click += (_, _) => action(); return button;
    }
    private static StackPanel Row() => new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
    private void AddRow(UIElement item, Grid grid, double? height = null)
    {
        grid.RowDefinitions.Add(new RowDefinition { Height = height.HasValue ? new GridLength(height.Value) : GridLength.Auto }); Grid.SetRow(item, grid.RowDefinitions.Count - 1); grid.Children.Add(item);
    }
    private void Drag(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left || recording) return;
        var source = e.OriginalSource as DependencyObject;
        while (source != null) { if (source is ButtonBase or ComboBox or TextBox or Thumb) return; source = VisualTreeHelper.GetParent(source); }
        if (e.ClickCount == 2 && compact) { SetCompact(false); e.Handled = true; return; }
        e.Handled = true;
        try { DragMove(); SaveFrame(); } catch (InvalidOperationException) { }
    }
    private void Render()
    {
        if (!Dispatcher.CheckAccess()) { Dispatcher.BeginInvoke(Render); return; }
        // Polling must not replace a control while a popup or resize gesture owns capture.
        if (Mouse.Captured != null) { pendingRender = true; return; }
        pendingRender = false;
        var scrollOffset = liveScroll?.VerticalOffset ?? 0;
        rebuilding = true;
        var prefs = session.State.Settings;
        if (tray.ContextMenuStrip!.Items.Count > 0) tray.ContextMenuStrip.Items[0].Text = session.State.SelectedMatch?.Heading ?? "余光 · 选择比赛";
        bool dark = prefs.Theme == "dark" || prefs.Theme == "system" && !SystemParameters.HighContrast && ReadDarkTheme();
        ink = Color(dark ? "#ECE9E3" : "#252823"); muted = Color(dark ? "#A0A49A" : "#858B80"); paper = Color(dark ? "#20231F" : "#FCFCF8"); surface = Color(dark ? "#30352E" : "#F0F2EB");
        Topmost = prefs.Pinned; sheet.Background = paper; sheet.CornerRadius = new CornerRadius(compact ? 8 : 14); sheet.BorderBrush = surface; sheet.BorderThickness = new Thickness(1);
        root.Children.Clear(); root.RowDefinitions.Clear(); root.Margin = compact ? new Thickness(9, 0, 5, 0) : new Thickness(22, 16, 22, 18);
        compactControls = null; liveScroll = null;
        if (compact) RenderCompact(); else if (settingsOpen) RenderSettings(); else RenderExpanded();
        var resize = new Thumb { Width = 12, Height = 12, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom, Cursor = Cursors.SizeNWSE, Opacity = .3, Background = muted };
        resize.DragDelta += (_, e) => { Width = Math.Clamp(Width + e.HorizontalChange, 360, compact ? 1200 : 760); if (!compact) Height = Math.Clamp(Height + e.VerticalChange, 460, 1100); SaveFrame(); };
        Grid.SetRowSpan(resize, Math.Max(1, root.RowDefinitions.Count)); root.Children.Add(resize);
        if (liveScroll != null && !session.State.Following) liveScroll.ScrollToVerticalOffset(scrollOffset);
        rebuilding = false; ApplyHover();
    }
    private static bool ReadDarkTheme()
    {
        try { return Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) is int value && value == 0; }
        catch (System.Security.SecurityException) { return false; }
    }
    private void RenderCompact()
    {
        Height = session.State.Settings.Rows * 32;
        var first = new Grid { Height = 31, Background = Brushes.Transparent }; first.MouseLeftButtonDown += Drag;
        first.ColumnDefinitions.Add(new ColumnDefinition()); first.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var match = session.State.SelectedMatch;
        var line = (session.State.Demo ? "演示 · " : "") + (match?.Heading ?? "余光 · 选择一场比赛");
        if (session.State.Settings.Rows == 1 && !session.State.Settings.ScoreOnly) line += "   " + session.State.LatestText;
        if (session.State.ConnectionError.Length > 0) line += " · 连接重试中";
        first.Children.Add(Text(line, 12));
        compactControls = Row(); compactControls.Children.Add(Button("⇄", () => QuickMenu(), "切换比赛")); compactControls.Children.Add(Button("↗", () => SetCompact(false), "展开窗口"));
        Grid.SetColumn(compactControls, 1); first.Children.Add(compactControls); AddRow(first, root, 31);
        for (int index = 0; index < session.State.Settings.Rows - 1; index++)
        {
            var entry = session.State.Entries.ElementAtOrDefault(index); var row = new Border { Height = 32, Background = Brushes.Transparent, Child = Text(entry?.Content ?? (index == 0 ? session.State.LatestText : ""), 12, index == 0 ? ink : muted) }; row.MouseLeftButtonDown += Drag; AddRow(row, root, 32);
        }
    }
    private Grid Header()
    {
        var header = new Grid { Margin = new Thickness(0, 0, 0, 15), Background = Brushes.Transparent }; header.MouseLeftButtonDown += Drag;
        header.ColumnDefinitions.Add(new ColumnDefinition()); header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var brand = Row(); brand.Children.Add(new Image { Source = new BitmapImage(new Uri("pack://application:,,,/Assets/Brand.png")), Width = 24, Height = 24, Margin = new Thickness(0, 0, 8, 0) }); brand.Children.Add(Text("余光  /  YUGUANG", 13, ink, FontWeights.SemiBold)); header.Children.Add(brand);
        var actions = Row(); actions.Children.Add(Button("—", () => SetCompact(true), "精简窗口")); actions.Children.Add(Button(settingsOpen ? "返回" : "设置", () => { settingsOpen = !settingsOpen; Render(); })); actions.Children.Add(Button("×", Hide, "隐藏 · " + session.State.Settings.ShortcutLabel)); Grid.SetColumn(actions, 1); header.Children.Add(actions); return header;
    }
    private void RenderExpanded()
    {
        AddRow(Header(), root);
        var eyebrow = Text(session.State.Demo ? "演示模式 · 示例数据" : "NBA  /  LIVE COURTSIDE", 10, muted, FontWeights.SemiBold); eyebrow.Margin = new Thickness(0, 0, 0, 9); AddRow(eyebrow, root);
        var selectors = Row();
        var days = new ComboBox { Width = 142, Margin = new Thickness(0, 0, 8, 0), DisplayMemberPath = "Label", ItemsSource = session.State.Days, SelectedItem = session.State.Days.FirstOrDefault(day => day.Day == session.State.SelectedDay) };
        days.SelectionChanged += (_, _) => { if (days.SelectedItem is GameDay day && day.Day != session.State.SelectedDay) session.ChangeDay(day.Day); };
        var teams = new[] { "全部球队" }.Concat(colors.Keys.OrderBy(name => name)).ToArray(); var filter = new ComboBox { Width = 123, ItemsSource = teams, SelectedItem = session.State.TeamFilter };
        filter.SelectionChanged += (_, _) => { if (filter.SelectedItem is string team && team != session.State.TeamFilter) session.Filter(team); };
        selectors.Children.Add(days); selectors.Children.Add(filter); selectors.Children.Add(Button("↻", () => _ = session.RefreshScheduleAsync(), "刷新赛程")); AddRow(selectors, root);
        var matches = new StackPanel { Margin = new Thickness(0, 10, 0, 12) };
        foreach (var match in session.VisibleMatches) { var button = Button($"{match.Away}  {match.Score}  {match.Home}    · {match.Status}", () => session.Select(match)); button.HorizontalContentAlignment = HorizontalAlignment.Left; if (match.Id == session.State.SelectedMatch?.Id) button.BorderThickness = new Thickness(0, 0, 0, 2); button.BorderBrush = Color(Accent); matches.Children.Add(button); }
        if (matches.Children.Count == 0) matches.Children.Add(Text(session.State.LoadingSchedule ? "正在读取赛程…" : "这个比赛日暂无匹配赛事", 12, muted));
        AddRow(new ScrollViewer { Content = matches, MaxHeight = 133, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }, root);
        if (session.State.SelectedMatch is { } selected)
        {
            var board = new Grid { Background = surface, Margin = new Thickness(0, 0, 0, 12) }; for (int i = 0; i < 3; i++) board.ColumnDefinitions.Add(new ColumnDefinition());
            board.Children.Add(Team(selected.Away, 0)); var score = new StackPanel { Margin = new Thickness(0, 18, 0, 18), HorizontalAlignment = HorizontalAlignment.Center }; score.Children.Add(Text(selected.Score, 25, ink, FontWeights.SemiBold)); score.Children.Add(Text(selected.Status, 10, muted)); Grid.SetColumn(score, 1); board.Children.Add(score); board.Children.Add(Team(selected.Home, 2)); AddRow(board, root);
        }
        var status = new Grid(); status.ColumnDefinitions.Add(new ColumnDefinition()); status.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto }); status.Children.Add(Text("文字直播  /  " + (session.State.LoadingLive ? "连接中" : session.State.TextUpdatedAt?.ToLocalTime().ToString("HH:mm:ss") ?? "等待比赛"), 11, muted)); var follow = Button(session.State.Following ? "暂停滚动" : $"回到最新 · {session.State.Unread}", session.ToggleFollowing); Grid.SetColumn(follow, 1); status.Children.Add(follow); AddRow(status, root);
        var entries = new StackPanel(); foreach (var entry in session.State.Following ? session.State.Entries : session.State.FrozenEntries)
        {
            var item = new StackPanel { Margin = new Thickness(0, 10, 0, 12) }; item.Children.Add(Text(entry.Clock, 10, muted)); var content = Text(entry.Content, 13); content.TextWrapping = TextWrapping.Wrap; content.LineHeight = 22; item.Children.Add(content); entries.Children.Add(item);
        }
        if (entries.Children.Count == 0) entries.Children.Add(Text(session.State.LatestText, 13, muted));
        liveScroll = new ScrollViewer { Content = entries, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(0, 5, 0, 7) };
        root.RowDefinitions.Add(new RowDefinition()); Grid.SetRow(liveScroll, root.RowDefinitions.Count - 1); root.Children.Add(liveScroll);
        var error = session.State.PreferencesError.Length > 0 ? session.State.PreferencesError : session.State.ScheduleError.Length > 0 ? session.State.ScheduleError : session.State.ConnectionError;
        if (error.Length > 0) AddRow(Button(error + " · 重试", () => { _ = session.RefreshScheduleAsync(); session.Retry(); }), root);
        var footer = Text("使用余光关注比赛  ·  " + session.State.Settings.ShortcutLabel + " 隐藏", 10, muted); AddRow(footer, root);
    }
    private StackPanel Team(string name, int column)
    {
        var team = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(3, 12, 3, 12) };
        if (!session.State.Settings.SimpleMode && colors.ContainsKey(name)) team.Children.Add(new Image { Source = new BitmapImage(new Uri($"pack://application:,,,/Assets/Teams/{Uri.EscapeDataString(name)}.png")), Width = 42, Height = 42, Margin = new Thickness(0, 0, 0, 5) });
        team.Children.Add(Button(name + (session.State.Settings.Favorites.Contains(name) ? " ★" : " ☆"), () => session.ToggleFavorite(name), "关注球队")); team.Children.Add(new Border { Height = 2, Width = 24, Background = Color(colors.GetValueOrDefault(name, Accent)) }); Grid.SetColumn(team, column); return team;
    }
    private void RenderSettings()
    {
        AddRow(Header(), root); AddRow(Text("让余光，恰到好处。", 23, ink, FontWeights.SemiBold), root);
        var body = new StackPanel { Margin = new Thickness(0, 20, 0, 0) };
        void Check(string label, bool value, Action<bool> update) { var box = new CheckBox { Content = label, IsChecked = value, Foreground = ink, Margin = new Thickness(0, 10, 0, 10) }; box.Click += (_, _) => update(box.IsChecked == true); body.Children.Add(box); }
        Check("窗口始终置顶", session.State.Settings.Pinned, value => session.UpdateSettings(session.State.Settings with { Pinned = value }));
        Check("启动精简模式，并隐藏球队 Logo", session.State.Settings.SimpleMode, value => { session.UpdateSettings(session.State.Settings with { SimpleMode = value }); if (value) SetCompact(true); });
        Check("单行时只显示比分", session.State.Settings.ScoreOnly, value => session.UpdateSettings(session.State.Settings with { ScoreOnly = value }));
        body.Children.Add(Text("精简窗口行数", 12, muted)); var rows = new ComboBox { ItemsSource = Enumerable.Range(1, 6), SelectedItem = session.State.Settings.Rows, Margin = new Thickness(0, 8, 0, 14) }; rows.SelectionChanged += (_, _) => { if (rows.SelectedItem is int value && value != session.State.Settings.Rows) session.UpdateSettings(session.State.Settings with { Rows = value }); }; body.Children.Add(rows);
        body.Children.Add(Text("外观", 12, muted)); var themes = new ComboBox { ItemsSource = new[] { "跟随系统", "浅色", "深色" }, SelectedIndex = session.State.Settings.Theme == "light" ? 1 : session.State.Settings.Theme == "dark" ? 2 : 0, Margin = new Thickness(0, 8, 0, 14) }; themes.SelectionChanged += (_, _) => { var value = themes.SelectedIndex == 1 ? "light" : themes.SelectedIndex == 2 ? "dark" : "system"; if (value != session.State.Settings.Theme) session.UpdateSettings(session.State.Settings with { Theme = value }); }; body.Children.Add(themes);
        body.Children.Add(Text("全局显示 / 隐藏快捷键", 12, muted)); body.Children.Add(Button(recording ? "按下组合键… Esc 取消" : session.State.Settings.ShortcutLabel + " · 点击录制", () => { recording = true; Render(); Focus(); }));
        body.Children.Add(Text(shortcutError, 11, Color(Accent))); body.Children.Add(Text(session.State.PreferencesError, 11, Color(Accent)));
        var note = Text("鼠标移开精简窗口后，边框和控件自动隐去。\n双击文字展开；右上角 ⇄ 可直接切换比赛。\n\n余光 0.2.0 · Windows 原生版\n一边用 AI 编程，一边观看比赛。", 12, muted); note.TextWrapping = TextWrapping.Wrap; note.Margin = new Thickness(0, 25, 0, 0); body.Children.Add(note);
        root.RowDefinitions.Add(new RowDefinition()); var scroll = new ScrollViewer { Content = body, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }; Grid.SetRow(scroll, root.RowDefinitions.Count - 1); root.Children.Add(scroll);
    }
    private void ApplyHover()
    {
        bool visible = !compact || menuOpen || Native.PointerInside(this); sheet.Background = visible ? paper : Brushes.Transparent; sheet.BorderBrush = visible ? surface : Brushes.Transparent;
        if (compactControls != null) compactControls.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        foreach (var thumb in root.Children.OfType<Thumb>()) thumb.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
    }
    private void QuickMenu()
    {
        var menu = new ContextMenu(); menuOpen = true;
        foreach (var day in session.State.Days) { var item = new MenuItem { Header = day.Label, IsCheckable = true, IsChecked = day.Day == session.State.SelectedDay }; item.Click += (_, _) => { session.ChangeDay(day.Day); Dispatcher.BeginInvoke(() => QuickMenu()); }; menu.Items.Add(item); }
        menu.Items.Add(new Separator()); foreach (var match in session.SwitchableMatches) { var item = new MenuItem { Header = match.Heading, IsCheckable = true, IsChecked = match.Id == session.State.SelectedMatch?.Id }; item.Click += (_, _) => session.Select(match); menu.Items.Add(item); }
        if (session.SwitchableMatches.Count == 0) menu.Items.Add(new MenuItem { Header = "暂无赛事", IsEnabled = false });
        menu.Closed += (_, _) => { menuOpen = false; ApplyHover(); }; menu.PlacementTarget = this; menu.Placement = PlacementMode.MousePoint; menu.IsOpen = true;
    }
    private void BuildTray()
    {
        var menu = tray.ContextMenuStrip!; menu.Items.Clear(); menu.Items.Add(new Forms.ToolStripMenuItem(session.State.SelectedMatch?.Heading ?? "余光 · 选择比赛") { Enabled = false }); menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("显示 / 隐藏直播", null, (_, _) => Dispatcher.Invoke(ToggleVisibility)); menu.Items.Add("选择比赛", null, (_, _) => Dispatcher.Invoke(() => { Show(); QuickMenu(); })); menu.Items.Add("精简 / 展开", null, (_, _) => Dispatcher.Invoke(() => { Show(); SetCompact(!compact); })); menu.Items.Add("偏好设置…", null, (_, _) => Dispatcher.Invoke(() => { settingsOpen = true; SetCompact(false); Show(); Activate(); })); menu.Items.Add(new Forms.ToolStripSeparator()); menu.Items.Add("退出余光", null, (_, _) => Dispatcher.Invoke(() => Quit(0)));
    }
    private void SetCompact(bool value) { if (compact == value) { Render(); return; } SaveFrame(); compact = value; RestoreFrame(); Render(); }
    private void RestoreFrame()
    {
        rebuilding = true; var frame = compact ? compactFrame : expandedFrame; Width = frame?.Width ?? 430; Height = compact ? session.State.Settings.Rows * 32 : frame?.Height ?? 680;
        // Screen coordinates are device pixels; PointFromScreen converts the selected monitor's work area to WPF units.
        var screen = Forms.Screen.FromHandle(handle); var start = PointFromScreen(new Point(screen.WorkingArea.Left, screen.WorkingArea.Top)); var end = PointFromScreen(new Point(screen.WorkingArea.Right, screen.WorkingArea.Bottom));
        var area = new WindowBounds(Left + start.X, Top + start.Y, end.X - start.X, end.Y - start.Y);
        if (!double.IsFinite(area.X)) area = new WindowBounds(SystemParameters.WorkArea.X, SystemParameters.WorkArea.Y, SystemParameters.WorkArea.Width, SystemParameters.WorkArea.Height);
        var clamped = new WindowBounds(frame?.X ?? area.X + 80, frame?.Y ?? area.Y + 80, Width, Height).Clamp(area); Left = clamped.X; Top = clamped.Y; Width = clamped.Width; Height = clamped.Height; rebuilding = false;
    }
    private void SaveFrame()
    {
        var frame = new WindowBounds(Left, Top, Width, Height); if (!frame.IsValid) return;
        if (compact) compactFrame = frame; else expandedFrame = frame;
        // Store without rebuilding the view during a drag.
    }
    public void ToggleVisibility() { if (IsVisible) Hide(); else { Show(); Activate(); } }
    private bool RegisterShortcut(uint modifiers, uint key)
    {
        int candidate = hotKeyId == 1 ? 2 : 1;
        if (!Native.RegisterHotKey(handle, candidate, modifiers | 0x4000, key)) { shortcutError = "快捷键被其他程序占用，请更换组合键。"; return false; }
        Native.UnregisterHotKey(handle, hotKeyId); hotKeyId = candidate; shortcutError = ""; return true;
    }
    private IntPtr Hook(IntPtr window, int message, IntPtr wParam, IntPtr lParam, ref bool handled) { if (message == 0x0312 && wParam.ToInt32() == hotKeyId) { if (!recording) ToggleVisibility(); handled = true; } return IntPtr.Zero; }
    private void KeyDownRecorder(object sender, KeyEventArgs e)
    {
        if (!recording) return; e.Handled = true; var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape) { recording = false; Render(); return; }
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) return;
        var modifiers = (uint)((Keyboard.Modifiers.HasFlag(ModifierKeys.Alt) ? 1 : 0) | (Keyboard.Modifiers.HasFlag(ModifierKeys.Control) ? 2 : 0) | (Keyboard.Modifiers.HasFlag(ModifierKeys.Shift) ? 4 : 0) | (Keyboard.Modifiers.HasFlag(ModifierKeys.Windows) ? 8 : 0)); var virtualKey = (uint)KeyInterop.VirtualKeyFromKey(key);
        if ((modifiers & 11) == 0) { shortcutError = "请包含 Ctrl、Alt 或 Win。"; recording = false; Render(); return; }
        bool same = modifiers == session.State.Settings.ShortcutModifiers && virtualKey == session.State.Settings.ShortcutKey;
        if (same || RegisterShortcut(modifiers, virtualKey)) { recording = false; session.UpdateSettings(session.State.Settings with { ShortcutModifiers = modifiers, ShortcutKey = virtualKey }); } else { recording = false; Render(); }
    }
    private void OnClosing(object? sender, CancelEventArgs e) { if (!quitting) { e.Cancel = true; Hide(); } }
    public void Quit(int exitCode)
    {
        quitting = true; hover.Stop(); SaveFrame(); session.Changed -= Render;
        session.UpdateSettings(session.State.Settings with { ExpandedFrame = expandedFrame, CompactFrame = compactFrame }); session.Dispose(); Native.UnregisterHotKey(handle, hotKeyId); tray.Visible = false; tray.Dispose(); trayIcon.Dispose(); Close(); Application.Current.Shutdown(exitCode);
    }
    public void Capture(string path)
    {
        UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)ActualWidth, (int)ActualHeight, 96, 96, PixelFormats.Pbgra32); bitmap.Render(this);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var output = File.Create(path); encoder.Save(output);
    }
    public string SelfTest()
    {
        int checks = 0; void Assert(bool condition, string label) { if (!condition) throw new InvalidOperationException(label); checks++; }
        Assert(session.State.Demo, "Diagnostics require explicit demo mode"); Assert(colors.Count == 30, "30 team assets");
        foreach (var team in colors.Keys) Assert(new BitmapImage(new Uri($"pack://application:,,,/Assets/Teams/{Uri.EscapeDataString(team)}.png")).PixelWidth > 0, "team " + team);
        Assert(session.State.SelectedMatch?.Heading.Contains("102 : 99") == true, "score direction"); BuildTray(); Assert(tray.ContextMenuStrip!.Items[0].Text?.Contains("102 : 99") == true, "tray score");
        SetCompact(true); for (int rows = 1; rows <= 6; rows++) { session.UpdateSettings(session.State.Settings with { Rows = rows }); UpdateLayout(); Assert(Height == 32 * rows && Math.Abs(ActualHeight - Height) < 1, "actual compact height " + rows); }
        session.Select(session.SwitchableMatches[1]); Assert(compact, "quick selection keeps compact"); SetCompact(false); Assert(Height >= 460, "restore expanded frame");
        settingsOpen = true; Render(); Assert(root.Children.Count > 1, "settings render");
        Assert(shortcutError.Length == 0, "global hotkey registration"); Hide(); ToggleVisibility(); Assert(IsVisible, "restore hidden window");
        return JsonSerializer.Serialize(new { passed = checks, platform = "WPF", font = FontFamily.Source, rows = "1–6", assets = colors.Count });
    }
}
