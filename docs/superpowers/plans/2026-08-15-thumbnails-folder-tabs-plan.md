# 缩略图标签式分组展示实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把壁纸配置页中栏从"平铺全部壁纸"改为"左栏标签切换视图"——左栏 ScanUrlsPanel 文件夹列表变为标签（含固定"全部"标签），点击标签经 config 中转切换 ThumbnailsPanel 的 model 为该文件夹壁纸组。

**Architecture:** config.qml 作为协调层持有选中状态单向传递。`ScanUrlsPanel.selectedFolder`（"" = 全部）→ config 绑定 → `ThumbnailsPanel.activeFolder` → `refreshModel()` 计算 `gridModel` = `activeFolder=="" ? wallpapers : wallpapers.byKey(activeFolder)`。不改动 C++ 数据层；`byKey()` 返回的 `QList<WallpaperItem*>`（QObject 指针数组）在 QML 中直接作 GridView model。**实测确认（2026-08-15 probe）**：对象列表作 model 时 `model.xxx` 恒为 undefined、仅 `modelData.xxx` 可读，与全组模式（`QAbstractListModel` role 访问）语义分裂。故 delegate（`WallpaperDelegate` 与 `ThumbnailsPanel.onClicked`）采用双路径兼容 `model.xxx ?? modelData.xxx`：全组走 role、单组走 Q_PROPERTY、mock（JS 数组）走 `modelData`，三态统一。

**Tech Stack:** Qt6 / KF6 QML、KCM.GridView、Kirigami（SubtitleDelegate/InlineViewHeader）、qmltestrunner（Qt6）、qmllint。

## Global Constraints

- **源文件全部留在工作区，不单独 commit**：ThumbnailsPanel.qml / ScanUrlsPanel.qml / config.qml 均处于用户未提交的 scanPaths→scanUrls 重构工作区中（git M / ?? 状态）。本计划对这些文件的改动**叠加在工作区上，不 add 不 commit**，由用户提交重构时一并提交。新增测试文件（tst_FolderTabs.qml / FolderTabsHost.qml）同样留在工作区（依赖工作区 UI 改动，分支单独提交会导致不一致）。
- **不修改** `plugin/wallpapermodel.h` / `.cpp`、`plugin/wallpapercontroller.*`、`plugin/wallpaperentry.*`、`plugin/wallpaperitem.*` 的数据层逻辑（folderName/parentPath 已有；本计划不使用 GroupRole/section）。
- **生产 QML 额外修改** `package/contents/ui/view/WallpaperDelegate.qml`（原文件清单之外）：因对象列表作 model 时 `model.xxx` 不可用（probe 实测），需双路径兼容 `model.xxx ?? modelData.xxx`。该文件在用户工作区（未提交），改动叠加其上。
- **中文注释与 commit message**（commit 仅用于可提交文件；本计划默认不 commit 任何文件）。
- QML 测试用 Qt6 `qmltestrunner`（`/usr/bin/qmltestrunner` 是 Qt5，须用 CMake find 到的 Qt6 版）；offscreen 环境下 GridView 需显式宽高才能实例化 delegate。
- KDeclarative 国际化函数（i18n/i18nc/i18nd/i18ndc）在 qmltestrunner 不可用，测试内用同名 property mock（现有 tst_*.qml 先例）。
- `byKey(key)` 返回裸指针快照，仅在下次 `scan()/addEntries()/clear()` 前有效；UI 侧通过监听 `modelReset` 重新计算，规避悬空。
- mock 的 `wallpapers` 用 JS 数组模拟（可挂 `byKey`/`get` 方法）；真实 `WallpaperModel` 才有 `byKey`，mock 不模拟 `modelReset`（重扫不在 UI 测试范围）。

---

### Task 1: ThumbnailsPanel 支持 activeFolder/gridModel 切换

**Files:**
- Modify: `package/contents/ui/view/ThumbnailsPanel.qml`
- Modify: `package/contents/ui/view/WallpaperDelegate.qml`（双路径兼容，见 Step 5）
- Modify: `test/tst_ThumbnailsBinding.qml`
- Modify: `test/tst_ThumbnailsHighlight.qml`

**Interfaces:**
- Produces: `ThumbnailsPanel.activeFolder: string`（默认 `""` = 全部；外部 config 写入）；保留 `property alias view`；内部 `gridModel` 驱动 `view.model`。
- Consumes: `htmlWallpaper.wallpapers`（需有 `byKey(url)` 方法）；`htmlWallpaper.wallpapers.modelReset` 信号（重扫时刷新）。

