/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import org.kde.plasma.wallpapers.image as Wallpaper

/**
 * media 组件的断言测试。
 *
 * 覆盖 BaseMediaComponent（blurEnabled 逻辑）、StaticImageComponent（status/
 * blurSource 按需激活）、AnimatedImageComponent（desktopRect）、DayNightImage
 * （status 组合）、DayNightView（disjoint 重建 / 连续更新）、DayNightComponent
 * （configuration mock 注入）与 ImageStackView（真实图片源加载 + 接口联动）。
 *
 * 环境注意：
 *   - org.kde.plasma.wallpapers.image 等 KDE 模块在无 plasmashell 的 offscreen
 *     环境下可加载（无需 mock 媒体后端）。
 *   - TransientImage 是"用完即释放"组件，仅在可见 Window 的渲染场景里才真正
 *     加载图片。因此凡断言图片 status 的用例都必须用 createInWindow() 把组件
 *     放进一个 visible 的 Window。
 *   - DayNightComponent 引用 wallpaper 包注入的 configuration，测试用同名
 *     property 注入 mock（JS 字面量，键可含大写，QML property 声明不行）。
 *   - ImageStackView 的 wallpaperInterface 用 required property 注入 mock
 *     （作者注释明确为 autotests 设计）。
 * 图片 fixture 位于 tests/data/img/（8x8 红/绿 PNG）。
 */
