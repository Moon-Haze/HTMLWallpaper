/*
    SPDX-FileCopyrightText: 2025 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.wallpapers.image as Wallpaper

/**
 * 昼夜双图合成单元。
 *
 * 用两张 TransientImage 分别承载“底层图（bottomUrl）”与“顶层图（topUrl）”，
 * 顶层图以 blendFactor 透明度叠加在底层图上，实现日夜平滑过渡。
 * 每张图片加载完成后调用 commit() 应用最终叠加参数。
 */
Item {
    id: root

    // 底层图（当前时段主图）与顶层图（另一时段的覆盖图）地址
    property url bottomUrl
    property url topUrl
    // 顶层图透明度（0=完全显示底层，1=完全显示顶层）
    property real blendFactor
    property int fillMode

    // 综合两张图的加载状态对外报告
    readonly property int status: {
        if (firstImage.status === Image.Error || secondImage.status === Image.Error) {
            return Image.Error;
        } else if (firstImage.status === Image.Loading || secondImage.status === Image.Loading) {
            return Image.Loading;
        } else if (firstImage.status === Image.Ready || secondImage.status === Image.Ready) {
            return Image.Ready;
        } else {
            return Image.Null;
        }
    }

    // 两张可复用图片（TransientImage 用完即释放）
    Wallpaper.TransientImage {
        id: firstImage
        anchors.fill: parent
        fillMode: root.fillMode
    }

    Wallpaper.TransientImage {
        id: secondImage
        anchors.fill: parent
        fillMode: root.fillMode
    }

    // 同步图片源：把两张图分别指向 bottomUrl / topUrl，就绪后立即应用叠加
    function sync(): void {
        // 找出当前承载底层图的那张图片作为 currentItem，另一张作 nextItem
        let currentItem;
        let nextItem;
        if (firstImage.source === root.bottomUrl) {
            currentItem = firstImage;
            nextItem = secondImage;
        } else if (secondImage.source === root.bottomUrl) {
            currentItem = secondImage;
            nextItem = firstImage;
        } else {
            // 尚未分配底层图：优先复用已有内容的图，其次用空图
            if (secondImage.source !== "") {
                currentItem = secondImage;
                nextItem = firstImage;
            } else {
                currentItem = firstImage;
                nextItem = secondImage;
            }
        }

        currentItem.source = root.bottomUrl;
        nextItem.source = root.topUrl;

        // 两张图都已就绪则直接应用叠加
        if (root.status === Image.Ready) {
            commit();
        }
    }

    // 应用最终叠加参数：底层图完全可见，顶层图按 blendFactor 叠加在上
    function commit(): void {
        // 定位承载底层图的图
        let currentItem;
        if (firstImage.source === root.bottomUrl) {
            currentItem = firstImage;
        } else if (secondImage.source === root.bottomUrl) {
            currentItem = secondImage;
        } else {
            return;
        }

        // 定位承载顶层图的图
        let nextItem;
        if (firstImage.source === root.topUrl) {
            nextItem = firstImage;
        } else if (secondImage.source === root.topUrl) {
            nextItem = secondImage;
        } else {
            return;
        }

        // 底层在下面完全显示，顶层在上面按比例透明
        currentItem.z = 0;
        currentItem.opacity = 1.0;

        nextItem.z = 1;
        nextItem.opacity = root.blendFactor;
    }

    // 任一输入变化时延迟一帧再同步，避免高频抖动
    onBottomUrlChanged: Qt.callLater(sync);
    onTopUrlChanged: Qt.callLater(sync);
    onBlendFactorChanged: Qt.callLater(sync);

    // 图片就绪后应用叠加
    onStatusChanged: () => {
        if (status === Image.Ready) {
            commit();
        }
    }

    // 首次初始化同步
    Component.onCompleted: sync();
}