- [ ] **Step 1: 更新 tst_ThumbnailsBinding.qml mock（带 byKey 的 JS 数组）**

现有 mock 是 `ListModel`（无 `byKey`，无法模拟单组模式）。改为 JS 数组 + `byKey`/`get` 方法。替换 `test/ThumbnailsHost.qml` 中 `htmlWallpaper.wallpapers` 的定义：

```qml
    // 模拟 config.qml 外层控制器（WallpaperController { id: htmlWallpaper }）
    QtObject {
        id: htmlWallpaper
        property string selectWallpaper: ""
        // 模拟 WallpaperModel：JS 数组作 model，可挂 byKey/get 方法。
        // byKey 返回整个数组（mock 简化：不分 key 返回不同组）。
        property var wallpapers: (function () {
            const all = [
                { name: "a", title: "a", path: "file:///a.html", file: "file:///a.html", preview: "" }
            ];
            all.byKey = function (url) { return all; };
            all.get = function (i) { return all[i]; };
            return all;
        })()
    }
```

- [ ] **Step 2: 跑 tst_ThumbnailsBinding 确认当前断言失败（红）**

```bash
cmake --build build --target tst_ThumbnailsBinding >/dev/null 2>&1 || true
ctest --test-dir build -R tst_ThumbnailsBinding --output-on-failure
```

预期失败原因：`view.model` 当前仍直接绑 `htmlWallpaper.wallpapers`，断言 `host.panel.view.model === host.htmlWallpaperController.wallpapers` 可能通过；但 mock 改数组后若无 `byKey` 相关断言则仅作基建。记录当前实际结果即可（红/绿均接受，本步是 mock 基建）。

- [ ] **Step 3: 更新 tst_ThumbnailsHighlight.qml mock 为 JS 数组**

`init()` 中 `htmlWallpaper` mock 的 `wallpapers` 由 `ListModel` 改为 JS 数组（同样挂 `byKey`/`get`），元素字段不变（name/title/path/file/preview）。测试内 `htmlWallpaper.wallpapers.get(0).file` 继续可用（mock 提供 get）。

```qml
        htmlWallpaper = Qt.createQmlObject(
            'import QtQuick;'
            + '\nQtObject {'
            + '\n  property string selectWallpaper: ""'
            + '\n  property var wallpapers: (function () {'
            + '\n    const all = ['
            + '\n      { name: "a", title: "a", path: "file:///a.html", file: "file:///a.html", preview: "" },'
            + '\n      { name: "b", title: "b", path: "file:///b.html", file: "file:///b.html", preview: "" },'
            + '\n      { name: "c", title: "c", path: "file:///c.html", file: "file:///c.html", preview: "" }'
            + '\n    ];'
            + '\n    all.byKey = function (url) { return all; };'
            + '\n    all.get = function (i) { return all[i]; };'
            + '\n    return all;'
            + '\n  })()'
            + '\n}',
            testCase);
```

- [ ] **Step 4: 实现 ThumbnailsPanel（activeFolder + gridModel + refreshModel）**

在 `ThumbnailsPanel.qml` 中：

新增属性与刷新函数（放在 `property var previewSize` 之后）：

```qml
    // 当前选中的扫描根 key（"" = 全部）。由调用方 config.qml 注入绑定。
    property string activeFolder: ""
    // 当前网格 model：全部 → htmlWallpaper.wallpapers；单组 → byKey(activeFolder)
    property var gridModel: null

    // 依 activeFolder 重新计算 gridModel，并滚回顶部、清空选中高亮
    function refreshModel() {
        const walls = htmlWallpaper && htmlWallpaper.wallpapers ? htmlWallpaper.wallpapers : null;
        if (!walls) {
            gridModel = null;
            return;
        }
        gridModel = activeFolder.length === 0 ? walls : walls.byKey(activeFolder);
        wallpapersGrid.view.currentIndex = -1;
        wallpapersGrid.view.positionViewAtIndex(0, ListView.Beginning);
    }

    onActiveFolderChanged: refreshModel()
    onHtmlWallpaperChanged: refreshModel()

    // 重扫保护：WallpaperModel beginResetModel 时旧 byKey 快照失效，重算 gridModel
    Connections {
        target: htmlWallpaper && htmlWallpaper.wallpapers ? htmlWallpaper.wallpapers : null
        function onModelReset() { refreshModel(); }
    }
```

