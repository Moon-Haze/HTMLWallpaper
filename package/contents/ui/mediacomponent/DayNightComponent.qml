/*
    SPDX-FileCopyrightText: 2025 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.wallpapers.image

/**
 * 昼夜双图媒体组件：按当前日夜状态在“白昼图 / 黑夜图”之间平滑混合。
 *
 * DayNightWallpaper 负责依据配置的日夜计划计算当前状态（state），
 * DayNightView 负责把两张图按 blendFactor 做透明叠加过渡。
 */
BaseMediaComponent {
    id: dayNightComponent
    blurSource: blurLoader.item

    // 对外暴露合成视图的加载状态
    readonly property alias status: dayNightView.status

    // 合成视图：接收 DayNightWallpaper 生成的快照（bottom/top/blendFactor）
    DayNightView {
        id: dayNightView
        anchors.fill: parent
        fillMode: dayNightComponent.fillMode
        snapshot: dayNightWallpaper.snapshot
    }

    // 依据日夜计划驱动状态切换
    DayNightWallpaper {
        id: dayNightWallpaper
        initialState: configuration.DarkLightScheduleState
        source: dayNightComponent.source

        // 状态变化时把新的日夜状态写回配置持久化
        onStateChanged: () => {
            if (configuration.DarkLightScheduleState != state) {
                configuration.DarkLightScheduleState = state;
                configuration.writeConfig();
            }
        }
    }

    // 需要模糊背景时，用当前“底层图（bottom）”作为模糊源
    Loader {
        id: blurLoader
        anchors.fill: parent
        active: dayNightComponent.blurEnabled
        sourceComponent: Image {
            asynchronous: true
            cache: false
            autoTransform: true
            fillMode: Image.PreserveAspectCrop
            source: dayNightWallpaper.snapshot.bottom
            sourceSize: dayNightComponent.sourceSize
            visible: false
        }
    }
}
