/*
    SPDX-FileCopyrightText: 2025 Vlad Zahorodnii <vlad.zahorodnii@kde.org>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

import org.kde.kirigami as Kirigami

/**
 * 昼夜视图容器：用 StackView 管理 DayNightImage 的创建与替换。
 *
 * 当日夜状态发生大幅变化（snapshot 不再连续）时，重建整张合成图并淡入；
 * 当 blendFactor 等轻微变化时，直接更新现有 DayNightImage 的属性，避免重建。
 */
StackView {
    id: root

    // DayNightWallpaper 提供的合成快照 {bottom, top, blendFactor, disjoint}
    property var snapshot
    property int fillMode

    // 正在加载/待展示的新合成图
    property var nextItem: null
    // 对外暴露下一张图的加载状态
    readonly property int status: nextItem ? nextItem.status : Image.Null
    // 初始化是否完成（决定快照变化时是重建还是更新）
    property bool complete: false

    // 快照变化：状态连续则原地更新，否则整体重建
    onSnapshotChanged: if (complete) {
        tryReset();
    }
    onFillModeChanged: if (complete) {
        reset();
    }

    // DayNightImage 组件模板；切换过渡期间开离屏渲染层提升合成质量
    Component {
        id: baseImage

        DayNightImage {
            layer.enabled: root.replaceEnter.running
            StackView.onRemoved: destroy()
        }
    }

    // 新图淡入过渡
    replaceEnter: Transition {
        NumberAnimation {
            id: enterAnimation
            property: "opacity"
            from: 0
            to: 1
            duration: Kirigami.Units.veryLongDuration
        }
    }

    // 旧图多停留片刻，避免新旧图切换时露出空白
    replaceExit: Transition {
        PauseAnimation {
            duration: enterAnimation.duration + 500 // 500 to ensure that the previous item doesn't go away before the new item too soon
        }
    }

    // 把已就绪的合成图替换进视图（首屏用 Immediate，其余带淡入过渡）
    function commit(): void {
        if (nextItem.status === Image.Loading) {
            return;
        }

        nextItem.statusChanged.disconnect(root.commit);

        let operation;
        if (empty) {
            operation = StackView.Immediate;
        } else {
            operation = StackView.Transition;
        }

        replace(nextItem, {}, operation);
    }

    // 重建一张全新的 DayNightImage（用于日夜状态大幅切换）
    function reset(): void {
        // 若上一张还在加载，先取消其回调，避免误提交
        if (status === Image.Loading) {
            nextItem.statusChanged.disconnect(root.commit);
        }

        // 用当前快照参数实例化新的合成图
        nextItem = baseImage.createObject(root, {
            bottomUrl: snapshot.bottom,
            topUrl: snapshot.top,
            blendFactor: snapshot.blendFactor,
            fillMode: fillMode,
            implicitWidth: root.width,
            implicitHeight: root.height,
            visible: false, // 就绪前隐藏
        });
        if (!nextItem) {
            console.warn("Failed to instantiate DayNightImage:", baseImage.errorString());
        }

        // 就绪则立即替换，否则等它加载完
        if (nextItem.status === Image.Ready) {
            commit();
        } else {
            nextItem.statusChanged.connect(root.commit);
        }
    }

    // 快照变化时的入口：disjoint 表示日夜状态跳变，需重建；否则原地更新属性
    function tryReset(): void {
        if (snapshot.disjoint) {
            reset();
        } else {
            nextItem.bottomUrl = snapshot.bottom;
            nextItem.topUrl = snapshot.top;
            nextItem.blendFactor = snapshot.blendFactor;
        }
    }

    // 初始化：先重建一次，再允许后续快照更新
    Component.onCompleted: {
        reset();
        complete = true;
    }
}
