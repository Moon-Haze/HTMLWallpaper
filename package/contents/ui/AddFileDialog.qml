/*
    SPDX-FileCopyrightText: 2023 Fushan Wen <qydwhotmail@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound


import QtQuick
import QtQuick.Dialogs as QtDialogs

/**
 * “添加壁纸”对话框加载器。
 *
 * 根据当前配置的壁纸类型，动态加载两种系统对话框之一：
 * - 单张图片模式（org.kde.image）→ 文件选择对话框（FileDialog），可多选图片
 * - 幻灯片/HTML 模式（com.github.Moon-Haze.htmlwallpaper）→ 文件夹选择对话框
 *   （FolderDialog），把整个文件夹加入轮播路径
 */
Loader {
    id: dialogLoader

    asynchronous: true
    // 依据当前壁纸类型决定实例化哪个对话框组件
    sourceComponent: configDialog.currentWallpaper === "org.kde.image" ? addFileDialog : addFolderDialog

    // 监听对话框的确认 / 取消信号，把选择结果交给 ImageBackend 处理
    Connections {
        target: dialogLoader.item
        // 用户点击“确定”：按对话框类型把选中内容加入壁纸库
        function onAccepted() {
            let added = false;
            if (dialogLoader.item instanceof QtDialogs.FileDialog) {
                // 文件对话框：逐张把选中的图片加入用户壁纸模型
                const fileDialog = dialogLoader.item as QtDialogs.FileDialog;
                const folder = fileDialog.currentFolder;
                fileDialog.selectedFiles.forEach(url => {
                    added |= imageWallpaper.addUsersWallpaper(url).length > 0;
                });
                imageWallpaper.lastFolder = folder;
            } else if (dialogLoader.item instanceof QtDialogs.FolderDialog) {
                // 文件夹对话框：把文件夹加入幻灯片轮播路径
                const folderDialog = dialogLoader.item as QtDialogs.FolderDialog;
                const folder = folderDialog.currentFolder;
                added = imageWallpaper.addSlidePath(folderDialog.selectedFolder);
                imageWallpaper.lastFolder = folder;
            }
            // 确有新内容加入时，通知界面刷新并标记配置变更
            if (added) {
                root.wallpaperBrowseCompleted();
                root.configurationChanged();
            }
            // 用完即销毁对话框，释放内存
            dialogLoader.destroy();
        }
        // 用户点击“取消”：直接销毁对话框
        function onRejected() {
            dialogLoader.destroy();
        }
    }

    Component {
        id: addFileDialog

        QtDialogs.FileDialog {
            id: fileDialog
            visible: dialogLoader.status === Loader.Ready
            currentFolder: imageWallpaper.lastFolder
            nameFilters: imageWallpaper.nameFilters()
            fileMode: QtDialogs.FileDialog.OpenFiles
            options: QtDialogs.FileDialog.ReadOnly
            title: i18ndc("plasma_wallpaper_org.kde.image", "@title:window", "Open Image")
        }
    }

    Component {
        id: addFolderDialog

        QtDialogs.FolderDialog {
            id: folderDialog
            visible: dialogLoader.status === Loader.Ready
            currentFolder: imageWallpaper.lastFolder
            options: QtDialogs.FolderDialog.ReadOnly
            title: i18nc("@title:window", "Directory with the wallpaper to show slides from")
        }
    }
}
