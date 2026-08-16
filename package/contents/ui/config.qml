/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2019 David Redondo <kde@david-redondo.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

import com.github.moon_haze.htmlwallpaper
import "view" as View
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

    property alias cfg_SelectWallpaper: wallpaperController.selectWallpaper
    // property alias wallpaper: mainView.wallpaper
    property alias cfg_ScanPaths: wallpaperController.scanPaths

    spacing: 0

    // —— HTML 壁纸解析器（C++ 后端）：扫描扫描目录下含 *.html 的壁纸子目录，
    // 提供壁纸列表 / 参数表 / 预览。ScanPaths 跟随 cfg_ScanPaths（扫描目录），
    // 变化时触发重扫；ScanPaths 本身即 QStringList，QML 侧直接作目录列表的 model。
    WallpaperController {
        id: wallpaperController
        // 路径变化时重扫（数据源即 ScanPaths，无需中间模型同步）
        onScanPathsChanged: {
            wallpaperController.scan()
        }

        Component.onCompleted:{
            wallpaperController.scan()
        }
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

        RowLayout {
            id: mainView

            anchors.fill: parent
            spacing: 0
            
            // —— 左栏：扫描目录（文件夹）列表 ——
            View.ScanPathsPanel {
                id: scanPathsView
                spacing: 0
                Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                wallpaperController: wallpaperController
            }

            Kirigami.Separator {
                Layout.fillHeight: true
            }

            // —— 中栏：HTML 壁纸缩略图网格 ——
            View.ThumbnailsPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                wallpaperController: wallpaperController
            }
        }
    }
    
}
