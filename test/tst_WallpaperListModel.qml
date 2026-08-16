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
    property var wallpaperController: null

    SignalSpy {
        id: scanSpy
        signalName: "scanFinished"
    }

    SignalSpy {
        id: activeModelSpy
        signalName: "activeModelChanged"
    }

    function init() {
        wallpaperController = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; WallpaperController {}", testCase);
        verify(wallpaperController !== null, "WallpaperController 实例化失败");
        scanSpy.target = wallpaperController;
        activeModelSpy.target = wallpaperController;
    }

    function cleanup() {
        activeModelSpy.target = null;
        scanSpy.target = null;
        if (wallpaperController) {
            wallpaperController.destroy();
            wallpaperController = null;
        }
    }

    // 扫描 fixtures 并等待 scanFinished
    function scanAndWait(paths) {
        wallpaperController.scanPaths = paths;
        wallpaperController.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
    }

    // 单 root：modelFor(扫描根) 收录 6 个，get(i) 返回 WallpaperItem 元数据
    function test_scanCollectsWallpapers() {
        scanAndWait([fixtureDir]);
        const model = wallpaperController.modelFor(String(fixtureDir));
        verify(model !== null, "modelFor 应返回 model");
        compare(model.count, 6);
        const first = model.get(0);
        verify(first !== null, "get(0) 不应为 null");
        compare(first.name, "aurora");
    }

    // get(i) 返回 WallpaperItem：name/title/file 等基础元数据（从单 root model 取）
    function test_scanCollectsMetadata() {
        scanAndWait([fixtureDir]);
        const model = wallpaperController.modelFor(String(fixtureDir));
        const aurora = model.get(0);
        verify(aurora !== null, "get(0) 不应为 null");
        compare(aurora.name, "aurora");
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file);
        const matrix = model.get(1);
        verify(matrix.file.endsWith("/data/wallpapers/matrix/main.html"), "matrix file: " + matrix.file);
        const missing = model.get(2);
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
    }

    // 多 root：各文件夹独立 model；allModel 聚合跨源总数
    function test_multiRootIndependentModelsAndAggregate() {
        scanAndWait([fixtureDir, extraDir]);
        const m1 = wallpaperController.modelFor(String(fixtureDir));
        const m2 = wallpaperController.modelFor(String(extraDir));
        verify(m1 !== null && m2 !== null, "两个扫描根应有各自 model");
        compare(m1.count, 6, "fixtureDir 应收录 6 个");
        compare(m2.count, 2, "extraDir 应收录 2 个（red/blue）");

        // 全部视图：allModel 懒建并缓存同一实例
        // （聚合求和/跨源定位的 C++ 逻辑已由 tst_wallpapercontroller 覆盖）
        const all1 = wallpaperController.allModel();
        const all2 = wallpaperController.allModel();
        verify(all1 !== null, "allModel 应返回合并 model");
        compare(all1, all2, "allModel 应缓存同一实例（保活复用）");
    }

    // 移除扫描根后：modelCount 下降（releaseStaleModels）
    function test_removingRootDropsModel() {
        scanAndWait([fixtureDir, extraDir]);
        compare(wallpaperController.modelCount(), 2, "扫描两个根应有 2 个 model");

        wallpaperController.scanPaths = [fixtureDir];
        wallpaperController.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");
        compare(wallpaperController.modelCount(), 1, "移除 extraDir 后其 model 应被释放");
    }

    // activeModel：ScanPathsPanel 点击驱动的状态下沉到真实 controller
    // （模拟：点击文件夹 → activeModel = modelFor(url)；点击全部 → allModel()）
    function test_activeModelTracksClickTarget() {
        scanAndWait([fixtureDir, extraDir]);
        const m1 = wallpaperController.modelFor(String(fixtureDir));
        verify(m1 !== null, "modelFor 应返回 model");

        compare(wallpaperController.activeModel, null, "默认 activeModel 应为 null");
        compare(activeModelSpy.count, 0);

        // 模拟点击文件夹：activeModel 指向该文件夹 model
        wallpaperController.activeModel = m1;
        compare(wallpaperController.activeModel, m1, "点击文件夹：activeModel 应指向 modelFor 实例");
        compare(activeModelSpy.count, 1);

        // 同值幂等：不重复 emit
        wallpaperController.activeModel = m1;
        compare(activeModelSpy.count, 1);

        // 模拟点击"全部"：activeModel 指向懒建合并 model
        wallpaperController.activeModel = wallpaperController.allModel();
        compare(wallpaperController.activeModel, wallpaperController.allModel(), "点击全部：activeModel 应指向合并 model");
        compare(activeModelSpy.count, 2);
    }
}
