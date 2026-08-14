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
 * 覆盖异步扫描流程（QtConcurrent worker 枚举目录 + QFile 读 project.json）
 * 与 scanPaths 路径管理。fixtures 位于 tests/data/wallpapers/
 * （aurora / matrix / nova / fetch / missing-entry / paramfallback 被收录；
 *   neon 无 project.json、offline 非 web 被过滤）。
 */
TestCase {
    id: testCase
    name: "ParserTests"

    // 指向 fixtures 根目录（tst_Parser.qml 位于 tests/ 下）
    property url fixtureDir: Qt.resolvedUrl("data/wallpapers")
    // 每个测试函数独立创建的解析器实例
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

    // —— 扫描路径（scanPaths）——

    // 直接赋值 scanPaths 生效（数据源就是它本身，无中间模型）
    function test_scanPaths_assign() {
        parser.scanPaths = ["file:///a", "file:///b"];
        compare(parser.scanPaths.length, 2);
        compare(String(parser.scanPaths[0]), "file:///a");
        compare(String(parser.scanPaths[1]), "file:///b");
    }

    function test_scanPaths_addRemove() {
        // scanPaths 默认带一个扫描路径，先清空从无开始
        parser.scanPaths = [];
        compare(parser.scanPaths.length, 0, "初始无扫描路径");

        parser.addScanPath("file:///a");
        parser.addScanPath("file:///b/");
        compare(parser.scanPaths.length, 2);
        compare(String(parser.scanPaths[0]), "file:///a");
        compare(String(parser.scanPaths[1]), "file:///b/");

        // 重复路径去重
        parser.addScanPath("file:///a");
        compare(parser.scanPaths.length, 2, "重复路径应被拒绝");

        // 删除
        parser.removeScanPath("file:///a");
        compare(parser.scanPaths.length, 1);
        compare(String(parser.scanPaths[0]), "file:///b/");
    }


    // —— 异步扫描 ——

    function test_scanCollectsWebWallpapers() {
        scanSpy.target = parser;
        parser.scanPaths = [fixtureDir];
        parser.scan();
        // 注意：SignalSpy.wait() 超时会自动 FAIL 并终止测试，成功时返回 undefined，
        // 不能用 verify(wait(...))；wait 只作事件循环驱动，结果看 count
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");

        // aurora + matrix + nova + fetch + missing-entry + paramfallback 被收录；
        // neon 无 project.json、offline 非 web 被过滤
        compare(parser.wallpapers.count, 6, "期望 6 个壁纸，实际 " + parser.wallpapers.count);

        let aurora = null, matrix = null, nova = null, fetch = null, missing = null;
        for (let i = 0; i < parser.wallpapers.count; i++) {
            let item = parser.wallpapers.get(i);
            if (item.name === "aurora") aurora = item;
            if (item.name === "matrix") matrix = item;
            if (item.name === "nova") nova = item;
            if (item.name === "fetch") fetch = item;
            if (item.name === "missing-entry") missing = item;
        }
        verify(aurora !== null, "缺少 aurora");
        verify(matrix !== null, "缺少 matrix");
        verify(nova !== null, "缺少 nova");
        verify(fetch !== null, "缺少 fetch");
        verify(missing !== null, "缺少 missing-entry");

        // aurora 字段（缺省 file 用 index.html）
        compare(aurora.title, "Aurora");
        compare(aurora.workshopid, "1234567890");
        compare(aurora.tags, "aurora, sky"); // ListModel role 内是字符串，非数组
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file);
        verify(aurora.preview.endsWith("/data/wallpapers/aurora/preview.jpg"), "preview: " + aurora.preview);
        // source/display 别名
        compare(aurora.source, aurora.file);
        compare(aurora.display, "Aurora");

        // aurora 扩展元数据（project.json 顶层字段 → WallpaperItem Q_PROPERTY）
        compare(aurora.monetization, false);
        compare(aurora.contentrating, "Everyone");
        compare(aurora.ratingsex, "none");
        compare(aurora.ratingviolence, "none");
        compare(aurora.version, 3);
        compare(aurora.workshopurl, "steam://url/CommunityFilePage/1234567890");
        compare(aurora.supportsAudio, true);

        // matrix 用自定义 file=main.html
        verify(matrix.file.endsWith("/data/wallpapers/matrix/main.html"), "matrix file: " + matrix.file);

        // matrix 有 general.properties 可配置属性表，经 properties（WallpaperPropertyModel
        // ListModel）暴露：按 order 排序（speed=1/color=2/glow=3/charset=4）共 4 行
        verify(matrix.properties !== null, "matrix.properties 应为 ListModel");
        compare(matrix.properties.count, 4, "matrix 应含 4 个可配置属性");
        compare(matrix.properties.get(0).key, "speed"); // order=1 首行
        compare(matrix.properties.get(1).key, "color");
        compare(matrix.properties.get(3).key, "charset");
        compare(matrix.properties.byKey("speed").type, "slider");
        compare(matrix.properties.byKey("speed").min, 1);
        compare(matrix.properties.byKey("color").value, "0 1 0");
        compare(matrix.supportsaudioprocessing, false); // matrix 的 general 无 supportsaudioprocessing

        // nova 无 preview 字段 → 自动探测到 preview.jpg
        verify(nova.preview.endsWith("/data/wallpapers/nova/preview.jpg"), "nova preview 应自动探测: " + nova.preview);
        compare(nova.title, "Nova");

        // missing-entry 的 file 指向不存在的 ghost.html → 自动探测到 real.html
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
        compare(missing.title, "Missing Entry");
    }
}
