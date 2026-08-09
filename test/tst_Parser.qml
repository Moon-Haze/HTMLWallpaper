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
        compare(meta.entry, "file:///some/dir/aurora/page.html");
        compare(meta.preview, "file:///some/dir/aurora/prev.png");
    }

    function test_parseMetadata_defaults() {
        // 缺省 file → index.html；缺省 preview → 空串
        let meta = parser._parseMetadata("file:///d/wp", {});
        compare(meta.entry, "file:///d/wp/index.html");
        compare(meta.preview, "");
        // title 缺省 → 目录名；type 缺省 → "web"
        compare(meta.title, "wp");
        compare(meta.type, "web");
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

    // —— 属性解析 ——

    function test_parseProperties_orderAndDefaults() {
        parser._parseProperties({
            "alpha": { "type": "slider", "value": 5, "min": 1, "max": 20, "order": 2 },
            "beta": { "type": "bool", "order": 1 },
            "gamma": { "type": "color" },
            "delta": { "type": "combo", "options": [{ "label": "A", "value": "a" }, { "label": "B", "value": "b" }] },
            "epsilon": { "type": "text" }
        });
        compare(parser.currentProperties.length, 5);
        // order 排序：beta(1) < alpha(2) 在前
        compare(parser.currentProperties[0].key, "beta");
        compare(parser.currentProperties[1].key, "alpha");
        // 无 order 的（gamma/delta/epsilon）排最后，彼此顺序不做强断言（依赖 JS 排序稳定性）
        let tail = [];
        for (let i = 2; i < 5; i++) {
            tail.push(parser.currentProperties[i].key);
        }
        tail.sort();
        compare(tail.join(","), "delta,epsilon,gamma");
        // 默认值兜底（按 key 查找，避免依赖无 order 属性的相对顺序）
        function item(key) {
            for (let i = 0; i < parser.currentProperties.length; i++) {
                if (parser.currentProperties[i].key === key) {
                    return parser.currentProperties[i];
                }
            }
            return null;
        }
        compare(item("beta").propValue, false);    // bool → false
        compare(item("alpha").propValue, 5);       // slider → value
        compare(item("gamma").propValue, "0 0 0"); // color → "0 0 0"
        compare(item("delta").propValue, "a");     // combo → 首个 option
        compare(item("epsilon").propValue, "");    // text → ""
        // 属性字段透传
        compare(item("alpha").min, 1);
        compare(item("alpha").max, 20);
        compare(item("delta").options.length, 2);
        // type 缺省 → text
        parser._parseProperties({ "x": {} });
        compare(parser.currentProperties[0].type, "text");
        compare(parser.currentProperties[0].text, "x"); // text 缺省 → key
    }

    function test_parseProperties_sliderDefault() {
        // slider 无 value → min
        parser._parseProperties({ "s": { "type": "slider", "min": 3, "max": 9 } });
        compare(parser.currentProperties[0].propValue, 3);
        // slider 无 min → 0
        parser._parseProperties({ "s": { "type": "slider" } });
        compare(parser.currentProperties[0].propValue, 0);
    }

    // —— 查询串构造 ——

    function test_buildQueryString() {
        parser._parseProperties({
            "speed": { "type": "slider", "value": 5 },
            "color": { "type": "color", "value": "0 1 0" },
            "glow": { "type": "bool", "value": true },
            "off": { "type": "bool", "value": false },
            "empty": { "type": "text", "value": "" }
        });
        let qs = parser.buildQueryString();
        verify(qs.indexOf("speed=5") >= 0, "缺少 speed=5: " + qs);
        verify(qs.indexOf("color=%2300ff00") >= 0, "color 未转 hex: " + qs); // # → %23
        verify(qs.indexOf("glow=true") >= 0, "bool true 未序列化: " + qs);
        verify(qs.indexOf("off=false") >= 0, "bool false 未序列化: " + qs);
        verify(qs.indexOf("empty") < 0, "空值不应出现: " + qs);
    }

    function test_buildQueryString_urlEncode() {
        parser._parseProperties({
            "key with space": { "type": "text", "value": "a&b=c" }
        });
        let qs = parser.buildQueryString();
        verify(qs.indexOf("key%20with%20space=a%26b%3Dc") >= 0, "URL 编码不正确: " + qs);
    }

    // —— 参数 JSON 序列化 ——

    function test_buildPropertiesJson() {
        parser._parseProperties({
            "speed": { "type": "slider", "value": 5 },
            "color": { "type": "color", "value": "0 1 0" },
            "glow": { "type": "bool", "value": true },
            "off": { "type": "bool", "value": false },
            "empty": { "type": "text", "value": "" }
        });
        let obj = JSON.parse(parser.buildPropertiesJson());
        compare(obj.speed, 5);
        compare(obj.color, "#00ff00"); // color → hex
        compare(obj.glow, true);
        compare(obj.off, false);
        // 空值属性跳过
        verify(!("empty" in obj), "空值不应出现在 JSON 中");
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

    // —— URL 拼接 ——

    function test_applyPropertiesToUrl() {
        // 无属性 → 原样返回
        parser._parseProperties({});
        compare(parser.applyPropertiesToUrl("file:///a/index.html"), "file:///a/index.html");

        // 有属性 → 加 ?
        parser._parseProperties({ "a": { "type": "text", "value": "1" } });
        compare(parser.applyPropertiesToUrl("file:///a/index.html"), "file:///a/index.html?a=1");
        // URL 已有 ? → 用 &
        compare(parser.applyPropertiesToUrl("file:///a/index.html?x=1"), "file:///a/index.html?x=1&a=1");
    }

    // —— 路径工具 ——

    function test_pathJoin() {
        compare(parser._pathJoin("file:///a/b/", "/c"), "file:///a/b/c");
        compare(parser._pathJoin("file:///a/b", "c.html"), "file:///a/b/c.html");
        compare(parser._pathJoin("file:///a/b/", "c/d.html"), "file:///a/b/c/d.html");
    }

    function test_basename() {
        compare(parser._basename("file:///a/b/c"), "c");
        compare(parser._basename("file:///a/b/c/"), "c");
        compare(parser._basename("c"), "c");
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

        // aurora + matrix + nova + fetch 被收录；neon 无 project.json、offline 非 web 被过滤
        compare(parser.wallpapers.count, 4, "期望 4 个壁纸，实际 " + parser.wallpapers.count);

        let aurora = null, matrix = null, nova = null, fetch = null;
        for (let i = 0; i < parser.wallpapers.count; i++) {
            let item = parser.wallpapers.get(i);
            if (item.name === "aurora") aurora = item;
            if (item.name === "matrix") matrix = item;
            if (item.name === "nova") nova = item;
            if (item.name === "fetch") fetch = item;
        }
        verify(aurora !== null, "缺少 aurora");
        verify(matrix !== null, "缺少 matrix");
        verify(nova !== null, "缺少 nova");
        verify(fetch !== null, "缺少 fetch");

        // aurora 字段（缺省 file 用 index.html）
        compare(aurora.title, "Aurora");
        compare(aurora.workshopid, "1234567890");
        compare(aurora.tags, "aurora, sky"); // ListModel role 内是字符串，非数组
        verify(aurora.entry.endsWith("/data/wallpapers/aurora/index.html"), "entry: " + aurora.entry);
        verify(aurora.preview.endsWith("/data/wallpapers/aurora/preview.jpg"), "preview: " + aurora.preview);

        // matrix 用自定义 file=main.html
        verify(matrix.entry.endsWith("/data/wallpapers/matrix/main.html"), "matrix entry: " + matrix.entry);

        // nova 无 preview 字段 → 自动探测到 preview.jpg
        verify(nova.preview.endsWith("/data/wallpapers/nova/preview.jpg"), "nova preview 应自动探测: " + nova.preview);
        compare(nova.title, "Nova");
    }

    function test_parseWallpaper() {
        parseSpy.target = parser;
        parser.parseWallpaper(Qt.resolvedUrl("data/wallpapers/matrix"));
        parseSpy.wait(5000);
        verify(parseSpy.count > 0, "wallpaperParsed 未在 5s 内发出");

        compare(parser.currentWallpaper.title, "Matrix Rain");
        compare(parser.currentProperties.length, 4);

        // 按 order 排序：speed(1) color(2) glow(3) charset(4)
        compare(parser.currentProperties[0].key, "speed");
        compare(parser.currentProperties[1].key, "color");
        compare(parser.currentProperties[2].key, "glow");
        compare(parser.currentProperties[3].key, "charset");

        compare(parser.currentProperties[0].propValue, 5);
        compare(parser.currentProperties[0].min, 1);
        compare(parser.currentProperties[0].max, 20);
        compare(parser.currentProperties[1].propValue, "0 1 0");
        compare(parser.currentProperties[2].propValue, true);
        compare(parser.currentProperties[3].propValue, "katakana");
        compare(parser.currentProperties[3].options.length, 2);
        compare(parser.currentProperties[3].options[0].value, "katakana");
    }

    function test_parseWallpaper_missingJson() {
        parseSpy.target = parser;
        parser.parseWallpaper(Qt.resolvedUrl("data/wallpapers/neon"));
        // neon 无 project.json → currentWallpaper 为 null
        verify(parser.currentWallpaper === null, "无 project.json 时 currentWallpaper 应为 null");
        compare(parser.currentProperties.length, 0);
    }

    // —— 协议辅助：绝对 URL / 子路径 / query 保留 ——

    function test_parseMetadata_absoluteEntry() {
        // 绝对 URL 原样使用（不拼接壁纸目录）
        let meta = parser._parseMetadata("file:///d/wp", { "file": "https://example.com/a.html", "type": "web" });
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

    // —— 协议辅助：group 分组 ——

    function test_propertyGroups() {
        // 给 g1 内属性固定 order，避免依赖无 order 属性的排序稳定性（V4 排序不稳定）
        parser._parseProperties({
            "a": { "type": "slider", "group": "g1", "value": 1, "order": 1 },
            "b": { "type": "bool", "value": true },
            "c": { "type": "combo", "group": "g2", "value": "x" },
            "d": { "type": "text", "group": "g1", "order": 2 }
        });
        function findGroup(groups, name) {
            for (let i = 0; i < groups.length; i++) {
                if (groups[i].group === name) {
                    return groups[i];
                }
            }
            return null;
        }
        let groups = parser.propertyGroups();
        compare(groups.length, 3, "期望 3 组，实际 " + groups.length);
        let g1 = findGroup(groups, "g1");
        verify(g1 !== null, "缺少 g1 组");
        compare(g1.items.length, 2);
        // g1 内按 order 排序：a(1) 在 d(2) 前
        compare(g1.items[0].key, "a");
        compare(g1.items[1].key, "d");
        let def = findGroup(groups, "");
        verify(def !== null, "缺少默认组");
        compare(def.items.length, 1);
        compare(def.items[0].key, "b");
        let g2 = findGroup(groups, "g2");
        verify(g2 !== null, "缺少 g2 组");
        compare(g2.items.length, 1);
        compare(g2.items[0].key, "c");
    }

    function test_propertyGroups_typeGroupAnchor() {
        // type="group" 属性是组锚点：key 即组名、text 即组标题；不进入任何组。
        // 无显式 group 的属性归入最近的锚点（顺序锚定）。
        parser._parseProperties({
            "schemecolor": { "type": "color", "group": "appearance", "order": 1 },
            "appearance": { "type": "group", "text": "Appearance", "order": 2 },
            "textsize": { "type": "slider", "group": "appearance", "order": 3 },
            "themegroup": { "type": "group", "text": "Theme", "order": 100 },
            "theme": { "type": "combo", "order": 101 },
            "glow": { "type": "bool", "order": 102 }
        });
        function findGroup(groups, name) {
            for (let i = 0; i < groups.length; i++) {
                if (groups[i].group === name) {
                    return groups[i];
                }
            }
            return null;
        }
        let groups = parser.propertyGroups();
        compare(groups.length, 2, "期望 2 组，实际 " + groups.length);
        // appearance 组：显式 group 的成员，锚点标题取自 type="group" 的 text
        let app = findGroup(groups, "appearance");
        verify(app !== null, "缺少 appearance 组");
        compare(app.title, "Appearance");
        compare(app.items.length, 2);
        compare(app.items[0].key, "schemecolor"); // order 1 < 3
        compare(app.items[1].key, "textsize");
        // themegroup 组：theme/glow 无显式 group，顺序锚定到最近的 themegroup 锚点
        let theme = findGroup(groups, "themegroup");
        verify(theme !== null, "缺少 themegroup 组");
        compare(theme.title, "Theme");
        compare(theme.items.length, 2);
        compare(theme.items[0].key, "theme");
        compare(theme.items[1].key, "glow");
        // 锚点自身（type="group"）不进入任何组的 items
        for (let i = 0; i < groups.length; i++) {
            for (let j = 0; j < groups[i].items.length; j++) {
                verify(groups[i].items[j].type !== "group", "group 类型属性不应出现在 items 中");
            }
        }
    }
}
