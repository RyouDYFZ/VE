# VE - A Bridge for exposing NSVisualEffectView to C# via C-style exports

VE 是一个用于 macOS 的 Swift 动态库，允许 Avalonia/C# 应用调用原生 NSVisualEffectView 实现 Liquid Glass 效果，可在窗口中动态控制透明度、材质、圆角和状态

## 特性
    macOS 原生毛玻璃背景（NSVisualEffectView）
    支持 x86_64 + arm64 架构（universal dylib）
    动态控制 VE 属性：
        材质（Material）
        状态（State）
        混合模式（Blending）
        透明度（Alpha）
        圆角（CornerRadius）

## Notes
    Env macOS 26 Tahoe +
    每个 ve_create* 返回的 handle 必须最终调用 ve_remove_and_release
    VE 默认在 contentView 下层，不会阻塞控件
    可以动态修改透明度与圆角，VE 会随窗口大小自动调整
    确保 .dylib 在 .app/Contents/Frameworks 的位置

## 快速开始

1. 构建并拷贝到 Avalonia macOS App Bundle

```Bash
./build_bridge.sh
```

将 `build/libVisualEffectBridge.dylib` 拷贝到 `*.app/Contents/Frameworks/libVisualEffectBridge.dylib`
2. 在 C# / Avalonia 中引用
    添加 `NativeMethods.cs`

```C#
using System;
using System.Runtime.InteropServices;

static partial class NativeMethods
{
    const string LIB = "VisualEffectBridge";

    [LibraryImport(LIB)]
    public static partial IntPtr ve_create_and_attach(IntPtr nsWindow, double x, double y, double w, double h);

    [LibraryImport(LIB)]
    public static partial void ve_remove_and_release(IntPtr handle);

    [LibraryImport(LIB)]
    public static partial void ve_set_material_sidebar(IntPtr handle);
    [LibraryImport(LIB)]
    public static partial void ve_set_alpha(IntPtr handle, double alpha);
    [LibraryImport(LIB)]
    public static partial void ve_set_layer_corner_radius(IntPtr handle, double radius);
}
```

    使用封装类 `VisualEffectView.cs`
```C#
public class VisualEffectView : IDisposable
{
    private IntPtr _handle;

    public VisualEffectView(Window window)
    {
        if (!OperatingSystem.IsMacOS()) return;
        var nsWindow = window.PlatformImpl?.Handle ?? IntPtr.Zero;
        if (nsWindow == IntPtr.Zero) return;
        _handle = NativeMethods.ve_create_and_attach(nsWindow, 0, 0, window.ClientSize.Width, window.ClientSize.Height);
    }

    public double Alpha
    {
        set { if (_handle != IntPtr.Zero) NativeMethods.ve_set_alpha(_handle, value); }
    }

    public void SetMaterialSidebar()
    {
        if (_handle != IntPtr.Zero) NativeMethods.ve_set_material_sidebar(_handle);
    }

    public void SetCornerRadius(double radius)
    {
        if (_handle != IntPtr.Zero) NativeMethods.ve_set_layer_corner_radius(_handle, radius);
    }

    public void Dispose()
    {
        if (_handle != IntPtr.Zero)
        {
            NativeMethods.ve_remove_and_release(_handle);
            _handle = IntPtr.Zero;
        }
    }
}
```

    在 Avalonia Window 中使用
    
```C#
private VisualEffectView _veView;

this.Opened += (s, e) =>
{
    _veView = new VisualEffectView(this);
    _veView.SetMaterialSidebar();
    _veView.Alpha = 0.95;
    _veView.SetCornerRadius(12);
};

this.Closing += (s, e) =>
{
    _veView?.Dispose();
};
```

