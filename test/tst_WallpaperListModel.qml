/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import com.github.moon_haze.htmlwallpaper

/**
 * WallpaperListModel（C++）互斥单选单元测试。
 *
 * 覆盖：扫描后默认选中第一项、setExclusiveChecked 互斥写回、
 * 取消允许全不选、越界调用安全返回。
 * fixtures 位于 tests/data/wallpapers/（aurora / fetch / matrix / nova 被收录）。
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
        compare(htmlWallpaper.wallpapers.count, 4, "期望 4 个壁纸，实际 " + htmlWallpaper.wallpapers.count);
        return htmlWallpaper.wallpapers;
    }

    // 扫描后默认选中第一项（按名排序：aurora 在前）
    function test_scanDefaultFirstChecked() {
        const model = scanWallpapers();
        verify(model.get(0).checked === true, "第一项默认应被选中");
        for (let i = 1; i < model.count; i++) {
            verify(model.get(i).checked === false, "非首项不应被选中: " + i);
        }
    }

    // 勾选第 i 项 → 互斥:仅该项保持勾选,其余全部取消
    function test_exclusiveCheck() {
        const model = scanWallpapers();
        model.setExclusiveChecked(2, true);
        for (let i = 0; i < model.count; i++) {
            verify(model.get(i).checked === (i === 2), "勾选 2 后状态不符: " + i);
        }
    }

    // 取消唯一勾选项 → 允许全不选
    function test_uncheckAllowsNone() {
        const model = scanWallpapers();
        model.setExclusiveChecked(0, false);
        for (let i = 0; i < model.count; i++) {
            verify(model.get(i).checked === false, "取消后仍为勾选: " + i);
        }
    }

    // 越界调用安全返回,状态不变
    function test_outOfBounds() {
        const model = scanWallpapers();
        model.setExclusiveChecked(-1, true);
        model.setExclusiveChecked(model.count, true);
        // 越界调用不影响现有勾选状态
        verify(model.get(0).checked === true, "越界后首项应保持默认选中");
        for (let i = 1; i < model.count; i++) {
            verify(model.get(i).checked === false, "越界后非首项不应被选中: " + i);
        }
    }
}
