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
 * 展示 htmlWallpaper.wallpapers（C++ WallpaperListModel），每项带单选按钮，
 * 唯一勾选项为当前轮播壁纸（互斥选择，见 setExclusiveChecked）。
 */
Item {
    id: thumbnailsComponent
    anchors.fill: parent

    // 暴露底层 GridView，供外部滚动到指定项
    property alias view: wallpapersGrid.view
    property var screenSize: Qt.size(Screen.width, Screen.height)
    // 注入的解析器实例（由 SlideshowComponent 传入）
    property QtObject htmlWallpaper: null

    // 供网格使用的数据模型：解析器扫描到的壁纸列表（含勾选状态）
    readonly property QtObject imageModel: htmlWallpaper ? htmlWallpaper.wallpapers : null

    // 监听"添加壁纸完成"信号：滚动回顶部以展示新加入的壁纸
    Connections {
        target: root
        function onWallpaperBrowseCompleted() {
            // Scroll to top to view added images
            wallpapersGrid.view.positionViewAtIndex(0, GridView.Beginning);
            wallpapersGrid.resetCurrentIndex(); // BUG 455129
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // —— 工具栏（无法作为 GridView 的 header 挂载，见 QTBUG-117035）——
        // FIXME: can't make it a header of the grid view due to the lack of a
        // headerPositioning: property; see https://bugreports.qt.io/browse/QTBUG-117035.
        Kirigami.InlineViewHeader {
            Layout.fillWidth: true
            text: i18nd("plasma_wallpaper_org.kde.image", "Images")
            actions: [
                // "应用"按钮：把当前唯一勾选项应用为轮播壁纸（写 cfg_DisplayPage + 解析参数）
                Kirigami.Action {
                    icon.name: "applyWallpaper"
                    text: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Apply")
                    Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Apply Selected Wallpaper")
                    displayHint: Kirigami.DisplayHint.KeepVisible
                    onTriggered: {
                        // 找到当前唯一勾选项；用户取消了全部勾选时安全跳过
                        for (let i = 0; i < thumbnailsComponent.imageModel.count; i++) {
                            const item = thumbnailsComponent.imageModel.get(i);
                            if (item.checked) {
                                if (thumbnailsComponent.htmlWallpaper && item.path) {
                                    thumbnailsComponent.htmlWallpaper.parseWallpaper(item.path);
                                    root.cfg_DisplayPage = item.source; // source == entry
                                }
                                break;
                            }
                        }
                    }
                }
            ]
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

                // 模型异步加载后把选中项重置回第一项
                function resetCurrentIndex() {
                    wallpapersGrid.view.currentIndex = 0;
                }

                // 直接挂模型，节省缩略图下方标签的额外空间
                view.model: thumbnailsComponent.imageModel

                // 单元格尺寸随屏幕宽高比调整，保持缩略图比例不拉伸
                view.implicitCellWidth: {
                    const factor = screenSize.width / screenSize.height; // As a pct of screen height
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
                    htmlWallpaper: thumbnailsComponent.htmlWallpaper
                    // 计算缩略图采样尺寸：太小会糊，按屏幕 1/8 起，下限一档
                    previewSize: {
                        // Set minimum image sample size, otherwise it's very blurry
                        const baseSize = Kirigami.Units.gridUnit * 22;
                        const preferredSize = Qt.size(thumbnailsComponent.screenSize.width / 8, thumbnailsComponent.screenSize.height / 8);
                        const aspectRatio = thumbnailsComponent.screenSize.width / thumbnailsComponent.screenSize.height;

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
                }
            }
        }
    }
}
