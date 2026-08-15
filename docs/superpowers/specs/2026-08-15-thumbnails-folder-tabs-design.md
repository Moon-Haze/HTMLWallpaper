# 缩略图标签式分组展示设计

**日期**：2026-08-15

## 背景与目标

HTMLWallpaper 壁纸配置页当前为三栏布局：左栏扫描目录列表（ScanUrlsPanel）、中栏缩略图网格（ThumbnailsPanel，一次平铺所有扫描根收集的壁纸）、右栏参数（已删除）。

此前壁纸按扫描根分组存储（WallpaperModel 的 `m_items`/`keys()`/`byKey()`），但 UI 仍全部平铺。现改为**标签式分组展示**：

> 左栏 ScanUrlsPanel 的文件夹列表变为标签（tab），点击标签，中栏缩略图视图切换为对应文件夹的壁纸组。

## 用户确认的决策

1. **左栏操作保留**：标签仍保留删除/在文件管理器中打开按钮（悬停显示），"添加文件夹"按钮保留在悬浮标题栏。
2. **加"全部"标签**：左栏顶部固定一个"全部"标签，点击显示所有扫描根合并的壁纸；其余标签显示单个文件夹组。
3. **标签只管视图**：点击标签仅切换缩略图视图，不自动应用壁纸；应用壁纸仍靠点击缩略图（现状不变）。
4. **切换滚回顶部**：切换标签时中栏 GridView 滚动回顶部、选中高亮清空。

## 架构

[config.qml](../../../package/contents/ui/config.qml) 作为协调层，单向传递"当前选中文件夹"状态：

```
ScanUrlsPanel (左栏)
   │  property string selectedFolder   （"" = 全部）
   │  点击标签 → 更新 selectedFolder
   ▼
config.qml 绑定:
   ThumbnailsPanel.activeFolder = scanUrlsView.selectedFolder
   ▼
ThumbnailsPanel (中栏)
   model = activeFolder=="" ? wallpapers(全部)
                          : wallpapers.byKey(activeFolder)(单组)
```

**不改动 C++ 数据层**。`WallpaperModel::byKey(key)` 返回的 `QList<WallpaperItem*>`（QObject 指针数组）在 QML 中可作 GridView 的 model。但实测（qmltestrunner offscreen probe，2026-08-15）确认：**JS 数组与 QML 内创建的 QObject 数组作 model 时，delegate 内 `model.xxx`（role 名访问）为 `undefined`，仅 `modelData.xxx` 可读**；生产 `QList<WallpaperItem*>` 经 QVariantList 转换可能暴露 Q_PROPERTY 为 named role（未在真实插件环境复测，两种引擎语义均被双路径兜底）。这与全组模式（`wallpapers` 为 `QAbstractListModel`，role 访问 `model.xxx` 可用）的访问方式不一致。因此 `WallpaperDelegate` 与 `ThumbnailsPanel` 的 `onClicked` 采用**双路径兼容**：

```qml
model.xxx ?? modelData.xxx
```

全组模式走 role 路径（`model.xxx` 可用），单组模式走 Q_PROPERTY 路径（`modelData.xxx` 可用）；`??`（nullish coalescing）仅在左侧为 `null`/`undefined` 时取右侧，无副作用。mock 用 JS 对象数组即经 `modelData` 路径验证单组行为。

## 数据流

1. **初始**：`selectedFolder = ""`，中栏显示全部壁纸（`wallpapers`）。
2. **点击文件夹标签**：`ScanUrlsPanel.selectedFolder = url`（归一化扫描根 URL）→ config 绑定 → `ThumbnailsPanel.activeFolder = url` → model 切换为 `wallpapers.byKey(url)`。
3. **点击"全部"标签**：`selectedFolder = ""` → model 切回 `wallpapers`。
4. **重扫**：`scanUrls` 变化触发 `scan()`，WallpaperModel `clear()`+`addEntries()` 导致 modelReset；`byKey` 快照随之失效。ThumbnailsPanel 监听 `modelReset` 重新计算 model，避免悬空指针。
5. **删除当前选中文件夹**：`selectedFolder` 重置为 `""`（回落到"全部"）。

## 文件改动

### 1. `package/contents/ui/view/ScanUrlsPanel.qml`

- 新增属性 `property string selectedFolder: ""`（"" = 全部）。
- 顶部（`Kirigami.Separator` 之后）新增固定**"全部"标签**（不随列表滚动）：
  - `Kirigami.BasicListItem`，文本 `i18nd("plasma_wallpaper_org.kde.image", "All")`；
  - `highlighted: selectedFolder === ""`；
  - `onClicked`：`selectedFolder = ""`、`scanUrlsView.currentIndex = -1`。
- 文件夹 ListView：
  - 保留 `model: htmlWallpaper.scanUrls`、悬浮标题栏（含"添加文件夹"按钮）；
  - delegate 变为**可点击标签**：`onClicked` 设 `scanUrlsView.currentIndex = index`、`selectedFolder = modelData`；
  - 高亮跟随 `ListView.isCurrentItem`（`highlightFollowsCurrentItem` 保证滚动跟随）；
  - 保留右侧删除/打开按钮（原有逻辑），删除当前选中文件夹时回退 `selectedFolder = ""`。
