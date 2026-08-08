/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Dialogs
import QtTest

/**
 * 高依赖组件的冒烟测试。
 *
 * config.qml / ThumbnailsComponent / WallpaperDelegate 依赖 KCM 框架与
 * plasmashell 注入的上下文（wallpaperConfiguration、imageModel 等），
 * 无法在测试环境轻量实例化，故 smoke 验证到"QML 可编译、所有 import 模块
 * 可解析"（Component.Ready）。
 *
 * AddFileDialog 自包含（Loader + 两个系统对话框），只需 mock 三个上下文对象，
 * 故做完整实例化测试：验证 Loader 依据 configDialog.currentWallpaper 在
 * FileDialog（单图模式）与 FolderDialog（HTML/幻灯片模式）之间切换。
 *
 * 环境注意：KDeclarative 的国际化函数（i18n/i18ndc 等）在 qmltestrunner 里
 * 不可用，用同名 property 注入 mock（作用域链可达动态创建的子对象）。
 */
TestCase {
    id: testCase
    name: "SmokeTests"

    // KDeclarative 国际化函数 mock（返回原文；动态创建的子组件经作用域链解析）
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    // AddFileDialog 上下文 mock。configDialog 必须是 QML 对象而非 JS 字面量：
    // 真实环境里 currentWallpaper 是 KCM 注入的可变 QML 属性，Loader 的
    // sourceComponent 绑定依赖它；JS 字面量的赋值不触发 QML 绑定重算。
    property var configDialog: Qt.createQmlObject(
        'import QtQuick; QtObject { property string currentWallpaper: "org.kde.image" }',
        testCase)
    property var imageWallpaper: ({
        lastFolder: Qt.resolvedUrl("data/img"),
        nameFilters: function () { return ["*.png", "*.jpg"]; },
        addUsersWallpaper: function (url) { return ["file:///tmp/added"]; },
        addSlidePath: function (url) { return true; }
    })
    property var root: ({
        wallpaperBrowseCompleted: function () {},
        configurationChanged: function () {}
    })

    function compiles(relPath) {
        let c = Qt.createComponent("../package/contents/ui/" + relPath);
        if (c.status !== Component.Ready) {
            fail(relPath + " 编译失败: " + c.errorString());
            return false;
        }
        c.destroy();
        return true;
    }

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    // —— 编译 smoke ——

    function test_config_compiles() {
        verify(compiles("config.qml"), "config.qml 应可编译");
    }

    function test_thumbnails_compiles() {
        verify(compiles("ThumbnailsComponent.qml"), "ThumbnailsComponent 应可编译");
    }

    function test_wallpaperDelegate_compiles() {
        verify(compiles("WallpaperDelegate.qml"), "WallpaperDelegate 应可编译");
    }

    function test_addFileDialog_compiles() {
        verify(compiles("AddFileDialog.qml"), "AddFileDialog 应可编译");
    }

    // —— AddFileDialog 实例化 smoke ——

    function test_addFileDialog_loadsFileDialog() {
        configDialog.currentWallpaper = "org.kde.image"; // 单图模式
        let d = Qt.createComponent("../package/contents/ui/AddFileDialog.qml").createObject(testCase);
        verify(d !== null, "AddFileDialog 实例化失败");
        verify(waitForCondition(() => d.status === Loader.Ready, 3000),
               "文件对话框未在 3s 内加载，status=" + d.status);
        verify(d.item instanceof FileDialog, "单图模式应加载 FileDialog");
        compare(d.item.fileMode, FileDialog.OpenFiles);
        d.destroy();
    }

    function test_addFileDialog_loadsFolderDialog() {
        configDialog.currentWallpaper = "com.github.Moon-Haze.htmlwallpaper"; // HTML/幻灯片模式
        let d = Qt.createComponent("../package/contents/ui/AddFileDialog.qml").createObject(testCase);
        verify(d !== null, "AddFileDialog 实例化失败");
        verify(waitForCondition(() => d.status === Loader.Ready, 3000),
               "文件夹对话框未在 3s 内加载，status=" + d.status);
        verify(d.item instanceof FolderDialog, "HTML 模式应加载 FolderDialog");
        d.destroy();
    }

    function test_addFileDialog_switchesWithConfig() {
        // 切换 currentWallpaper → Loader 重建对应对话框
        configDialog.currentWallpaper = "org.kde.image";
        let d = Qt.createComponent("../package/contents/ui/AddFileDialog.qml").createObject(testCase);
        verify(d !== null);
        verify(waitForCondition(() => d.status === Loader.Ready, 3000), "FileDialog 未加载");
        verify(d.item instanceof FileDialog);

        configDialog.currentWallpaper = "com.github.Moon-Haze.htmlwallpaper";
        verify(waitForCondition(() => d.status === Loader.Ready
                                && d.item instanceof FolderDialog, 3000),
               "切换配置后应重建为 FolderDialog");
        d.destroy();
    }
}
