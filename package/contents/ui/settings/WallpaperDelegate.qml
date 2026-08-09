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
 * 展示预览图（可带模糊背景），支持点击应用壁纸与单选参与轮播。
 * 左上角叠加单选按钮，当前勾选项为唯一轮播壁纸（互斥选择）。
 */
KCM.GridDelegate {
    id: wallpaperDelegate

    // 暴露给外层：背景色与预览采样尺寸
    property alias color: backgroundRect.color
    property alias previewSize: previewImage.sourceSize
    // 注入的解析器实例（点选应用时使用）
    property QtObject htmlWallpaper: null

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
                visible: false
            }
        }

        Image {
            id: previewImage
            anchors.fill: parent
            asynchronous: true
            retainWhileLoading: true
            cache: false
            source: model.preview
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
        if (htmlWallpaper && model.path) {
            htmlWallpaper.parseWallpaper(model.path);
            root.cfg_DisplayPage = model.source;
        } else {
            // 无路径项（如“添加”占位）点击时翻转勾选，同样走互斥写回
            if (htmlWallpaper && htmlWallpaper.wallpapers) {
                htmlWallpaper.wallpapers.setExclusiveChecked(index, !model.checked)
            }
        }
        // 注意：不再手动改 GridView.currentIndex，以免销毁 cfg_DisplayPage 驱动的绑定，
        // 高亮由 resetCurrentIndex() 建立的绑定自动跟随 cfg_DisplayPage
    }
}
