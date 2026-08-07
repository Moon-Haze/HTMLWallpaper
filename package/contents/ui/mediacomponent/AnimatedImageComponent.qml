/*
    SPDX-FileCopyrightText: 2022 Fushan Wen <qydwhotmail@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick

import org.kde.plasma.wallpapers.image as PlasmaWallpaper

import org.kde.kwindowsystem

/**
 * 动态图媒体组件：渲染 AnimatedImage（GIF 等），并在最大化窗口遮挡时自动暂停以省电。
 */
BaseMediaComponent {
    id: animatedImageComponent

    // 桌面区域矩形（用于判断是否有窗口覆盖在壁纸上）
    readonly property rect desktopRect: Window.window ? Qt.rect(Window.window.x, Window.window.y, Window.window.width, Window.window.height) : Qt.rect(0, 0, 0, 0)
    // 对外暴露加载状态
    readonly property alias status: mainImage.status
    // 强制播放：即使被遮挡也不暂停（配置项 forceImageAnimation）
    property bool forceImageAnimation: false

    blurSource: blurLoader.item

    // 监控最大化窗口的数量与区域，判断动态图是否应暂停
    PlasmaWallpaper.MaximizedWindowMonitor {
        id: activeWindowMonitor
        regionGeometry: animatedImageComponent.desktopRect
    }

    // 主动态图
    AnimatedImage {
        id: mainImage
        anchors.fill: parent
        asynchronous: true
        cache: false
        autoTransform: true

        fillMode: animatedImageComponent.fillMode
        source: animatedImageComponent.source
        // sourceSize is read-only
        // sourceSize 为只读属性，故此处复用父级传值
        // https://github.com/qt/qtdeclarative/blob/23b4ab24007f489ac7c2b9ceabe72fa625a51f3d/src/quick/items/qquickanimatedimage_p.h#L39

        // 有最大化窗口遮挡桌面、且未强制播放时暂停动画，降低 CPU/GPU 占用
        paused: !animatedImageComponent.forceImageAnimation && activeWindowMonitor.count > 0 && !KWindowSystem.showingDesktop
    }

    // 需要模糊背景时加载模糊源副本
    Loader {
        id: blurLoader
        anchors.fill: parent
        active: animatedImageComponent.blurEnabled
        sourceComponent: Image {
            asynchronous: true
            cache: false
            autoTransform: true
            fillMode: Image.PreserveAspectCrop
            source: mainImage.source
            sourceSize: animatedImageComponent.sourceSize
            visible: false // will be rendered by the blur
        }
    }
}
