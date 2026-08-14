# 参数配置面板重写设计（PropertyPanel 恢复与新契约适配）

- 日期：2026-08-13
- 状态：已批准（经 brainstorming 三处决策确认）
- 相关提交：2d7d7e4（选中壁纸下沉 C++ 属性，模型层改值语义，面板迁移 view/）

## 背景与目标

`view/PropertyPanel.qml` 因 HTMLBackend 解耦重构而停用（依赖的 `currentWallpaper` /
`evaluateCondition` / `colorToHex` / `wallpaperParsed` API 已删除），在 `config.qml`
右栏被注释屏蔽。本次将其重写为消费新契约：从 C++ backend 加载的 wallpaper 的
project（`WallpaperProject` → `WallpaperItem::properties` 只读
`WallpaperPropertyModel`）中获取调节参数，按参数 `type` 自适应加载对应控件。

已确认的决策：

1. **可调 + 应用到壁纸**：改动写入 `cfg_WallpaperProperties`（JSON），由 KCM 持久化，
   渲染实例 `main.qml` 监听配置变化并实时注入 HTML 页面。
2. **每壁纸一份存储**：`cfg_WallpaperProperties` 存 `{ "<file>": {key: value}, ... }`，
   切换壁纸加载对应段、改动写回对应段，不串参数。
3. **支持 condition 可见性过滤**：在 C++ `HTMLBackend` 恢复 `evaluateCondition`
   （QJSEngine，复刻旧版逻辑）。

## 现有数据流与契约

- 中栏 `ThumbnailsPanel` 点击壁纸 → `htmlWallpaper.selectWallpaper = model.file`
  （`file` 即入口绝对 URL，与 `WallpaperItem.source()` 同一值）。
- `HTMLBackend::wallpapers`（`WallpaperListModel`）提供 `get(i)` / `byKey(key)`，
  `m_indexByKey` 按 `source()`（= file）索引，故 `byKey(selectWallpaper)` 可定位当前壁纸。
- `WallpaperItem::properties`（`WallpaperPropertyModel`，只读 `QAbstractListModel`）：
  `count` / `get(i)` / `byKey(key)`，行是 `WallpaperPropertyItem`（QObject 门面，
  Q_PROPERTY 全 `CONSTANT`：key/type/text/value/min/max/step/fraction/precision/
  options/condition/group/order）。
- `WallpaperProperty` 值类型已做规范化：type 缺失→"text"、text 缺失→key、value 缺失按
  type 兜底、order 缺失→int max（稳定排最后）。
- `main.qml` 渲染实例已监听 `configuration.onValueChanged`：
  `key === "WallpaperProperties"` → `_injectProperties()` → `runJavaScript`
  `applyUserProperties(json)`，无监听器则带参数重载页面。

## 架构与数据流

```
中栏点击壁纸 → htmlWallpaper.selectWallpaper = model.file
   │  (selectWallpaperChanged 信号)
   ▼
PropertyPanel 重建 → wallpapers.byKey(file) → WallpaperItem.properties
   │               （只读 WallpaperPropertyModel，行 = WallpaperPropertyItem）
   ▼
可观察镜像（QtObject 数组）+ 分组（group 锚点）+ 已存值覆盖默认值
   ▼
Repeater 按 type 加载控件：text / bool / slider / combo / color / textinput / file / group
   ▼ 用户改值
更新镜像 → 重算 condition 可见性 → 组装 { file: {key: value} } → 写 cfg_WallpaperProperties
   │  （KCM 自动持久化，保留其他壁纸段）
   ▼
渲染实例 main.qml 收到 configuration.onValueChanged("WallpaperProperties")
   → 提取当前 _displayPage 对应段 → _injectProperties() → runJavaScript 推给 HTML 页面
```

每壁纸参数段 key 用 `file`（与 `selectWallpaper` / `_displayPage` / `cfg_SelectWallpaper`
同一值），切换壁纸不串参数。

## 组件设计

### 1. PropertyPanel.qml（重写）

输入属性：

- `property QtObject htmlWallpaper`：HTMLBackend 实例（可 null，面板显示空态）。
- `property string wallpaperPropertiesJson`：已存参数 JSON（每壁纸一份）。
- `signal applyProperties(string json)`：改动后组装完整 JSON 发给外层（config.qml）。

重建时机：

- `htmlWallpaper.selectWallpaperChanged` → 重建。
- `htmlWallpaper.scanFinished` → 重建（scan 后模型整体重建，含当前壁纸属性）。

核心函数（沿用旧版命名与结构）：

- `_rebuild()`：清空旧镜像；`selectWallpaper` 为空或 `wallpapers.byKey` 为 null →
  空态；否则遍历 `item.properties`（`get(i)`），每属性建 QtObject 镜像（字段
  key/type/text/value/min/max/step/fraction/precision/options/condition/group/order/
  visibleByCondition 全 property 化）；用当前壁纸已存段 `{key: value}` 覆盖默认 value。
- `_buildGroups()`：沿用旧版——`type==="group"` 是组锚点（key 即组名、text 即组标题），
  其余属性归入 `group` 字段指定组（空则归最近锚点组），组按首次出现顺序排列。
- `_recomputeVisibility()`：构建 propsMap（key → propValue），逐属性调
  `htmlWallpaper.evaluateCondition(condition, propsMap)` 写 `visibleByCondition`。
