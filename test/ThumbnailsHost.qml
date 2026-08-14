/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import "../package/contents/ui/view" as View

/**
 * 模拟 config.qml 的嵌套结构，用于验证 ThumbnailsPanel 的控制器绑定解析。
 *
 * 复刻 config.qml 的关键结构：根 ColumnLayout(id: root) 内声明一个与
 * 子面板同名（htmlWallpaper）的控制器子对象，经 root 别名属性
 * （htmlWallpaperController）暴露给 ThumbnailsPanel，验证组件内声明式
 * binding 下经别名引用能正确解析到外层控制器，而非被面板自身同名属性
 * 遮蔽成自引用 Binding loop。
 */
ColumnLayout {
    id: root

    // 经别名把外层控制器暴露给子组件（名避开面板自身属性名 htmlWallpaper）
    property alias htmlWallpaperController: htmlWallpaper

    // 模拟 config.qml 外层控制器（WallpaperController { id: htmlWallpaper }）
    QtObject {
        id: htmlWallpaper
        property string selectWallpaper: ""
        property ListModel wallpapers: ListModel {
            ListElement { name: "a"; title: "a"; path: "file:///a.html"; file: "file:///a.html"; preview: "" }
        }
    }

    // 暴露面板供测试断言
    property Item panel: null

    View.ThumbnailsPanel {
        id: panelItem
        // 经 root 别名引用外层控制器，避开自身同名属性遮蔽
        htmlWallpaper: root.htmlWallpaperController
        width: 600
        height: 400
    }

    Component.onCompleted: {
        root.panel = panelItem
    }
}
