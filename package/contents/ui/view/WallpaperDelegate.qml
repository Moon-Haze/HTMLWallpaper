/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QtControls2
import Qt5Compat.GraphicalEffects
import QtWebEngine

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
    // 注：pendingDeletion 在 WallpaperModel/WallpaperItem/mock 三态下均为
    // undefined，无需 modelData 兜底；保持单路径避免 QAbstractListModel 下
    // 空 modelData 的属性访问。
    // view.model 恒为真 QAbstractListModel，role 直接可用，不再需要 modelData 双路径。
    opacity: model.pendingDeletion ? 0.5 : 1

    text: model.title

    // —— 缩略图内容 ——
    thumbnail: Rectangle {
        id: backgroundRect
        anchors.fill: parent

        // 预览图未就绪时显示占位图标；失败态切"缺图"图标，避免误读为加载中
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            source: previewImage.status === Image.Error ? "image-missing" : "view-preview"
            visible: previewImage.status !== Image.Ready
        }

        Image {
            id: previewImage
            anchors.fill: parent
            // 等比缩放后居中裁剪，填满缩略图而不错乱比例（类似 CSS object-fit: cover）
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            retainWhileLoading: true
            cache: false
            source: model.preview
            // 加载完成淡入，避免占位图标硬切
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.shortDuration }
            }
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
}
