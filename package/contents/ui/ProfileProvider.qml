/*
 *   SPDX-FileCopyrightText: 2026 Moon Haze
 *   SPDX-License-Identifier: LGPL-2.0-or-later
 */

pragma Singleton

import QtQuick
import QtWebEngine

/**
 * 单例对象（在 qmldir 中声明为 pragma Singleton），
 * 提供整个插件共用的 WebEngineProfile。
 */
QtObject {
    /**
     * 所有屏幕共享同一个 WebEngineProfile：
     * - 多显示器时每屏都是一个 WallpaperItem 实例，共享此 profile 可复用缓存/UA/Cookie
     * - 独立 storageName 将壁纸缓存与 plasmashell 内其他 WebEngine 组件隔离
     */
    readonly property WebEngineProfile sharedProfile: WebEngineProfile {
        // storageName 决定磁盘上缓存目录的名字；非 of-the-record 才会持久化缓存
        storageName: "htmlwallpaper"
        // offTheRecord 为 false：壁纸的 Cookie / 缓存数据持久化到磁盘
        offTheRecord: false
        storageName: "htmlwallpaper"
        offTheRecord: false
    }
}
