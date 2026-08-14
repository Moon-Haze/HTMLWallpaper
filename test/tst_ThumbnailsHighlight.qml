/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 缩略图高亮联动行为测试（currentIndex 跟随 htmlWallpaper.selectWallpaper）。
 *
 * 验证"选中壁纸驱动高亮"（2d7d7e4 重构后由 ThumbnailsPanel::updateHighlight
 * 实现，注入时 / selectWallpaperChanged / scanFinished 三处触发同步）：
 *   - currentIndex 跟随 selectWallpaper 对应项（打开面板/改配置 → 高亮跟随）；
 *   - 无匹配项回退第一格（索引 0）；
 *   - 扫描完成（scanFinished）后重新同步，重扫后高亮仍跟随 selectWallpaper。
 *
 * 环境注意：htmlWallpaper 用 mock（QtObject 声明 selectWallpaper 属性 +
 * selectWallpaperChanged 信号 + wallpapers ListModel + indexOf 辅助函数），
 * 需手动 emit selectWallpaperChanged（JS 属性赋值不自动触发信号）。
 */
TestCase {
    id: testCase
    name: "ThumbnailsHighlightTests"

    // KDeclarative 国际化函数 mock（返回原文；动态创建的子组件经作用域链解析）
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    property var htmlWallpaper: null
    property var comp: null

    function init() {
        // htmlWallpaper mock：selectWallpaper（可跟踪）+ wallpapers（ListModel）+
        // indexOf 辅助 + scanFinished 信号。注意：createQmlObject 内联对象体成员
        // 必须以换行分隔。
        htmlWallpaper = Qt.createQmlObject(
            'import QtQuick;'
            + '\nQtObject {'
            + '\n  property string selectWallpaper: "a.html"'
            + '\n  signal selectWallpaperChanged()'
            + '\n  property ListModel wallpapers: ListModel {'
            + '\n    ListElement { source: "a.html"; path: "file:///a.html"; checked: false; display: "a" }'
            + '\n    ListElement { source: "b.html"; path: "file:///b.html"; checked: false; display: "b" }'
            + '\n    ListElement { source: "c.html"; path: "file:///c.html"; checked: true; display: "c" }'
            + '\n  }'
            + '\n  function indexOf(source) {'
            + '\n    for (var i = 0; i < wallpapers.count; i++) {'
            + '\n      if (wallpapers.get(i).source === source) return i;'
            + '\n    }'
            + '\n    return -1;'
            + '\n  }'
            + '\n  signal scanFinished()'
            + '\n}',
            testCase);
        verify(htmlWallpaper !== null, "htmlWallpaper mock 实例化失败");

        let c = Qt.createComponent("../package/contents/ui/view/ThumbnailsPanel.qml");
        verify(c.status === Component.Ready, "ThumbnailsPanel 加载失败: " + c.errorString());
        comp = c.createObject(testCase, { htmlWallpaper: htmlWallpaper });
        verify(comp !== null, "ThumbnailsPanel 实例化失败");
        c.destroy();
    }

    function cleanup() {
        if (comp) {
            comp.destroy();
            comp = null;
        }
        if (htmlWallpaper) {
            htmlWallpaper.destroy();
            htmlWallpaper = null;
        }
    }

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    // 设置 selectWallpaper 并手动触发信号（mock 属性赋值不自动 emit）
    function setSelectWallpaper(value) {
        htmlWallpaper.selectWallpaper = value;
        htmlWallpaper.selectWallpaperChanged();
    }

    // 打开面板时高亮 = selectWallpaper 对应项；改动配置时高亮跟随
    function test_currentIndex_followsSelectWallpaper() {
        // 初始 selectWallpaper = "a.html"，注入时 updateHighlight 已同步 → 索引 0
        verify(waitForCondition(() => comp.view.currentIndex === 0, 2000),
               "初始 currentIndex 应为 0，实际 " + comp.view.currentIndex);

        // 改配置 → 高亮自动跟随
        setSelectWallpaper("b.html");
        verify(waitForCondition(() => comp.view.currentIndex === 1, 2000),
               "currentIndex 应跟随 selectWallpaper 到 1，实际 " + comp.view.currentIndex);

        setSelectWallpaper("c.html");
        verify(waitForCondition(() => comp.view.currentIndex === 2, 2000),
               "currentIndex 应跟随 selectWallpaper 到 2，实际 " + comp.view.currentIndex);
    }

    // 无匹配项回退第一格
    function test_unmatchedSelectWallpaper_fallsBackToZero() {
        setSelectWallpaper("zzz.html");
        verify(waitForCondition(() => comp.view.currentIndex === 0, 2000),
               "无匹配应回退 0，实际 " + comp.view.currentIndex);
    }

    // 扫描完成重新同步：重扫后高亮仍跟随 selectWallpaper
    function test_scanFinished_rebuildsBinding() {
        setSelectWallpaper("b.html");
        verify(waitForCondition(() => comp.view.currentIndex === 1, 2000),
               "初始 b.html 应在索引 1，实际 " + comp.view.currentIndex);

        // 模拟重扫：清空模型、重新填充，触发 scanFinished → updateHighlight 重新同步
        htmlWallpaper.wallpapers.clear();
        htmlWallpaper.scanFinished();
        // 空模型 → 回退 0
        verify(waitForCondition(() => comp.view.currentIndex === 0, 2000),
               "空模型应回退 0，实际 " + comp.view.currentIndex);

        htmlWallpaper.wallpapers.append({ source: "b.html", path: "file:///b.html", checked: false, display: "b" });
        htmlWallpaper.scanFinished();
        // b.html 现在在索引 0 → 高亮应回到 0
        verify(waitForCondition(() => comp.view.currentIndex === 0, 2000),
               "重扫后 b.html 应在索引 0，实际 " + comp.view.currentIndex);
    }
}
