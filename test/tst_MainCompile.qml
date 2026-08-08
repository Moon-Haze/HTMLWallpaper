import QtQuick
import QtTest

/**
 * main.qml（运行时入口）冒烟测试。
 *
 * 依赖 plasmashell 的 WallpaperItem 类型与 QtWebEngine，环境特殊；此处验证
 * 到 QML 可编译（Component.Ready）+ 混合注入的纯逻辑（_pageUrl 拼接：
 * DisplayPage 纯入口 + wallpaperProperties query，已有 ? 时用 & 续接）。
 */
TestCase {
    id: testCase
    name: "MainCompile"

    property var wallpaper: null

    function test_main_compiles() {
        let c = Qt.createComponent("../package/contents/ui/main.qml");
        verify(c.status === Component.Ready, "main.qml 应可编译: " + c.errorString());
        c.destroy();
    }

    // 实例化后验证 _pageUrl 的混合注入拼接（query 拼接是纯逻辑，不依赖 WebEngine 渲染）
    function test_pageUrl_mixed() {
        let c = Qt.createComponent("../package/contents/ui/main.qml");
        if (c.status !== Component.Ready) {
            verify(false, "编译失败: " + c.errorString());
            return;
        }
        wallpaper = c.createObject(testCase);
        verify(wallpaper !== null, "main.qml 实例化失败: " + c.errorString());

        // 无参数（{}）→ 纯入口 + wallpaperProperties query
        wallpaper._displayPage = "file:///a/index.html";
        wallpaper._propertiesJson = "{}";
        compare(wallpaper._pageUrl(), "file:///a/index.html?wallpaperProperties=%7B%7D");

        // 有参数 → URL 编码进 query
        wallpaper._propertiesJson = "{\"a\":1}";
        compare(wallpaper._pageUrl(), "file:///a/index.html?wallpaperProperties=%7B%22a%22%3A1%7D");

        // 入口已带 ? → 用 & 续接，不破坏原 query
        wallpaper._displayPage = "file:///a/index.html?x=1";
        compare(wallpaper._pageUrl(), "file:///a/index.html?x=1&wallpaperProperties=%7B%22a%22%3A1%7D");

        // 空入口 → 空串（WebEngineView.url 不接受空）
        wallpaper._displayPage = "";
        compare(wallpaper._pageUrl(), "");

        wallpaper.destroy();
        c.destroy();
    }
}
