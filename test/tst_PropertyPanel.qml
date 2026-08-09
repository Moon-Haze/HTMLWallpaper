/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import Qt.labs.folderlistmodel

import org.kde.kquickcontrols as KQuickControls

/**
 * PropertyPanel 单元测试。
 *
 * 用真实 HTMLBackend（C++）+ fetch fixture（仿 FetchTerminal 精简版：
 * type="group" 锚点、condition 显隐、覆盖 color/slider/combo/bool/text/
 * textinput/file 全类型）走完整解析链路，验证：
 *   - 可观察属性模型 _obsItems 的生成与字段透传
 *   - 分组渲染结构 _groups（锚点标题、顺序锚定、成员顺序）
 *   - 各类型控件实例化与初始值
 *   - condition 显隐切换（改 theme 后重算）
 *   - propertyChanged 信号
 *   - 可观察模型 ↔ 控件绑定同步
 */
TestCase {
    id: testCase
    name: "PropertyPanelTests"

    // KDeclarative 国际化函数 mock（作用域链可达动态创建的子对象）
    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    property url fixtureDir: Qt.resolvedUrl("data/wallpapers/fetch")

    property var parser: null
    property var panel: null

    SignalSpy {
        id: parsedSpy
        signalName: "wallpaperParsed"
    }
    SignalSpy {
        id: changedSpy
        signalName: "propertyChanged"
    }

    function init() {
        // C++ 后端模块类型；PropertyPanel 通过 htmlWallpaper 属性注入
        parser = Qt.createQmlObject("import com.github.moon_haze.htmlwallpaper; HTMLBackend {}", testCase);
        verify(parser !== null, "HTMLBackend 实例化失败");

        let comp = Qt.createComponent("../package/contents/ui/settings/PropertyPanel.qml");
        verify(comp.status === Component.Ready, "PropertyPanel 加载失败: " + comp.errorString());
        panel = comp.createObject(testCase);
        verify(panel !== null, "PropertyPanel 实例化失败");
        comp.destroy();
    }

    function cleanup() {
        parsedSpy.target = null;
        changedSpy.target = null;
        if (panel) {
            panel.destroy();
            panel = null;
        }
        if (parser) {
            parser.destroy();
            parser = null;
        }
    }

    // 解析 fetch fixture 并挂到面板（等待异步解析完成后面板自动重建）
    function loadFetch() {
        panel.htmlWallpaper = parser;
        parsedSpy.target = parser;
        parser.parseWallpaper(fixtureDir);
        parsedSpy.wait(5000);
        verify(parsedSpy.count > 0, "wallpaperParsed 未在 5s 内发出");
    }

    // 在 _obsItems 里按 key 找可观察属性项
    function obsItem(key) {
        for (let i = 0; i < panel._obsItems.length; i++) {
            if (panel._obsItems[i].key === key) {
                return panel._obsItems[i];
            }
        }
        return null;
    }

    // 从某对象递归找指定 QML 类型的子控件（用于定位布局根内部的真实控件）
    function findControl(root, klass) {
        if (!root) {
            return null;
        }
        const children = root.children;
        for (let i = 0; i < children.length; i++) {
            if (children[i] instanceof klass) {
                return children[i];
            }
            const r = findControl(children[i], klass);
            if (r) {
                return r;
            }
        }
        return null;
    }

    // —— 可观察属性模型 ——

    function test_obsItems_generated() {
        loadFetch();
        // 10 个属性（含 2 个 group 锚点）都转成 QtObject
        compare(panel._obsItems.length, 10, "期望 10 项，实际 " + panel._obsItems.length);
        const theme = obsItem("theme");
        verify(theme !== null, "缺少 theme 项");
        compare(theme.type, "combo");
        compare(theme.propValue, "dark");
        compare(theme.options.length, 2);
        compare(theme.options[1].value, "custom");
        const textsize = obsItem("textsize");
        compare(textsize.min, 4);
        compare(textsize.max, 48);
        compare(textsize.propValue, 16);
        const bg = obsItem("backgroundcolor");
        compare(bg.condition, "theme.value === \"custom\"");
        // group 锚点也在 _obsItems 中（供 condition 求值时完整覆盖），但标记为 group
        const appearance = obsItem("appearance");
        verify(appearance !== null, "缺少 appearance 锚点项");
        compare(appearance.type, "group");
    }

    // —— 分组渲染结构 ——

    function test_groups_structure() {
        loadFetch();
        compare(panel._groups.length, 2, "期望 2 组，实际 " + panel._groups.length);
        // appearance 组：显式 group 成员，标题取自 type="group" 的 text
        compare(panel._groups[0].group, "appearance");
        compare(panel._groups[0].title, "Appearance");
        compare(panel._groups[0].items.length, 2);
        compare(panel._groups[0].items[0].key, "schemecolor"); // order 1 < 3
        compare(panel._groups[0].items[1].key, "textsize");
        // themegroup 组：无显式 group 的属性顺序锚定到最近的锚点
        compare(panel._groups[1].group, "themegroup");
        compare(panel._groups[1].title, "Theme");
        compare(panel._groups[1].items.length, 6);
        compare(panel._groups[1].items[0].key, "theme");
        compare(panel._groups[1].items[5].key, "logo");
        // 组内 items 必须是 QtObject（可观察），非 JS 字面量
        verify(panel._groups[0].items[0] instanceof QtObject,
               "组内 items 应为可观察 QtObject");
        // group 锚点自身不出现在任何组的 items
        const allKeys = [];
        for (let i = 0; i < panel._groups.length; i++) {
            for (let j = 0; j < panel._groups[i].items.length; j++) {
                allKeys.push(panel._groups[i].items[j].key);
            }
        }
        verify(allKeys.indexOf("appearance") < 0, "appearance 锚点不应在 items 中");
        verify(allKeys.indexOf("themegroup") < 0, "themegroup 锚点不应在 items 中");
    }

    // —— 控件实例化与初始值 ——

    function test_controls_generated() {
        loadFetch();
        // slider → Slider（根是 RowLayout，内含 Slider）
        const sliderRoot = findChild(panel, "prop-textsize");
        verify(sliderRoot !== null, "缺少 prop-textsize 控件");
        const slider = findControl(sliderRoot, QQC2.Slider);
        verify(slider !== null, "textsize 应为 Slider");
        compare(slider.from, 4);
        compare(slider.to, 48);
        compare(slider.value, 16);

        // combo → ComboBox
        const combo = findControl(findChild(panel, "prop-theme"), QQC2.ComboBox);
        verify(combo !== null, "theme 应为 ComboBox");
        compare(combo.count, 2);
        compare(combo.currentText, "Dark"); // value "dark" → 首项

        // bool → CheckBox（根即 CheckBox，无需递归）
        const checkBox = findChild(panel, "prop-glow");
        verify(checkBox instanceof QQC2.CheckBox, "glow 应为 CheckBox");
        verify(checkBox.checked === true, "glow 初始应为 true");

        // color → ColorButton（"R G B" → #RRGGBB）
        const colorBtn = findControl(findChild(panel, "prop-schemecolor"), KQuickControls.ColorButton);
        verify(colorBtn !== null, "schemecolor 应为 ColorButton");
        compare(colorBtn.color.toString(), "#000000");

        // textinput → TextField
        const textField = findControl(findChild(panel, "prop-name"), QQC2.TextField);
        verify(textField !== null, "name 应为 TextField");
        compare(textField.text, "x");

        // file → RowLayout + Browse 按钮
        const fileRoot = findChild(panel, "prop-logo");
        verify(fileRoot !== null, "缺少 prop-logo 控件");
        const fileBtn = findControl(fileRoot, QQC2.Button);
        verify(fileBtn !== null, "logo 应有 Browse 按钮");
    }

    // —— condition 显隐 ——

    function test_condition_visibility() {
        loadFetch();
        const bg = obsItem("backgroundcolor");
        verify(bg !== null);
        // 初始 theme=dark → condition(theme==="custom") 为 false → 隐藏
        verify(bg.visibleByCondition === false, "backgroundcolor 初始应隐藏");

        // 切到 custom → 显示
        obsItem("theme").propValue = "custom";
        panel._onValueChanged();
        verify(bg.visibleByCondition === true, "backgroundcolor 应显示");

        // 切回 dark → 隐藏
        obsItem("theme").propValue = "dark";
        panel._onValueChanged();
        verify(bg.visibleByCondition === false, "backgroundcolor 应再次隐藏");

        // 无 condition 的属性恒显示
        verify(obsItem("glow").visibleByCondition === true, "glow 应恒显示");
    }

    // —— propertyChanged 信号 ——

    function test_propertyChanged_emitted() {
        loadFetch();
        changedSpy.target = panel;
        obsItem("glow").propValue = false;
        panel._onValueChanged();
        compare(changedSpy.count, 1, "改值应发一次 propertyChanged");

        // 再次改动（带 condition 重算）仍发信号
        obsItem("theme").propValue = "custom";
        panel._onValueChanged();
        compare(changedSpy.count, 2);
    }

    // —— 可观察模型 ↔ 控件绑定同步 ——

    function test_control_value_sync() {
        loadFetch();
        // 改可观察项 → ComboBox 绑定同步到新值（offscreen 下留帧处理绑定）
        obsItem("theme").propValue = "custom";
        testCase.wait(50);
        const combo = findControl(findChild(panel, "prop-theme"), QQC2.ComboBox);
        verify(combo !== null, "theme 应为 ComboBox");
        compare(combo.currentIndex, 1, "combo 应同步到 custom 的索引");
        compare(combo.currentText, "Custom");
    }
}
