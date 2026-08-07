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
import org.kde.newstuff as NewStuff
import org.kde.kitemmodels as KItemModels

/**
 * 壁纸缩略图网格（图片模式与幻灯片/HTML 模式共用）。
 *
 * - 单图模式（org.kde.image）：展示用户壁纸库，点击某张直接设为壁纸；
 * - 幻灯片/HTML 模式（com.github.Moon-Haze.htmlwallpaper）：展示可选幻灯片，
 *   每项带勾选框，勾选集合决定轮播内容。
 * 工具栏提供“添加 / 获取新壁纸 / 全选 / 全不选”操作。
 */
Item {
    id: thumbnailsComponent
    anchors.fill: parent

    // 暴露底层 GridView，供外部滚动到指定项
    property alias view: wallpapersGrid.view
    property var screenSize: Qt.size(Screen.width, Screen.height)

    // 供网格使用的数据模型：
    // - 单图模式：排序后的用户壁纸模型（sortedWallpaperModel）
    // - 幻灯片模式：ImageBackend 提供的 slideFilterModel（含勾选状态）
    readonly property QtObject imageModel: (configDialog.currentWallpaper === "org.kde.image") ? sortedWallpaperModel : imageWallpaper.slideFilterModel

    // 对 imageWallpaper.wallpaperModel 做不区分大小写的字母排序
    KItemModels.KSortFilterProxyModel  {
        id: sortedWallpaperModel
        sortRole: Qt.DisplayRole
        sortCaseSensitivity: Qt.CaseInsensitive
        sortColumn: 0
        sourceModel: (configDialog.currentWallpaper === "org.kde.image") ? imageWallpaper.wallpaperModel : null
        // 在排序后的模型中查找某张图片的索引（做源/代理索引映射）
        function indexOf(image : string) : int {
            if (!sourceModel) {
                return -1
            }
            const idx = sourceModel.indexOf(image)

            if (idx < 0) {
                return idx
            }

            const sourceIndex = sourceModel.index(idx, 0)
            return mapFromSource(sourceIndex).row
        }
        // 打开某个列表项对应的文件夹（反向映射回源模型再调用）
        function openContainingFolder(listIndex : int) {
            if (sourceModel) {
                sourceModel.openContainingFolder(mapToSource(index(listIndex, 0)).row)
            }
        }
    }


    // 监听壁纸库加载完成：若当前选中的图片不在模型里，自动补加
    Connections {
        target: imageWallpaper
        function onLoadingChanged(loading: bool) {
            if (loading) {
                return;
            }
            // 单图模式下，确保 cfg_Image 指向的图片存在于用户壁纸库中
            if (configDialog.currentWallpaper === "org.kde.image" && imageModel.indexOf(cfg_Image) < 0) {
                imageWallpaper.addUsersWallpaper(cfg_Image);
            }
            wallpapersGrid.resetCurrentIndex();
        }
    }

    // 监听“添加壁纸完成”信号：滚动回顶部以展示新加入的图片
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
                // “添加图片…”：仅单图模式可见，弹出文件选择框
                Kirigami.Action {
                    icon.name: "list-add-symbolic"
                    text: i18ndc("plasma_wallpaper_org.kde.image", "@action:button the thing being added is an image file", "Add…")
                    Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Add Wallpaper Image…")
                    visible: configDialog.currentWallpaper == "org.kde.image"
                    onTriggered: root.openChooserDialog();
                },
                // “获取新壁纸…”：通过 KNewStuff 下载壁纸包
                NewStuff.Action {
                    configFile: Kirigami.Settings.isMobile ? "wallpaper-mobile.knsrc" : "wallpaper.knsrc"
                    text: i18ndc("plasma_wallpaper_org.kde.image", "@action:button the new things being gotten are wallpapers", "Get New…")
                    Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Get New Wallpaper Images…")
                    displayHint: Kirigami.DisplayHint.KeepVisible
                    viewMode: NewStuff.Page.ViewMode.Preview
                },
                // “全选”：批量勾选所有幻灯片（仅 HTMLWallpaper 模式）
                Kirigami.Action {
                    icon.name: "edit-select-all-symbolic"
                    shortcut: StandardKey.SelectAll
                    text: i18ndc("plasma_wallpaper_org.kde.image", "@action:button the things being selected are wallpapers", "Select All")
                    Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Select All Slides")
                    displayHint: Kirigami.DisplayHint.KeepVisible
                    visible: configDialog.currentWallpaper == "com.github.Moon-Haze.htmlwallpaper"
                    onTriggered: thumbnailsComponent.imageModel.selectAllSlides();
                },
                // “全不选”：取消勾选全部幻灯片
                Kirigami.Action {
                    icon.name: "edit-select-none-symbolic"
                    shortcut: StandardKey.Deselect
                    text: i18ndc("plasma_wallpaper_org.kde.image", "@action:button the things being unselected are wallpapers", "Select None")
                    Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Unselect All Slides")
                    displayHint: Kirigami.DisplayHint.KeepVisible
                    visible: configDialog.currentWallpaper == "com.github.Moon-Haze.htmlwallpaper"
                    onTriggered: thumbnailsComponent.imageModel.deselectAllSlides();
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

                // 把当前选中项指向 cfg_Image 对应的缩略图
                function resetCurrentIndex() {
                    //that min is needed as the module will be populated in an async way
                    //and only on demand so we can't ensure it already exists
                    // 取 min 是因为模型是异步加载的，索引可能暂时越界
                    if (configDialog.currentWallpaper === "org.kde.image") {
                        wallpapersGrid.view.currentIndex = Qt.binding(() => configDialog.currentWallpaper === "org.kde.image" ?  Math.min(imageModel.indexOf(cfg_Image), imageModel.count - 1) : 0);
                    }
                }

                //kill the space for label under thumbnails
                // 直接挂模型，节省缩略图下方标签的额外空间
                view.model: thumbnailsComponent.imageModel

                //set the size of the cell, depending on Screen resolution to respect the aspect ratio
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

                // 网格项使用 WallpaperDelegate，并传入配色与预览采样尺寸
                view.delegate: WallpaperDelegate {
                    color: cfg_Color
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

    // 单图模式下选中了非默认壁纸时高亮网格
    KCM.SettingHighlighter {
        target: wallpapersGrid
        highlight: configDialog.currentWallpaper === "org.kde.image" && cfg_Image != cfg_ImageDefault
    }
}
