# PropertyPanel 参数面板重写 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 重写 `view/PropertyPanel.qml`，从 C++ backend 加载的 wallpaper 的 `WallpaperItem::properties`（只读 `WallpaperPropertyModel`）获取调节参数，按 `type` 自适应加载对应控件，改动每壁纸一份写入 `cfg_WallpaperProperties` 并实时应用到 HTML 壁纸页面。

**Architecture:** 中栏点击壁纸 → `htmlWallpaper.selectWallpaper = model.file` → PropertyPanel 监听 `selectWallpaperChanged`，经 `wallpapers.byKey(file)` 定位 `WallpaperItem`，遍历其 `properties` 建可观察 QtObject 镜像 + 分组；控件改动更新镜像 → 重算 condition 可见性 → 组装 `{file:{...}}` 写 `cfg_WallpaperProperties`（KCM 持久化）→ 渲染实例 `main.qml` 提取当前壁纸段并注入 HTML 页面。condition 求值在 C++ `HTMLBackend::evaluateCondition`（QJSEngine，复刻旧版逻辑）。

**Tech Stack:** Qt 6.10+ / KF6 6.26+ / QML + QtQuick / QJSEngine / CMake Presets（native）。

## Global Constraints

- 全部新增/修改代码注释与提交信息用简体中文（项目约定）；代码标识符保持英文。
- Qt ≥ 6.10，KF6 ≥ 6.26；`find_package(Qt6 REQUIRED COMPONENTS Core Quick Qml Concurrent)`（顶层 CMakeLists 已满足）。
- 变量/参数名避开 `slots` / `signals` / `emit` / `foreach`（Qt `#define` 会吞同名标识符）。
- 用 `QList` 不用 `QVector`（Qt 6.11 已移除 QVector 别名）。
- 参数 JSON 结构固定：`{ "<file>": { key: value, ... }, ... }`；段 key 用 `file`（与 `selectWallpaper` / `_displayPage` / `WallpaperItem.source()` 同一值）。
- `evaluateCondition`：空 condition / 语法错误 / 求值异常 → 宽松返回 `true`（属性始终显示）。
- `WallpaperPropertyItem` Q_PROPERTY 全 `CONSTANT` 只读；QML 侧 `get(i)` 返回值缺键即 `undefined`，强类型字段赋值前须兜底（`p.x !== undefined ? p.x : ""`）。
- 不改 `test/CMakeLists.txt`：QML 测试由 `file(GLOB CONFIGURE_DEPENDS "tst_*.qml")` 自动收集，新增 `test/tst_evaluateCondition.qml` 即自动注册。
- 构建命令：`cmake --build --preset native`（build 目录已配置 native 预设）；测试：`ctest --preset native -R <name> -V`；QML 静态检查：`qmllint`（/usr/bin/qmllint）。

---

## 文件结构

| 文件 | 动作 | 职责 |
|---|---|---|
| `plugin/htmlbackend.h` | 修改 | 声明 `Q_INVOKABLE bool evaluateCondition(...)`；成员 `QJSEngine m_engine` |
| `plugin/htmlbackend.cpp` | 修改 | 实现 `evaluateCondition`（QJSEngine） |
| `test/tst_evaluateCondition.qml` | 新建 | 测试 evaluateCondition 各语法用例 |
| `package/contents/ui/main.qml` | 修改 | `_propertiesJson` 改为提取当前 `_displayPage` 参数段 |
| `package/contents/ui/view/PropertyPanel.qml` | 重写 | 消费新契约：byKey 定位壁纸、读 properties、按 type 加载控件、condition 过滤、写回 JSON |
| `package/contents/ui/config.qml` | 修改 | 恢复右栏 PropertyPanel 挂载 |

依赖顺序：Task 1（C++）独立 → Task 2（main.qml）独立 → Task 3（PropertyPanel，依赖 Task 1）→ Task 4（config.qml，依赖 Task 3）。

---

## Task 1: C++ HTMLBackend 恢复 evaluateCondition

**Files:**
- Modify: `plugin/htmlbackend.h`
- Modify: `plugin/htmlbackend.cpp`
- Create: `test/tst_evaluateCondition.qml`

**Interfaces:**
- Produces: `bool HTMLBackend::evaluateCondition(const QString &condition, const QVariantMap &props)` — Q_INVOKABLE，QML 可调用；`condition` 形如 `theme.value === "custom"`，`props` 为 key→value 映射；空 / 语法错误 → `true`。Task 3 的 `_recomputeVisibility()` 消费它。

- [ ] **Step 1: 写失败测试 `test/tst_evaluateCondition.qml`**

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
import QtQuick
import QtTest

import com.github.moon_haze.htmlwallpaper

