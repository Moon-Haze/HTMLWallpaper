/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2019 David Redondo <kde@david-redondo.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

/**
 * HTML 壁纸缩略图网格（com.github.moon_haze.htmlwallpaper 模式中栏）。
 *
 * 展示 gridModel（C++ WallpaperModel 单文件夹 或 AllWallpapersModel 合并）
 * 缩略图网格；点击某项把选中壁纸状态写入
 * view.model.selectedIndex = index（选中行，选中态纯 UI 不落盘）并使当前
 * 项高亮（wallpapersGrid.view.currentIndex = index，见 WallpaperDelegate.onClicked）。
 */
Item {
    id: thumbnails
    // 暴露底层 GridView，供外部滚动到指定项
    property alias view: wallpapersGrid.view

    // 注入的解析器实例（由调用方 config.qml 传入）
    required property QtObject wallpaperController

    property var previewSize: {
        const baseSize = Kirigami.Units.gridUnit * 22;
        const preferredSize = Qt.size(Screen.width / 8, Screen.height / 8);
        const aspectRatio = Screen.width / Screen.height;

        // 横向屏：宽不足下限则以下限为准
        if (aspectRatio >= 1.0) {
            if (preferredSize.width >= baseSize) {
                return preferredSize;
            } else {
                return Qt.size(baseSize, baseSize / aspectRatio);
            }
        } else {
            // 纵向屏：高不足下限则以下限为准
            if (preferredSize.height >= baseSize) {
                return preferredSize;
            } else {
                return Qt.size(baseSize * aspectRatio, baseSize);
            }
        }
    }

    // 当前网格 model：全部 → controller.allModel()（懒建合并）；单文件夹 → controller.modelFor(activeFolder)
    property var gridModel: null

    // 依 activeFolder 重新计算 gridModel，并滚回顶部、清空选中高亮
    // function refreshModel() {
    //     if (!wallpaperController) {
    //         gridModel = null;
    //         return;
    //     }
    //     gridModel = activeFolder.length === 0
    //         ? wallpaperController.allModel()
    //         : wallpaperController.modelFor(activeFolder);
    //     wallpapersGrid.view.currentIndex = -1;
    //     // 选中态与 currentIndex 对齐：切组后清掉残留高亮。typeof 守卫兼容
    //     // 测试 mock 的 JS 数组（数组无 selectedIndex 属性）。
    //     if (gridModel && typeof gridModel.selectedIndex !== "undefined") {
    //         gridModel.selectedIndex = -1;
    //     }
    //     wallpapersGrid.view.positionViewAtIndex(0, ListView.Beginning);
    // }

    // controller.activeModel 变化（点击文件夹/全部标签）→ 清空选中高亮：
    // model 替换时 GridView 不自动复位 currentIndex，需显式归 -1。
    // 选中态与 currentIndex 对齐：切组后清掉残留高亮（typeof 守卫兼容
    // 测试 mock 的 JS 数组，数组无 selectedIndex 属性）。
    Connections {
        target: wallpaperController
        function onActiveModelChanged() {
            wallpapersGrid.view.currentIndex = -1;
            const m = wallpapersGrid.view.model;
            if (m && typeof m.selectedIndex !== "undefined") {
                m.selectedIndex = -1;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // —— 工具栏
        Kirigami.InlineViewHeader {
            Layout.fillWidth: true
            text: i18nd("plasma_wallpaper_org.kde.image", "Images")
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Kirigami.Theme.inherit: false
            Kirigami.Theme.colorSet: Kirigami.Theme.View
            color: Kirigami.Theme.backgroundColor

            KCM.GridView {
                id: wallpapersGrid
                anchors.fill: parent

                framedView: false

                // 直接挂模型，节省缩略图下方标签的额外空间
                view.model: wallpaperController.activeModel

                // 单元格尺寸随屏幕宽高比调整，保持缩略图比例不拉伸
                view.implicitCellWidth: {
                    const factor = Screen.width / Screen.height; // As a pct of screen height
                    const intendedLength = Kirigami.Units.gridUnit * (Kirigami.Settings.isMobile ? 10 : 6);
                    return factor * intendedLength + Kirigami.Units.smallSpacing * 2
                }
                view.implicitCellHeight: {
                    const intendedLength = Kirigami.Units.gridUnit * (Kirigami.Settings.isMobile ? 10 : 6);
                    return intendedLength + Kirigami.Units.smallSpacing * 2 + Kirigami.Units.gridUnit * 3
                }

                // 复用项视图实例以提升滚动性能
                view.reuseItems: true

                // 网格项使用 WallpaperDelegate，并传入配色、预览采样尺寸与解析器实例
                view.delegate: WallpaperDelegate {
                    wallpaperController: thumbnails.wallpaperController
                    // 计算缩略图采样尺寸：太小会糊，按屏幕 1/8 起，下限一档
                    previewSize: thumbnails.previewSize
                    // 点击行为：wallpaperController && model.path 时响应——把选中行写入
                    // view.model.selectedIndex（合并 model 跨源转发到所属文件夹源），
                    // 并让当前项高亮跟随点击项
                    onClicked: {
                        // console.log("WallpaperDelegate clicked:", model.name, model.path,model.preview, model.file, "at index", index);

                        if (model.path) {
                            view.model.selectedIndex = index;
                            view.currentIndex = index;
                            wallpaperController.selectWallpaper = model.file;
                            console.log("Selected wallpaper:", model.file, "at index", index);
                        }
                    }
                }
            }
        }
    }
}
