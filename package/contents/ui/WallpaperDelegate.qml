/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QtControls2
import Qt5Compat.GraphicalEffects

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

/**
 * 网格中的单个壁纸缩略图项。
 *
 * 展示预览图（可带模糊背景），支持悬停操作菜单与点击切换。
 * 在 HTMLWallpaper 模式下左上角叠加一个勾选框，用于选择幻灯片集合。
 */
KCM.GridDelegate {
    id: wallpaperDelegate

    // 暴露给外层：背景色与预览采样尺寸
    property alias color: backgroundRect.color
    property alias previewSize: previewImage.sourceSize
    // 当前项的来源与选择器（用于单图模式下的 URL 定位）
    property string key: model.source
    property list<string> selectors: model.selectors
    // 标记为“待删除”的项半透明显示
    opacity: model.pendingDeletion ? 0.5 : 1
    scale: index, 1 // Workaround for https://bugreports.qt.io/browse/QTBUG-107458

    // 悬停操作菜单里的标题与副标题
    text: model.display
    subtitle: model.author

    hoverEnabled: true

    // —— 悬停操作菜单 ——
    actions: [
        // 在文件管理器中打开该壁纸所在文件夹
        Kirigami.Action {
            icon.name: "document-open-folder"
            tooltip: i18nd("plasma_wallpaper_org.kde.image", "Open Containing Folder")
            onTriggered: imageModel.openContainingFolder(index)
        },
        // “恢复”：撤销待删除标记
        Kirigami.Action {
            icon.name: "edit-undo"
            visible: model.pendingDeletion
            tooltip: i18nd("plasma_wallpaper_org.kde.image", "Restore wallpaper")
            onTriggered: model.pendingDeletion = false
        },
        // “移除”：仅单图模式下可删除可移除项；先标记为待删除（二次确认删除）
        Kirigami.Action {
            icon.name: "edit-delete-remove"
            tooltip: i18nd("plasma_wallpaper_org.kde.image", "Remove Wallpaper")
            visible: model.removable && !model.pendingDeletion && configDialog.currentWallpaper == "org.kde.image"
            onTriggered: {
                model.pendingDeletion = true;

                // 若删除的是当前选中项，把选中移到下一项，避免空选
                if (wallpapersGrid.view.currentIndex === index) {
                    const newIndex = (index + 1) % (imageModel.count - 1);
                    wallpapersGrid.view.itemAtIndex(newIndex).clicked();
                }
                root.configurationChanged(); // BUG 438585
            }
        }
    ]

    // —— 缩略图内容 ——
    thumbnail: Rectangle {
        id: backgroundRect
        color: cfg_Color // 背景色（FillMode 为 Pad/Fit 时可见）
        anchors.fill: parent

        // 预览图未就绪时显示占位图标
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            source: "view-preview"
            visible: previewImage.status != Image.Ready
        }

        // 模糊效果：开启“背景模糊”时把预览图高斯模糊后铺在底下
        FastBlur {
            id: fastBlur
            visible: cfg_Blur
            anchors.fill: parent
            radius: 4
            source: Image {
                asynchronous: true
                retainWhileLoading: true
                cache: false
                fillMode: Image.PreserveAspectCrop
                source: fastBlur.visible ? previewImage.source : ""
                sourceSize: previewImage.sourceSize
                visible: false // 只作为模糊源，不直接显示
            }
        }

        // 主预览图
        Image {
            id: previewImage
            anchors.fill: parent
            asynchronous: true
            retainWhileLoading: true
            cache: false
            fillMode: cfg_FillMode
            source: model.preview
        }

        // HTMLWallpaper 模式下的勾选框：控制该幻灯片是否参与轮播
        QtControls2.CheckBox {
            visible: configDialog.currentWallpaper === "com.github.Moon-Haze.htmlwallpaper"
            anchors.left: parent.left
            anchors.margins: Kirigami.Units.smallSpacing
            anchors.top: parent.top
            checked: visible ? model.checked : false
            onToggled: model.checked = checked
        }

        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.InOutQuad
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.InOutQuad
        }
    }

    // 点击行为：
    // - 单图模式：直接选中该壁纸（应用到桌面）
    // - 幻灯片/HTML 模式：切换勾选状态
    onClicked: {
        if (configDialog.currentWallpaper === "org.kde.image") {
            root.selectWallpaper(key, selectors);
        } else {
            model.checked = !model.checked
        }
        GridView.currentIndex = index;
    }
}
