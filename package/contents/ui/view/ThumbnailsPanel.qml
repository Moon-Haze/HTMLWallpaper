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
                view.currentIndex: wallpaperController.activeIndex
                // 网格项使用 WallpaperDelegate，并传入配色、预览采样尺寸与解析器实例
                view.delegate: WallpaperDelegate {
                    wallpaperController: thumbnails.wallpaperController
                    // 计算缩略图采样尺寸：太小会糊，按屏幕 1/8 起，下限一档
                    previewSize: thumbnails.previewSize
                    // 点击行为
                    onClicked: {
                        wallpaperController.activeIndex = index;
                    }
                }
            }
        }
    }
}
