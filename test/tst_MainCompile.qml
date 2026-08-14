import QtQuick
import QtTest

/**
 * main.qml（运行时入口）冒烟测试。
 *
 * 依赖 plasmashell 的 WallpaperItem 类型与 QtWebEngine，环境特殊；此处验证
 * 到 QML 可编译（Component.Ready）。
 */
TestCase {
    id: testCase
    name: "MainCompile"

    function test_main_compiles() {
        let c = Qt.createComponent("../package/contents/ui/main.qml");
        verify(c.status === Component.Ready, "main.qml 应可编译: " + c.errorString());
        c.destroy();
    }
}
