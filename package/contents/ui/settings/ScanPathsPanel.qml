/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2019 David Redondo <kde@david-redondo.de>
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.wallpapers.image as PlasmaWallpaper

/**
 * HTML 壁纸配置面板（com.github.moon_haze.htmlwallpaper 模式下显示）。
 *
 * 上半部分：轮播排序方式（随机 / 按名称 / 按修改时间）、按文件夹分组；
 * 主体三栏布局：
 *   左栏：扫描目录（文件夹）列表，可增删、打开目录；
 *   中栏：ThumbnailsView 展示目录下的 HTML 壁纸网格（点选即应用）；
 *   右栏：PropertyPanel 编辑当前壁纸的协议参数（color/slider/combo/bool/…）。
 *
 * 数据源是 config.qml 注入的 HTMLBackend（C++）单实例：
 *   目录列表 ← htmlWallpaper.scanPaths；壁纸网格 ← htmlWallpaper.wallpapers；
 *   参数面板 ← 已随 HTMLBackend 解耦重构停用（见下方右栏 PropertyPanel 注释）；
 *   可配置属性表现在经 WallpaperItem::properties（WallpaperPropertyModel ListModel）
 *   的 get(i) / byKey(key) 暴露，不再有 currentWallpaper.general.properties。
 * 目录增删走 config 的 addScanPath/removeScanPath（只改 cfg_ScanPaths 持久化，
 * 由 scanPaths 绑定同步 htmlWallpaper → 重扫）。参数"可调不持久"：改动只更新
 * 面板会话内镜像，不写 cfg_WallpaperProperties、不应用到壁纸。
 *
 * For proper alignment, an ancestor **MUST** have id "appearanceRoot" and property "parentLayout"
 */
// —— 左栏：扫描目录（文件夹）列表 ——
ColumnLayout {
    
    property alias scanPaths: scanPathsView.model
    

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    QQC2.ScrollView {
        id: foldersScroll
        Layout.fillWidth: true
        Layout.fillHeight: true

        // 用主题背景色，视觉上把列表区与设置区区分开
        background: Rectangle {
            Kirigami.Theme.inherit: false
            Kirigami.Theme.colorSet: Kirigami.Theme.View
            color: Kirigami.Theme.backgroundColor
        }

        // 扫描目录列表：数据源是 htmlWallpaper.scanPaths（跟随 cfg_ScanPaths）
        ListView {
            id: scanPathsView
            headerPositioning: ListView.OverlayHeader
            // 悬浮标题栏，含“添加文件夹”按钮
            header: Kirigami.InlineViewHeader {
                width: scanPathsView.width
                text: i18nd("plasma_wallpaper_org.kde.image", "Folders")
                actions: [
                    Kirigami.Action {
                        icon.name: "list-add-symbolic"
                        text: i18ndc("plasma_wallpaper_org.kde.image", "@action button the thing being added is a folder", "Add…")
                        Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Add Folder…")
                        onTriggered: root.openChooserDialog()
                    }
                ]
            }
            
            delegate: Kirigami.SubtitleDelegate {
                id: baseListItem
                // 字符串数组 model：modelData 直接是路径字符串
                required property string modelData

                width: scanPathsView.width
                // Don't need a highlight or hover effects
                // 列表项无需悬停高亮效果
                hoverEnabled: false
                down: false

                // 主标题只显示文件夹名（去掉末尾斜杠后取最后一段）
                text: {
                    var strippedPath = String(modelData).replace(/\/+$/, "");
                    return strippedPath.split('/').pop()
                }
                // Subtitle: the path to the folder
                // 副标题显示父目录路径
                subtitle: {
                    var strippedPath = String(modelData).replace(/\/+$/, "");
                    return strippedPath.replace(/\/[^\/]*$/, '');;
                }

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.TitleSubtitle {
                        Layout.fillWidth: true
                        // Header: the folder
                        // 标题：文件夹名；副标题：路径
                        title: baseListItem.text
                        subtitle: baseListItem.subtitle
                    }

                    // 从扫描列表移除该文件夹
                    QQC2.ToolButton {
                        icon.name: "edit-delete-remove-symbolic"
                        text: i18nd("plasma_wallpaper_org.kde.image", "Remove Folder")
                        display: QQC2.Button.IconOnly
                        onClicked: root.removeScanPath(baseListItem.modelData)

                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }

                    // 在文件管理器中打开该文件夹
                    QQC2.ToolButton {
                        icon.name: "document-open-folder"
                        text: i18nd("plasma_wallpaper_org.kde.image", "Open Folder…")
                        display: QQC2.Button.IconOnly
                        onClicked: Qt.openUrlExternally(baseListItem.modelData)

                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: text
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }

            // 未配置任何文件夹时显示空态提示
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - (Kirigami.Units.largeSpacing * 4)
                visible: scanPathsView.count === 0
                text: i18nd("plasma_wallpaper_org.kde.image", "There are no wallpaper locations configured")
            }
        }
    }
}


