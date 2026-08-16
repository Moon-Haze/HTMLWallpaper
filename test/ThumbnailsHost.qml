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
 * 子面板同名（wallpaperController）的控制器子对象，经 root 别名属性
 * （wallpaperControllerController）暴露给 ThumbnailsPanel，验证组件内声明式
 * binding 下经别名引用能正确解析到外层控制器，而非被面板自身同名属性
 * 遮蔽成自引用 Binding loop。
 *
 * mock（wallpaperController）模拟新架构：单文件夹 ListModel（modelA）经
 * modelFor/allModel 返回，供 ThumbnailsPanel 全部模式取全部数据。
 */
ColumnLayout {
    id: root

    // 经别名把外层控制器暴露给子组件（名避开面板自身属性名 wallpaperController）
    property alias wallpaperControllerController: wallpaperController

    // 模拟 config.qml 外层控制器（WallpaperController { id: wallpaperController }）
    QtObject {
        id: wallpaperController
        // 选中壁纸状态：ListModel 的 selectedIndex（mock 模拟 model 层属性）
        // 单文件夹 model：ListModel（真 model，role 可用）。
        // QtObject 无 default property，ListModel 需用 property 声明（否则
        // 直接作子对象会报 "Cannot assign to non-existent default property"）。
        property ListModel modelA: ListModel {
            property int selectedIndex: -1
            ListElement { name: "a"; title: "a"; path: "file:///a.html"; file: "file:///a.html"; preview: "" }
        }
        // 新架构：modelFor/allModel 返回该文件夹 model
        function modelFor(url) { return modelA; }
        function allModel() { return modelA; }
    }

    // 暴露面板供测试断言
    property Item panel: null

    View.ThumbnailsPanel {
        id: panelItem
        // 经 root 别名引用外层控制器，避开自身同名属性遮蔽
        wallpaperController: root.wallpaperControllerController
        width: 600
        height: 400
    }

    Component.onCompleted: {
        root.panel = panelItem
    }
}
