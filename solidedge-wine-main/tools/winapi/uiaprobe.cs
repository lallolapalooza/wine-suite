// uiaprobe.cs — drive the exact .NET UI Automation code path that asks DWM whether a window is
// cloaked, so the Wine log line the user reported
//
//      fixme:dwmapi:DwmGetWindowAttribute attribute 14 not implemented
//
// can be produced and its absence after the patch demonstrated.
//
// The path, from ILSpy (FINDINGS M5):
//   System.Windows.Automation.AutomationElement.FromHandle(hwnd)
//     -> HwndProxyElementProvider.GetNextSibling()
//        -> IsWindowReallyVisible()  -> IsWindowCloaked()
//           -> DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED (14), &v, 4)
//
// build (inside the prefix, so the .NET Framework tools are the ones actually used):
//   wine C:\windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:exe \
//        /out:C:\uiaprobe.exe C:\uiaprobe.cs /r:UIAutomationClient.dll /r:UIAutomationTypes.dll \
//        /r:WindowsBase.dll /r:System.Windows.Forms.dll
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Automation;

static class UiaProbe
{
    [DllImport("user32.dll")] static extern IntPtr FindWindowW(string cls, string title);

    static void Main()
    {
        Console.WriteLine("uiaprobe: pid=" + Process.GetCurrentProcess().Id);

        // Give ourselves a visible top-level window to ask about.
        var form = new System.Windows.Forms.Form { Text = "uiaprobeTarget", Width = 260, Height = 160 };
        form.Show();
        Application_DoEvents();
        IntPtr hwnd = form.Handle;
        Console.WriteLine("target hwnd = 0x" + hwnd.ToInt64().ToString("x"));

        Console.WriteLine("--- AutomationElement.FromHandle + sibling walk (the IsWindowReallyVisible path)");
        try
        {
            AutomationElement el = AutomationElement.FromHandle(hwnd);
            Console.WriteLine("FromHandle ok: " + (el == null ? "null" : el.Current.Name));
            TreeWalker walker = TreeWalker.ControlViewWalker;
            AutomationElement sib = walker.GetNextSibling(el);
            Console.WriteLine("GetNextSibling -> " + (sib == null ? "null" : "ok"));
            AutomationElement prev = walker.GetPreviousSibling(el);
            Console.WriteLine("GetPreviousSibling -> " + (prev == null ? "null" : "ok"));
            AutomationElement parent = walker.GetParent(el);
            Console.WriteLine("GetParent -> " + (parent == null ? "null" : "ok"));
        }
        catch (Exception ex)
        {
            Console.WriteLine("automation threw: " + ex.GetType().Name + ": " + ex.Message);
        }

        Console.WriteLine("--- AutomationElement.RootElement child walk");
        try
        {
            AutomationElementCollection kids = AutomationElement.RootElement.FindAll(
                TreeScope.Children, Condition.TrueCondition);
            Console.WriteLine("root children = " + kids.Count);
        }
        catch (Exception ex)
        {
            Console.WriteLine("root walk threw: " + ex.GetType().Name + ": " + ex.Message);
        }

        Console.WriteLine("uiaprobe: done");
        form.Close();
    }

    static void Application_DoEvents()
    {
        for (int i = 0; i < 20; i++)
        {
            System.Windows.Forms.Application.DoEvents();
            Thread.Sleep(10);
        }
    }
}