`KCM.GridView` 内 model 绑定从直接绑定改为 gridModel：

```qml
                // 直接挂模型，节省缩略图下方标签的额外空间
                view.model: thumbnails.gridModel
```

注意：原 `view.model: htmlWallpaper ? htmlWallpaper.wallpapers : null` 中 `htmlWallpaper` 是组件自身属性（绑定自引用坑已在 config 别名注释说明）；改为 `thumbnails.gridModel` 由 refreshModel 赋值，无声明式绑定自引用问题。`Connections.target` 表达式里读 `htmlWallpaper.wallpapers` 仅为取 target，非赋值，安全。

- [ ] **Step 5: 实现 delegate 双路径兼容（WallpaperDelegate + onClicked）**

对象列表（`byKey` 返回 `QList<WallpaperItem*>`，mock 的 JS 数组同理）作 model 时，delegate 内 `model.xxx`（role 名访问）恒为 undefined、仅 `modelData.xxx` 可读（qmltestrunner offscreen probe 实测确认）。全组模式（`wallpapers` 为 QAbstractListModel）下 `model.xxx` 是 role 访问、可用。统一三态（全组/单组/mock），delegate 与 `onClicked` 的字段读取改双路径兼容 `model.xxx ?? modelData.xxx`。

`package/contents/ui/view/WallpaperDelegate.qml` 三处读取：

```qml
    opacity: (model.pendingDeletion ?? modelData.pendingDeletion) ? 0.5 : 1
    text: model.title ?? modelData.title
    source: model.preview ?? modelData.preview
```

`ThumbnailsPanel.qml` 的 `view.delegate.onClicked`：

```qml
                    onClicked: {
                        if (htmlWallpaper && (model.path ?? modelData.path)) {
                            htmlWallpaper.selectWallpaper = model.file ?? modelData.file;
                            wallpapersGrid.view.currentIndex = index;
                            console.log("Selected wallpaper:", model.file ?? modelData.file, "at index", index);
                        }
                    }
```

说明：全组模式 `model.pendingDeletion` 本就 undefined（WallpaperModel 无此 role），`??` 后仍是 falsy → opacity 1，行为不变；单组/mock 同理。`??`（nullish coalescing）仅左侧为 null/undefined 时取右侧，无副作用。

- [ ] **Step 6: 跑两个现有测试（绿）**

```bash
cmake --build build >/dev/null 2>&1
ctest --test-dir build -R "tst_ThumbnailsBinding|tst_ThumbnailsHighlight" --output-on-failure
```

预期：tst_ThumbnailsBinding 的 `view.model === wallpapers` 断言仍成立（activeFolder 默认 "" → gridModel = walls = 同一数组引用）；tst_ThumbnailsHighlight 点击行为不变（mock JS 数组经 `modelData` 路径 + onClicked 双路径兼容，selectWallpaper 断言通过）。

- [ ] **Step 7: 不 commit（源文件/测试均在用户工作区）**

---

### Task 2: ScanUrlsPanel 标签化（selectedFolder + "全部"标签 + 可点击高亮）

**Files:**
- Modify: `package/contents/ui/view/ScanUrlsPanel.qml`（用户未跟踪文件，叠加修改）

**Interfaces:**
- Produces: `ScanUrlsPanel.selectedFolder: string`（默认 `""` = 全部；config 绑定读取）。delegate 点击 → `selectedFolder = modelData`；"全部"标签点击 → `selectedFolder = ""`。
- Consumes: 自身 `htmlWallpaper`（scanUrls 作 model；删除按钮用 removeScanUrl）。

- [ ] **Step 1: 新增 selectedFolder 属性 + "全部"标签**

在 `ScanUrlsPanel.qml` 根 ColumnLayout 属性区（`property QtObject htmlWallpaper: null` 后）新增：

```qml
    // 当前选中的扫描根 URL（"" = 全部）。由 config.qml 绑定到 ThumbnailsPanel.activeFolder
    property string selectedFolder: ""
```

在 `Kirigami.Separator` 之后、`QQC2.ScrollView` 之前插入固定"全部"标签：

```qml
    // —— 顶部固定"全部"标签：显示所有扫描根合并的壁纸 ——
    Kirigami.SubtitleDelegate {
        Layout.fillWidth: true
        text: i18nd("plasma_wallpaper_org.kde.image", "All")
        // 选中态：selectedFolder 为空即"全部"
        highlighted: scanUrlsPanel.selectedFolder.length === 0
        onClicked: scanUrlsPanel.selectedFolder = ""
    }
```

