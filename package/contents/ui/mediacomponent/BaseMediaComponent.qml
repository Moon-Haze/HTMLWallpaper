/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls

/**
 * 所有媒体组件的公共基类。
 *
 * 提供一块黑色背景（防止图片留白时露出桌面下层内容），
 * 并统一定义子类需要实现的接口属性（source / fillMode / sourceSize / blur），
 * 以及模糊背景的开关逻辑。子类只需填充自己的图片内容即可。
 */
Rectangle {
    id: backgroundColor

    // 黑色底：FillMode 为 Pad/Fit 时兜底显示
    color: "black"
    z: -2

    // —— 子类需要传入 / 实现的接口属性 ——
    property bool blur: false                  // 是否开启背景模糊
    required property url source               // 图片 URL
    property int fillMode
    required property size sourceSize

    /**
     * This defines the item that will be blurred and used in the background
     */
    // 要被模糊渲染的源项（由子类提供）
    property var blurSource
    // 仅当开启模糊且图片未铺满（Fit/Pad）时才真正需要模糊
    readonly property bool blurEnabled: backgroundColor.blur
        && (backgroundColor.fillMode === Image.PreserveAspectFit || backgroundColor.fillMode === Image.Pad)

    // 非激活状态时禁用离屏渲染层，释放 GPU 资源
    layer.enabled: StackView.status !== StackView.Active && StackView.status !== StackView.Deactivating

    // 模糊背景由 BlurComponent（FastBlur）实现，按需加载
    Loader {
        anchors.fill: parent
        active: backgroundColor.blurEnabled
        visible: active
        z: 0
        source: "BlurComponent.qml"
    }
}
