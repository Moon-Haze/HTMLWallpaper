/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import "../package/contents/ui/view" as View

/**
 * 模拟 config.qml 的左栏-中栏联动结构，用于验证标签切换。
 *
 * 复刻 config.qml 关键结构：根内声明控制器子对象，ScanPathsPanel 与
 * ThumbnailsPanel 并排，ThumbnailsPanel.activeFolder 绑定
 * scanPathsPanel.selectedFolder（经 root 别名引用外层控制器避开同名遮蔽）。
 * 暴露 scanPathsView/thumbnails 供测试断言。
 *
 * mock（wallpaperController）模拟新架构：每文件夹一个 model（groupA/groupB），
 * modelFor(url) 按 URL 返回对应组；allModel() 返回合并缓存数组。
 */
ColumnLayout {
    id: root

    // offscreen 下显式尺寸：让 ScanPathsPanel 内部 ListView 有布局空间、
    // 从而实例化 delegate（测试触发其 clicked 需要真实 delegate 实例）
    width: 800
    height: 400

    property alias wallpaperControllerController: wallpaperController
    // 暴露两个面板供测试断言
    property Item scanPathsView: null
    property Item thumbnails: null

    // 模拟 config.qml 外层控制器（新架构：modelFor/allModel）
    QtObject {
        id: wallpaperController
        // scanPaths：两个扫描根
        property var scanPaths: ["file:///root/a", "file:///root/b"]
        // 当前活动壁纸集合：由 ScanPathsPanel 点击驱动（文件夹 → modelFor 组；全部 → allModel）
        property var activeModel: null

        // 每文件夹一个 model：groupA / groupB
        property var groupA: [
            { name: "a1", title: "a1", path: "file:///a1.html", file: "file:///a1.html", preview: "" },
            { name: "a2", title: "a2", path: "file:///a2.html", file: "file:///a2.html", preview: "" }
        ]
        property var groupB: [
            { name: "b1", title: "b1", path: "file:///b1.html", file: "file:///b1.html", preview: "" }
        ]

        // 合并缓存：首次 allModel() 调用构建，之后返回同一引用（供引用相等断言）
        property var allModelCache: null
        function allModel() {
            if (allModelCache === null) {
                const all = [];
                for (const g of [groupA, groupB]) {
                    for (const e of g) {
                        all.push(e);
                    }
                }
                allModelCache = all;
            }
            return allModelCache;
        }

        // modelFor：key 归一化（去末尾斜杠）后返回对应组
        function modelFor(url) {
            const key = String(url).replace(/\/+$/, "");
            if (key === "file:///root/a") return groupA;
            if (key === "file:///root/b") return groupB;
            return [];
        }

        // 模拟 controller.folderName：去末尾斜杠后取最后一段
        function folderName(url) {
            const s = String(url).replace(/\/+$/, "");
            return s.substring(s.lastIndexOf("/") + 1);
        }
        // 模拟 controller.parentPath：去末尾斜杠后去掉最后一段
        function parentPath(url) {
            const s = String(url).replace(/\/+$/, "");
            return s.substring(0, s.lastIndexOf("/"));
        }

        function addScanPath(url) { scanPaths.push(String(url)); }
        function removeScanPath(url) {
            scanPaths = scanPaths.filter(function (u) { return u !== String(url); });
        }
    }

    View.ScanPathsPanel {
        id: scanPathsPanel
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: 320
        wallpaperController: wallpaperController
    }

    View.ThumbnailsPanel {
        id: thumbnailsPanel
        Layout.fillWidth: true
        Layout.fillHeight: true
        wallpaperController: root.wallpaperControllerController
        // 标签联动（复刻 config.qml）
        activeFolder: scanPathsPanel.selectedFolder
        width: 600
        height: 400
    }

    Component.onCompleted: {
        root.scanPathsView = scanPathsPanel;
        root.thumbnails = thumbnailsPanel;
    }
}
