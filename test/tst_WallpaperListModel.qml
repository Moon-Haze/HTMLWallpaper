/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import com.github.moon_haze.htmlwallpaper

/**
 * WallpaperListModel（C++）单元测试。
 *
 * 覆盖：扫描收录、get(i) 返回 WallpaperItem 元数据（含扩展字段与 file 入口）、
 * file 存在性兜底（missing-entry → real.html）、越界 get 安全返回 null。
 * fixtures 位于 tests/data/wallpapers/（aurora / fetch / matrix / nova / missing-entry /
 * paramfallback 被收录）。
 */
TestCase {
    id: testCase
    name: "WallpaperListModelTests"

    // 指向 fixtures 根目录（本文件位于 tests/ 下）
    property url fixtureDir: Qt.resolvedUrl("data/wallpapers")
    // 每个测试函数独立创建的解析器实例
    property var htmlWallpaper: null

    SignalSpy {
        id: scanSpy
        signalName: "scanFinished"
    }

    function init() {
        htmlWallpaper = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; HTMLBackend {}", testCase);
        verify(htmlWallpaper !== null, "HTMLBackend 实例化失败");
        scanSpy.target = htmlWallpaper;
    }

    function cleanup() {
        scanSpy.target = null;
        if (htmlWallpaper) {
            htmlWallpaper.destroy();
            htmlWallpaper = null;
        }
    }

    // 扫描 fixture 并等待 scanFinished,返回 wallpapers 模型
    function scanWallpapers() {
        htmlWallpaper.rootPaths = [fixtureDir];
        htmlWallpaper.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
        compare(htmlWallpaper.wallpapers.count, 6, "期望 6 个壁纸，实际 " + htmlWallpaper.wallpapers.count);
        return htmlWallpaper.wallpapers;
    }

    // 扫描后按 name 排序：aurora 在首
    function test_scanCollectsWallpapers() {
        const model = scanWallpapers();
        compare(model.count, 6);
        const first = model.get(0);
        verify(first !== null, "get(0) 不应为 null");
        compare(first.name, "aurora");
    }

    // get(i) 返回 WallpaperItem：基础元数据 + 扩展字段 + file 入口
    function test_getReturnsItemMetadata() {
        const model = scanWallpapers();
        let aurora = null, matrix = null;
        for (let i = 0; i < model.count; i++) {
            const item = model.get(i);
            if (item.name === "aurora") aurora = item;
            if (item.name === "matrix") matrix = item;
        }
        verify(aurora !== null, "缺少 aurora");
        verify(matrix !== null, "缺少 matrix");

        // aurora：缺省 file 用 index.html，扩展字段来自 project.json 顶层
        compare(aurora.title, "Aurora");
        compare(aurora.workshopid, "1234567890");
        compare(aurora.tags, "aurora, sky");
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file);
        compare(aurora.monetization, false);
        compare(aurora.contentrating, "Everyone");
        compare(aurora.version, 3);
        compare(aurora.supportsAudio, true);

        // matrix：自定义 file=main.html + general.properties 可配置属性表（ListModel）
        verify(matrix.file.endsWith("/data/wallpapers/matrix/main.html"), "matrix file: " + matrix.file);
        verify(matrix.properties !== null, "matrix.properties 应为 ListModel");
        compare(matrix.properties.count, 4);
        compare(matrix.properties.byKey("speed").type, "slider");
        compare(matrix.supportsaudioprocessing, false);
    }

    // missing-entry 的 file 指向不存在的 ghost.html → 自动探测到 real.html
    function test_fileFallbackWhenMissing() {
        const model = scanWallpapers();
        let missing = null;
        for (let i = 0; i < model.count; i++) {
            const item = model.get(i);
            if (item.name === "missing-entry") missing = item;
        }
        verify(missing !== null, "缺少 missing-entry");
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
        compare(missing.title, "Missing Entry");
    }

    // 越界 get 安全返回 null
    function test_outOfBoundsGetReturnsNull() {
        const model = scanWallpapers();
        verify(model.get(-1) === null, "get(-1) 应为 null");
        verify(model.get(model.count) === null, "get(count) 应为 null");
        verify(model.get(model.count + 10) === null, "get(count+10) 应为 null");
    }
}
