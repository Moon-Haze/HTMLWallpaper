/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2019 David Redondo <kde@david-redondo.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import com.github.moon_haze.htmlwallpaper

/**
 * 壁纸"配置"页主界面（在系统设置 / 桌面壁纸右键菜单中打开）。
 *
 * 纯 HTML 壁纸模式（com.github.moon_haze.htmlwallpaper）：主体为
 * ScanPathsPanel 三栏面板（扫描目录 / 壁纸网格 / 参数编辑），
 * 下方 DropArea 支持把文件夹拖进配置窗口添加扫描目录。
 * 所有 cfg_* 属性与 KConfig 绑定（由 KCM 框架自动读写配置项）。
 *
 * For proper alignment, an ancestor **MUST** have id "appearanceRoot" and property "parentLayout"
 */
ColumnLayout {
    id: root

    // 由外层注入的环境对象。
    // 注意：KCM（kcm_wallpaper 的 main.qml）会用 setProperty 向本组件注入
    // configDialog 与 wallpaperConfiguration 两个属性，**必须显式声明**；
    // 若缺少 configDialog 声明，KCM 注入时报 "Cannot assign to non-existent
    // property configDialog"（致命错误）→ 组件加载 not ready → 配置页打开失败。
    property var configDialog
    property var wallpaperConfiguration: wallpaper.configuration
    property var parentLayout
    
    property alias cfg_ScanPaths: htmlWallpaper.scanPaths
    property string cfg_DisplayPage                  // 当前 HTML 壁纸入口页面（DisplayPage 配置）
    property string cfg_WallpaperProperties        // 当前 HTML 壁纸参数 JSON（运行时注入/重启恢复）

    spacing: 0

    // 任一配置项被界面改动后发出，通知外层（如预览、配置写入）刷新
    signal configurationChanged()
    // 用户在文件夹对话框中添加完文件夹后发出
    signal wallpaperBrowseCompleted();
    // 保存配置：清除内部预览标记
    function saveConfig() {
        wallpaperConfiguration.PreviewImage = "null"; // internal, no need to save to file
    }

    // 弹出"添加文件夹"对话框（组件用完即销毁）
    function openChooserDialog() {
        const dialogComponent = Qt.createComponent("settings/AddFolderDialog.qml");
        dialogComponent.createObject(root);
        dialogComponent.destroy();
    }

    // —— HTML 壁纸解析器（C++ 后端）：扫描扫描目录下的 project.json，提供壁纸
    // 列表 / 参数表 / 预览。scanPaths 跟随 cfg_ScanPaths（扫描目录），
    // 变化时触发重扫；scanPaths 本身即 QStringList，QML 侧直接作目录列表的 model。
    HTMLBackend {
        id: htmlWallpaper
        // 路径变化时重扫（数据源即 scanPaths，无需中间模型同步）
        onScanPathsChanged: htmlWallpaper.scan()
        // 扫描完成 → 按 cfg_DisplayPage 匹配勾选当前壁纸（无匹配回退第一项）
        // onScanFinished: root.syncCheckedFromDisplayPage()
        // 初始化：scanPaths 绑定赋初值不触发 onScanPathsChanged，补一次初始扫描，
        // 否则打开配置面板时中栏网格为空
        Component.onCompleted: htmlWallpaper.scan()
    }

    // 增删扫描目录：只改 cfg_ScanPaths（持久化 + 触发绑定链），
    // 由 scanPaths 绑定自动同步 htmlWallpaper。
    function addScanPath(path: url): void {
        const p = String(path);
        if (cfg_ScanPaths.indexOf(p) >= 0) {
            return;
        }
        const list = cfg_ScanPaths.slice();
        list.push(p);
        cfg_ScanPaths = list;
    }
    function removeScanPath(path: url): void {
        const p = String(path);
        const list = cfg_ScanPaths.filter(x => String(x) !== p);
        cfg_ScanPaths = list;
    }

    // —— 主内容区：接受拖放，加载 HTML 壁纸面板 ——
    DropArea {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // 拖动进入：携带 URL（文件夹）时允许投放
        onEntered: drag => {
            if (drag.hasUrls) {
                drag.accept();
            }
        }
        // 放下：全部作为扫描目录添加
        onDropped: drop => {
            drop.urls.forEach(function (url) {
                root.addScanPath(url);
            });
        }

        // 懒加载 HTML 壁纸面板，传入解析器实例与屏幕尺寸
        Loader {
            id: thumbnailsLoader
            anchors.fill: parent

            function loadWallpaper () {
                let props = {
                    // configApi：config 根对象。MainView 及子组件（ScanPathsPanel /
                    // ThumbnailsPanel / WallpaperDelegate）经它访问 cfg_*、增删目录
                    // 方法、wallpaperBrowseCompleted 信号，契约与重构前三栏内嵌时一致。
                    configApi: root,
                    configuration: root.wallpaperConfiguration,
                    htmlWallpaper: htmlWallpaper
                };
                thumbnailsLoader.setSource("settings/MainView.qml", props);
            }
        }

        // 初次加载
        Component.onCompleted: () => {
            thumbnailsLoader.loadWallpaper();
        }
    }

    // 关闭配置页时清理内部预览标记
    Component.onDestruction: {
        if (wallpaperConfiguration)
            wallpaperConfiguration.PreviewImage = "null";
    }
}
