/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 标签式分组展示集成测试：左栏点击标签 → 中栏缩略图视图切换。
 *
 * 锁定 config 层联动：
 *   - 默认选中"全部"：ThumbnailsPanel.gridModel === wallpapers（全部）
 *   - 点击文件夹标签 → activeFolder = 该 URL，gridModel === byKey(url)（单组）
 *   - 点击"全部"标签 → gridModel 切回全部
 *   - 切换标签后 view.currentIndex 复位为 -1（清高亮）
 *
 * 环境注意：htmlWallpaper 用 mock（JS 数组 wallpapers + byKey）；i18n 函数 mock。
 */
TestCase {
    id: testCase
    name: "FolderTabsTests"

    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    property var host: null

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    function init() {
        let c = Qt.createComponent("FolderTabsHost.qml");
        verify(c.status === Component.Ready, "FolderTabsHost 加载失败: " + c.errorString());
        host = c.createObject(testCase);
        verify(host !== null, "host 实例化失败");
        verify(waitForCondition(() => host.scanUrlsView !== null, 2000), "面板未就绪");
        c.destroy();
    }

    function cleanup() {
        if (host) {
            host.destroy();
            host = null;
        }
    }

    // 默认"全部"：gridModel 是 wallpapers 全量数组
    function test_defaultShowsAll() {
        // activeFolder 默认空 → gridModel 连 wallpapers
        compare(host.thumbnails.activeFolder, "");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        // 全部模式下 gridModel 即 wallpapers 引用
        compare(host.thumbnails.view.model, host.htmlWallpaperController.wallpapers);
    }

    // 点击文件夹标签：触发 ListView delegate 的 clicked 信号（等价真实点击），
    // 锁定 onClicked: selectedFolder = modelData 这条链路；后续
    // activeFolder→gridModel 断言与绑定链验证（tst_FolderTabs 其余用例）一致。
    function test_clickFolderShowsGroup() {
        const list = host.scanUrlsView.folderList;
        verify(waitForCondition(() => list.count === 2, 2000), "scanUrls 未就绪");
        list.currentIndex = 0;
        verify(waitForCondition(() => list.currentItem !== null, 2000), "文件夹 delegate 未实例化");
        list.currentItem.clicked();
        compare(host.scanUrlsView.selectedFolder, "file:///root/a");
        compare(host.thumbnails.activeFolder, "file:///root/a");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        // 单组模式：gridModel 应为 groupA（byKey("file:///root/a") 返回的数组）
        compare(host.thumbnails.view.model.length, 2);
        compare(host.thumbnails.view.model[0].title, "a1");
    }

    // 点击"全部"标签 → 切回全部（先经真实点击选中某文件夹，再触发 allTab）
    function test_clickAllRestoresAll() {
        const list = host.scanUrlsView.folderList;
        list.currentIndex = 1;
        verify(waitForCondition(() => list.currentItem !== null, 2000), "文件夹 delegate 未实例化");
        list.currentItem.clicked();
        compare(host.scanUrlsView.selectedFolder, "file:///root/b");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.model.length, 1);

        // 触发固定"全部"标签点击 → selectedFolder 置空
        host.scanUrlsView.allTab.clicked();
        compare(host.scanUrlsView.selectedFolder, "");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.model, host.htmlWallpaperController.wallpapers);
        compare(host.thumbnails.view.model.length, 3);
    }

    // 切换标签后 currentIndex 复位（清高亮）
    function test_switchResetsCurrentIndex() {
        host.thumbnails.view.currentIndex = 2;
        // 先固化前置：赋值确实生效（否则断言 -1 会退化为"本来就 -1"的弱自证）
        compare(host.thumbnails.view.currentIndex, 2);
        host.scanUrlsView.selectedFolder = "file:///root/a";
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.currentIndex, -1);
    }
}
