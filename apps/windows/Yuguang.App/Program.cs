using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading;
using System.Windows;
using Yuguang.Core;

namespace Yuguang.App;
public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        try { return Run(args); }
        catch (Exception error)
        {
            var index = Array.IndexOf(args, "--report");
            if (index >= 0 && index + 1 < args.Length) File.WriteAllText(args[index + 1], error.ToString());
            else MessageBox.Show("余光启动失败：" + error.Message, "余光", MessageBoxButton.OK, MessageBoxImage.Error);
            return 1;
        }
    }
    private static int Run(string[] args)
    {
        using var instance = new Mutex(true, @"Local\Yuguang.Native.Windows", out var firstInstance);
        if (!firstInstance) return 0;
        using var client = new HttpClient();
        var store = new SettingsStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Yuguang", "settings.json"));
        using var session = new LiveSession(new HupuApi(client), store.Load(), store.Save);
        if (args.Contains("--demo")) session.LoadDemo();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var window = new MainWindow(session);
        app.Startup += async (_, _) =>
        {
            window.Show();
            if (args.Contains("--self-test"))
            {
                int code = 0; string report;
                var index = Array.IndexOf(args, "--report");
                try { if (index >= 0 && index + 1 < args.Length) window.Capture(Path.ChangeExtension(args[index + 1], ".png")); report = window.SelfTest(); }
                catch (Exception error) { code = 1; report = error.ToString(); }
                if (index >= 0 && index + 1 < args.Length) File.WriteAllText(args[index + 1], report);
                window.Quit(code);
            }
            else await session.StartAsync();
        };
        return app.Run();
    }
}
