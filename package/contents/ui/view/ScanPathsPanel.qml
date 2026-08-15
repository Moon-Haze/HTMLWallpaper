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
 * 展示并管理 htmlWallpaper.scanPaths（QStringList）中的扫描目录，
 * 支持增删与在文件管理器中打开目录；未配置目录时显示空态提示。
 *
 * 数据源是 config.qml 注入的 WallpaperController（C++）单实例：
 *   目录列表 ← htmlWallpaper.scanPaths；壁纸网格 ← htmlWallpaper.modelFor/allModel
 *   （每文件夹一个 WallpaperModel）。
 * 目录增删走 config 的 addScanPath/removeScanPath（只改 cfg_ScanPaths 持久化，
 * 由 scanPaths 绑定同步 htmlWallpaper → 重扫）。
 *
 */
// —— 左栏：扫描目录（文件夹）列表 ——
ColumnLayout {
    id: scanPathsPanel

    // 注入的解析器实例（由调用方 config.qml 传入）
    property QtObject htmlWallpaper: null

    // 当前选中的扫描根 URL（"" = 全部）。由 config.qml 绑定到 ThumbnailsPanel.activeFolder
    property string selectedFolder: ""

    // 暴露内部列表与"全部"入口供集成测试驱动真实交互（只读引用，不参与生产行为）
    property alias folderList: scanPathsView
    property alias allTab: allAction

    // —— 顶部动作 ——
    // header 内引用；根级定义使 property alias allTab 合法（header 内嵌 id 对根不可见）。
    // Kirigami.Action 非 Item，不参与 ColumnLayout 布局。
    Kirigami.Action {
        id: allAction
        icon.name: "all-wallpapers-symbolic"
        text: i18ndc("plasma_wallpaper_org.kde.image", "@action switch to look all wallpapers", "All")
        Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "All")
        // 激活态语义：未选中任何文件夹（"全部"）时处于 checked 态。
        // Kirigami.Action 无 highlighted 属性，用 checkable+checked 达成同语义（上游 plasma-workspace 同款）。
        checkable: true
        checked: scanPathsPanel.selectedFolder.length === 0
        onTriggered: scanPathsPanel.selectedFolder = ""
    }

    Kirigami.Action {
        id: addFolderAction
        icon.name: "list-add-symbolic"
        text: i18ndc("plasma_wallpaper_org.kde.image", "@action button the thing being added is a folder", "Add…")
        Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Add Folder…")
        onTriggered: {
            const dialogComponent = Qt.createComponent("AddFolderDialog.qml");
            dialogComponent.createObject(scanPathsPanel, {
                addScanPath: (path) => {
                    htmlWallpaper.addScanPath(String(path));
                }
            });
            dialogComponent.destroy();
        }
    }

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

            model: htmlWallpaper.scanPaths

            headerPositioning: ListView.OverlayHeader
            // 悬浮标题栏，含“添加文件夹”按钮
            header: Kirigami.InlineViewHeader {
                width: scanPathsView.width
                text: i18nd("plasma_wallpaper_org.kde.image", "Folders")
                actions: [
                    allAction,
                    addFolderAction
                ]
            }

            delegate: Kirigami.SubtitleDelegate {
                id: baseListItem
                // 字符串数组 model：modelData 直接是路径字符串
                required property string modelData

                width: scanPathsView.width

                // 标签点击：切换中栏为当前文件夹壁纸组
                onClicked: scanPathsPanel.selectedFolder = modelData
                // 选中态高亮：当前选中文件夹
                highlighted: scanPathsPanel.selectedFolder === modelData

                // Don't need a highlight or hover effects
                // 列表项无需悬停高亮效果
                hoverEnabled: false
                down: false

                // 主标题只显示文件夹名（路径解析在 C++ WallpaperController 实现）
                text: htmlWallpaper.folderName(modelData)
                // Subtitle: the path to the folder
                // 副标题显示父目录路径（路径解析在 C++ WallpaperController 实现）
                subtitle: htmlWallpaper.parentPath(modelData)

                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.TitleSubtitle {
                        Layout.fillWidth: true
                        // Header: the folder
                        // 标题：文件夹名；副标题：路径
                        title: baseListItem.text
                        subtitle: baseListItem.subtitle
                    }

                    // 从扫描列表移除该文件夹：走 config 层 removeScanPath（持久化
                    // cfg_ScanPaths），由 scanPaths 绑定同步 ListView 与解析器重扫
                    QQC2.ToolButton {
                        icon.name: "edit-delete-remove-symbolic"
                        text: i18nd("plasma_wallpaper_org.kde.image", "Remove Folder")
                        display: QQC2.Button.IconOnly
                        onClicked: {
                            // 删除的是当前选中文件夹 → 回退到"全部"
                            if (scanPathsPanel.selectedFolder === String(baseListItem.modelData)) {
                                scanPathsPanel.selectedFolder = "";
                            }
                            htmlWallpaper.removeScanPath(String(baseListItem.modelData));
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
                visible: scanPathsView.count === 0
                text: i18nd("plasma_wallpaper_org.kde.image", "There are no wallpaper locations configured")
            }
        }
    }
}


