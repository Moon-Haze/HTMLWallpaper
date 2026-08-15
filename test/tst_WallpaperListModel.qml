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
 * 覆盖：扫描收录、get(i) 返回 WallpaperItem 元数据（name/title/file/preview 等）、
 * file 入口探测（missing-entry → real.html）、越界 get 安全返回 null。
 * fixtures 位于 test/data/wallpapers/（aurora / matrix / missing-entry / neon /
 * nova / offline 被收录）。
 */
TestCase {
    id: testCase
    name: "WallpaperListModelTests"

    // 指向 fixtures 根目录（本文件位于 test/ 下）
    property url fixtureDir: Qt.resolvedUrl("data/wallpapers")
    // 第二个扫描根：red / blue 两个壁纸目录
    property url extraDir: Qt.resolvedUrl("data/extra")
    // 每个测试函数独立创建的控制器实例
    property var htmlWallpaper: null

    SignalSpy {
        id: scanSpy
        signalName: "scanFinished"
    }

    function init() {
        htmlWallpaper = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; WallpaperController {}", testCase);
        verify(htmlWallpaper !== null, "WallpaperController 实例化失败");
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
        htmlWallpaper.scanUrls = [fixtureDir];
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

    // get(i) 返回 WallpaperItem：name/title/file 等基础元数据
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

        // aurora：title = name，缺省入口用 index.html
        compare(aurora.title, "aurora");
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file);

        // matrix：入口为 main.html
        verify(matrix.file.endsWith("/data/wallpapers/matrix/main.html"), "matrix file: " + matrix.file);
    }

    // missing-entry 目录仅 real.html → 探测到 real.html
    function test_fileFallbackWhenMissing() {
        const model = scanWallpapers();
        let missing = null;
        for (let i = 0; i < model.count; i++) {
            const item = model.get(i);
            if (item.name === "missing-entry") missing = item;
        }
        verify(missing !== null, "缺少 missing-entry");
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
        compare(missing.title, "missing-entry");
    }

    // 越界 get 安全返回 null
    function test_outOfBoundsGetReturnsNull() {
        const model = scanWallpapers();
        verify(model.get(-1) === null, "get(-1) 应为 null");
        verify(model.get(model.count) === null, "get(count) 应为 null");
        verify(model.get(model.count + 10) === null, "get(count+10) 应为 null");
    }

    // 扫描 [fixtureDir, extraDir] 两个根并等待 scanFinished
    function scanMultiRoots() {
        htmlWallpaper.scanUrls = [fixtureDir, extraDir];
        htmlWallpaper.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
        return htmlWallpaper.wallpapers;
    }

    // 多 root 分组：keys 保序、groupCount、count 汇总、byKey 组内成员
    function test_multiRootGrouping() {
        const model = scanMultiRoots();
        compare(model.count, 8, "期望 8 个壁纸(6+2)，实际 " + model.count);
        compare(model.groupCount(), 2, "期望 2 个分组");

        const keys = model.keys();
        compare(keys.length, 2, "keys 应有 2 项");
        compare(String(keys[0]), String(fixtureDir), "第一组应为 fixtureDir");
        compare(String(keys[1]), String(extraDir), "第二组应为 extraDir");

        // byKey 取整组
        const groupA = model.byKey(fixtureDir);
        verify(groupA !== null, "byKey(fixtureDir) 不应为 null");
        compare(groupA.length, 6, "fixtureDir 组应含 6 个壁纸");
        compare(String(groupA[0].name), "aurora", "fixtureDir 组第一个应为 aurora");

        const groupB = model.byKey(extraDir);
        compare(groupB.length, 2, "extraDir 组应含 2 个壁纸");
        compare(String(groupB[0].name), "blue", "extraDir 组第一个应为 blue(字母序)");

        // 不存在 key → 空数组
        const missing = model.byKey("file:///nonexistent");
        verify(missing !== null, "byKey 不存在 key 应返回空数组而非 null");
        compare(missing.length, 0, "不存在 key 应返回空组");
    }

    // 扁平顺序：groupOrder 顺序 × 组内字母序；indexOf 仍按 source 命中
    function test_flatOrderAcrossGroups() {
        const model = scanMultiRoots();
        compare(String(model.get(0).name), "aurora", "扁平第一个应为 aurora");
        compare(String(model.get(6).name), "blue", "扁平第 7 个(索引 6)应为 blue");

        compare(model.indexOf(String(model.get(0).source)), 0, "aurora 行号应为 0");
        compare(model.indexOf(String(model.get(6).source)), 6, "blue 行号应为 6");
        compare(model.indexOf("file:///nonexistent.html"), -1, "不存在 source 应返回 -1");
    }
}
