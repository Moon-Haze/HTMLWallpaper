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
 * config.qml / MainView / WallpaperDelegate 依赖 KCM 框架与
 * plasmashell 注入的上下文（ imageModel 等），
 * 无法在测试环境轻量实例化，故 smoke 验证到"QML 可编译、所有 import 模块
 * 可解析"（Component.Ready）。
 *
 * AddFolderDialog 自包含（Loader + 系统文件夹对话框），只需 mock config 层
 * 上下文，故做完整实例化测试：验证它始终加载 FolderDialog（纯 HTML 模式），
 * 且确认后把选中文件夹交给 config 的 addScanPath。
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

    // AddFolderDialog 上下文 mock：其 onAccepted 调用 config 层（动态作用域里
    // 的 root 即本 TestCase）的 addScanPath / wallpaperBrowseCompleted / 配置刷新。
    property var root: ({
        addScanPath: function (path) { testCase.addedPaths.push(String(path)); },
        wallpaperBrowseCompleted: function () {},
        configurationChanged: function () {}
    })
    property var addedPaths: []

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
        // ThumbnailsView 已拆分为 MainView（三栏容器）+ ThumbnailsPanel（中栏网格）
        verify(compiles("settings/MainView.qml"), "MainView 应可编译");
        verify(compiles("settings/ThumbnailsPanel.qml"), "ThumbnailsPanel 应可编译");
    }

    function test_wallpaperDelegate_compiles() {
        verify(compiles("settings/WallpaperDelegate.qml"), "WallpaperDelegate 应可编译");
    }

    function test_slideshowComponent_compiles() {
        verify(compiles("settings/ScanPathsPanel.qml"), "ScanPathsPanel 应可编译");
    }

    function test_propertyPanel_compiles() {
        verify(compiles("settings/PropertyPanel.qml"), "PropertyPanel 应可编译");
    }

    function test_parser_compiles() {
        // HtmlWallpaperParser.qml 已删除，改为验证 C++ 后端模块可实例化
        let parser = Qt.createQmlObject(
            "import com.github.moon_haze.htmlwallpaper; HTMLBackend {}", testCase);
        verify(parser !== null, "HTMLBackend 应可实例化");
        parser.destroy();
    }

    function test_addFolderDialog_compiles() {
        verify(compiles("settings/AddFolderDialog.qml"), "AddFolderDialog 应可编译");
    }

    // —— 字符串数组 model 的 delegate 语义（scanPaths 作 model 用 modelData 防回归）——
    // scanPaths 是 QStringList，QML 里即字符串数组；字符串数组作 model 时
    // modelData 直接是元素值（没有 path role，model.path 是 undefined）。
    // 此测试固化该语义，防止将来误用 model.path 导致 delegate 拿不到路径。
    function test_stringArrayModel_usesModelData() {
        // 注意：createQmlObject 内联字符串的对象体成员必须以换行分隔
        //（同一行空格分隔会导致 "Expected token" 解析错误），故每段前加 \n。
        let container = Qt.createQmlObject(
            'import QtQuick;'
            + '\nItem {'
            + '\n  id: c'
            + '\n  property var collected: []'
            + '\n  Repeater {'
            + '\n    model: ["file:///usr/share/wp/a", "file:///usr/share/wp/b"]'
            + '\n    delegate: Item {'
            + '\n      Component.onCompleted: {'
            + '\n        c.collected.push(String(modelData));'
            + '\n      }'
            + '\n    }'
            + '\n  }'
            + '\n}',
            testCase);
        verify(waitForCondition(() => container.collected.length === 2, 2000),
               "delegate 未实例化，collected=" + container.collected.length);
        // 字符串数组 model：modelData 即元素值
        compare(container.collected[0], "file:///usr/share/wp/a");
        compare(container.collected[1], "file:///usr/share/wp/b");
        container.destroy();
    }

    // —— AddFolderDialog 实例化 smoke ——

    function test_addFolderDialog_loadsFolderDialog() {
        let d = Qt.createComponent("../package/contents/ui/settings/AddFolderDialog.qml").createObject(testCase);
        verify(d !== null, "AddFolderDialog 实例化失败");
        verify(waitForCondition(() => d.status === Loader.Ready, 3000),
               "文件夹对话框未在 3s 内加载，status=" + d.status);
        verify(d.item instanceof FolderDialog, "纯 HTML 模式应加载 FolderDialog");
        d.destroy();
    }

    // 模拟用户确认：onAccepted 应把选中文件夹交给 config 的 addScanPath
    function test_addFolderDialog_accepted_addsScanPath() {
        addedPaths = [];
        let d = Qt.createComponent("../package/contents/ui/settings/AddFolderDialog.qml").createObject(testCase);
        verify(d !== null, "AddFolderDialog 实例化失败");
        verify(waitForCondition(() => d.status === Loader.Ready && d.item, 3000),
               "FolderDialog 未加载");
        // 手动触发对话框的 accepted 信号（Connections.onAccepted 里会销毁 Loader）
        d.item.accepted();
        verify(waitForCondition(() => addedPaths.length > 0, 3000),
               "onAccepted 未调用 root.addScanPath");
    }
}