- 空态提示不变。

### 2. `package/contents/ui/view/ThumbnailsPanel.qml`

- 新增属性 `property string activeFolder: ""`。
- 网格 model 改为**受控变量**（不用纯绑定，因需响应 modelReset）：

```qml
property var gridModel: null

function refreshModel() {
    if (!htmlWallpaper || !htmlWallpaper.wallpapers) {
        gridModel = null;
        return;
    }
    gridModel = activeFolder.length === 0
        ? htmlWallpaper.wallpapers
        : htmlWallpaper.wallpapers.byKey(activeFolder);
    // 切换标签：滚回顶部 + 清空高亮
    wallpapersGrid.view.currentIndex = -1;
    wallpapersGrid.view.positionViewAtIndex(0, ListView.Beginning);
}
```

- 触发刷新：`onActiveFolderChanged`、`onHtmlWallpaperChanged`、`Connections { target: htmlWallpaper?.wallpapers; onModelReset: refreshModel() }`（重扫保护）。
- `view.model: gridModel`；`view.currentIndex` 语义不变。
- `view.delegate` 的 `onClicked` 改双路径兼容（单组模式 `model.path`/`model.file` 为 `undefined`）：

```qml
                    onClicked: {
                        if (htmlWallpaper && (model.path ?? modelData.path)) {
                            htmlWallpaper.selectWallpaper = model.file ?? modelData.file;
                            wallpapersGrid.view.currentIndex = index;
                            console.log("Selected wallpaper:", model.file ?? modelData.file, "at index", index);
                        }
                    }
```

### 2b. `package/contents/ui/view/WallpaperDelegate.qml`

- 所有 `model.xxx` 读取改双路径兼容 `model.xxx ?? modelData.xxx`（`text: model.title`、`source: model.preview`、`opacity: model.pendingDeletion`）。
- 全组模式（`QAbstractListModel`）走 role 路径；单组模式（`QList<WallpaperItem*>`）走 Q_PROPERTY 路径；mock（JS 数组）走 `modelData` 路径——三态统一。

### 3. `package/contents/ui/config.qml`

- 在 `View.ThumbnailsPanel` 上新增绑定：`activeFolder: scanUrlsView.selectedFolder`。
- 其余不变。

### 4. 测试

- **`test/ThumbnailsHost.qml` / `test/tst_ThumbnailsHighlight.qml`**：mock 的 `wallpapers` 由 `ListModel` 改为 JS 数组（挂 `byKey`/`get` 方法）。delegate 双路径兼容下，JS 数组经 `modelData` 路径读取字段，与单组模式（`QList<WallpaperItem*>`）行为一致。`activeFolder` 默认 "" 时 `view.model === wallpapers` 断言保留（同一数组引用）；点击联动断言保留（走 `modelData` 路径）。
- **新增 `test/tst_FolderTabs.qml`**（含 mock host 或直接内联 mock）：
- **新增 `test/tst_FolderTabs.qml`**（含 mock host 或直接内联 mock）：
  - 默认选中"全部"：`view.model === wallpapers`；
  - 点击文件夹标签：`view.model === byKey(url)` 且 `activeFolder` 传递正确；
  - 点击"全部"标签：model 切回 `wallpapers`；
  - 切换标签后 `currentIndex` 复位为 -1、滚动回顶部（`positionViewAtIndex(0)` 可达性验证）。
- mock controller 需提供 `scanUrls`（QStringList）、`wallpapers`（含 `byKey` 的 ListModel 或对象）、`selectWallpaper`、`addScanUrl`/`removeScanUrl`（现有 mock 已具备大部分）。

## 边界与风险

- **`byKey` 快照悬空**：重扫时旧组被 `delete`。用 `modelReset` 监听重新计算 model 规避；`byKey()` 返回快照仅在下次 `scan()/addEntries()/clear()` 前有效（已有注释）。
- **删除选中文件夹**：`selectedFolder` 必须回落 `""`，否则中栏绑定到不存在的 key。
- **`scanUrls` 空列表**：无文件夹时左栏仅剩"全部"标签，中栏正常显示空态。
- **QList<QObject*> 作 model 的语义**：JS 数组 / QML 内 QObject 数组作 model 时 `model.xxx` 为 undefined、仅 `modelData.xxx` 可读（probe 实测）；生产 `QList<QObject*>` 经 QVariantList 转换可能暴露 Q_PROPERTY 为 named role（未复测，不影响正确性）。delegate 改用双路径 `model.xxx ?? modelData.xxx`：全组走 role、单组走 Q_PROPERTY 或 modelData、mock 走 JS 对象属性，三态统一。`pendingDeletion` 在三态均为 undefined → opacity 1（无此 role 的模型，符合预期），保持单路径 `model.pendingDeletion ? 0.5 : 1`（QAbstractListModel 下空 modelData 的属性访问虽宽容不抛错，但无需兜底）。
- **不引入 section**：`GridView.section` 方案已否决（用户明确选择标签切换形态）。
