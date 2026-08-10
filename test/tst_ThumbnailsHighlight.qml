/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 缩略图高亮联动行为测试（currentIndex 绑定 cfg_DisplayPage）。
 *
 * 验证"配置驱动高亮"的持久绑定语义（见 docs/superpowers/specs/2026-08-09-
 * highlight-binding-design.md）：
 *   - currentIndex 由 resetCurrentIndex() 建立的 Qt.binding 驱动，跟随
 *     root.cfg_DisplayPage 变化（打开面板/改配置 → 高亮跟随当前应用壁纸）；
 *   - 无匹配项回退第一格（索引 0）；
 *   - 扫描完成（scanFinished）后重建绑定，重扫后高亮仍跟随 cfg_DisplayPage。
 *
 * 环境注意：KDeclarative 国际化函数用同名 property 注入 mock；root 经动态
 * 作用域链解析到本 TestCase（其 cfg_DisplayPage 是声明属性，可被绑定追踪）。
 */
TestCase {
    id: testCase
    name: "ThumbnailsHighlightTests"

    // KDeclarative 国际化函数 mock（返回原文；动态创建的子组件经作用域链解析）
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    // root mock：ThumbnailsView 经作用域链把 root 解析到本 TestCase，
    // cfg_DisplayPage 作为声明属性可被 Qt.binding 追踪
    property string cfg_DisplayPage: "a.html"
    signal wallpaperBrowseCompleted()
    property var root: testCase

    property var htmlWallpaper: null
    property var comp: null

    function init() {
        // htmlWallpaper mock：wallpapers（ListModel）+ scanFinished 信号
        // 注意：createQmlObject 内联对象体成员必须以换行分隔
        htmlWallpaper = Qt.createQmlObject(
            'import QtQuick;'
            + '\nQtObject {'
            + '\n  property ListModel wallpapers: ListModel {'
            + '\n    ListElement { source: "a.html"; path: "file:///a.html"; checked: false; display: "a" }'
            + '\n    ListElement { source: "b.html"; path: "file:///b.html"; checked: false; display: "b" }'
            + '\n    ListElement { source: "c.html"; path: "file:///c.html"; checked: true; display: "c" }'
            + '\n  }'
            + '\n  signal scanFinished()'
            + '\n}',
            testCase);
        verify(htmlWallpaper !== null, "htmlWallpaper mock 实例化失败");

        let c = Qt.createComponent("../package/contents/ui/settings/ThumbnailsView.qml");
        verify(c.status === Component.Ready, "ThumbnailsView 加载失败: " + c.errorString());
        comp = c.createObject(testCase, { htmlWallpaper: htmlWallpaper });
        verify(comp !== null, "ThumbnailsView 实例化失败");
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

    // 打开面板时高亮 = cfg_DisplayPage 对应项；改动配置时高亮跟随
    function test_currentIndex_followsDisplayPage() {
        // 初始 cfg_DisplayPage = "a.html" → 索引 0
        verify(waitForCondition(() => comp.view.currentIndex === 0, 2000),
               "初始 currentIndex 应为 0，实际 " + comp.view.currentIndex);

        // 改配置 → 高亮自动跟随（绑定驱动）
        cfg_DisplayPage = "b.html";
        verify(waitForCondition(() => comp.view.currentIndex === 1, 2000),
               "currentIndex 应跟随 cfg_DisplayPage 到 1，实际 " + comp.view.currentIndex);

        cfg_DisplayPage = "c.html";
        verify(waitForCondition(() => comp.view.currentIndex === 2, 2000),
               "currentIndex 应跟随 cfg_DisplayPage 到 2，实际 " + comp.view.currentIndex);
    }

    // 无匹配项回退第一格（与 checked 回退行为一致）
    function test_unmatchedDisplayPage_fallsBackToZero() {
        cfg_DisplayPage = "zzz.html";
        verify(waitForCondition(() => comp.view.currentIndex === 0, 2000),
               "无匹配应回退 0，实际 " + comp.view.currentIndex);
    }

    // 扫描完成重建绑定：重扫后高亮仍跟随 cfg_DisplayPage
    function test_scanFinished_rebuildsBinding() {
        cfg_DisplayPage = "b.html";
        verify(waitForCondition(() => comp.view.currentIndex === 1, 2000),
               "初始 b.html 应在索引 1，实际 " + comp.view.currentIndex);

        // 模拟重扫：清空模型、重新填充，触发 scanFinished → resetCurrentIndex 重建绑定
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
