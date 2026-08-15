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
 * HTML 壁纸扫描目录列表（左栏）。
 *
 * 展示并管理 htmlWallpaper.scanUrls（QStringList）中的扫描目录，
 * 支持增删与在文件管理器中打开目录；未配置目录时显示空态提示。
 *
 * 数据源是 config.qml 注入的 WallpaperController（C++）单实例：
 *   目录列表 ← htmlWallpaper.scanUrls；壁纸网格 ← htmlWallpaper.wallpapers
 *   （WallpaperModel）。
 * 目录增删走 config 的 addScanUrl/removeScanUrl（只改 cfg_ScanUrls 持久化，
 * 由 scanUrls 绑定同步 htmlWallpaper → 重扫）。
 *
 */
// —— 左栏：扫描目录（文件夹）列表 ——
ColumnLayout {
    id: scanUrlsPanel

    // 注入的解析器实例（由调用方 config.qml 传入）
    property QtObject htmlWallpaper: null

    // 当前选中的扫描根 URL（"" = 全部）。由 config.qml 绑定到 ThumbnailsPanel.activeFolder
    property string selectedFolder: ""

    // 暴露内部列表与"全部"标签供集成测试驱动真实点击（只读引用，不参与生产行为）
    property alias folderList: scanUrlsView
    property alias allTab: allTabDelegate

    Kirigami.Separator {
        Layout.fillWidth: true
    }

    // —— 顶部固定"全部"标签：显示所有扫描根合并的壁纸 ——
    Kirigami.SubtitleDelegate {
        id: allTabDelegate
        Layout.fillWidth: true
        text: i18nd("plasma_wallpaper_org.kde.image", "All")
        // 选中态：selectedFolder 为空即"全部"
        highlighted: scanUrlsPanel.selectedFolder.length === 0
        onClicked: scanUrlsPanel.selectedFolder = ""
        // 与文件夹标签一致：列表项无需悬停/按压反馈
        hoverEnabled: false
        down: false
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

        // 扫描目录列表：数据源是 htmlWallpaper.scanUrls（跟随 cfg_ScanUrlss）
        ListView {
            id: scanUrlsView

            model: htmlWallpaper.scanUrls

            headerPositioning: ListView.OverlayHeader
            // 悬浮标题栏，含“添加文件夹”按钮
            header: Kirigami.InlineViewHeader {
                width: scanUrlsView.width
                text: i18nd("plasma_wallpaper_org.kde.image", "Folders")
                actions: [
                    Kirigami.Action {
                        icon.name: "list-add-symbolic"
                        text: i18ndc("plasma_wallpaper_org.kde.image", "@action button the thing being added is a folder", "Add…")
                        Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Add Folder…")
                        onTriggered:{
                            const dialogComponent = Qt.createComponent("AddFolderDialog.qml");
                            // 只注入对话框所需的最小依赖：两个回调，不暴露 config 根对象。
                            // addScanUrl 实现在 config.qml（改 cfg_ScanUrls 才持久化）；
                            // 完成后这里通知 config 层刷新缩略图 / 标记配置变更
                            dialogComponent.createObject(scanUrlsPanel, {
                                addScanUrl: (path) => {
                                    htmlWallpaper.addScanUrl(String(path));
                                }
                            });
                            dialogComponent.destroy();
                        }
                    }
                ]
            }
            
            delegate: Kirigami.SubtitleDelegate {
                id: baseListItem
                // 字符串数组 model：modelData 直接是路径字符串
                required property string modelData

                width: scanUrlsView.width

                // 标签点击：切换中栏为当前文件夹壁纸组
                onClicked: scanUrlsPanel.selectedFolder = modelData
                // 选中态高亮：当前选中文件夹
                highlighted: scanUrlsPanel.selectedFolder === modelData

                // Don't need a highlight or hover effects
                // 列表项无需悬停高亮效果
                hoverEnabled: false
                down: false

                // 主标题只显示文件夹名（路径解析在 C++ WallpaperModel 实现）
                text: htmlWallpaper.wallpapers.folderName(modelData)
                // Subtitle: the path to the folder
                // 副标题显示父目录路径（路径解析在 C++ WallpaperModel 实现）
                subtitle: htmlWallpaper.wallpapers.parentPath(modelData)

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.TitleSubtitle {
                        Layout.fillWidth: true
                        // Header: the folder
                        // 标题：文件夹名；副标题：路径
                        title: baseListItem.text
                        subtitle: baseListItem.subtitle
                    }

                    // 从扫描列表移除该文件夹：走 config 层 removeScanUrls（持久化
                    // cfg_ScanUrlss），由 scanUrls 绑定同步 ListView 与解析器重扫
                    QQC2.ToolButton {
                        icon.name: "edit-delete-remove-symbolic"
                        text: i18nd("plasma_wallpaper_org.kde.image", "Remove Folder")
                        display: QQC2.Button.IconOnly
                        onClicked: {
                            // 删除的是当前选中文件夹 → 回退到"全部"
                            if (scanUrlsPanel.selectedFolder === String(baseListItem.modelData)) {
                                scanUrlsPanel.selectedFolder = "";
                            }
                            htmlWallpaper.removeScanUrl(String(baseListItem.modelData));
                        }
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
                visible: scanUrlsView.count === 0
                text: i18nd("plasma_wallpaper_org.kde.image", "There are no wallpaper locations configured")
            }
        }
    }
}


