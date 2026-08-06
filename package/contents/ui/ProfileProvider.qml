/*
 *   SPDX-FileCopyrightText: 2026 Moon Haze
 *   SPDX-License-Identifier: LGPL-2.0-or-later
 */

pragma Singleton

import QtQuick
import QtWebEngine

QtObject {
    /**
     * 所有屏幕共享同一个 WebEngineProfile：
     * - 多显示器时每屏都是一个 WallpaperItem 实例，共享此 profile 可复用缓存/UA/Cookie
     * - 独立 storageName 将壁纸缓存与 plasmashell 内其他 WebEngine 组件隔离
     */
    readonly property WebEngineProfile sharedProfile: WebEngineProfile {
        storageName: "htmlwallpaper"
        offTheRecord: false
    }
}
