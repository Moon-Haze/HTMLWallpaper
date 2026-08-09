/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest
import Qt.labs.folderlistmodel
import com.github.moon_haze.htmlwallpaper

/**
 * HTMLBackend（C++）单元测试。
 *
 * 覆盖解析器的全部纯函数（colorToHex / 元数据 / 属性 / 查询串 / 路径工具）
 * 与异步扫描流程（QtConcurrent worker 枚举目录 + QFile 读 project.json）。
 * fixtures 位于 tests/data/wallpapers/（aurora=web、matrix=web+属性表、
 * neon=无 project.json、offline=非 web 类型）。
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
    SignalSpy {
        id: parseSpy
        signalName: "wallpaperParsed"
    }

    function init() {
        // C++ 后端模块类型，每个测试函数独立重建实例
        parser = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; HTMLBackend {}", testCase);
        verify(parser !== null, "HTMLBackend 实例化失败");
    }

    function cleanup() {
        scanSpy.target = null;
        parseSpy.target = null;
        if (parser) {
            parser.destroy();
            parser = null;
        }
    }

    // —— colorToHex ——

    function test_colorToHex() {
        compare(parser.colorToHex("0 0 0"), "#000000");
        compare(parser.colorToHex("1 1 1"), "#ffffff");
        compare(parser.colorToHex("1 0.5 0"), "#ff8000");
        compare(parser.colorToHex("0 0.5 1"), "#0080ff");
    }

    function test_colorToHex_invalid() {
        // 非字符串 → 黑
        compare(parser.colorToHex(123), "#000000");
        // 分量不足 → 黑
        compare(parser.colorToHex("1 0"), "#000000");
        // 含 NaN → 黑
        compare(parser.colorToHex("a 0 0"), "#000000");
        // 空串 → 黑
        compare(parser.colorToHex(""), "#000000");
        // 多空格容忍
        compare(parser.colorToHex("  1   0.5   0  "), "#ff8000");
    }

    function test_colorToHex_clamp() {
        // 越界值截断到 0~1
        compare(parser.colorToHex("2 0 0"), "#ff0000");
        compare(parser.colorToHex("-1 0 0"), "#000000");
        compare(parser.colorToHex("0 5 0"), "#00ff00");
    }

    // —— 元数据解析 ——

    function test_parseMetadata_fields() {
        let meta = parser._parseMetadata("file:///some/dir/aurora", {
            "title": "A Title",
            "description": "A description",
            "tags": ["tag1", "tag2"],
            "type": "web",
            "visibility": "public",
            "workshopid": 42,
            "file": "page.html",
            "preview": "prev.png"
        });
        verify(meta !== null);
        compare(meta.name, "aurora");
        compare(meta.title, "A Title");
        compare(meta.description, "A description");
        compare(meta.tags, "tag1, tag2"); // 数组序列化为逗号分隔字符串（ListModel role 不能存字符串数组）
        compare(meta.type, "web");
        compare(meta.visibility, "public");
        compare(meta.workshopid, "42"); // 数字转字符串
        compare(meta.path, "file:///some/dir/aurora");
        compare(meta.file, "file:///some/dir/aurora/page.html");
        compare(meta.entry, "file:///some/dir/aurora/page.html"); // file 的兼容别名
        compare(meta.preview, "file:///some/dir/aurora/prev.png");
    }

    function test_parseMetadata_defaults() {
        // 缺省 file → index.html；缺省 preview → 空串
        let meta = parser._parseMetadata("file:///d/wp", {});
        compare(meta.file, "file:///d/wp/index.html");
        compare(meta.entry, "file:///d/wp/index.html");
        compare(meta.preview, "");
        // title 缺省 → 目录名；type 缺省 → "web"
        compare(meta.title, "wp");
        compare(meta.type, "web");
    }

    function test_parseMetadata_extendedFields() {
        // 缺省值：monetization/supportsAudio → false，version → 0，其余 → 空串
        let m = parser._parseMetadata("file:///d/aurora", {});
        compare(m.monetization, false);
        compare(m.contentrating, "");
        compare(m.ratingsex, "");
        compare(m.ratingviolence, "");
        compare(m.version, 0);
        compare(m.workshopurl, "");
        compare(m.supportsAudio, false);
        compare(m.supportsaudioprocessing, false);
        verify(Object.keys(m.general).length === 0, "缺省 general 应为空对象");
        verify(Object.keys(m.generalProperties).length === 0, "缺省 generalProperties 应为空对象");

        // 完整字段透传（模拟 FetchTerminal 的 project.json 顶层字段）
        m = parser._parseMetadata("file:///d/fetch", {
            "monetization": true,
            "contentrating": "Everyone",
            "ratingsex": "none",
            "ratingviolence": "none",
            "version": 4,
            "workshopurl": "steam://url/CommunityFilePage/3528316973",
            "supportsAudio": true,
            "general": {
                "properties": { "theme": { "type": "combo", "value": "dark" }, "glow": { "type": "bool", "value": true } },
                "supportsaudioprocessing": true
            }
        });
        compare(m.monetization, true);
        compare(m.contentrating, "Everyone");
        compare(m.ratingsex, "none");
        compare(m.ratingviolence, "none");
        compare(m.version, 4);
        compare(m.workshopurl, "steam://url/CommunityFilePage/3528316973");
        compare(m.supportsAudio, true);
        // general 容器：原样保留 properties + supportsaudioprocessing
        compare(m.supportsaudioprocessing, true);
        compare(m.general.supportsaudioprocessing, true);
        verify("theme" in m.generalProperties, "generalProperties 应含 theme");
        compare(m.generalProperties["theme"].type, "combo");
        verify("properties" in m.general, "general 应含 properties 键");
        compare(m.general.properties["glow"].type, "bool");

        // supportsAudio 与 supportsaudioprocessing 语义区分：只有顶层 supportsAudio
        // 时合并值 supportsAudio=true，而 supportsaudioprocessing 仍为 false（仅 general 原始值）
        m = parser._parseMetadata("file:///d/x", { "supportsAudio": true });
        compare(m.supportsAudio, true);
        compare(m.supportsaudioprocessing, false);

        // supportsAudio 合并 general.supportsaudioprocessing（AudioVisualizer/CanvasBg 走此来源）
        m = parser._parseMetadata("file:///d/dots", { "general": { "supportsaudioprocessing": true } });
        compare(m.supportsAudio, true);
        // 顶层与 general 均为 false → false
        m = parser._parseMetadata("file:///d/calm", { "general": { "supportsaudioprocessing": false } });
        compare(m.supportsAudio, false);
    }

    function test_parseMetadata_webTypeFilter() {
        parser.requireWebType = true;
        verify(parser._parseMetadata("file:///d", { "type": "web" }) !== null);
        verify(parser._parseMetadata("file:///d", { "type": "web dynamic" }) !== null);
        // 明确非 HTML 类型（视频/3D 场景/程序/纯音频）→ null
        verify(parser._parseMetadata("file:///d", { "type": "scene" }) === null);
        verify(parser._parseMetadata("file:///d", { "type": "video" }) === null);
        verify(parser._parseMetadata("file:///d", { "type": "application" }) === null);
        // HTML 类壁纸除 "web" 外还有 color（纯色/渐变）、group（分组），
        // 必须收录——否则这些壁纸的扫描结果为空（历史 bug：白名单误杀）
        verify(parser._parseMetadata("file:///d", { "type": "color" }) !== null);
        verify(parser._parseMetadata("file:///d", { "type": "group" }) !== null);
        verify(parser._parseMetadata("file:///d", { "type": "Web" }) !== null); // 大小写不敏感
        // 类型缺失按 web 处理
        verify(parser._parseMetadata("file:///d", {}) !== null);

        parser.requireWebType = false;
        verify(parser._parseMetadata("file:///d", { "type": "scene" }) !== null);
    }

    // —— 扫描路径（rootPaths）——

    // 直接赋值 rootPaths 生效（数据源就是它本身，无中间模型）
    function test_rootPaths_assign() {
        parser.rootPaths = ["file:///a", "file:///b"];
        compare(parser.rootPaths.length, 2);
        compare(String(parser.rootPaths[0]), "file:///a");
        compare(String(parser.rootPaths[1]), "file:///b");
    }

    function test_rootPaths_addRemove() {
        // rootPaths 默认带一个扫描路径，先清空从无开始
        parser.rootPaths = [];
        compare(parser.rootPaths.length, 0, "初始无扫描路径");

        parser.addScanPath("file:///a");
        parser.addScanPath("file:///b/");
        compare(parser.rootPaths.length, 2);
        compare(String(parser.rootPaths[0]), "file:///a");
        compare(String(parser.rootPaths[1]), "file:///b/");

        // 重复路径去重
        parser.addScanPath("file:///a");
        compare(parser.rootPaths.length, 2, "重复路径应被拒绝");

        // 删除
        parser.removeScanPath("file:///a");
        compare(parser.rootPaths.length, 1);
        compare(String(parser.rootPaths[0]), "file:///b/");
    }


    // —— 异步扫描 ——

    function test_scanCollectsWebWallpapers() {
        scanSpy.target = parser;
        parser.rootPaths = [fixtureDir];
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
        verify(aurora.file.endsWith("/data/wallpapers/aurora/index.html"), "file: " + aurora.file); // project.json 的 file 字段（缺省 index.html）
        verify(aurora.preview.endsWith("/data/wallpapers/aurora/preview.jpg"), "preview: " + aurora.preview);

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

        // matrix 有 general.properties 可配置属性表，经 WallpaperGeneral（QObject）
        // 暴露为只读 ListModel：按 order 排序（speed=1/color=2/glow=3/charset=4）共 4 行
        verify(matrix.general !== null, "matrix.general 应为 WallpaperGeneral 对象");
        verify(matrix.general.properties !== null, "matrix.general.properties 应为 ListModel");
        compare(matrix.general.properties.count, 4, "matrix 应含 4 个可配置属性");
        compare(matrix.general.properties.get(0).key, "speed"); // order=1 首行
        compare(matrix.general.properties.get(1).key, "color");
        compare(matrix.general.properties.get(3).key, "charset");
        compare(matrix.general.properties.byKey("speed").type, "slider");
        compare(matrix.general.properties.byKey("speed").min, 1);
        compare(matrix.general.properties.byKey("color").value, "0 1 0");
        compare(matrix.general.supportsaudioprocessing, false); // matrix 的 general 无 supportsaudioprocessing
        // 便捷属性 generalProperties / supportsaudioprocessing 委托到 general 对象
        verify(matrix.generalProperties !== null, "matrix generalProperties 应为 ListModel");
        compare(matrix.generalProperties.byKey("speed").type, "slider");
        compare(matrix.supportsaudioprocessing, false);

        // nova 无 preview 字段 → 自动探测到 preview.jpg
        verify(nova.preview.endsWith("/data/wallpapers/nova/preview.jpg"), "nova preview 应自动探测: " + nova.preview);
        compare(nova.title, "Nova");

        // missing-entry 的 file 指向不存在的 ghost.html → 自动探测到 real.html
        verify(missing.file.endsWith("/data/wallpapers/missing-entry/real.html"), "missing file 应自动探测: " + missing.file);
        compare(missing.title, "Missing Entry");
    }

    function test_parseWallpaper() {
        parseSpy.target = parser;
        parser.parseWallpaper(Qt.resolvedUrl("data/wallpapers/matrix"));
        parseSpy.wait(5000);
        verify(parseSpy.count > 0, "wallpaperParsed 未在 5s 内发出");

        compare(parser.currentWallpaper.title, "Matrix Rain");
        // 可配置属性表挂在 currentWallpaper.general.properties（只读 ListModel）
        const model = parser.currentWallpaper.general.properties;
        verify(model !== null, "general.properties 应为 ListModel");
        // 按 order 排序：speed(1) color(2) glow(3) charset(4)
        compare(model.count, 4);
        compare(model.get(0).key, "speed");
        compare(model.get(1).key, "color");
        compare(model.get(2).key, "glow");
        compare(model.get(3).key, "charset");
        compare(model.get(0).value, 5);
        compare(model.get(0).min, 1);
        compare(model.get(0).max, 20);
        compare(model.get(1).value, "0 1 0");
        compare(model.get(2).value, true);
        compare(model.get(3).value, "katakana");
        compare(model.get(3).options.length, 2);
        compare(model.get(3).options[0].value, "katakana");
    }

    function test_parseWallpaper_missingJson() {
        parseSpy.target = parser;
        parser.parseWallpaper(Qt.resolvedUrl("data/wallpapers/neon"));
        // neon 无 project.json → currentWallpaper 为 null
        verify(parser.currentWallpaper === null, "无 project.json 时 currentWallpaper 应为 null");
    }

    // —— 属性模型：order 排序 + value/text/type 兜底 ——

    // paramfallback fixture 的 general.properties 各属性缺 value/text/type/order：
    // 验证 WallpaperPropertyModel 的规范化（order 升序、无 order 排最后、兜底默认值）。
    function test_propertyModel_orderAndDefaults() {
        scanSpy.target = parser;
        parser.rootPaths = [fixtureDir];
        parser.scan();
        scanSpy.wait(5000);
        verify(scanSpy.count > 0, "scanFinished 未在 5s 内发出");

        let pf = null;
        for (let i = 0; i < parser.wallpapers.count; i++) {
            const item = parser.wallpapers.get(i);
            if (item.name === "paramfallback") {
                pf = item;
                break;
            }
        }
        verify(pf !== null, "缺少 paramfallback");
        const model = pf.general.properties;
        verify(model !== null, "general.properties 应为 ListModel");
        compare(model.count, 5);
        // 按 order 排序：beta(1) alpha(2) delta(3) gamma(4)，无 order 的 epsilon 稳定排最后
        compare(model.get(0).key, "beta");
        compare(model.get(1).key, "alpha");
        compare(model.get(2).key, "delta");
        compare(model.get(3).key, "gamma");
        compare(model.get(4).key, "epsilon");
        // value 兜底默认值
        compare(model.byKey("beta").value, false);    // bool → false
        compare(model.byKey("alpha").value, 3);       // slider 无 value → min
        compare(model.byKey("delta").value, "a");     // combo 无 value → 首个 option
        compare(model.byKey("gamma").value, "0 0 0"); // color → "0 0 0"
        compare(model.byKey("epsilon").value, "");    // text → ""
        // type/text 兜底
        compare(model.byKey("epsilon").type, "text"); // type 缺省 → "text"
        compare(model.byKey("epsilon").text, "epsilon"); // text 缺省 → key
        // byKey / get 一致性
        compare(model.get(0).key, model.byKey("beta").key);
    }

    // —— 协议辅助：绝对 URL / 子路径 / query 保留 ——

    function test_parseMetadata_absoluteEntry() {
        // 绝对 URL 原样使用（不拼接壁纸目录）
        let meta = parser._parseMetadata("file:///d/wp", { "file": "https://example.com/a.html", "type": "web" });
        compare(meta.file, "https://example.com/a.html");
        compare(meta.entry, "https://example.com/a.html");
        meta = parser._parseMetadata("file:///d/wp", { "file": "file:///x/y.html", "type": "web" });
        compare(meta.entry, "file:///x/y.html");
        // 相对子路径拼接
        meta = parser._parseMetadata("file:///d/wp", { "file": "img/bg.html", "type": "web" });
        compare(meta.entry, "file:///d/wp/img/bg.html");
        // 带 query 保留
        meta = parser._parseMetadata("file:///d/wp", { "file": "page.html?x=1", "type": "web" });
        compare(meta.entry, "file:///d/wp/page.html?x=1");
    }

    // —— 协议辅助：condition 求值 ——

    function test_evaluateCondition() {
        // 空 / 未定义 → true
        verify(parser.evaluateCondition("", {}));
        verify(parser.evaluateCondition(undefined, {}));
        // 字符串比较（===）
        verify(parser.evaluateCondition("theme.value === \"custom\"", { "theme": "custom" }));
        verify(!parser.evaluateCondition("theme.value === \"custom\"", { "theme": "dark" }));
        // 布尔宽松比较（WE 惯用 ==）
        verify(parser.evaluateCondition("coloredascii.value == true", { "coloredascii": true }));
        verify(!parser.evaluateCondition("coloredascii.value == true", { "coloredascii": false }));
        // 数值比较
        verify(parser.evaluateCondition("saturation.value > 1", { "saturation": 2 }));
        verify(!parser.evaluateCondition("saturation.value > 1", { "saturation": 0.5 }));
        // 多属性引用 + 逻辑组合
        verify(parser.evaluateCondition("theme.value === \"custom\" && alpha.value > 0",
                                        { "theme": "custom", "alpha": 1 }));
        // 表达式异常 → 宽松 true（不崩溃）
        verify(parser.evaluateCondition("theme.value ===", {}));
    }
}
