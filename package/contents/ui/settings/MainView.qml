/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2019 David Redondo <kde@david-redondo.de>
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.wallpapers.image as PlasmaWallpaper

/**
 * HTML 壁纸配置面板（com.github.moon_haze.htmlwallpaper 模式下显示）。
 *
 * 上半部分：轮播排序方式（随机 / 按名称 / 按修改时间）、按文件夹分组；
 * 主体三栏布局：
 *   左栏：扫描目录（文件夹）列表，可增删、打开目录；
 *   中栏：ThumbnailsPanel 展示目录下的 HTML 壁纸网格（点选即应用）；
 *   右栏：PropertyPanel 编辑当前壁纸的协议参数（color/slider/combo/bool/…）。
 *
 * 数据源是 config.qml 注入的 HTMLBackend（C++）单实例：
 *   目录列表 ← htmlWallpaper.scanPaths；壁纸网格 ← htmlWallpaper.wallpapers；
 *   参数面板 ← 已随 HTMLBackend 解耦重构停用（见下方右栏 PropertyPanel 注释）；
 *   可配置属性表现在经 WallpaperItem::properties（WallpaperPropertyModel ListModel）
 *   的 get(i) / byKey(key) 暴露，不再有 currentWallpaper.general.properties。
 * 目录增删走 config 的 addScanPath/removeScanPath（只改 cfg_ScanPaths 持久化，
 * 由 scanPaths 绑定同步 htmlWallpaper → 重扫）。参数"可调不持久"：改动只更新
 * 面板会话内镜像，不写 cfg_WallpaperProperties、不应用到壁纸。
 *
 * For proper alignment, an ancestor **MUST** have id "appearanceRoot" and property "parentLayout"
 */
RowLayout {
    id: root

    // —— 由 config.qml 经 Loader 注入 ——
    property QtObject htmlWallpaper: null
    // KCM 注入的 KConfigPropertyMap（config.qml 转传，当前仅存档用）
    property var configuration: null
    // config.qml 根对象：本组件是独立加载的面板容器，子组件（ScanPathsPanel /
    // ThumbnailsPanel / WallpaperDelegate）通过 root.<name> 访问的 cfg_*、增删
    // 目录方法与 wallpaperBrowseCompleted 信号在这里统一代理到 config 层，
    // 契约与重构前（三栏直接内嵌 config.qml）保持一致。

    property var configApi: null

    // cfg_DisplayPage 双向同步：delegate 点选写入 → 写回 config 持久化；
    // config 恢复 / 外部变化 → 经下方 Connections 反向同步回本组件。
    property string cfg_DisplayPage
    // 增删扫描目录 / 弹"添加文件夹"对话框：转发给 config 层（持久化 + 触发绑定链）
    function openChooserDialog() { if (configApi) configApi.openChooserDialog(); }
    function removeScanPath(path) { if (configApi) configApi.removeScanPath(path); }
    function addScanPath(path) { if (configApi) configApi.addScanPath(path); }
    // AddFolderDialog 添加完文件夹 → config 信号 → 转发给 ThumbnailsPanel
    signal wallpaperBrowseCompleted()

    onConfigApiChanged: {
        if (configApi) {
            cfg_DisplayPage = configApi.cfg_DisplayPage;
        }
    }
    onCfg_DisplayPageChanged: {
        if (configApi && configApi.cfg_DisplayPage !== cfg_DisplayPage) {
            configApi.cfg_DisplayPage = cfg_DisplayPage;
        }
    }
    Connections {
        target: configApi
        function onCfg_DisplayPageChanged() {
            if (root.cfg_DisplayPage !== configApi.cfg_DisplayPage) {
                root.cfg_DisplayPage = configApi.cfg_DisplayPage;
            }
        }
        function onWallpaperBrowseCompleted() {
            root.wallpaperBrowseCompleted();
        }
    }

    spacing: 0

    // —— 左栏：扫描目录（文件夹）列表 ——
    ScanPathsPanel {
        id: scanPathsView
        spacing: 0
        Layout.maximumWidth: Kirigami.Units.gridUnit * 16
        scanPaths: htmlWallpaper ? htmlWallpaper.scanPaths : null
    }

    Kirigami.Separator {
        Layout.fillHeight: true
    }

    // —— 中栏：HTML 壁纸缩略图网格 ——
    ThumbnailsPanel {
        Layout.fillWidth: true
        Layout.fillHeight: true
        // 注意：必须写 root.htmlWallpaper，不能写裸 htmlWallpaper——
        // ThumbnailsPanel 自身有同名 htmlWallpaper 属性，裸标识符会被解析成
        // 它自己的属性，形成自引用绑定（"Binding loop for htmlWallpaper"）。
        htmlWallpaper: root.htmlWallpaper
    }

    Kirigami.Separator {
        Layout.fillHeight: true
    }

    // —— 右栏：参数面板 ——
    // PropertyPanel 组件当前停用（HTMLBackend 解耦重构删除了其依赖的
    // currentWallpaper / evaluateCondition / colorToHex / wallpaperParsed API）。
    // 若未来恢复，须先按新契约重写 PropertyPanel.qml：
    // 属性表经 wallpapers.get(i).properties（WallpaperPropertyModel）的
    // get(i) / byKey(key) 访问，condition 可见性不再有 evaluateCondition 支持。
    // PropertyPanel {
    //     Layout.fillHeight: true
    //     Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    //     Layout.maximumWidth: Kirigami.Units.gridUnit * 34
    //     htmlWallpaper: root.htmlWallpaper
    //     // 参数改动不再写 cfg_WallpaperProperties（可调不持久）；propertyChanged
    //     // 信号保留供测试 / 后续扩展消费
    // }
}

