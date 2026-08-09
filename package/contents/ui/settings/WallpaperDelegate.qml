/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

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
 * 展示预览图（可带模糊背景），支持点击应用壁纸与勾选参与轮播。
 * 左上角叠加勾选框，用于选择幻灯片集合。
 */
KCM.GridDelegate {
    id: wallpaperDelegate

    // 暴露给外层：背景色与预览采样尺寸
    property alias color: backgroundRect.color
    property alias previewSize: previewImage.sourceSize
    // 注入的解析器实例（点选应用时使用）
    property QtObject imageWallpaper: null

    // 标记为"待删除"的项半透明显示（HTML 模式模型无此 role，恒为不透明）
    opacity: model.pendingDeletion ? 0.5 : 1
    scale: index, 1 // Workaround for https://bugreports.qt.io/browse/QTBUG-107458

    // 标题与副标题（HTML 模式用 description，缺省时回退 author）
    text: model.display
    subtitle: model.description !== undefined && model.description ? model.description : model.author

    hoverEnabled: true

    // —— 缩略图内容 ——
    thumbnail: Rectangle {
        id: backgroundRect
        anchors.fill: parent

        // 预览图未就绪时显示占位图标
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            source: "view-preview"
            visible: previewImage.status != Image.Ready
        }

        // 主预览图
        Image {
            id: previewImage
            anchors.fill: parent
            asynchronous: true
            retainWhileLoading: true
            cache: false
            source: model.preview
        }

        // 勾选框：控制该幻灯片是否参与轮播
        QtControls2.CheckBox {
            anchors.left: parent.left
            anchors.margins: Kirigami.Units.smallSpacing
            anchors.top: parent.top
            checked: model.checked
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

    // 点击行为：解析并应用该壁纸（参数经 wallpaperParsed 写配置）；
    // 无路径时仅切换勾选状态
    onClicked: {
        if (imageWallpaper && model.path) {
            imageWallpaper.parseWallpaper(model.path);
            root.cfg_DisplayPage = model.source;
        } else {
            model.checked = !model.checked
        }
        GridView.currentIndex = index;
    }
}
