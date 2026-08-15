/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import com.github.moon_haze.htmlwallpaper

/**
 * 每文件夹一个 model 的多文件夹语义测试（C++ controller 集成）。
 *
 * 覆盖：scan 后 modelFor(各扫描根) 返回对应文件夹 model（count/收录/入口
 * 探测）；两个扫描根各自独立 model；全部视图 allModel 懒建缓存实例；删一个
 * 扫描根后其 model 被释放。
 * fixtures 位于 test/data/wallpapers/（aurora / matrix / missing-entry / neon /
 * nova / offline 被收录）。
 */
TestCase {
    id: testCase
    name: "WallpaperListModelTests"

    property url fixtureDir: Qt.resolvedUrl("data/wallpapers")
    property url extraDir: Qt.resolvedUrl("data/extra")
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

    // 扫描 fixtures 并等待 scanFinished
    function scanAndWait(paths) {
        htmlWallpaper.scanPaths = paths;
        htmlWallpaper.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
    }

    // 单 root：modelFor(扫描根) 收录 6 个，get(i) 返回 WallpaperItem 元数据
    function test_scanCollectsWallpapers() {
        scanAndWait([fixtureDir]);
        const model = htmlWallpaper.modelFor(String(fixtureDir));
        verify(model !== null, "modelFor 应返回 model");
        compare(model.count, 6);
        const first = model.get(0);
        verify(first !== null, "get(0) 不应为 null");
        compare(first.name, "aurora");
    }

    // get(i) 返回 WallpaperItem：name/title/file 等基础元数据（从单 root model 取）
    function test_scanCollectsMetadata() {
        scanAndWait([fixtureDir]);
        const model = htmlWallpaper.modelFor(String(fixtureDir));
        const aurora = model.get(0);
        verify(aurora !== null, "get(0) 不应为 null");
        compare(aurora.name, "aurora");
        compare(aurora.title, "aurora");
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file);
        const matrix = model.get(1);
        verify(matrix.file.endsWith("/data/wallpapers/matrix/main.html"), "matrix file: " + matrix.file);
        const missing = model.get(2);
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
    }

    // 多 root：各文件夹独立 model；allModel 聚合跨源总数
    function test_multiRootIndependentModelsAndAggregate() {
        scanAndWait([fixtureDir, extraDir]);
        const m1 = htmlWallpaper.modelFor(String(fixtureDir));
        const m2 = htmlWallpaper.modelFor(String(extraDir));
        verify(m1 !== null && m2 !== null, "两个扫描根应有各自 model");
        compare(m1.count, 6, "fixtureDir 应收录 6 个");
        compare(m2.count, 2, "extraDir 应收录 2 个（red/blue）");

        // 全部视图：allModel 懒建并缓存同一实例
        // （聚合求和/跨源定位的 C++ 逻辑已由 tst_wallpapercontroller 覆盖）
        const all1 = htmlWallpaper.allModel();
        const all2 = htmlWallpaper.allModel();
        verify(all1 !== null, "allModel 应返回合并 model");
        compare(all1, all2, "allModel 应缓存同一实例（保活复用）");
    }

    // 移除扫描根后：modelCount 下降（releaseStaleModels）
    function test_removingRootDropsModel() {
        scanAndWait([fixtureDir, extraDir]);
        compare(htmlWallpaper.modelCount(), 2, "扫描两个根应有 2 个 model");

        htmlWallpaper.scanPaths = [fixtureDir];
        htmlWallpaper.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
        compare(htmlWallpaper.modelCount(), 1, "移除 extraDir 后其 model 应被释放");
    }
}
