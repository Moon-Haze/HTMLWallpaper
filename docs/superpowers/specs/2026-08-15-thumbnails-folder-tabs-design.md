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

**不改动 C++ 数据层**。`WallpaperModel::byKey(key)` 返回的 `QList<WallpaperItem*>`（QObject 指针数组）在 QML 中可直接作 GridView 的 model：`WallpaperItem` 的 Q_PROPERTY（`title`/`preview`/`file`/`path`）与现有 role 名一致，delegate 无需改动，`model.title` 等访问方式不变。

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

### 3. `package/contents/ui/config.qml`

- 在 `View.ThumbnailsPanel` 上新增绑定：`activeFolder: scanUrlsView.selectedFolder`。
- 其余不变。

### 4. 测试

- **`test/tst_ThumbnailsBinding.qml`**：mock 的 `wallpapers` 仍为 ListModel；`activeFolder` 默认 "" → model 连 `wallpapers`，`view.model` 断言保留；补 `byKey` mock 覆盖单组模式（可选）。
- **`test/tst_ThumbnailsHighlight.qml`**：mock 补 `byKey` 方法（返回整组列表）；`activeFolder` 默认 "" 时行为不变，点击联动断言保留。
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
- **QList<QObject*> 作 model 的限制**：无 `pendingDeletion` 等 WallpaperModel 特有 role，但 HTML 模式下 delegate 本就不读取该字段（undefined → opacity 1），无影响。
- **不引入 section**：`GridView.section` 方案已否决（用户明确选择标签切换形态）。
