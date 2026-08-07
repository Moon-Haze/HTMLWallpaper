/*
    SPDX-FileCopyrightText: 2022 Fushan Wen <qydwhotmail@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import Qt5Compat.GraphicalEffects

/**
 * 背景模糊组件：对 blurSource 做高斯模糊。
 * 通过 BaseMediaComponent 里的 Loader 按需加载，
 * 因此本文件依赖基类的 backgroundColor 与 blurSource 属性。
 *
 * Qt5Compat.GraphicalEffects is gone in Qt6, so put it in a Loader to avoid blank wallpapers.
 * TODO Qt 6
 * Qt6 中 Qt5Compat.GraphicalEffects 已弃用，放在 Loader 里按需加载可避免整张壁纸空白
 */
FastBlur {
    source: backgroundColor.blurSource  // 基类提供的模糊输入源
    radius: 32                          // 模糊半径
}