注意：根 ColumnLayout 需有 `id`（当前为 `scanUrlsPanel`，已存在）。

- [ ] **Step 2: 文件夹 delegate 变为可点击标签（高亮跟随选中）**

现有 delegate 是 `Kirigami.SubtitleDelegate { id: baseListItem ... }`。新增点击与高亮（保留 text/subtitle/按钮逻辑）：

```qml
            delegate: Kirigami.SubtitleDelegate {
                id: baseListItem
                // 字符串数组 model：modelData 直接是路径字符串
                required property string modelData

                width: scanUrlsView.width

                // 标签点击：切换中栏为当前文件夹壁纸组
                onClicked: scanUrlsPanel.selectedFolder = modelData
                // 选中态高亮：当前选中文件夹
                highlighted: scanUrlsPanel.selectedFolder === modelData

                // 原有 text/subtitle/contentItem 按钮逻辑保持不变
                ...
            }
```

原 `hoverEnabled: false / down: false` 保留（列表项无需悬停效果）。

- [ ] **Step 3: 删除当前选中文件夹时回退 selectedFolder**

删除按钮 `onClicked` 中，`htmlWallpaper.removeScanUrl(...)` 前加回退：

```qml
                    QQC2.ToolButton {
                        icon.name: "edit-delete-remove-symbolic"
                        text: i18nd("plasma_wallpaper_org.kde.image", "Remove Folder")
                        display: QQC2.Button.IconOnly
                        onClicked: {
                            // 删除的是当前选中文件夹 → 回退到"全部"
                            if (scanUrlsPanel.selectedFolder === String(baseListItem.modelData)) {
                                scanUrlsPanel.selectedFolder = "";
                            }
                            htmlWallpaper.removeScanUrl(String(baseListItem.modelData));
                        }
                        ...
                    }
```

- [ ] **Step 4: qmllint 校验**

```bash
qmllint package/contents/ui/view/ScanUrlsPanel.qml
```

预期无错误（i18nd 在 qmllint 下可能告警缺失翻译，属预期；`required property`/`pragma ComponentBehavior: Bound` 已具备）。

- [ ] **Step 5: 不 commit（叠加用户未跟踪工作区）**

---

### Task 3: config.qml 中转绑定 + 新增 tst_FolderTabs 集成测试

**Files:**
- Modify: `package/contents/ui/config.qml`
- Create: `test/FolderTabsHost.qml`
- Create: `test/tst_FolderTabs.qml`

**Interfaces:**
- Produces: config 中 `View.ThumbnailsPanel { activeFolder: scanUrlsView.selectedFolder }`；`test/tst_FolderTabs.qml`（`name: "FolderTabsTests"`，被 CMake glob 收集）。
- Consumes: Task 1 的 `ThumbnailsPanel.activeFolder`、Task 2 的 `ScanUrlsPanel.selectedFolder`。

- [ ] **Step 1: config.qml 加中转绑定**

`View.ThumbnailsPanel` 实例（`htmlWallpaper: root.htmlWallpaperController` 那处）追加：

```qml
            // —— 中栏：HTML 壁纸缩略图网格 ——
            View.ThumbnailsPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                htmlWallpaper: root.htmlWallpaperController
                // 标签联动：左栏选中文件夹 → 中栏显示对应壁纸组
                activeFolder: scanUrlsView.selectedFolder
            }
```

- [ ] **Step 2: 新增 test/FolderTabsHost.qml（模拟 config 三层联动）**

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami

import "../package/contents/ui/view" as View

/**
 * 模拟 config.qml 的左栏-中栏联动结构，用于验证标签切换。
 *
 * 复刻 config.qml 关键结构：根内声明控制器子对象，ScanUrlsPanel 与
 * ThumbnailsPanel 并排，ThumbnailsPanel.activeFolder 绑定
 * scanUrlsView.selectedFolder（经 root 别名引用外层控制器避开同名遮蔽）。
 * 暴露 scanUrlsView/thumbnails 供测试断言。
 */
