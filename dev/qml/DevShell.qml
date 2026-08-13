/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * HTMLWallpaper 配置界面的独立调试壳（开发分支 dev/config-app）。
 *
 * 在 QML 层 mock 掉 plasmashell/KCM 注入的上下文，让 config.qml 原样跑在
 * 一个普通窗口里：
 *   - i18n*、wallpaper、appearanceRoot：经动态作用域被 Loader 加载的
 *     config.qml 继承（config.qml 未声明这些属性，只能走作用域）；
 *   - configDialog / cfg_*：config.qml **声明过**的属性，走 setSource 的
 *     初始属性注入（与 KCM 的 QQmlComponent initial property 机制一致）。
 *
 * 布局：左 60% 为 config.qml 三栏面板，右 40% 为 WebEngine 实时预览。
 * 选中壁纸 / 调整参数 → 监听 cfg_SelectWallpaper / cfg_WallpaperProperties →
 * 同步给预览面板。
 */
ApplicationWindow {
    id: win
    // 大尺寸固定窗口：便于直接观察三栏 + 预览（屏幕 2560x1440）
    width: 1700
    height: 1100
    visible: true
    title: "HTML Wallpaper Config"

    // —— mock plasmashell/KCM 注入的上下文 ——

    // KDeclarative 国际化函数 mock（返回原文，与 qmltestrunner 的 mock 一致）
    property var i18n:  function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    // wallpaper.configuration：mock KConfigPropertyMap（main.cpp 注入的 C++
    // DevConfigMap）。必须用 C++ 动态属性——QML 静态属性不允许大写开头
    //（property string SelectWallpaper 会让整个组件静默加载失败），而真实
    // KConfigPropertyMap 的键都是大写开头（SelectWallpaper/PreviewImage/…）。
    property var mockConfigMap: devConfigMap
    property var wallpaper: QtObject {
        property var configuration: devConfigMap
    }

    // configDialog：KCM 注入的上下文对象。config.qml 保留属性声明但纯 HTML
    // 模式下不再消费其 currentWallpaper；提供 mock 保持注入路径与真实一致。
    property var configDialog: QtObject {
        property string currentWallpaper: "com.github.moon_haze.htmlwallpaper"
    }

    // config.qml 的 twinFormLayouts 对齐依赖 ancestor appearanceRoot；
    // 代码里有 typeof 保护，缺省也能跑，这里提供空壳保证完整
    property var appearanceRoot: QtObject {
        property var parentLayout: null
    }
    // —— 左：config.qml 配置界面 ——
    Loader {
        id: configLoader
        
        anchors.fill: parent

        // 以 KCM 同款方式注入 cfg_* 初始值（main.xml 默认值）
        Component.onCompleted: configLoader.setSource(
            "../../package/contents/ui/config.qml", {
                cfg_ScanPaths: ["/usr/share/html-wallpapers"],
                cfg_SelectWallpaper: "https://kde.org/",
                cfg_WallpaperProperties: "{}"
            })
    }
    


    // dev 诊断：确认窗口尺寸与 config.qml 加载结果。
    // 用 Qt.callLater 延迟到本轮事件循环末尾再打印——直接在 onCompleted 打印时
    // Loader 可能尚未完成 setSource（status 误报 0/Null），延迟后才是真实结果。
    // （自截图由 main.cpp --screenshot 的 grabWindow 负责；QML grabToImage
    // 对 WebEngine 无效且报“item has no QML engine”，不再在 QML 层抓图）
    Component.onCompleted: {
        Qt.callLater(() => {
            console.log("[dev] DevShell loaded: win=" + win.width + "x" + win.height
                + ", loader.status=" + configLoader.status
                + ", loader.item=" + configLoader.item);
        });
    }
}
