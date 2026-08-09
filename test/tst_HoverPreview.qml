/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

import "../package/contents/ui/settings"

/**
 * 缩略图悬停 HTML 预览行为测试(防抖 + 生命周期)。
 *
 * 验证 WallpaperDelegate 的悬停预览逻辑:
 *   - 悬停 ≥300ms 才实例化预览(防抖,快速滑过不触发);
 *   - 预览 URL 设置为入口 HTML(model.source);
 *   - 移开立即销毁实例,恢复 preview 图片。
 *
 * 环境注意:offscreen 下无法驱动只读的 hovered,也不可靠地渲染真实
 * WebEngineView,故通过注入的假组件(webViewComponentOverride)验证逻辑,
 * 并直接调用 startHoverPreview()/stopHoverPreview() 驱动(与真实鼠标
 * 经 onHoveredChanged 走同一入口)。
 */
TestCase {
    id: testCase
    name: "HoverPreviewTests"

    // KDeclarative 国际化 mock(与 tst_ThumbnailsHighlight 一致)
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    // delegate 经作用域链依赖的 cfg_*:提供默认值避免未定义警告
    property color cfg_Color: "black"
    property bool cfg_Blur: false

    property var fakeWebView: null
    property var grid: null
    property var delegate: null

    function init() {
        // 假 WebEngine 组件:带 url 的普通 Rectangle,替代真实 WebEngineView
        fakeWebView = Qt.createQmlObject(
            'import QtQuick;'
            + '\nRectangle {'
            + '\n  property string url: ""'
            + '\n}',
            testCase);
        verify(fakeWebView !== null, "假 WebEngine 组件实例化失败");

        grid = Qt.createQmlObject(
            'import QtQuick;'
            + '\nimport "../package/contents/ui/settings";'
            + '\nGridView {'
            + '\n  width: 200; height: 200'
            + '\n  cellWidth: 200; cellHeight: 200'
            + '\n  property Component fakeWebComponent: testCase.fakeWebView'
            + '\n  model: ListModel {'
            + '\n    ListElement { source: "file:///a/index.html"; preview: "file:///a/preview.png"; display: "a"; description: "desc a"; path: "file:///a"; checked: false }'
            + '\n  }'
            + '\n  delegate: WallpaperDelegate {'
            + '\n    webViewComponentOverride: fakeWebComponent'
            + '\n  }'
            + '\n}',
            testCase);
        verify(grid !== null, "GridView 实例化失败");
        // 第 0 项(唯一项)即当前项 → 拿到 delegate 实例(等首帧布局就绪)
        verify(waitForCondition(() => grid.currentItem !== null, 2000),
               "delegate 实例未就绪");
        delegate = grid.currentItem;
    }

    function cleanup() {
        if (grid) {
            grid.destroy();
            grid = null;
        }
        if (fakeWebView) {
            fakeWebView.destroy();
            fakeWebView = null;
        }
        delegate = null;
    }

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    // 悬停满 300ms 才实例化;URL 设置为入口 HTML
    function test_hover_delay_then_preview() {
        delegate.startHoverPreview();
        // 防抖期内未实例化
        verify(!delegate.hoverPreviewActive, "300ms 内不应实例化预览");
        // 满 300ms 后实例化
        verify(waitForCondition(() => delegate.hoverPreviewActive, 2000),
               "悬停满 300ms 后应实例化预览");
        compare(delegate.hoverPreviewUrl, "file:///a/index.html");
    }

    // 快速滑过(< 300ms 即移开)永不实例化
    function test_quick_move_no_preview() {
        delegate.startHoverPreview();
        delegate.stopHoverPreview(); // 立即移开
        testCase.wait(500); // 若防抖失效,此刻已实例化
        verify(!delegate.hoverPreviewActive, "快速滑过不应实例化预览");
    }

    // 移开立即销毁实例
    function test_stop_destroys_preview() {
        delegate.startHoverPreview();
        verify(waitForCondition(() => delegate.hoverPreviewActive, 2000),
               "悬停满 300ms 后应实例化预览");
        delegate.stopHoverPreview();
        verify(!delegate.hoverPreviewActive, "移开应立即销毁预览实例");
    }
}