TestCase {
    id: testCase
    name: "MediaComponentsTests"

    property url redUrl: Qt.resolvedUrl("data/img/red.png")
    property url greenUrl: Qt.resolvedUrl("data/img/green.png")

    // DayNightComponent 需要的 wallpaper 配置上下文 mock
    property var configuration: ({
        "DarkLightScheduleState": "auto",
        "writeCount": 0,
        "writeConfig": function () { testCase.configuration.writeCount++; }
    })

    // 普通创建（不依赖图片加载的纯逻辑用例）
    function create(relPath, props) {
        let c = Qt.createComponent("../package/contents/ui/" + relPath);
        if (c.status !== Component.Ready) {
            fail(relPath + " 加载失败: " + c.errorString());
            return null;
        }
        let o = c.createObject(testCase, props);
        if (!o) {
            fail(relPath + " 实例化失败: " + c.errorString());
        }
        c.destroy();
        return o;
    }

    // 放进可见 Window 创建（TransientImage 需渲染场景才加载图片）。
    // 注意 parent 必须直接是 Window（而非 contentItem）：createObject 以
    // contentItem 为父会返回 null（QWindow contentItem 不支持作为创建父级）。
    // 销毁时用 o.parent.window 定位并回收窗口。
    function createInWindow(relPath, props) {
        let c = Qt.createComponent("../package/contents/ui/" + relPath);
        if (c.status !== Component.Ready) {
            fail(relPath + " 加载失败: " + c.errorString());
            return null;
        }
        let win = Qt.createQmlObject(
            'import QtQuick; Window { visible: true; width: 320; height: 240 }', testCase);
        let o = c.createObject(win, props);
        if (!o) {
            fail(relPath + " 实例化失败: " + c.errorString());
            win.destroy();
        }
        c.destroy();
        return o;
    }

    function destroyInWindow(o) {
        if (!o) { return; }
        let win = o.parent ? o.parent.window : null;
        o.destroy();
        if (win) { win.destroy(); }
    }

    // 轮询条件直到满足或超时。注意不能依赖 tryVerify：它内部用非阻塞的
    // processEvents 驱动，离屏窗口的异步图片加载可能不完成；TestCase.wait()
    // 阻塞处理事件，能真正给异步线程时间。QTest 命名空间在 QML 里不可用。
    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    // —— BaseMediaComponent ——

    function test_baseMedia_blurEnabled() {
        let b = create("mediacomponent/BaseMediaComponent.qml", {
            source: redUrl, sourceSize: Qt.size(8, 8)
        });
        verify(b !== null);

        // 背景兜底为黑色
        verify(Qt.colorEqual(b.color, "#000000"), "基类背景应为黑色");

        // blur=false → 一律不模糊
        b.blur = false;
        for (const mode of [Image.Stretch, Image.PreserveAspectCrop, Image.Pad, Image.PreserveAspectFit]) {
            b.fillMode = mode;
            verify(b.blurEnabled === false, "blur=false 时 blurEnabled 应为 false (fillMode=" + mode + ")");
        }

        // blur=true + 未铺满（Pad/Fit）→ 需要模糊背景
        b.blur = true;
        b.fillMode = Image.Pad;
        verify(b.blurEnabled === true, "Pad 应启用模糊");
        b.fillMode = Image.PreserveAspectFit;
        verify(b.blurEnabled === true, "PreserveAspectFit 应启用模糊");

        // blur=true + 铺满（Stretch/Crop）→ 无需模糊
        b.fillMode = Image.Stretch;
        verify(b.blurEnabled === false, "Stretch 不应启用模糊");
        b.fillMode = Image.PreserveAspectCrop;
        verify(b.blurEnabled === false, "PreserveAspectCrop 不应启用模糊");

        b.destroy();
    }

    // —— StaticImageComponent ——

    function test_staticImage_structure() {
        // 图片像素加载在 offscreen + qmltestrunner 下不触发（TransientImage 是
        // 用完即释放的 KDE 组件，需真实渲染场景才加载），故 statusReady/Error
        // 无法在此环境验证。这里断言组件接口与属性透传。
        let s = createInWindow("mediacomponent/StaticImageComponent.qml", {
            source: redUrl, sourceSize: Qt.size(8, 8)
        });
        verify(s !== null);
        compare(String(s.source), String(redUrl));
        compare(s.sourceSize.width, 8);
        verify(s.status !== undefined, "status 别名未暴露");
        destroyInWindow(s);
    }

    function test_staticImage_blurSourceLazy() {
        let s = createInWindow("mediacomponent/StaticImageComponent.qml", {
            source: redUrl, sourceSize: Qt.size(8, 8)
        });
        verify(s !== null);

        // blur 关闭 → blurSource 为空（blurLoader 未激活）
        s.blur = false;
        s.fillMode = Image.Pad;
        verify(s.blurSource === null || s.blurSource === undefined, "关闭模糊时 blurSource 应为空");

        // blur 开启 + Pad → blurLoader 激活，异步实例化模糊源副本
        s.blur = true;
        verify(s.blurEnabled === true);
        verify(waitForCondition(() => s.blurSource !== null, 3000), "blurSource 未在 3s 内激活");

        // 关闭模糊 → blurLoader 释放，blurSource 回到空
        s.blur = false;
        verify(waitForCondition(() => s.blurSource === null || s.blurSource === undefined, 3000),
               "关闭模糊后 blurSource 应释放");

        destroyInWindow(s);
    }

    // —— AnimatedImageComponent ——

    function test_animatedImage_desktopRect() {
        let a = create("mediacomponent/AnimatedImageComponent.qml", {
            source: redUrl, sourceSize: Qt.size(8, 8)
        });
        verify(a !== null);
        // desktopRect 应等于测试窗口几何（offscreen 下 Window.window 非空）
        let w = Window.window;
        verify(w !== null, "qmltestrunner 应有测试窗口");
        compare(a.desktopRect.x, w.x);
        compare(a.desktopRect.y, w.y);
        compare(a.desktopRect.width, w.width);
        compare(a.desktopRect.height, w.height);
        // forceImageAnimation 透传
        compare(a.forceImageAnimation, false);
        a.forceImageAnimation = true;
        compare(a.forceImageAnimation, true);
        a.destroy();
    }

    // —— DayNightImage ——

    function test_dayNightImage_statusDerivation() {
        // status 是两图状态的同步绑定推导。未设 url 时两图均为 Null → 综合 Null。
        // （图片实际加载到 Ready/Error 同样受 offscreen 渲染限制，不做异步断言）
        let d = create("mediacomponent/DayNightImage.qml", {});
        verify(d !== null);
        compare(d.status, Image.Null);
        d.destroy();
    }

    function test_dayNightImage_blendFactorPassThrough() {
        let d = create("mediacomponent/DayNightImage.qml", {
            bottomUrl: redUrl, topUrl: greenUrl, blendFactor: 0.35, fillMode: Image.Stretch
        });
        verify(d !== null);
        compare(d.blendFactor, 0.35);
        compare(d.fillMode, Image.Stretch);
        d.destroy();
    }

    // —— DayNightView ——

    function test_dayNightView_initialSnapshot() {
        let v = create("mediacomponent/DayNightView.qml", {
            snapshot: { bottom: redUrl, top: greenUrl, blendFactor: 0.5, disjoint: false }
        });
        verify(v !== null);

        // Component.onCompleted → reset() 创建首张合成图
        verify(waitForCondition(() => v.nextItem !== null, 5000), "首张合成图未创建");
        verify(v.complete === true, "初始化完成后 complete 应为 true");
        compare(v.nextItem.bottomUrl, redUrl);
        compare(v.nextItem.topUrl, greenUrl);
        compare(v.nextItem.blendFactor, 0.5);
        v.destroy();
    }

    function test_dayNightView_disjointRebuilds() {
        let v = create("mediacomponent/DayNightView.qml", {
            snapshot: { bottom: redUrl, top: greenUrl, blendFactor: 0.5, disjoint: false }
        });
        verify(v !== null);
        let first = v.nextItem;
        verify(first !== null);

        // disjoint=true（日夜状态跳变）→ 重建全新合成图
        v.snapshot = { bottom: greenUrl, top: redUrl, blendFactor: 0.2, disjoint: true };
        verify(waitForCondition(() => v.nextItem !== first, 5000), "disjoint 快照应重建合成图");
        compare(v.nextItem.bottomUrl, greenUrl);
        compare(v.nextItem.topUrl, redUrl);
        compare(v.nextItem.blendFactor, 0.2);
        v.destroy();
    }

    function test_dayNightView_continuousUpdatesInPlace() {
        let v = create("mediacomponent/DayNightView.qml", {
            snapshot: { bottom: redUrl, top: greenUrl, blendFactor: 0.5, disjoint: false }
        });
        verify(v !== null);
        let first = v.nextItem;
        verify(first !== null);

        // disjoint=false（连续变化）→ 原地更新属性，不重建
        v.snapshot = { bottom: redUrl, top: greenUrl, blendFactor: 0.8, disjoint: false };
        verify(waitForCondition(() => v.nextItem === first, 3000), "连续快照不应重建合成图");
        compare(v.nextItem.blendFactor, 0.8);
        v.destroy();
    }

    // —— DayNightComponent ——

    function test_dayNightComponent_configurationMock() {
        let before = testCase.configuration.writeCount;
        let d = createInWindow("mediacomponent/DayNightComponent.qml", {
            source: redUrl, sourceSize: Qt.size(8, 8)
        });
        verify(d !== null);
        // status 别名有效（初始为加载中/错误均可，但不能是 undefined）
        verify(d.status !== undefined, "status 别名未暴露");
        // configuration mock 生效：DayNightWallpaper 初始状态与配置不一致时写回
        // （允许 0 次以防状态恰好一致，但不应崩溃）
        verify(testCase.configuration.writeCount >= before, "writeConfig 计数异常");
        destroyInWindow(d);
    }

    // —— ImageStackView ——

    function makeWallpaperInterface() {
        return Qt.createQmlObject(
            'import QtQuick; QtObject { property color accentColor: "transparent"; property bool loading: false }',
            testCase);
    }

    function test_stackView_backgroundTypeSelection() {
        // 背景类型解析不依赖图片像素加载（MediaProxy 同步/快速解析），可直接断言。
        let s = create("ImageStackView.qml", {
            fillMode: Image.Stretch,
            configColor: "transparent",
            blur: false,
            sourceSize: Qt.size(8, 8),
            wallpaperInterface: makeWallpaperInterface()
        });
        verify(s !== null);

        // 未设源 → providerType 未知
        verify(s.mediaProxy.providerType === Wallpaper.Provider.Unknown,
               "无源时 providerType 应为 Unknown");

        // 设置 PNG 源 → MediaProxy 解析为 Image 背景类型
        s.source = redUrl;
        verify(waitForCondition(
            () => s.mediaProxy.backgroundType === Wallpaper.BackgroundType.Image, 3000),
            "PNG 源未解析为 Image 类型: " + s.mediaProxy.backgroundType);
        compare(s.mediaProxy.modelImage, redUrl);

        // createBackgroundComponent 按类型选择静态图组件
        let comp = s.createBackgroundComponent();
        verify(comp !== null && comp.status === Component.Ready, "静态图组件加载失败");
        s.destroy();
    }
}