Item {
    id: root

    HTMLBackend {
        id: parser
    }

    TestCase {
        name: "evaluateCondition"

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
}
```

- [ ] **Step 2: 构建并跑测试确认失败**

Run: `cmake --build --preset native && ctest --preset native -R tst_evaluateCondition -V`
Expected: FAIL — `parser.evaluateCondition is not a function`（方法尚不存在）。若构建报错停在编译，同样符合预期。

- [ ] **Step 3: 在 `plugin/htmlbackend.h` 加声明与 QJSEngine 成员**

在文件头 include 区加 `#include <QJSEngine>`（`#include "wallpaperlistmodel.h"` 之后）：

```cpp
#include "wallpaperlistmodel.h"
#include "wallpaperproject.h" // ScanResult / WallpaperProjectJson

#include <QJSEngine>
```

在 public 的 Q_INVOKABLE 区（`scan()` 声明之后）加：

```cpp
    /** 求值 property condition（如 "theme.value === \"custom\""）；空 / 语法错误 → 宽松 true。 */
    Q_INVOKABLE bool evaluateCondition(const QString &condition, const QVariantMap &props);
```

在 private 区（`bool m_scanning = false;` 之后）加成员：

```cpp
    bool m_scanning = false;
    QJSEngine m_engine; // property condition 求值引擎（仅主线程使用）
    WallpaperListModel *m_wallpapers = nullptr;
```

- [ ] **Step 4: 在 `plugin/htmlbackend.cpp` 实现 evaluateCondition**

在文件末尾 `HTMLBackend::scan()` 实现之后追加：

```cpp
bool HTMLBackend::evaluateCondition(const QString &condition, const QVariantMap &props)
{
    const QString cond = condition.trimmed();
    if (cond.isEmpty()) {
        return true;
    }
    // 与旧实现（pkg/local/src/plugin/htmlbackend.cpp）等价：每个属性键作为参数名
    // 注入，表达式通过 .value 引用属性值。
    const QStringList keys = props.keys();
    const QString src = QStringLiteral("(function(") + keys.join(QStringLiteral(","))
                        + QStringLiteral(") { return (") + cond + QStringLiteral("); })");
    QJSValue fn = m_engine.evaluate(src);
    if (!fn.isCallable()) {
        return true; // 语法错误（如 "theme.value ==="）→ 宽松 true
    }
    QJSValueList args;
    args.reserve(keys.size());
    for (const QString &k : keys) {
        QJSValue wrapper = m_engine.newObject();
        wrapper.setProperty(QStringLiteral("value"), m_engine.toScriptValue(props.value(k)));
        args.append(wrapper);
    }
    const QJSValue result = fn.call(args);
    if (result.isError()) {
        return true;
    }
    return result.toBool();
}
```

- [ ] **Step 5: 构建并跑测试确认通过**

Run: `cmake --build --preset native && ctest --preset native -R tst_evaluateCondition -V`
Expected: PASS（8 个 verify / verify! 断言全过，1 条 TestCase 通过）。

- [ ] **Step 6: 提交**

```bash
git add plugin/htmlbackend.h plugin/htmlbackend.cpp test/tst_evaluateCondition.qml
git commit -m "feat(backend): HTMLBackend 恢复 evaluateCondition（QJSEngine 求值 property condition）

复刻旧版实现：空/语法错误/求值异常宽松返回 true；每个属性键作函数参数，
表达式经 .value 引用属性值。新增 tst_evaluateCondition.qml 覆盖 ===/==/>/&& 用例。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: main.qml 适配每壁纸参数段提取

**Files:**
- Modify: `package/contents/ui/main.qml`

**Interfaces:**
- Consumes: `configuration.WallpaperProperties`（字符串，`{file:{...}}` 结构）、`_displayPage`（当前入口 URL）。
- Produces: `string _extractPropertiesForPage()` — 解析配置、取 `_displayPage` 段、返回该段 JSON（无匹配段 → `"{}"`）。供 `_injectProperties()` 使用。

背景：`_propertiesJson` 目前直接等于 `configuration.WallpaperProperties`（全局单份）；现改为每壁纸一份后，注入页面的必须是当前 `_displayPage` 对应的参数段，否则页面收到 `{file:{...}}` 而非 `{key:value}`。

- [ ] **Step 1: 在 `_pageUrl()` 定义之后加 `_extractPropertiesForPage()`**

```qml
    // 从配置 WallpaperProperties（每壁纸一份 { "<file>": {key:value} }）提取当前
    // _displayPage 对应的参数段；无匹配段返回 "{}"（页面用 project.json 默认值）。
    function _extractPropertiesForPage(): string {
        let all = {};
        try {
            all = JSON.parse(wallpaper.configuration.WallpaperProperties || "{}");
        } catch (e) {
            all = {};
        }
        const seg = all[wallpaper._displayPage];
        return JSON.stringify(seg && typeof seg === "object" ? seg : {});
    }
```

- [ ] **Step 2: 改 `onValueChanged("WallpaperProperties")` 分支**

原：

```qml
            } else if (key === "WallpaperProperties") {
                wallpaper._propertiesJson = wallpaper.configuration.WallpaperProperties || "{}";
                wallpaper._injectProperties();
```

改：

```qml
            } else if (key === "WallpaperProperties") {
                wallpaper._propertiesJson = wallpaper._extractPropertiesForPage();
                wallpaper._injectProperties();
```

- [ ] **Step 3: 改 `Component.onCompleted`**

原：

```qml
    Component.onCompleted: {
        wallpaper._displayPage = wallpaper.configuration.SelectWallpaper || "";
        wallpaper._propertiesJson = wallpaper.configuration.WallpaperProperties || "{}";
        wallpaper._applyUrl();
    }
```

改：

```qml
    Component.onCompleted: {
        wallpaper._displayPage = wallpaper.configuration.SelectWallpaper || "";
        wallpaper._propertiesJson = wallpaper._extractPropertiesForPage();
        wallpaper._applyUrl();
    }
```

- [ ] **Step 4: qmllint 静态检查**

Run: `qmllint -I build/bin package/contents/ui/main.qml`
Expected: 无 error（main.qml 引用 `WallpaperItem` 基类类型，若报"类型未定义"，确认是 warning 级别不阻塞即可）。

- [ ] **Step 5: 提交**

```bash
git add package/contents/ui/main.qml
git commit -m "refactor(ui): main.qml 从每壁纸参数 JSON 提取当前壁纸段注入页面

WallpaperProperties 改为 {file:{...}} 结构后，_propertiesJson 不再直接取配置，
经 _extractPropertiesForPage() 取 _displayPage 对应段，无段回退 {}。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: PropertyPanel.qml 重写（新契约）

**Files:**
- Rewrite: `package/contents/ui/view/PropertyPanel.qml`

**Interfaces:**
- Consumes:
  - `htmlWallpaper`（HTMLBackend）：`selectWallpaper` / `wallpapers.byKey(file)` / `evaluateCondition(cond, propsMap)` / `scanFinished` 信号。
  - `WallpaperPropertyItem` 字段：key/type/text/value/min/max/step/fraction/precision/options/condition/group/order（Q_PROPERTY 全 CONSTANT）。
- Produces:
  - 属性 `QtObject htmlWallpaper`（注入）。
  - 属性 `string wallpaperPropertiesJson`（已存参数 JSON，每壁纸一份）。
  - 信号 `void applyProperties(string json)`（改动后发完整 JSON 给外层）。
  - Task 4（config.qml）消费以上三个。

重写要点（对照旧文件）：
1. 删除旧顶部"已停用"注释与旧契约引用；更新为消费 `WallpaperItem::properties`。
2. 输入属性：保留 `htmlWallpaper`；新增 `wallpaperPropertiesJson` + `applyProperties` 信号。
3. `currentWallpaper` 改为派生：`htmlWallpaper.selectWallpaper` 非空 → `htmlWallpaper.wallpapers.byKey(file)`，否则 null。
4. 重建驱动：`Connections` 监听 `htmlWallpaper` 的 `selectWallpaperChanged` 与 `scanFinished` → `_rebuild()`（`htmlWallpaper` 为 null 时 `enabled: false`）。
5. `_rebuild()`：模型来源改 `item.properties`（`get(i)`），遍历建 QtObject 镜像；用当前壁纸已存段 `_storedProps` 覆盖默认 `value`。
6. `_recomputeVisibility()`：调 `htmlWallpaper.evaluateCondition(item.condition, propsMap)`（Task 1 提供，签名一致）。
7. `_onValueChanged()`：重算可见性 → 组装 `{file:{...}}`（解析 `wallpaperPropertiesJson` 保留其他段，仅替换当前段）→ `applyProperties(json)`。
8. color 组件：去掉 `colorToHex` 依赖，改用 `_rgbToColor("R G B")` 转 QML color；QML color → `"R G B"` 沿用旧 `_hexToRgb`。
9. file 组件：`currentFolder` 改用 `panel.currentWallpaper.path`。
10. 渲染区（分隔线/标题/ScrollView/分组折叠/controlDelegate/空态）沿用旧版结构，仅控件镜像来源变化。

- [ ] **Step 1: 重写 `view/PropertyPanel.qml` 完整文件**

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs

import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

/**
 * 壁纸参数设置面板（HTMLWallpaper 模式右栏）。
 *
 * 数据源：当前选中壁纸（htmlWallpaper.selectWallpaper）经
 * WallpaperListModel.byKey(file) 定位 WallpaperItem，取其只读
 * WallpaperPropertyModel（WallpaperPropertyItem 行，Q_PROPERTY 全 CONSTANT）。
 * 按 type 自适应加载控件：
 *
 *   group     → 折叠组标题（type==="group" 是组锚点，key 即组名、text 即标题）
 *   text      → 提示 Label（允许含 HTML）
 *   bool      → CheckBox
 *   slider    → Slider + 数值标签（尊重 fraction / precision）
 *   combo     → ComboBox（options 的 label/value role 匹配 propValue）
 *   color     → ColorButton（"R G B" ↔ QML color，QML 纯转换）
 *   textinput → TextField
 *   file      → 文件选择按钮（存相对壁纸目录路径）
 *
 * 模型只读：每属性被转换为一个可观察 QtObject 镜像（字段 property 化）作
 * Repeater model。用户改动只更新镜像 + 重算 condition 可见性；随后把镜像组装为
 * 每壁纸一份的 JSON（{ "<file>": {key:value} }，保留其他壁纸段）经 applyProperties
 * 信号发给外层（config.qml 写 cfg_WallpaperProperties，KCM 持久化，渲染实例实时注入）。
 *
 * condition 可见性：调 htmlWallpaper.evaluateCondition（C++ QJSEngine），
 * 空 / 语法错误宽松 true。
 */
Item {
    id: propertyPanel

    // 注入的解析器实例（HTMLBackend，可为 null → 面板空态）
    property QtObject htmlWallpaper: null
    // 已存参数 JSON（每壁纸一份 { "<file>": {key:value} }）；本组件只读该值，
    // 改动经 applyProperties 写回（由外层持有并持久化）
    property string wallpaperPropertiesJson: "{}"
    // 参数被用户修改：组装后的完整 JSON（含全部壁纸段）
    signal applyProperties(string json)

    // 当前壁纸门面（WallpaperItem，可 null）：selectWallpaper 非空 → byKey 命中
    readonly property QtObject currentWallpaper: {
        if (!htmlWallpaper || !htmlWallpaper.wallpapers) {
            return null;
        }
        const file = htmlWallpaper.selectWallpaper;
        return file ? htmlWallpaper.wallpapers.byKey(file) : null;
    }
    // 当前壁纸已存参数段 {key: value}（null 表示无已存段）
    property var _storedProps: null

    // —— 可观察属性镜像：模型行 → QtObject（元素可观察）——
    property var _obsItems: []
    // 分组渲染结构：[{ group, title, items:[QtObject...] }]
    property var _groups: []
    // 控件区固定内容宽度（供 delegate 对齐）
    property real _contentWidth: 0

    // 当前壁纸变化 → 重建（htmlWallpaper 为 null 时禁用 Connections）
    Connections {
        target: htmlWallpaper
        enabled: htmlWallpaper !== null
        function onSelectWallpaperChanged() { propertyPanel._rebuild(); }
        function onScanFinished() { propertyPanel._rebuild(); }
    }
    // 初次挂载重建（selectWallpaper 初始赋值不触发 changed；已存参数在重建时经
    // _parseStoredSegment 读最新 cfg——用户改动写回 cfg 不重建，避免控件闪烁）
    Component.onCompleted: { _rebuild(); }

    // 按属性 type 选控件组件
    function _componentFor(type) {
        switch (type) {
        case "slider": return sliderComponent;
        case "color": return colorComponent;
        case "combo": return comboComponent;
        case "bool": return boolComponent;
        case "textinput": return textInputComponent;
        case "file": return fileComponent;
        case "text":
        default: return textComponent;
        }
    }

    // 解析当前壁纸（selectWallpaper）的已存参数段；无段 / JSON 非法 → null
    function _parseStoredSegment() {
        const file = htmlWallpaper ? htmlWallpaper.selectWallpaper : "";
        if (!file) {
            return null;
        }
        let all = {};
        try {
            all = JSON.parse(wallpaperPropertiesJson || "{}");
        } catch (e) {
            all = {};
        }
        const seg = all[file];
        return (seg && typeof seg === "object") ? seg : null;
    }

    // 把当前壁纸 properties 模型重建为可观察 QtObject 数组 + 分组
    function _rebuild() {
        for (let i = 0; i < _obsItems.length; i++) {
            _obsItems[i].destroy();
        }
        _obsItems = [];
        _groups = [];
        _storedProps = _parseStoredSegment();

        const item = currentWallpaper;
        if (!item) {
            return;
        }
        const model = item.properties;
        if (!model || model.count === 0) {
            return;
        }
        for (let i = 0; i < model.count; i++) {
            const p = model.get(i); // WallpaperPropertyItem（QObject 门面）
            if (!p) {
                continue;
            }
            const obj = Qt.createQmlObject(
                "import QtQuick; QtObject {"
                + " property string key;"
                + " property string type;"
                + " property string text;"
                + " property var propValue;"
                + " property var min;"
                + " property var max;"
                + " property var step;"
                + " property var fraction;"
                + " property var precision;"
                + " property var options;"
                + " property string condition;"
                + " property string group;"
                + " property int order;"
                + " property bool visibleByCondition: true;"
                + "}",
                propertyPanel, "propItem" + i);
            // 模型行缺键时 get(i) 对应字段为 undefined，强类型字段须兜底
            obj.key = p.key !== undefined ? p.key : "";
            obj.type = p.type !== undefined ? p.type : "text";
            obj.text = p.text !== undefined ? p.text : "";
            // 已存参数覆盖 project.json 默认值
            obj.propValue = (_storedProps !== null && p.key in _storedProps)
                            ? _storedProps[p.key] : p.value;
            obj.min = p.min;
            obj.max = p.max;
            obj.step = p.step;
            obj.fraction = p.fraction;
            obj.precision = p.precision;
            obj.options = p.options !== undefined ? p.options : [];
            obj.condition = p.condition !== undefined ? p.condition : "";
            obj.group = p.group !== undefined ? p.group : "";
            obj.order = p.order !== undefined ? p.order : 0;
            _obsItems.push(obj);
        }
        _groups = _buildGroups();
        _recomputeVisibility();
    }

    // 复刻原 HTMLBackend::propertyGroups() 的分组逻辑（_obsItems 已按 order 排序）：
    // type==="group" 属性是组锚点（key 即组名、text 即组标题），不进入任何组的 items；
    // 其余属性归入 group 字段指定的组（空则归最近的锚点组）；组按首次出现顺序排列。
    function _buildGroups() {
        const map = {};
        const order = [];
        const titles = {};
        let anchor = "";
        for (let i = 0; i < _obsItems.length; i++) {
            const item = _obsItems[i];
            if (item.type === "group") {
                anchor = item.key;
                if (!(anchor in map)) {
                    map[anchor] = [];
                    order.push(anchor);
                }
                titles[anchor] = item.text !== undefined && item.text !== "" ? item.text : anchor;
                continue;
            }
            const g = item.group !== undefined && item.group !== "" ? item.group : anchor;
            if (!(g in map)) {
                map[g] = [];
                order.push(g);
            }
            if (g !== "" && !(g in titles)) {
                titles[g] = g;
            }
            map[g].push(item);
        }
        const groups = [];
        for (let i = 0; i < order.length; i++) {
            const g = order[i];
            groups.push({ "group": g, "title": titles[g] !== undefined ? titles[g] : g, "items": map[g] });
        }
        return groups;
    }

    // 重算所有带 condition 的属性的可见性（值变化时调用）
    function _recomputeVisibility() {
        if (!htmlWallpaper) {
            return;
        }
        const propsMap = {};
        for (let i = 0; i < _obsItems.length; i++) {
            propsMap[_obsItems[i].key] = _obsItems[i].propValue;
        }
        for (let i = 0; i < _obsItems.length; i++) {
            const item = _obsItems[i];
            item.visibleByCondition = htmlWallpaper.evaluateCondition(item.condition, propsMap);
        }
    }

    // 任一控件的值被改动：重算 condition 可见性，组装每壁纸一份 JSON 并通知外层
    function _onValueChanged() {
        _recomputeVisibility();
        const file = htmlWallpaper ? htmlWallpaper.selectWallpaper : "";
        if (!file) {
            return;
        }
        let all = {};
        try {
            all = JSON.parse(wallpaperPropertiesJson || "{}");
        } catch (e) {
            all = {};
        }
        const seg = {};
        for (let i = 0; i < _obsItems.length; i++) {
            const item = _obsItems[i];
            // group 锚点与 text 提示不入参数表
            if (item.type === "group" || item.type === "text") {
                continue;
            }
            seg[item.key] = item.propValue;
        }
        all[file] = seg;
        applyProperties(JSON.stringify(all));
    }

    // QML color → "R G B"（各分量 0~1，Wallpaper Engine 协议）
    function _hexToRgb(colorValue) {
        const s = String(colorValue.toString()); // "#rrggbb" 或 "#aarrggbb"
        const hex = s.length >= 7 ? s.slice(-6) : "000000";
        const r = parseInt(hex.substr(0, 2), 16) / 255;
        const g = parseInt(hex.substr(2, 2), 16) / 255;
        const b = parseInt(hex.substr(4, 2), 16) / 255;
        return r + " " + g + " " + b;
    }

    // "R G B"（各分量 0~1）→ QML color（colorToHex 已随解耦重构删除，QML 纯转换）
    function _rgbToColor(value) {
        const parts = String(value || "").trim().split(/\s+/);
        const r = parseFloat(parts[0]) || 0;
        const g = parseFloat(parts[1]) || 0;
        const b = parseFloat(parts[2]) || 0;
        return Qt.rgba(r, g, b, 1);
    }

    // —— 控件组件（根对象注入 modelData + panel；modelData 是可观察 QtObject）——

    Component {
        id: sliderComponent
        RowLayout {
            property var modelData: null
            property QtObject panel: null
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: modelData ? modelData.text : ""
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignRight
            }
            QQC2.Slider {
                id: slider
                Layout.preferredWidth: 200
                from: modelData && modelData.min !== undefined ? modelData.min : 0
                to: modelData && modelData.max !== undefined ? modelData.max : 100
                stepSize: modelData && modelData.step ? modelData.step : 0
                onMoved: {
                    if (!modelData) {
                        return;
                    }
                    let v = slider.value;
                    if (modelData.fraction && modelData.precision !== undefined) {
                        const f = Math.pow(10, modelData.precision);
                        v = Math.round(slider.value * f) / f;
                    }
                    modelData.propValue = v;
                    if (panel) {
                        panel._onValueChanged();
                    }
                }
                // 外部值同步到滑块；拖动中暂停，避免覆盖用户输入
                Binding {
                    target: slider
                    property: "value"
                    value: modelData && modelData.propValue !== undefined ? modelData.propValue : 0
                    when: modelData !== null && !slider.pressed
                }
            }
            QQC2.Label {
                Layout.preferredWidth: 48
                text: modelData ? (modelData.fraction
                                   ? (modelData.precision !== undefined
                                      ? Number(modelData.propValue).toFixed(modelData.precision)
                                      : String(modelData.propValue))
                                   : String(Math.round(modelData.propValue))) : ""
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    Component {
        id: colorComponent
        RowLayout {
            property var modelData: null
            property QtObject panel: null
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: modelData ? modelData.text : ""
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
            }
            KQuickControls.ColorButton {
                id: colorButton
                color: modelData && modelData.type === "color"
                       ? panel._rgbToColor(modelData.propValue) : "#000000"
                onColorChanged: {
                    if (!modelData || !panel) {
                        return;
                    }
                    const hex = panel._hexToRgb(modelData.propValue);
                    // 仅当颜色确实被用户改动时写回（程序同步会命中相等分支，避免循环）
                    if (colorButton.color.toString().toUpperCase() !== hex.toUpperCase()) {
                        modelData.propValue = panel._hexToRgb(colorButton.color);
                        panel._onValueChanged();
                    }
                }
            }
        }
    }

    Component {
        id: comboComponent
        RowLayout {
            property var modelData: null
            property QtObject panel: null
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: modelData ? modelData.text : ""
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
            }
            QQC2.ComboBox {
                id: combo
                Layout.preferredWidth: 200
                model: modelData ? modelData.options : []
                textRole: "label"
                valueRole: "value"
                currentIndex: modelData ? Math.max(0, indexOfValue(modelData.propValue)) : 0
                onActivated: {
                    if (!modelData) {
                        return;
                    }
                    modelData.propValue = combo.currentValue;
                    if (panel) {
                        panel._onValueChanged();
                    }
                }
            }
        }
    }

    Component {
        id: boolComponent
        QQC2.CheckBox {
            id: checkBox
            property var modelData: null
            property QtObject panel: null
            width: parent.width
            text: modelData ? modelData.text : ""
            checked: modelData ? modelData.propValue : false
            onToggled: {
                if (!modelData) {
                    return;
                }
                modelData.propValue = checked;
                if (panel) {
                    panel._onValueChanged();
                }
            }
        }
    }

    Component {
        id: textInputComponent
        RowLayout {
            property var modelData: null
            property QtObject panel: null
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: modelData ? modelData.text : ""
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
            }
            QQC2.TextField {
                id: textField
                Layout.preferredWidth: 200
                text: modelData && modelData.propValue !== undefined ? String(modelData.propValue) : ""
                onTextEdited: {
                    if (!modelData) {
                        return;
                    }
                    modelData.propValue = textField.text;
                    if (panel) {
                        panel._onValueChanged();
                    }
                }
            }
        }
    }

    Component {
        id: textComponent
        QQC2.Label {
            id: infoLabel
            property var modelData: null
            property QtObject panel: null
            width: parent.width
            text: modelData ? modelData.text : ""
            textFormat: Text.RichText
            wrapMode: Text.WordWrap
        }
    }

    Component {
        id: fileComponent
        RowLayout {
            property var modelData: null
            property QtObject panel: null
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: modelData ? modelData.text : ""
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
            }
            QQC2.TextField {
                id: fileField
                Layout.preferredWidth: 160
                readOnly: true
                text: modelData ? String(modelData.propValue || "") : ""
            }
            QQC2.Button {
                text: i18nd("plasma_wallpaper_com.github.moon_haze.htmlwallpaper", "Browse…")
                onClicked: fileDialog.open()
            }
            FileDialog {
                id: fileDialog
                title: i18nd("plasma_wallpaper_com.github.moon_haze.htmlwallpaper", "Choose file")
                currentFolder: panel && panel.currentWallpaper ? panel.currentWallpaper.path : ""
                onAccepted: {
                    if (!modelData || !panel) {
                        return;
                    }
                    const base = String(panel.currentWallpaper.path);
                    let rel = String(fileDialog.selectedFile);
                    // 存相对壁纸目录的路径（引用可随目录移动）
                    if (rel.indexOf(base) === 0) {
                        rel = rel.substring(base.length).replace(/^\/+/, "");
                    }
                    modelData.propValue = rel;
                    panel._onValueChanged();
                }
            }
        }
    }

    // —— 单个控件项：按 type 加载控件组件，暴露 modelData / objectName ——
    Component {
        id: controlDelegate
        Item {
            id: controlItem
            required property var modelData
            width: propertyPanel._contentWidth
            visible: modelData.visibleByCondition
            height: visible ? (controlLoader.item ? controlLoader.item.implicitHeight : 0) : 0

            Loader {
                id: controlLoader
                anchors.left: parent.left
                anchors.right: parent.right
                sourceComponent: propertyPanel._componentFor(modelData.type)
                onItemChanged: {
                    if (controlLoader.item) {
                        controlLoader.item.modelData = controlItem.modelData;
                        controlLoader.item.panel = propertyPanel;
                        controlLoader.item.objectName = "prop-" + controlItem.modelData.key;
                    }
                }
            }
        }
    }

    // —— 渲染 ——
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // 顶部：当前壁纸标题
        QQC2.Label {
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            text: propertyPanel.currentWallpaper ? propertyPanel.currentWallpaper.title : ""
            visible: text !== ""
            elide: Text.ElideRight
            font.weight: Font.DemiBold
        }

        // —— 内容区：参数滚动列表（有属性时）/ 空态提示（无属性时）——
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // 空态：未选中 / 无可配置参数
            Kirigami.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.largeSpacing * 4
                visible: propertyPanel._obsItems.length === 0
                text: propertyPanel.currentWallpaper
                      ? i18nd("plasma_wallpaper_com.github.moon_haze.htmlwallpaper",
                              "This wallpaper has no configurable properties")
                      : i18nd("plasma_wallpaper_com.github.moon_haze.htmlwallpaper",
                              "Select a wallpaper to configure its properties")
            }

            QQC2.ScrollView {
                id: scrollView
                anchors.fill: parent
                visible: propertyPanel._obsItems.length > 0
                clip: true
                background: Rectangle {
                    Kirigami.Theme.inherit: false
                    Kirigami.Theme.colorSet: Kirigami.Theme.View
                    color: Kirigami.Theme.backgroundColor
                }
                // ScrollView 的 contentItem 必须是 Flickable 类型
                contentItem: Flickable {
                    id: flickable
                    contentWidth: column.width
                    contentHeight: column.implicitHeight
                    Column {
                        id: column
                        width: scrollView.availableWidth
                        spacing: 0
                        // 同步实际内容宽度给控件 delegate 对齐
                        onWidthChanged: propertyPanel._contentWidth = width
                        Component.onCompleted: propertyPanel._contentWidth = width

                        // 分组渲染：组标题（可折叠）→ 组内控件
                        Repeater {
                            model: propertyPanel._groups
                            delegate: Column {
                                id: groupColumn
                                required property var modelData
                                width: column.width
                                property bool _collapsed: false

                                // 组标题（非默认组）：点击折叠/展开组内容
                                QQC2.ItemDelegate {
                                    width: groupColumn.width
                                    visible: modelData.group !== ""
                                    text: modelData.title
                                    leftPadding: Kirigami.Units.largeSpacing
                                    onClicked: groupColumn._collapsed = !groupColumn._collapsed
                                    contentItem: RowLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        Kirigami.Icon {
                                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                                            Layout.preferredHeight: Layout.preferredWidth
                                            source: groupColumn._collapsed ? "arrow-right" : "arrow-down"
                                        }
                                        QQC2.Label {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                    }
                                    background: Rectangle {
                                        color: Qt.darker(Kirigami.Theme.backgroundColor, 1.05)
                                    }
                                }

                                Column {
                                    width: groupColumn.width
                                    visible: !groupColumn._collapsed
                                    Repeater {
                                        model: modelData.items
                                        delegate: controlDelegate
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: qmllint 静态检查**

Run: `qmllint -I build/bin package/contents/ui/view/PropertyPanel.qml`
Expected: 无 error；warning（未定义 i18nd / 未使用的 property 等）可接受，不阻塞。若报 `KQuickControls` 找不到，确认是 import 路径问题（build/bin 与系统模块），不阻塞实现。

- [ ] **Step 3: 运行既有测试确认未回归**

Run: `ctest --preset native -R "tst_Smoke|tst_Parser|tst_WallpaperListModel|tst_evaluateCondition" -V`
Expected: 全部 PASS（PropertyPanel 未接入测试，回归面是既有模型/解析测试）。

- [ ] **Step 4: 提交**

```bash
git add package/contents/ui/view/PropertyPanel.qml
git commit -m "feat(ui): 重写 PropertyPanel 消费 WallpaperItem::properties 新契约

从 byKey(selectWallpaper) 定位当前壁纸，读只读 WallpaperPropertyModel 建可观察
镜像 + 分组；按 type 自适应加载控件（含 color QML 纯转换替代 colorToHex）；
condition 经 HTMLBackend.evaluateCondition 过滤；改动组装每壁纸一份 JSON 经
applyProperties 写回 cfg_WallpaperProperties。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: config.qml 恢复右栏挂载

**Files:**
- Modify: `package/contents/ui/config.qml`

**Interfaces:**
- Consumes: Task 3 产物 — `View.PropertyPanel` 的 `htmlWallpaper` / `wallpaperPropertiesJson` 属性、`applyProperties` 信号；`root.cfg_WallpaperProperties`（string，KCM 自动持久化）。
- Produces: 右栏挂载，参数改动经 `onApplyProperties` 写 `root.cfg_WallpaperProperties`。

- [ ] **Step 1: 替换右栏注释块为实际挂载**

删除 config.qml 中 `// —— 右栏：参数面板 ——` 起的注释块（当前为被注释的 `PropertyPanel { ... }`），替换为：

```qml
            // —— 右栏：参数面板 ——
            // 数据源经 htmlWallpaper 定位当前壁纸（selectWallpaper）→ WallpaperItem.properties；
            // 改动组装每壁纸一份 JSON 写回 cfg_WallpaperProperties（KCM 持久化，渲染实例实时注入）。
            View.PropertyPanel {
                Layout.fillHeight: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 24
                Layout.maximumWidth: Kirigami.Units.gridUnit * 34
                htmlWallpaper: htmlWallpaper
                wallpaperPropertiesJson: root.cfg_WallpaperProperties
                onApplyProperties: (json) => root.cfg_WallpaperProperties = json
            }
```

- [ ] **Step 2: qmllint 静态检查**

Run: `qmllint -I build/bin package/contents/ui/config.qml`
Expected: 无 error。若报 `HTMLBackend` / `View.PropertyPanel` 类型未定义，确认是 import 解析 warning，不阻塞。

- [ ] **Step 3: 手动功能验证（可选，需桌面环境）**

Run: 安装/预览后打开「桌面壁纸配置」，中栏选中壁纸，右栏应显示其参数；改动后切换到渲染实例确认页面更新；切换壁纸确认参数各自独立。
（无桌面环境时以 qmllint + 代码审查为准。）

- [ ] **Step 4: 提交**

```bash
git add package/contents/ui/config.qml
git commit -m "feat(ui): config.qml 恢复右栏 PropertyPanel 挂载

数据经 htmlWallpaper 定位当前壁纸；改动经 onApplyProperties 写回
cfg_WallpaperProperties（KCM 持久化）。

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## 完成标准

- `test/tst_evaluateCondition.qml` 全部用例通过（`ctest --preset native -R tst_evaluateCondition -V`）。
- 既有测试 `tst_Smoke` / `tst_Parser` / `tst_WallpaperListModel` / `tst_wallpaperproject` 无回归。
- `qmllint -I build/bin` 对 `main.qml` / `PropertyPanel.qml` / `config.qml` 无 error。
- 桌面环境可用时：中栏选壁纸 → 右栏按 type 显示控件；改动写入配置并注入页面；切壁纸参数独立。
