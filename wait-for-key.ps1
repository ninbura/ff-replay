param(
  [string]$quitKey = "F24"
)

$keyLogger = @"
using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace KeyLogger{
  public static class Program {
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;

    private static HookProc hookProc = HookCallback;
    private static IntPtr hookId = IntPtr.Zero;
    private static int keyCode = 0;

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    public static int WaitForKey() {
        hookId = SetHook(hookProc);
        Application.Run();
        UnhookWindowsHookEx(hookId);
        return keyCode;
    }

    private static IntPtr SetHook(HookProc hookProc) {
        IntPtr moduleHandle = GetModuleHandle(Process.GetCurrentProcess().MainModule.ModuleName);
        return SetWindowsHookEx(WH_KEYBOARD_LL, hookProc, moduleHandle, 0);
    }

    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && wParam == (IntPtr)WM_KEYDOWN) {
            keyCode = Marshal.ReadInt32(lParam);
            Application.Exit();
        }

        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }
  }
}
"@

Add-Type -TypeDefinition $keyLogger -ReferencedAssemblies system.Windows.Forms

while ($keyPress -ne $quitKey) {
  $keyPress = [System.Windows.Forms.Keys][KeyLogger.Program]::WaitForKey()
}

Write-Host "`nCaught $quitKey, ending recording..." -ForegroundColor Green

exit