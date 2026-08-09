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
 * ⚠️ 已停用：本组件当前被 SlideshowComponent.qml 注释屏蔽，不参与生产。
 * 其依赖的 HTMLBackend C++ API 已随解耦重构删除——currentWallpaper /
 * evaluateCondition / colorToHex / wallpaperParsed 信号均已不存在，
 * 下面的代码引用（currentWallpaper / general.properties）只对旧版有效。
 * 若未来恢复本组件，须按新契约重写：
 *   属性表 ← WallpaperItem::properties（WallpaperPropertyModel ListModel）的
 *   get(i) / byKey(key)，值类型字段见 WallpaperPropertyItem；
 *   condition 可见性过滤不再有 evaluateCondition 支持（该功能已移除）。
 *
 * 原始设计（旧契约，保留作参考）：
 * 消费 HTMLBackend（C++）的 currentWallpaper.general.properties（只读
 * ListModel，WallpaperPropertyModel）把可配置属性渲染成可编辑控件：
 *
 *   group     → 折叠组标题（可点击折叠/展开组内容）
 *   text      → 提示 Label（允许含 HTML，如 <small>/<b>）
 *   bool      → CheckBox
 *   slider    → Slider + 数值标签（尊重 fraction / precision）
 *   combo     → ComboBox（label/value role 匹配 propValue）
 *   color     → KQuickControls.ColorButton（"R G B" ↔ #RRGGBB）
 *   textinput → TextField
 *   file      → 文件选择按钮（存相对壁纸目录的路径）
 *
 * 只读展示 + 会话内可调：模型本身只读（value 不存储、不写回 C++、不写
 * cfg_WallpaperProperties、不应用到壁纸），但控件仍可操作——改动只更新
 * 本面板的可观察镜像（QtObject），关面板重开即恢复默认值。
 *
 * 可观察性：模型行元素不可直接观察（改值不触发绑定），因此每个属性被转换
 * 为一个 QtObject（字段全部 property 化，含 visibleByCondition）作 Repeater
 * model。控件读写 QtObject 属性，绑定实时更新；用户改动值 → 重算所有
 * condition 的可见性 → 发 propertyChanged()（外层目前不再消费，保留信号
 * 供测试 / 后续扩展）。
 *
 * 接口：设置 htmlWallpaper 属性（可为 null，面板显示空态）。选中新壁纸时由
 * htmlWallpaper.currentWallpaper 的 changed 信号驱动重建。
 */
Item {
    id: propertyPanel

    // 注入的解析器实例（evaluateCondition / colorToHex / currentWallpaper 已随
    // HTMLBackend 解耦重构删除，下方引用仅对旧契约有效，恢复本组件前须重写）
    property QtObject htmlWallpaper: null

    // 便捷只读视图（可直接用于显示，无需额外绑定）
    readonly property var currentWallpaper: htmlWallpaper ? htmlWallpaper.currentWallpaper : null

    // 参数被用户修改（仅会话内镜像更新，不持久化）
    signal propertyChanged()

    // —— 可观察属性镜像：模型行 → QtObject（元素可观察）——
    // 每个 QtObject 字段对应属性定义的一项，另加 visibleByCondition（condition
    // 求值结果，控制控件显隐）。注意字段名用 propValue（对应模型行的 value）。
    property var _obsItems: []
    // 分组渲染结构：[{ group, title, items:[QtObject...] }]
    property var _groups: []

    // htmlWallpaper 赋值（含初始）即重建；后续 currentWallpaper 变化由 Connections 驱动
    onHtmlWallpaperChanged: { _rebuildObservable(); }
    Connections {
        target: htmlWallpaper
        function onCurrentWallpaperChanged() { _rebuildObservable(); }
    }

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

    // 把 currentWallpaper.general.properties 模型整体重建为可观察 QtObject 数组 + 分组
    function _rebuildObservable() {
        for (let i = 0; i < _obsItems.length; i++) {
            _obsItems[i].destroy();
        }
        _obsItems = [];
        _groups = [];
        if (!htmlWallpaper || !htmlWallpaper.currentWallpaper || !htmlWallpaper.currentWallpaper.general) {
            return;
        }
        const model = htmlWallpaper.currentWallpaper.general.properties;
        if (!model) {
            return;
        }
        for (let i = 0; i < model.count; i++) {
            const p = model.get(i); // QVariantMap 行（模型已按 order 排序并做了 value 兜底）
            // 每个属性一个 QtObject，字段 property 化（改动触发绑定更新）
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
            // 模型行缺键时 get(i) 对应字段为 undefined，赋给 property string/int 会报错，
            // 故对强类型字段做兜底（模型只规范化了 type/text/value/order）。
            obj.key = p.key !== undefined ? p.key : "";
            obj.type = p.type !== undefined ? p.type : "text";
            obj.text = p.text !== undefined ? p.text : "";
            obj.propValue = p.value;
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
        const map = {};   // 组名 → items 数组
        const order = []; // 组创建顺序
        const titles = {}; // 组名 → 标题
        let anchor = "";  // 当前激活的组锚点
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

    // 任一控件的值被改动：值只更新会话内可观察镜像（不写回模型 / C++ / 配置，
    // 符合"可调不持久"），重算 condition 可见性、通知外层（当前无消费方，保留信号）。
    function _onValueChanged() {
        _recomputeVisibility();
        propertyChanged();
    }

    // QML color（QColor）→ Wallpaper Engine "R G B"（各分量 0~1）
    function _hexToRgb(colorValue) {
        const s = String(colorValue.toString()); // "#rrggbb" 或 "#aarrggbb"
        const hex = s.length >= 7 ? s.slice(-6) : "000000";
        const r = parseInt(hex.substr(0, 2), 16) / 255;
        const g = parseInt(hex.substr(2, 2), 16) / 255;
        const b = parseInt(hex.substr(4, 2), 16) / 255;
        return r + " " + g + " " + b;
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
                color: modelData && modelData.type === "color" && panel && panel.htmlWallpaper
                       ? panel.htmlWallpaper.colorToHex(modelData.propValue) : "#000000"
                onColorChanged: {
                    if (!modelData || !panel || !panel.htmlWallpaper) {
                        return;
                    }
                    const hex = panel.htmlWallpaper.colorToHex(modelData.propValue);
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
                currentFolder: panel && panel.htmlWallpaper && panel.htmlWallpaper.currentWallpaper
                               ? panel.htmlWallpaper.currentWallpaper.path : ""
                onAccepted: {
                    if (!modelData || !panel || !panel.htmlWallpaper) {
                        return;
                    }
                    const base = String(panel.htmlWallpaper.currentWallpaper.path);
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

    // 控件区固定内容宽度（供 delegate 对齐）
    property real _contentWidth: 0

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
