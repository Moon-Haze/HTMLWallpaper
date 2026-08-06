# HTML Wallpaper - KDE Plasma 6 HTML 壁纸插件

[English](#english) | [中文](#中文)

<a id="中文"></a>

## 中文说明

这是一个 KDE Plasma 6 壁纸插件，允许你将任意 HTML 页面设置为桌面壁纸，支持鼠标交互。

### 特性

- ✅ 支持将本地 HTML 文件或远程网页设置为壁纸
- ✅ 支持鼠标交互（点击、滚动等）
- ✅ 支持缩放调整
- ✅ 允许不安全 HTTPS 连接（自签名证书）
- ✅ 自动播放媒体（无需用户手势）

### 系统要求

- KDE Plasma 6.0 或更高版本
- QtWebEngine

### 构建

依赖：KDE Plasma 6 开发包、Qt 6.10+（含 QtWebEngine）、vcpkg。

```bash
# 1. 设置 vcpkg 根目录（提供 ECM）
export VCPKG_ROOT=/path/to/vcpkg

# 2. 配置（vcpkg + 系统 KF6 预设）
cmake --preset vcpkg

# 3. 构建并安装
cmake --build --preset vcpkg
cmake --install build

# 4. 重启 plasmashell 使插件生效
kquitapp6 plasmashell && plasmashell &
```

> 提示：`cmake --preset vcpkg` 已把安装前缀设为 `~/.local`。
> 如果系统自带 QtWebEngine，不要启用 vcpkg 的 `qtwebengine` feature（可避免数小时的编译）。

### 使用方法

1. 安装完成后，右键桌面 → 配置桌面和壁纸
2. 在壁纸类型中选择 **HTML Wallpaper**
3. 在设置页面填写你要显示的 HTML 页面 URL：
   - 本地文件：使用 `file:///home/你的用户名/path/to/page.html`
   - 远程网页：直接输入 URL，例如 `https://example.com`
4. （可选）调整缩放因子以适应你的屏幕
5. 如果使用自签名 HTTPS 网站，勾选 "允许不安全 HTTPS"

### 示例

项目提供了一个测试页面，你可以使用这个路径测试交互功能：

```text
file:///home/你的用户名/path/to/HTMLWallpaper/examples/test.html
```

这个测试页面包含：

- 实时时钟
- 可点击的计数器按钮
- 可跳转的链接

如果按钮能正常点击，说明鼠标透传工作正常。

### 提示

- **鼠标交互**：本插件已启用鼠标事件透传，HTML 内容可以正常接收点击、滚轮等事件
- **性能**：复杂的动画和 JavaScript 可能会消耗一定的系统资源
- **本地文件**：如果你使用本地 HTML 文件，可以配合 JavaScript 实现动态壁纸、时钟、监控等功能
- **透明度**：如果你的 HTML 页面背景是透明的，壁纸会显示桌面背景色

### 卸载

删除已安装的插件文件：

```bash
rm -rf ~/.local/share/plasma/wallpapers/com.github.Moon-Haze.htmlwallpaper
kquitapp6 plasmashell && plasmashell &
```

### 致谢

原始项目由 [Marcel Richter](https://github.com/Marcel1202) 创建。本版本针对 KDE Plasma 6 进行了优化，并添加了鼠标交互支持。

---

<a id="english"></a>

## English Description

This is a KDE Plasma 6 wallpaper plugin that allows you to set any HTML page as your desktop wallpaper with mouse interaction support.

### Features

- ✅ Set any local HTML file or remote webpage as wallpaper
- ✅ Mouse interaction support (click, scroll, etc.)
- ✅ Zoom adjustment
- ✅ Allow insecure HTTPS connections (self-signed certificates)
- ✅ Auto-play media (no user gesture required)

### System Requirements

- KDE Plasma 6.0 or higher
- QtWebEngine

### Building

Dependencies: KDE Plasma 6 development packages, Qt 6.10+ (with QtWebEngine), and vcpkg.

```bash
# 1. Point vcpkg at your vcpkg root (provides ECM)
export VCPKG_ROOT=/path/to/vcpkg

# 2. Configure using the vcpkg + system KF6 preset
cmake --preset vcpkg

# 3. Build and install
cmake --build --preset vcpkg
cmake --install build

# 4. Restart plasmashell to load the plugin
kquitapp6 plasmashell && plasmashell &
```

> Note: `cmake --preset vcpkg` already sets the install prefix to `~/.local`.
> If your system ships QtWebEngine, keep the vcpkg `qtwebengine` feature disabled to avoid hours of compilation.

### Usage

1. After installation, right-click desktop → Configure Desktop and Wallpaper
2. Select **HTML Wallpaper** as the wallpaper type
3. Enter the HTML page URL you want to display in the settings page:
   - Local file: use `file:///home/your-username/path/to/page.html`
   - Remote webpage: just enter the URL, e.g. `https://example.com`
4. (Optional) Adjust the zoom factor to fit your screen
5. If using a self-signed HTTPS website, check "Allow insecure HTTPS"

### Example

The project includes a test page, you can use this path to test interaction:

```text
file:///home/your-username/path/to/HTMLWallpaper/examples/test.html
```

This test page includes:

- Real-time clock
- Clickable counter button
- Clickable links

If buttons work correctly, mouse passthrough is working.

### Notes

- **Mouse Interaction**: This plugin enables mouse event passthrough, so HTML content can receive click, wheel and other events normally
- **Performance**: Complex animations and JavaScript may consume some system resources
- **Local Files**: If you use local HTML files, you can create dynamic wallpapers, clocks, system monitors, etc. with JavaScript
- **Transparency**: If your HTML page has a transparent background, the wallpaper will show your desktop background color

### Uninstall

Remove the installed plugin files:

```bash
rm -rf ~/.local/share/plasma/wallpapers/com.github.Moon-Haze.htmlwallpaper
kquitapp6 plasmashell && plasmashell &
```

### Credits

Original project created by [Marcel Richter](https://github.com/Marcel1202). This version is optimized for KDE Plasma 6 with added mouse interaction support.

### License

LGPLv2+
