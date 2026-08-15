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
 * scanUrlsView.selectedFolder（经 root 别名引用外层控制器避开同名遮蔽）。
 * 暴露 scanUrlsView/thumbnails 供测试断言。
 */
ColumnLayout {
    id: root

    // offscreen 下显式尺寸：让 ScanPathsPanel 内部 ListView 有布局空间、
    // 从而实例化 delegate（测试触发其 clicked 需要真实 delegate 实例）
    width: 800
    height: 400

    property alias htmlWallpaperController: htmlWallpaper
    // 暴露两个面板供测试断言
    property Item scanUrlsView: null
    property Item thumbnails: null

    // 模拟 config.qml 外层控制器（WallpaperController + WallpaperModel）
    QtObject {
        id: htmlWallpaper
        property string selectWallpaper: ""
        // scanUrls：两个扫描根
        property var scanUrls: ["file:///root/a", "file:///root/b"]

        // 模拟 WallpaperModel：JS 数组 + byKey 按 key 返回不同组
        property var wallpapers: (function () {
            const all = [
                { name: "a1", title: "a1", path: "file:///a1.html", file: "file:///a1.html", preview: "" },
                { name: "a2", title: "a2", path: "file:///a2.html", file: "file:///a2.html", preview: "" },
                { name: "b1", title: "b1", path: "file:///b1.html", file: "file:///b1.html", preview: "" }
            ];
            const groupA = [all[0], all[1]];
            const groupB = [all[2]];
            // byKey 模拟：key 归一化（去末尾斜杠）后返回对应组
            all.byKey = function (url) {
                const key = url.replace(/\/+$/, "");
                if (key === "file:///root/a") return groupA;
                if (key === "file:///root/b") return groupB;
                return [];
            };
            all.get = function (i) { return all[i]; };
            // 模拟 WallpaperModel.folderName：去末尾斜杠后取最后一段
            all.folderName = function (url) {
                const s = String(url).replace(/\/+$/, "");
                return s.substring(s.lastIndexOf("/") + 1);
            };
            // 模拟 WallpaperModel.parentPath：去末尾斜杠后去掉最后一段
            all.parentPath = function (url) {
                const s = String(url).replace(/\/+$/, "");
                return s.substring(0, s.lastIndexOf("/"));
            };
            return all;
        })()

        function addScanPath(url) { scanUrls.push(String(url)); }
        function removeScanPath(url) {
            scanUrls = scanUrls.filter(function (u) { return u !== String(url); });
        }
    }

    View.ScanPathsPanel {
        id: scanUrlsPanel
        Layout.preferredWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredHeight: 320
        htmlWallpaper: htmlWallpaper
    }

    View.ThumbnailsPanel {
        id: thumbnailsPanel
        Layout.fillWidth: true
        Layout.fillHeight: true
        htmlWallpaper: root.htmlWallpaperController
        // 标签联动（复刻 config.qml）
        activeFolder: scanUrlsPanel.selectedFolder
        width: 600
        height: 400
    }

    Component.onCompleted: {
        root.scanUrlsView = scanUrlsPanel;
        root.thumbnails = thumbnailsPanel;
    }
}
