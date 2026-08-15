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
 * 对话框（FolderDialog），确认后调用注入的 addScanUrl 回调把选中文件夹
 * 加入扫描目录（回调由 config 层提供，负责持久化 cfg_ScanPaths），随后
 * 调用 onAdded 通知父级刷新缩略图 / 标记配置变更。
 *
 * 依赖注入只给本组件所需的两个回调，不暴露整个 config 根对象；addScanUrl
 * 的实现保留在 config.qml（QStringList 是值类型，改 cfg_ScanPaths 才持久化）。
 */
Loader {
    id: dialogLoader

    // 注入：把选中文件夹加入扫描目录的回调（config 层 addScanUrl）
    property var addScanUrl: null
    // 注入：添加成功后的回调（父级负责刷新缩略图 / 标记配置变更）
    property var onAdded: null

    asynchronous: true
    sourceComponent: addFolderDialog

    // 监听对话框的确认 / 取消信号，把选择结果交给上层处理
    Connections {
        target: dialogLoader.item
        // 用户点击"确定"：把选中文件夹加入扫描目录并通知父级
        function onAccepted() {
            if (dialogLoader.item instanceof QtDialogs.FolderDialog) {
                if (dialogLoader.addScanUrl) {
                    dialogLoader.addScanUrl(dialogLoader.item.selectedFolder);
                }
                if (dialogLoader.onAdded) {
                    dialogLoader.onAdded();
                }
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
