/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.wallpapers.image as Wallpaper

/**
 * 静态图片媒体组件：直接渲染一张普通图片（位图或 SVG 矢量图）。
 * 使用 TransientImage（一次性、用完即释放缓存），并可选提供模糊源。
 */
BaseMediaComponent {
    id: staticImageComponent

    // 对外暴露图片加载状态（Null/Loading/Ready/Error）
    readonly property alias status: mainImage.status

    // 模糊源使用下方加载的复制图
    blurSource: blurLoader.item

    // 主图片：铺满父区域
    Wallpaper.TransientImage {
        id: mainImage
        anchors.fill: parent

        fillMode: staticImageComponent.fillMode
        source: staticImageComponent.source
    }

    // 需要模糊背景时，加载一份只用于模糊的图片副本
    Loader {
        id: blurLoader
        anchors.fill: parent
        z: 0
        active: staticImageComponent.blurEnabled
        sourceComponent: Image {
            asynchronous: true
            cache: false
            autoTransform: true
            fillMode: Image.PreserveAspectCrop
            source: mainImage.source
            sourceSize: mainImage.sourceSize
            visible: false // will be rendered by the blur
            // 仅作为 FastBlur 的输入源，自身不直接显示
        }
    }
}