ColumnLayout {
    id: root

    property alias htmlWallpaperController: htmlWallpaper
    // 暴露两个面板供测试断言
    property Item scanUrlsView: null
    property Item thumbnails: null

    // 模拟 config.qml 外层控制器（WallpaperController + WallpaperModel）
    QtObject {
        id: htmlWallpaper
        property string selectWallpaper: ""
        // scanUrls：两个扫描根
        property var scanUrls: ["file:///root/a", "file:///root/b"]

        // 模拟 WallpaperModel：JS 数组 + byKey 按 key 返回不同组
        property var wallpapers: (function () {
            const all = [
                { name: "a1", title: "a1", path: "file:///a1.html", file: "file:///a1.html", preview: "" },
                { name: "a2", title: "a2", path: "file:///a2.html", file: "file:///a2.html", preview: "" },
                { name: "b1", title: "b1", path: "file:///b1.html", file: "file:///b1.html", preview: "" }
            ];
            const groupA = [all[0], all[1]];
            const groupB = [all[2]];
            // byKey 模拟：key 归一化（去末尾斜杠）后返回对应组
            all.byKey = function (url) {
                const key = url.replace(/\/+$/, "");
                if (key === "file:///root/a") return groupA;
                if (key === "file:///root/b") return groupB;
                return [];
            };
            all.get = function (i) { return all[i]; };
            return all;
        })()

        function addScanUrl(url) { scanUrls.push(String(url)); }
        function removeScanUrl(url) {
            scanUrls = scanUrls.filter(function (u) { return u !== String(url); });
        }
    }

    View.ScanUrlsPanel {
        id: scanUrlsPanel
        Layout.maximumWidth: Kirigami.Units.gridUnit * 16
        htmlWallpaper: htmlWallpaper
    }

    View.ThumbnailsPanel {
        id: thumbnailsPanel
        Layout.fillWidth: true
        Layout.fillHeight: true
        htmlWallpaper: root.htmlWallpaperController
        // 标签联动（复刻 config.qml）
        activeFolder: scanUrlsPanel.selectedFolder
        width: 600
        height: 400
    }

    Component.onCompleted: {
        root.scanUrlsView = scanUrlsPanel;
        root.thumbnails = thumbnailsPanel;
    }
}
```

- [ ] **Step 3: 新增 test/tst_FolderTabs.qml（标签切换集成测试）**

```qml
/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtTest

/**
 * 标签式分组展示集成测试：左栏点击标签 → 中栏缩略图视图切换。
 *
 * 锁定 config 层联动：
 *   - 默认选中"全部"：ThumbnailsPanel.gridModel === wallpapers（全部）
 *   - 点击文件夹标签 → activeFolder = 该 URL，gridModel === byKey(url)（单组）
 *   - 点击"全部"标签 → gridModel 切回全部
 *   - 切换标签后 view.currentIndex 复位为 -1（清高亮）
 *
 * 环境注意：htmlWallpaper 用 mock（JS 数组 wallpapers + byKey）；i18n 函数 mock。
 */
