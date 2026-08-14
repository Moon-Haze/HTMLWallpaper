/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 控制器绑定解析回归测试（防自引用 Binding loop）。
 *
 * config.qml 里 ThumbnailsPanel 的 htmlWallpaper 绑定必须经 root 别名
 * （htmlWallpaperController）引用外层控制器；若写裸 htmlWallpaper，会被
 * ThumbnailsPanel 自身同名属性遮蔽成自引用（面板拿到 null，中栏网格为空）。
 * 此测试经 ThumbnailsHost（模拟 config.qml 嵌套结构）锁定修复后语义：
 *   - 面板 htmlWallpaper 非 null 且等于外层控制器；
 *   - 面板 view.model 连到外层 wallpapers；
 *   - root 自身无 htmlWallpaper 属性（裸标识符会遮蔽外层 id 的根因）。
 *
 * 环境注意：htmlWallpaper 用 mock（QtObject 声明 selectWallpaper 属性 +
 * wallpapers ListModel）；KDeclarative 国际化函数在 qmltestrunner 不可用，
 * 用同名 property 注入 mock。
 */
TestCase {
    id: testCase
    name: "ThumbnailsBindingTests"

    // KDeclarative 国际化函数 mock（返回原文；动态创建的子组件经作用域链解析）
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    // config.qml 修复写法（root 别名）：面板应拿到外层控制器
    function test_nestedAliasBinding_resolvesOuter() {
        let c = Qt.createComponent("ThumbnailsHost.qml");
        verify(c.status === Component.Ready, "ThumbnailsHost 加载失败: " + c.errorString());
        let host = c.createObject(testCase);
        verify(host !== null, "host 实例化失败");
        verify(waitForCondition(() => host.panel !== null, 2000), "panel 未就绪");

        // 修复写法下面板拿到外层控制器（非 null、非自引用）
        verify(host.panel.htmlWallpaper !== null, "修复写法下面板 htmlWallpaper 不应为 null");
        compare(host.panel.htmlWallpaper, host.htmlWallpaperController);
        // 面板模型连到外层 wallpapers
        compare(host.panel.view.model, host.htmlWallpaperController.wallpapers);

        // 对照：root 自身无 htmlWallpaper 属性（裸 htmlWallpaper 会遮蔽外层 id）
        verify(host.htmlWallpaper === undefined,
               "root.htmlWallpaper 应为 undefined（root 无此属性）");

        host.destroy();
        c.destroy();
    }
}