- `_onValueChanged()`：重算可见性 → 组装 `{file: {...}}`（解析当前
  `wallpaperPropertiesJson` 保留其他壁纸段，仅替换当前段）→ `applyProperties(json)`。

控件组件（复用旧版 8 组件结构）：

- `text` → 提示 Label（RichText，可含 HTML）。
- `bool` → CheckBox。
- `slider` → Slider + 数值标签（尊重 fraction / precision）。
- `combo` → ComboBox（options 的 label/value role 匹配 propValue）。
- `color` → ColorButton；颜色转换**纯 QML 实现**（`colorToHex` 已删）：
  - `"R G B"`（各分量 0~1）→ QML color：`Qt.rgba(parseFloat(r), ...)`。
  - QML color → `"R G B"`：`color.r + " " + color.g + " " + color.b`（QML 分量即 0~1）。
- `textinput` → TextField。
- `file` → 文件选择按钮（存相对壁纸目录路径，`currentWallpaper.path` 改为
  `wallpapers.byKey(file).path`）。
- `group` → 组锚点，不进任何组的 items（由 `_buildGroups` 消费）。

渲染结构沿用旧版：分隔线 → 壁纸标题 → ScrollView(Flickable → Column) → Repeater
按组渲染（组标题可折叠）→ 组内 Repeater → `controlDelegate`（按 type 经 Loader
加载控件组件，暴露 modelData/objectName）。空态用 `Kirigami.PlaceholderMessage`
（未选中 / 无可配置属性两种文案）。

### 2. config.qml（恢复右栏）

取消右栏注释，恢复挂载：

```qml
View.PropertyPanel {
    Layout.fillHeight: true
    Layout.preferredWidth: Kirigami.Units.gridUnit * 24
    Layout.maximumWidth: Kirigami.Units.gridUnit * 34
    htmlWallpaper: htmlWallpaper
    wallpaperPropertiesJson: root.cfg_WallpaperProperties
    onApplyProperties: (json) => root.cfg_WallpaperProperties = json
}
```

`cfg_WallpaperProperties`（已存在的 `property string`）由 KCM 自动持久化；赋值即触发
保存，渲染实例实时收到。

### 3. main.qml（提取当前壁纸参数段）

`_propertiesJson` 不再直接等于 `configuration.WallpaperProperties`（现在是每壁纸一份
`{file: {...}}`），改为提取当前 `_displayPage` 对应段后再注入：

```qml
function _extractPropertiesForPage(): string {
    const all = JSON.parse(wallpaper.configuration.WallpaperProperties || "{}");
    const seg = all[wallpaper._displayPage];
    return JSON.stringify(seg && typeof seg === "object" ? seg : {});
}
```

- `Component.onCompleted` 与 `onValueChanged("WallpaperProperties")` 处均改为用
  `_extractPropertiesForPage()` 赋值 `_propertiesJson`。
- 无匹配段 → `"{}"`（页面用默认值）。

### 4. C++ HTMLBackend（恢复 evaluateCondition）

`htmlbackend.h` 声明 + `htmlbackend.cpp` 实现：

```cpp
Q_INVOKABLE bool evaluateCondition(const QString &condition, const QVariantMap &props);
```

逻辑复刻旧版（`pkg/local/src/plugin/htmlbackend.cpp` 中 `evaluateCondition`）：

1. `condition.trimmed()` 为空 → `true`。
2. 构造 `(function(key1, key2, ...) { return (<condition>); })`，键按 props 顺序注入。
3. 每个键作为函数参数传入 `{ value: <propValue> }` 包装对象（`QJSEngine::newObject`）。
4. `fn.call(args)` 求值；语法错误 / 非可调用 → 宽松返回 `true`。

依赖：`#include <QJSEngine>`，成员 `QJSEngine m_engine`。不修改模型层。

### 5. 测试

新增 QML 测试（沿用 test/ 框架与 `tst_Parser.qml` 风格，测试 `HTMLBackend.evaluateCondition`）：

`test_evaluateCondition`：

- 空 / undefined condition → true。
- 字符串严格比较 `theme.value === "custom"` 匹配与不匹配。
- 布尔宽松比较 `coloredascii.value == true`。
- 数值比较 `saturation.value > 1`。
- 多属性 + 逻辑组合 `theme.value === "custom" && alpha.value > 0`。
- 表达式异常（`theme.value ===`）→ 宽松 true 不崩溃。

新测试文件加入 `test/CMakeLists.txt` 的测试目标（沿用现有 tst_*.qml 的注册方式）。

UI 组件不写自动测试（offscreen 下控件加载坑多，且项目无 PropertyPanel UI 测试先例）。

## 边界与空态

- 未选中壁纸（`selectWallpaper` 空 / `byKey` 未命中）：面板空态「Select a wallpaper…」。
- 选中壁纸无可配置属性（`properties.count === 0`）：空态「no configurable properties」。
- 切换壁纸：面板重建，加载各自已存段（无已存段则显示 project.json 默认值）。
- condition 语法错误：宽松 true，属性始终显示（不崩溃）。

## 范围外（YAGNI）

- 不做参数分组折叠持久化（折叠状态为会话内 UI 状态）。
- 不恢复 `colorToHex`（QML 纯转换足够）。
- 不新增 C++ 参数序列化 API（JSON 组装在 QML，结构简单）。
- 不做 UI 组件自动化测试。
