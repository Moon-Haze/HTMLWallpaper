/*
    SPDX-FileCopyrightText: 2023 Fushan Wen <qydwhotmail@gmail.com>
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs as QtDialogs

/**
 * "添加文件夹"对话框加载器。
 *
 * 纯 HTML 模式（com.github.moon_haze.htmlwallpaper）：只加载文件夹选择
 * 对话框（FolderDialog），把选中的文件夹加入扫描目录——走 config.qml 的
 * addScanPath（持久化到 cfg_SlidePaths，由 rootPaths 绑定同步解析器）。
 */
Loader {
    id: dialogLoader

    asynchronous: true
    sourceComponent: addFolderDialog

    // 监听对话框的确认 / 取消信号，把选择结果交给 config 层处理
    Connections {
        target: dialogLoader.item
        // 用户点击"确定"：把选中文件夹加入扫描目录
        function onAccepted() {
            let added = false;
            if (dialogLoader.item instanceof QtDialogs.FolderDialog) {
                root.addScanPath(dialogLoader.item.selectedFolder);
                added = true;
            }
            // 确有新内容加入时，通知界面刷新并标记配置变更
            if (added) {
                root.wallpaperBrowseCompleted();
                root.configurationChanged();
            }
            // 用完即销毁对话框，释放内存
            dialogLoader.destroy();
        }
        // 用户点击"取消"：直接销毁对话框
        function onRejected() {
            dialogLoader.destroy();
        }
    }

    Component {
        id: addFolderDialog

        QtDialogs.FolderDialog {
            id: folderDialog
            visible: dialogLoader.status === Loader.Ready
            options: QtDialogs.FolderDialog.ReadOnly
            title: i18nc("@title:window", "Directory with the wallpaper to show slides from")
        }
    }
}
