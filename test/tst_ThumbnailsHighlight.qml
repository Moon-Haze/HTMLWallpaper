/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 缩略图点击联动行为测试（点击驱动高亮）。
 *
 * 锁定 ThumbnailsPanel 中 WallpaperDelegate 的 onClicked 行为：
 * 点击某缩略图 → view.model.selectedIndex = index（选中壁纸状态写入
 * model 层），且 wallpapersGrid.view.currentIndex = index（高亮跟随点击项）。
 * 不做反向同步：不验证 selectedIndex 变化反向驱动高亮。
 *
 * 环境注意：wallpaperController 用 mock（modelFor/allModel 返回的 ListModel，
 * 其声明 selectedIndex 属性模拟 C++ WallpaperModel 的 model 层状态）。
 * ListModel 是真 model，delegate 里 model.path 等 role 可直接读（单路径）。
 */
TestCase {
    id: testCase
    name: "ThumbnailsHighlightTests"

    // KDeclarative 国际化函数 mock（返回原文；动态创建的子组件经作用域链解析）
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    property var wallpaperController: null
    property var comp: null

    function init() {
        // wallpaperController mock：单文件夹 ListModel（modelFor/allModel 返回；
        // 元素含 file/path/title/preview 字段，供 delegate 与 onClicked 读取），
        // ListModel 声明 selectedIndex 属性模拟 C++ WallpaperModel 的选中状态。
        // 注意：createQmlObject 内联对象体成员必须以换行分隔。
        wallpaperController = Qt.createQmlObject(
            'import QtQuick;'
            + '\nQtObject {'
            // QtObject 无 default property，ListModel 需用 property 声明（否则
            // 直接作子对象会报 "Cannot assign to non-existent default property"）。
            + '\n  property ListModel modelA: ListModel {'
            + '\n    property int selectedIndex: -1'
            + '\n    ListElement { name: "a"; title: "a"; path: "file:///a.html"; file: "file:///a.html"; preview: "" }'
            + '\n    ListElement { name: "b"; title: "b"; path: "file:///b.html"; file: "file:///b.html"; preview: "" }'
            + '\n    ListElement { name: "c"; title: "c"; path: "file:///c.html"; file: "file:///c.html"; preview: "" }'
            + '\n  }'
            // ThumbnailsPanel 当前网格 model 直接读 wallpaperController.activeModel
            + '\n  property var activeModel: modelA'
            + '\n  function modelFor(url) { return modelA; }'
            + '\n  function allModel() { return modelA; }'
            + '\n}',
            testCase);
        verify(wallpaperController !== null, "wallpaperController mock 实例化失败");

        let c = Qt.createComponent("../package/contents/ui/view/ThumbnailsPanel.qml");
        verify(c.status === Component.Ready, "ThumbnailsPanel 加载失败: " + c.errorString());
        // 给足尺寸让 GridView 实例化可见 delegate（offscreen 下显式宽高驱动布局）
        comp = c.createObject(testCase, { wallpaperController: wallpaperController, width: 600, height: 400 });
        verify(comp !== null, "ThumbnailsPanel 实例化失败");
        c.destroy();
    }

    function cleanup() {
        if (comp) {
            comp.destroy();
            comp = null;
        }
        if (wallpaperController) {
            wallpaperController.destroy();
            wallpaperController = null;
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

    // 定位到第 i 项并触发其 delegate 的 clicked 信号（等价点击缩略图）。
    // 触发前把 currentIndex 复位到别的索引（(i + 1) % 3），使随后的
    // compare(currentIndex, i) 真实验证 onClicked 把高亮移回点击项，
    // 而非因预先设了 currentIndex=i 而恒真（自证循环）。
    function clickIndex(i) {
        comp.view.currentIndex = i;
        verify(waitForCondition(() => comp.view.currentItem !== null, 2000),
               "索引 " + i + " 的 delegate 未实例化");
        const delegate = comp.view.currentItem;   // 持有第 i 项 delegate
        comp.view.currentIndex = (i + 1) % 3;     // 复位到别的索引，使 currentIndex 断言有意义
        delegate.clicked();                        // 触发 onClicked（delegate 的 model context 仍有效）
    }

    // 点击缩略图 → view.model.selectedIndex = index，currentIndex = index
    function test_clickDelegate_setsSelectedIndexAndIndex() {
        // 初始选中为空（-1）；点击第 0 项
        clickIndex(0);
        compare(wallpaperController.allModel().selectedIndex, 0);
        compare(comp.view.currentIndex, 0);

        // 点击第 1 项 → 选中与高亮跟随点击项
        clickIndex(1);
        compare(wallpaperController.allModel().selectedIndex, 1);
        compare(comp.view.currentIndex, 1);
    }
}
