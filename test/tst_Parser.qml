/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import Qt.labs.folderlistmodel
import com.github.moon_haze.htmlwallpaper

/**
 * WallpaperController（C++）单元测试。
 *
 * 覆盖异步扫描流程（QtConcurrent worker 枚举根目录下各子目录的 *.html 入口）
 * 与 scanUrls 路径管理。fixtures 位于 test/data/wallpapers/
 * （aurora / matrix / missing-entry / neon / nova / offline 被收录；
 *   fetch / paramfallback 无 html 被过滤）。
 */
TestCase {
    id: testCase
    name: "ParserTests"

    // 指向 fixtures 根目录（tst_Parser.qml 位于 test/ 下）
    property url fixtureDir: Qt.resolvedUrl("data/wallpapers")
    // 每个测试函数独立创建的控制器实例
    property var parser: null

    SignalSpy {
        id: scanSpy
        signalName: "scanFinished"
    }

    function init() {
        // C++ 后端模块类型，每个测试函数独立重建实例
        parser = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; WallpaperController {}", testCase);
        verify(parser !== null, "WallpaperController 实例化失败");
    }

    function cleanup() {
        scanSpy.target = null;
        if (parser) {
            parser.destroy();
            parser = null;
        }
    }

    // —— 扫描路径（scanUrls）——

    // 直接赋值 scanUrls 生效（数据源就是它本身，无中间模型）
    function test_scanUrls_assign() {
        parser.scanUrls = ["file:///a", "file:///b"];
        compare(parser.scanUrls.length, 2);
        compare(String(parser.scanUrls[0]), "file:///a");
        compare(String(parser.scanUrls[1]), "file:///b");
    }

    function test_scanUrls_addRemove() {
        // scanUrls 默认带一个扫描路径，先清空从无开始
        parser.scanUrls = [];
        compare(parser.scanUrls.length, 0, "初始无扫描路径");

        parser.addScanPath("file:///a");
        parser.addScanPath("file:///b/");
        compare(parser.scanUrls.length, 2);
        compare(String(parser.scanUrls[0]), "file:///a");
        compare(String(parser.scanUrls[1]), "file:///b/");

        // 重复路径去重
        parser.addScanPath("file:///a");
        compare(parser.scanUrls.length, 2, "重复路径应被拒绝");

        // 删除
        parser.removeScanPath("file:///a");
        compare(parser.scanUrls.length, 1);
        compare(String(parser.scanUrls[0]), "file:///b/");
    }


    // —— 异步扫描 ——

    function test_scanCollectsWebWallpapers() {
        scanSpy.target = parser;
        parser.scanUrls = [fixtureDir];
        parser.scan();
        // 注意：SignalSpy.wait() 超时会自动 FAIL 并终止测试，成功时返回 undefined，
        // 不能用 verify(wait(...))；wait 只作事件循环驱动，结果看 count
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");

        // aurora / matrix / missing-entry / neon / nova / offline 被收录；
        // fetch / paramfallback 无 html 被过滤
        compare(parser.wallpapers.count, 6, "期望 6 个壁纸，实际 " + parser.wallpapers.count);

        let aurora = null, matrix = null, neon = null, nova = null, offline = null, missing = null;
        let fetch = null, paramfallback = null;
        for (let i = 0; i < parser.wallpapers.count; i++) {
            let item = parser.wallpapers.get(i);
            if (item.name === "aurora") aurora = item;
            if (item.name === "matrix") matrix = item;
            if (item.name === "neon") neon = item;
            if (item.name === "nova") nova = item;
            if (item.name === "offline") offline = item;
            if (item.name === "missing-entry") missing = item;
            if (item.name === "fetch") fetch = item;
            if (item.name === "paramfallback") paramfallback = item;
        }
        verify(aurora !== null, "缺少 aurora");
        verify(matrix !== null, "缺少 matrix");
        verify(neon !== null, "缺少 neon");
        verify(nova !== null, "缺少 nova");
        verify(offline !== null, "缺少 offline");
        verify(missing !== null, "缺少 missing-entry");
        // 排除项：无 html 的目录不被收录
        verify(fetch === null, "fetch 无 html 不应被收录");
        verify(paramfallback === null, "paramfallback 无 html 不应被收录");

        // aurora：title/display = name（目录名），缺省入口探测到 index.html
        compare(aurora.title, "aurora");
        compare(aurora.display, "aurora");
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file);
        // source 是 file 的别名
        compare(aurora.source, aurora.file);

        // matrix 目录下入口为 main.html
        verify(matrix.file.endsWith("/data/wallpapers/matrix/main.html"), "matrix file: " + matrix.file);

        // nova 目录下自动探测到 preview.jpg
        verify(nova.preview.endsWith("/data/wallpapers/nova/preview.jpg"), "nova preview 应自动探测: " + nova.preview);
        compare(nova.title, "nova");

        // missing-entry 目录仅 real.html → 探测到 real.html
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
        compare(missing.title, "missing-entry");
    }
}
