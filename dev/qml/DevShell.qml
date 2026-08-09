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
 * 选中壁纸 / 调整参数 → 监听 cfg_DisplayPage / cfg_WallpaperProperties →
 * 同步给预览面板。
 */
ApplicationWindow {
    id: win
    // 大尺寸固定窗口：便于直接观察三栏 + 预览（屏幕 2560x1440）
    width: 1700
    height: 1100
    visible: true
    title: "HTML Wallpaper Config (dev)"

    // —— mock plasmashell/KCM 注入的上下文 ——

    // KDeclarative 国际化函数 mock（返回原文，与 qmltestrunner 的 mock 一致）
    property var i18n:  function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    // wallpaper.configuration：mock KConfigPropertyMap（main.cpp 注入的 C++
    // DevConfigMap）。必须用 C++ 动态属性——QML 静态属性不允许大写开头
    //（property string DisplayPage 会让整个组件静默加载失败），而真实
    // KConfigPropertyMap 的键都是大写开头（DisplayPage/PreviewImage/…）。
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

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // —— 左：config.qml 配置界面 ——
        Loader {
            id: configLoader
            Layout.preferredWidth: win.width * 0.6
            Layout.fillHeight: true

            // 以 KCM 同款方式注入 cfg_* 初始值（main.xml 默认值）
            Component.onCompleted: configLoader.setSource(
                "../../package/contents/ui/config.qml", {
                    cfg_SlidePaths: ["/usr/share/html-wallpapers"], cfg_SlidePathsDefault: [],
                    cfg_DisplayPage: "", cfg_DisplayPageDefault: "https://kde.org/",
                    cfg_WallpaperProperties: "{}", cfg_WallpaperPropertiesDefault: "{}"
                })
            // config.qml 加载状态 / 错误（Loader 失败错误默认不上屏）
            onStatusChanged: {
                if (configLoader.status === Loader.Ready && configLoader.item) {
                    // 初始同步：cfg_* 的 setSource 注入赋值不触发 onCfg_*Changed
                    // 信号（那是初始化非变更），必须在这里把初始值喂给预览，
                    // 否则预览停留在 about:blank（后续用户改动仍走 Connections 实时同步）
                    preview.displayPage = configLoader.item.cfg_DisplayPage;
                    preview.propertiesJson = configLoader.item.cfg_WallpaperProperties;
                }
                if (configLoader.status === Loader.Error && configLoader.sourceComponent) {
                    const errs = configLoader.sourceComponent.errors;
                    for (let i = 0; i < errs.length; ++i) {
                        console.log("[dev] config.qml 错误:", errs[i].toString());
                    }
                }
            }
        }

        // 分隔线
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: "#555"
        }

        // —— 右：HTML 壁纸实时预览 ——
        PreviewPanel {
            id: preview
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    // 选中壁纸 / 调参数 → 预览联动。
    // target 绑定 configLoader.item：加载完成后自动连上，之后 cfg_* 变化实时同步。
    Connections {
        target: configLoader.item
        function onCfg_DisplayPageChanged() {
            preview.displayPage = configLoader.item.cfg_DisplayPage;
        }
        function onCfg_WallpaperPropertiesChanged() {
            preview.propertiesJson = configLoader.item.cfg_WallpaperProperties;
        }
    }

    // dev 诊断：确认窗口尺寸与 config.qml 加载结果
    // （自截图由 main.cpp --screenshot 的 grabWindow 负责；QML grabToImage
    // 对 WebEngine 无效且报“item has no QML engine”，不再在 QML 层抓图）
    Component.onCompleted: {
        console.log("[dev] DevShell onCompleted: win=" + win.width + "x" + win.height
            + ", loader.status=" + configLoader.status
            + ", loader.item=" + configLoader.item);
    }
}
