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

    // 监听解析器"扫描完成"信号：模型重扫后重建 currentIndex 绑定，
    // 让高亮跟随 cfg_DisplayPage（与 config.qml 的 checked 对齐互不干扰）
    Connections {
        target: htmlWallpaper
        function onScanFinished() {
            wallpapersGrid.resetCurrentIndex();
        }
    }

    // 组件就绪即建立首次绑定；模型异步填充后 count 变化会自动重算
    Component.onCompleted: wallpapersGrid.resetCurrentIndex()

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

                // 查找 cfg_DisplayPage 对应项在模型中的索引；空模型或无匹配回退 0
                function indexOfDisplayPage() {
                    const model = thumbnailsComponent.imageModel;
                    if (!model || model.count === 0) {
                        return 0;
                    }
                    for (let i = 0; i < model.count; i++) {
                        if (model.get(i).source === root.cfg_DisplayPage) {
                            return i;
                        }
                    }
                    return 0;
                }

                // 重建 currentIndex 绑定：高亮始终跟随 cfg_DisplayPage（配置驱动高亮）
                function resetCurrentIndex() {
                    wallpapersGrid.view.currentIndex = Qt.binding(() => indexOfDisplayPage());
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
