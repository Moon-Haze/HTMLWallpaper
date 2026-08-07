# HTMLWallpaper 测试指南

> 针对 KDE Plasma 6 Wallpaper 包（`KPackageStructure: Plasma/Wallpaper`）的测试方法汇总。
> 环境基线：Plasma **6.7.4**（CachyOS / pacman），Qt **6**，包插件 ID `com.github.Moon-Haze.htmlwallpaper`。

---

## 目录

- [HTMLWallpaper 测试指南](#htmlwallpaper-测试指南)
  - [目录](#目录)
  - [一、环境现状与快速上手](#一环境现状与快速上手)
    - [切换壁纸（命令行方式）](#切换壁纸命令行方式)
    - [关键验证路径（对应代码位置）](#关键验证路径对应代码位置)
  - [二、端到端测试（真实桌面集成）](#二端到端测试真实桌面集成)
    - [步骤](#步骤)
  - [三、开发迭代测试（symlink 快速重载，日常推荐）](#三开发迭代测试symlink-快速重载日常推荐)
    - [一次性设置](#一次性设置)
    - [每次改 QML 后的重载（plasmashell 不会自动热重载）](#每次改-qml-后的重载plasmashell-不会自动热重载)
  - [四、组件级预览（qml6 单独跑 UI）](#四组件级预览qml6-单独跑-ui)
    - [先说限制（重要）](#先说限制重要)
    - [测试壳（mock wallpaperInterface）](#测试壳mock-wallpaperinterface)
    - [运行](#运行)
  - [五、排错与日志](#五排错与日志)
  - [六、针对 slide-test 分支的工作闭环](#六针对-slide-test-分支的工作闭环)
    - [可选：一键重载脚本 `reload.sh`](#可选一键重载脚本-reloadsh)

---

## 一、环境现状与快速上手

- 壁纸包**已安装到系统目录**：`/usr/share/plasma/wallpapers/com.github.Moon-Haze.htmlwallpaper`（root 所有）。
- 桌面配置文件 `~/.config/plasma-org.kde.plasma.desktop-appletsrc` 中**保留过**本壁纸的使用记录：

  ```ini
  [Containments][1][Wallpaper][com.github.Moon-Haze.htmlwallpaper][General]
  DisplayPage=/home/swix/Pictures/html/FallingCherry/index.html
  ```

- 但当前生效的是 `org.kde.image`。**最快的路径 = 切回本壁纸 → 应用 → 看效果。**

### 切换壁纸（命令行方式）

```bash
# 把 containment 1 的壁纸插件切回本插件
sed -i 's/^wallpaperplugin=org.kde.image/wallpaperplugin=com.github.Moon-Haze.htmlwallpaper/' \
    ~/.config/plasma-org.kde.plasma.desktop-appletsrc
plasmashell --replace &
```

### 关键验证路径（对应代码位置）

| 功能                | 代码位置                                             | 验证点                                                                |
| ------------------- | ---------------------------------------------------- | --------------------------------------------------------------------- |
| HTML 渲染铺满桌面   | `package/contents/ui/main.qml:29`（`WebEngineView`） | 页面是否铺满、有无黑底/白屏闪烁（`backgroundColor` 在 `main.qml:39`） |
| 配置读取            | `main.qml:35`（`url: configuration.DisplayPage`）    | 改 `DisplayPage` 后页面是否跟随                                       |
| 拖放 .html 设为壁纸 | `main.qml:23`（`onOpenUrlRequested`）                | 拖本地 html 到桌面是否生效                                            |
| 幻灯片 / 图像组件   | `ImageStackView.qml`、`SlideshowComponent.qml` 等    | 切换/动画/缩放是否正常                                                |

---

## 二、端到端测试（真实桌面集成）

### 步骤

**1. 应用到桌面**（二选一）

- **图形界面**：右键桌面 → **配置壁纸** → 选「HTML Wallpaper」→ 填写 HTML 页面 URL。
- **命令行**：用上面的 sed + `plasmashell --replace`。

**2. 手动回归清单**

- [ ] HTML 页面铺满桌面，无白屏闪烁，黑底正确
- [ ] 修改配置 `DisplayPage` 后页面正确切换
- [ ] 拖一个 `.html` 文件到桌面 → 自动设为壁纸
- [ ] 多屏时各屏幕正常渲染（`main.qml` 中 `profile` 共享同一 `ProfileProvider`）
- [ ] `InsecureHTTPS` 配置下自签名证书行为符合预期（`main.qml:42`）
- [ ] 页面加载失败时显示错误提示层（`main.qml:63`）

---

## 三、开发迭代测试（symlink 快速重载，日常推荐）

系统级安装每次改代码都要重装，太慢。**用 symlink 把源码直接绑到壁纸目录**，改动即落盘。

### 一次性设置

```bash
# 1. 先把包装到用户目录
kpackagetool6 -t Plasma/Wallpaper -i package/

# 2. 用 symlink 替换安装目录，指向源码
rm -rf ~/.local/share/plasma/wallpapers/com.github.Moon-Haze.htmlwallpaper
ln -s "$PWD/package" ~/.local/share/plasma/wallpapers/com.github.Moon-Haze.htmlwallpaper
```

> 安装后会自动生成 `~/.local/share/plasma/wallpapers/com.github.Moon-Haze.htmlwallpaper/metadata.json` 等文件。
> symlink 之后，你编辑源码里的任何 `.qml` / `metadata.json`，plasmashell 读到的是同一份文件。

### 每次改 QML 后的重载（plasmashell 不会自动热重载）

```bash
plasmashell --replace &
# 或更干净：
kquitapp6 plasmashell; plasmashell & disown
```

---

## 四、组件级预览（qml6 单独跑 UI）

### 先说限制（重要）

- `main.qml` 的根 `WallpaperItem` 是 **plasmashell 进程内注册的类型**，`qml6` 直接加载会报 `WallpaperItem is not a type`，**不能**用它做组件预览。
- `ImageStackView.qml` 依赖 C++ 类型 `Wallpaper.MediaProxy`（位于 `/usr/lib/qt6/qml/org/kde/plasma/wallpapers/image`，本机已装）。它能在 `qml6` 中加载，但无 plasmashell 后端时 `MediaProxy` 会走 `useSingleImageDefaults()` 兜底（`ImageStackView.qml:81`），**看不到真实图片**，只能验证布局与动画。
- 可独立预览且依赖少的组件：`ThumbnailsComponent.qml`、`SlideshowComponent.qml`、`WallpaperDelegate.qml`、`AddFileDialog.qml`。

### 测试壳（mock wallpaperInterface）

`WallpaperDelegate.qml` 等组件用弱类型 `QtObject` 接收 `wallpaperInterface`（见 `ImageStackView.qml:22` 注释，上游 autotest 就是这么做的），所以单独跑时喂一个 mock 即可：

```qml
// tests/Harness.qml
import QtQuick
import QtQuick.Window

Window {
    width: 1280; height: 720; visible: true; color: "#333"

    QtObject {                          // mock wallpaperInterface
        id: wallpaperInterface
        property color accentColor: "transparent"
        property bool loading: false
    }

    Loader {
        anchors.fill: parent
        source: "../package/contents/ui/ThumbnailsComponent.qml"
        onLoaded: {
            // 给 required property 喂测试数据，例如：
            // item.model = [ { imagePath: "file:///tmp/test.png" } ]
        }
    }
}
```

### 运行

```bash
mkdir -p tests
qml6 tests/Harness.qml
```

---

## 五、排错与日志

QML 语法/运行时错误打在 plasmashell 的 stderr：

```bash
# 前台启动，直接看报错（含 QML 错误行号）
kquitapp6 plasmashell; plasmashell
# 或看 systemd 日志
journalctl --user --no-pager -n 50 | grep -i qml
```

放大日志：

```bash
QT_LOGGING_RULES="qt.qml.*=true;kf.plasma.*=true" plasmashell --replace &
```

> ⚠️ `plasmoidviewer` 虽然已安装，但它面向 **Plasma/Applet 包结构**，不适用于 `Plasma/Wallpaper` 包，不要在上面浪费时间。

---

## 六、针对 slide-test 分支的工作闭环

当前分支在改 `ImageStackView` / `SlideshowComponent` 幻灯片逻辑，推荐闭环：

1. 按[第三节](#三开发迭代测试symlink-快速重载日常推荐)建立 symlink；
2. 用[第二节](#二端到端测试真实桌面集成)的命令切回本壁纸并设好 `DisplayPage`；
3. 每改一版 → `plasmashell --replace` → 切壁纸 / 改源看图 → 循环。

### 可选：一键重载脚本 `reload.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

PKG_ID="com.github.Moon-Haze.htmlwallpaper"
WALLPAPERS_DIR="$HOME/.local/share/plasma/wallpapers"

# 1. 首次或失效时重建 symlink
if [ ! -L "$WALLPAPERS_DIR/$PKG_ID" ]; then
    kpackagetool6 -t Plasma/Wallpaper -i package/
    rm -rf "$WALLPAPERS_DIR/$PKG_ID"
    ln -s "$PWD/package" "$WALLPAPERS_DIR/$PKG_ID"
    echo "[*] symlink 已建立"
fi

# 2. 切回本壁纸插件
sed -i "s/^wallpaperplugin=org.kde.image/wallpaperplugin=$PKG_ID/" \
    "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

# 3. 重载 plasmashell
plasmashell --replace &
disown
echo "[*] 已重载，等待 plasmashell 起来…"
```

使用：`chmod +x reload.sh && ./reload.sh`