TestCase {
    id: testCase
    name: "FolderTabsTests"

    property var i18n: function (text) { return text; }
    property var i18nc: function (context, text) { return text; }
    property var i18nd: function (domain, text) { return text; }
    property var i18ndc: function (domain, context, text) { return text; }

    property var host: null

    function waitForCondition(cond, timeout) {
        let elapsed = 0;
        while (elapsed < timeout && !cond()) {
            testCase.wait(100);
            elapsed += 100;
        }
        return cond();
    }

    function init() {
        let c = Qt.createComponent("FolderTabsHost.qml");
        verify(c.status === Component.Ready, "FolderTabsHost 加载失败: " + c.errorString());
        host = c.createObject(testCase);
        verify(host !== null, "host 实例化失败");
        verify(waitForCondition(() => host.scanUrlsView !== null, 2000), "面板未就绪");
        c.destroy();
    }

    function cleanup() {
        if (host) {
            host.destroy();
            host = null;
        }
    }

    // 默认"全部"：gridModel 是 wallpapers 全量数组
    function test_defaultShowsAll() {
        // activeFolder 默认空 → gridModel 连 wallpapers
        compare(host.thumbnails.activeFolder, "");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        // 全部模式下 gridModel 即 wallpapers 引用
        compare(host.thumbnails.view.model, host.htmlWallpaperController.wallpapers);
    }

    // 点击文件夹标签：触发 ListView delegate 的 clicked 信号（等价真实点击），
    // 锁定 onClicked: selectedFolder = modelData 这条链路；绑定链中段
    // （activeFolder→gridModel）断言与直接赋值驱动等价。
    function test_clickFolderShowsGroup() {
        const list = host.scanUrlsView.folderList;
        verify(waitForCondition(() => list.count === 2, 2000), "scanUrls 未就绪");
        list.currentIndex = 0;
        verify(waitForCondition(() => list.currentItem !== null, 2000), "文件夹 delegate 未实例化");
        list.currentItem.clicked();
        compare(host.scanUrlsView.selectedFolder, "file:///root/a");
        compare(host.thumbnails.activeFolder, "file:///root/a");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        // 单组模式：gridModel 应为 groupA（byKey("file:///root/a") 返回的数组）
        compare(host.thumbnails.view.model.length, 2);
        compare(host.thumbnails.view.model[0].title, "a1");
    }

    // 点击"全部"标签 → 切回全部（先经真实点击选中某文件夹，再触发 allTab）
    function test_clickAllRestoresAll() {
        const list = host.scanUrlsView.folderList;
        list.currentIndex = 1;
        verify(waitForCondition(() => list.currentItem !== null, 2000), "文件夹 delegate 未实例化");
        list.currentItem.clicked();
        compare(host.scanUrlsView.selectedFolder, "file:///root/b");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.model.length, 1);

        // 触发固定"全部"标签点击 → selectedFolder 置空
        host.scanUrlsView.allTab.clicked();
        compare(host.scanUrlsView.selectedFolder, "");
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.model, host.htmlWallpaperController.wallpapers);
        compare(host.thumbnails.view.model.length, 3);
    }

    // 切换标签后 currentIndex 复位（清高亮）
    function test_switchResetsCurrentIndex() {
        host.thumbnails.view.currentIndex = 2;
        host.scanUrlsView.selectedFolder = "file:///root/a";
        verify(waitForCondition(() => host.thumbnails.view.model !== null, 2000), "gridModel 未就绪");
        compare(host.thumbnails.view.currentIndex, -1);
    }
}
```

说明：`test_clickFolderShowsGroup` / `test_clickAllRestoresAll` 通过暴露的 `folderList`（ListView）与 `allTab`（"全部"标签）取真实 delegate 实例并触发其 `clicked` 信号，锁定 `onClicked: selectedFolder = modelData` / `selectedFolder = ""` 点击链路（注：tst_ThumbnailsHighlight 只测缩略图 delegate 点击，不覆盖文件夹标签，不能作为此处兜底）；直接赋值 `selectedFolder` 仅用于绑定链中段（activeFolder→gridModel）的隔离验证（`test_switchResetsCurrentIndex`）。

- [ ] **Step 4: 跑新测试（绿）**

```bash
cmake --build build >/dev/null 2>&1
ctest --test-dir build -R tst_FolderTabs --output-on-failure
```

预期：4 个用例全绿。若 `compare(host.thumbnails.view.model, host.htmlWallpaperController.wallpapers)` 引用不相等（QML 数组 model 包装），改为断言 `view.model.length` 与首元素 title（同 test_clickFolderShowsGroup 的写法）。

- [ ] **Step 5: 不 commit（新增文件依赖工作区 UI，留在工作区）**

---

### Task 4: 收尾验证（qmllint + 全量测试 + 手工运行说明）

**Files:**
- 无源文件改动；仅验证。

- [ ] **Step 1: 三个改动 QML 全部 qmllint**

```bash
qmllint package/contents/ui/view/ThumbnailsPanel.qml
qmllint package/contents/ui/view/ScanUrlsPanel.qml
qmllint package/contents/ui/config.qml
qmllint test/tst_FolderTabs.qml
qmllint test/FolderTabsHost.qml
```

预期无 error（i18nd 缺翻译告警忽略）。

- [ ] **Step 2: 全量 QML + C++ 测试**

```bash
cmake --build build >/dev/null 2>&1
ctest --test-dir build --output-on-failure
```

预期基线（用户 scanUrls 重构未提交，已知预存失败容忍）：
- 通过：tst_ThumbnailsBinding、tst_ThumbnailsHighlight、tst_FolderTabs（新增）、tst_wallpapermodel、tst_wallpaperproject、tst_MainCompile。
- 已知失败（分支回退到 scanPaths 所致，非本计划回归）：tst_Parser（addScanPath）、tst_Smoke（ScanPathsPanel 引用）、tst_WallpaperListModel（scanPaths）——因用户工作区已改名 scanUrls/ScanUrlsPanel。
- 验证：新增/改动用例失败数不增加。

- [ ] **Step 3: 汇总说明（不 commit）**

向用户汇报：改动文件清单、测试结果、待用户提交 scanUrls 重构时一并纳入。不执行任何 git commit。

---
