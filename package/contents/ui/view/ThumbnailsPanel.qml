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
 * 展示 htmlWallpaper.wallpapers（C++ WallpaperModel）缩略图网格；点击某项
 * 应用该壁纸（htmlWallpaper.selectWallpaper = model.file）并使当前项高亮
 * （wallpapersGrid.view.currentIndex = index，见 WallpaperDelegate.onClicked）。
 */
Item {
    id: thumbnails
    // 暴露底层 GridView，供外部滚动到指定项
    property alias view: wallpapersGrid.view


    // 注入的解析器实例（由调用方 config.qml 传入）
    property QtObject htmlWallpaper: null

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

    // 当前选中的扫描根 key（"" = 全部）。由调用方 config.qml 注入绑定。
    property string activeFolder: ""
    // 当前网格 model：全部 → controller.allModel()（懒建合并）；单文件夹 → controller.modelFor(activeFolder)
    property var gridModel: null

    // 依 activeFolder 重新计算 gridModel，并滚回顶部、清空选中高亮
    function refreshModel() {
        if (!htmlWallpaper) {
            gridModel = null;
            return;
        }
        gridModel = activeFolder.length === 0
            ? htmlWallpaper.allModel()
            : htmlWallpaper.modelFor(activeFolder);
        wallpapersGrid.view.currentIndex = -1;
        wallpapersGrid.view.positionViewAtIndex(0, ListView.Beginning);
    }

    onActiveFolderChanged: refreshModel()
    onHtmlWallpaperChanged: refreshModel()

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
                view.model: thumbnails.gridModel

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
                    htmlWallpaper: thumbnails.htmlWallpaper
                    // 计算缩略图采样尺寸：太小会糊，按屏幕 1/8 起，下限一档
                    previewSize: thumbnails.previewSize
                    // 点击行为：htmlWallpaper && model.path 时响应——设置
                    // selectWallpaper = model.file，并让当前项高亮跟随点击项
                    onClicked: {
                        if (htmlWallpaper && model.path) {
                            htmlWallpaper.selectWallpaper = model.file;
                            wallpapersGrid.view.currentIndex = index;
                            console.log("Selected wallpaper:", model.file, "at index", index);
                        }
                    }
                }
            }
        }
    }
}
