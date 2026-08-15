# 每文件夹一个 WallpaperModel 设计

**日期**：2026-08-15

## 背景与目标

当前 `WallpaperModel` 是**单 QAbstractListModel 内部分组存储**：所有扫描根（文件夹）的壁纸合并在一个 model 里（`m_items: QHash<QString, QList<WallpaperItem*>>` + `m_groupOrder` + `m_flat` 扁平缓存），QML 端通过 `byKey(key)` 切片显示单组。这带来两个痛点：

1. **`byKey` 返回裸指针快照**：`QList<WallpaperItem*>` 在下次 `scan()/addEntries/clear` 前有效，跨重扫持有即悬空，QML 需靠 `Connections onModelReset` 重算兜底。
2. **对象数组作 model 的引擎语义分裂**：单组模式 `QList<QObject*>` 作 model 时 `model.xxx` 为 `undefined`，仅 `modelData.xxx` 可读，被迫在 delegate / `onClicked` 用 `model.xxx ?? modelData.xxx` 双路径兼容。

本次改为**每文件夹一个独立 `WallpaperModel`**（单文件夹语义）：

> 每个扫描根对应一个常驻 `WallpaperModel` 实例；中栏切换文件夹即切换 `view.model` 引用；"全部"标签用懒建的合并 model（`AllWallpapersModel`）聚合所有文件夹。

收益：`view.model` 恒为真 `QAbstractListModel`，`model.xxx` role 直接可用（**移除双路径兼容**）；无裸指针快照生命周期问题；单文件夹重扫只 reset 对应 model。

## 用户确认的决策

1. **"全部"标签保留**（当前为 ScanPathsPanel header 里的 `Kirigami.Action`，`allAction`），但合并 model 懒建：点"全部"时才创建 `AllWallpapersModel`（挂上各文件夹 model）；不点则不建。
2. **改造 WallpaperModel 为单文件夹**，Controller 持 `QList<WallpaperModel*>`。
3. **scan 时全量预扫所有文件夹**：后台一次扫所有扫描根，每文件夹一个常驻 model，切换即时（仅合并 model 懒建，文件夹 model 不懒建）。
4. **合并 model 用自定义 `AllWallpapersModel`**（非 Qt 内置 `QConcatenateTablesProxyModel`）：`QAbstractListModel` 聚合多源，监听各源 `modelReset` 自动自身 reset，行为可控。

## 命名基线（重要）

当前生产代码已统一为 **`scanPaths` / `addScanPath` / `removeScanPath`** 命名（`wallpapercontroller.h/.cpp`、`ScanPathsPanel.qml`、`config.qml` 均已一致）。**本任务不引入 `scanUrls` 命名**；仅**顺带把测试层残留的 `scanUrls` 引用统一为 `scanPaths`**（`tst_Parser.qml`、`FolderTabsHost.qml`、`tst_FolderTabs.qml`、`wallpaperentry.h` 注释），使全仓一致。

## 架构

```text
config.qml onScanPathsChanged → controller.scan()
  → controller 后台 scanWallpapers(scanPaths)（一次扫全部，按 root 归组返回）
  → 每组结果 → modelFor(group.key)->addEntries(group.entries)
  → 各 model 独立 modelReset；controller 发 scanFinished
  → scan 完成时 releaseStaleModels + 若已建合并 model 则 setSources 重挂最新源
    （保活复用，QML 引用无悬空；未建则保持未建——懒建语义不变）

QML 切换：ScanPathsPanel 标签 → activeFolder（"" = 全部）
  → ThumbnailsPanel.refreshModel():
      gridModel = activeFolder=="" ? htmlWallpaper.allModel()
                                   : htmlWallpaper.modelFor(activeFolder)
      view.currentIndex = -1; view.positionViewAtIndex(0, ...)
```

- **"全部"路径**：`allModel()` 懒建 `AllWallpapersModel`（缓存），挂当前全部文件夹 model 为源。
- **单文件夹路径**：`modelFor(url)` 返回该文件夹常驻 `WallpaperModel*`（key 归一化，不存在即新建空 model）。
- **重扫**：`onActiveFolderChanged` 重算 gridModel；model 实例常驻，`modelReset` 由 GridView 自动响应，无需 `Connections` 兜底。

## WallpaperModel（改造为单文件夹）

**文件**：`plugin/wallpapermodel.h` / `plugin/wallpapermodel.cpp`

```cpp
class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(QString key READ key CONSTANT)   // 本文件夹归一化 URL
public:
    enum Roles { NameRole = Qt::UserRole + 1, TitleRole, PathRole, PreviewRole, FileRole };
    Q_ENUM(Roles)

    explicit WallpaperModel(const QString &key, QObject *parent = nullptr);

    QString key() const;
    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 替换本文件夹全部条目；同文件夹重扫即整组覆盖。主线程调用；reset 一次。 */
    Q_INVOKABLE void addEntries(const QList<WallpaperEntry> &wallpapers);
    void clear();
    Q_INVOKABLE WallpaperItem *get(int i);
    Q_INVOKABLE int indexOf(const QString &source) const;

private:
    QString m_key;                 // 本文件夹归一化 URL（调试/容器映射用）
    QList<WallpaperItem *> m_items; // 本文件夹的壁纸项（QObject parent = 本 model）
};
```

- **删除**：`m_items`(QHash) / `m_groupOrder` / `m_flat`（扁平化缓存）、`byKey / keys / groupCount / folderName / parentPath / scan() / scanInProgress / m_watcher`。
- **保留**：roles 五字段、`count / rowCount / data / roleNames / get / indexOf / clear`。
- `addEntries` 去掉 key 参数，内部直接 `qDeleteAll` 旧 `m_items` 后重建，`beginResetModel()/endResetModel()`。
- 职责收敛为**纯数据容器**（一个文件夹的壁纸项列表），无扫描逻辑、无后台线程。

## WallpaperController（扫描编排 + 多 model 容器）

**文件**：`plugin/wallpapercontroller.h` / `plugin/wallpapercontroller.cpp`

```cpp
class WallpaperController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_NAMED_ELEMENT(WallpaperController)

    Q_PROPERTY(QString selectWallpaper READ selectWallpaper WRITE setSelectWallpaper NOTIFY selectWallpaperChanged)
    Q_PROPERTY(QStringList scanPaths READ scanPaths WRITE setScanPaths NOTIFY scanPathsChanged)
    Q_PROPERTY(bool scanInProgress READ scanInProgress NOTIFY scanInProgressChanged)

public:
    explicit WallpaperController(QObject *parent = nullptr);
    QString selectWallpaper() const;
    void setSelectWallpaper(const QString &wallpaper);
    QStringList scanPaths() const;
    void setScanPaths(const QStringList &urls);
    bool scanInProgress() const;
    int modelCount() const;

    Q_INVOKABLE void scan();
    Q_INVOKABLE bool addScanPath(const QString &url);
    Q_INVOKABLE void removeScanPath(const QString &url);
    /** 返回 url 对应文件夹的常驻 WallpaperModel*；不存在即新建（key 归一化）。 */
    Q_INVOKABLE WallpaperModel *modelFor(const QString &url);
    /** 返回懒建的合并 model（全部文件夹聚合）；scan 完成后缓存失效下回重建。 */
    Q_INVOKABLE QAbstractItemModel *allModel();
    Q_INVOKABLE QString folderName(const QString &url) const;
    Q_INVOKABLE QString parentPath(const QString &url) const;

Q_SIGNALS:
    void selectWallpaperChanged();
    void scanPathsChanged();
    void scanFinished();
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    WallpaperModel *obtainModel(const QString &url); // 内部：创建/复用（modelFor 的实现）
    void releaseStaleModels(const QStringList &kept); // 销毁已不在 scanPaths 的 model
    QString m_selectWallpaper;
    QStringList m_scanPaths;
    QList<WallpaperModel *> m_models;    // 按 key 缓存（key = WallpaperPath::toUrl 归一化）
    QAbstractItemModel *m_allModel = nullptr; // 懒建合并 model
    bool m_scanning = false;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
```

- **扫描编排上移**：`scanWallpapers`（现位于 wallpapermodel.cpp 匿名命名空间）移至 controller.cpp；`ScanResult/ScanGroup`（wallpaperentry.h）不动。单 `QFutureWatcher` 后台扫全部 roots，`finished` 回调中逐组 `modelFor(group.key)->addEntries(group.entries)`，再 `releaseStaleModels(scanPaths)` 清理已删文件夹的 model，最后若 `m_allModel` 已建（用户点过"全部"）则 `setSources(m_models)` 重挂最新源（保活复用，避免 QML 引用悬空——销毁重建会在 QML 正持引用时留下悬空指针；未建则不动，懒建语义保持），发 `scanFinished`。
- **命名保持**：`scanPaths / addScanPath / removeScanPath` 沿用当前生产命名，**不改名**（`Q_PROPERTY WallpaperModel *wallpapers` 删除，改为 `modelFor`/`allModel`）。
- `folderName / parentPath` 从 WallpaperModel 移入 controller（URL 工具，与单个 model 无关）。
- `scanInProgress / scanFinished / scanFailed` 信号保留（controller 原转发自 WallpaperModel，现直接持有）。

## AllWallpapersModel（合并 model，"全部"懒建）

**文件**：`plugin/allwallpapersmodel.h` / `plugin/allwallpapersmodel.cpp`（新增）

```cpp
class AllWallpapersModel : public QAbstractListModel
{
    Q_OBJECT
public:
    explicit AllWallpapersModel(QObject *parent = nullptr);
    /** 重建源挂载（源列表变化后调用）；内部监听各源 modelReset → 自身整体 reset。 */
    void setSources(const QList<WallpaperModel *> &sources);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

private:
    void onSourceReset();
    QList<WallpaperModel *> m_sources;
};
```

- `rowCount` = 各源 `rowCount` 求和；`data` 遍历源定位行后转调源 `data`（role 直接透传）；`roleNames` 硬编码对齐 `WallpaperModel::roleNames`（五字段）。
- 对每个源 `connect(modelReset, onSourceReset)`；任一源 reset → 自身 `beginResetModel()/endResetModel()`，GridView 自动刷新。
- `setSources` 需断开旧源连接、连接新源，并触发自身 reset。

## QML 层

### ThumbnailsPanel.qml

```qml
// 当前网格 model：全部 → controller.allModel()（懒建合并）；单文件夹 → controller.modelFor(activeFolder)
property var gridModel: null

function refreshModel() {
    if (!htmlWallpaper) {
        gridModel = null;
        return;
    }
    gridModel = activeFolder.length === 0
        ? htmlWallpaper.allModel()
        : htmlWallpaper.modelFor(activeFolder);
    wallpapersGrid.view.currentIndex = -1;
    wallpapersGrid.view.positionViewAtIndex(0, ListView.Beginning);
}
```

- **删除** `Connections onModelReset`：model 实例常驻，`modelReset` 由 GridView 自动响应；`onActiveFolderChanged`/`onHtmlWallpaperChanged` 触发重算即可。全部模式无需监听 scanFinished——合并 model 自身转发各源 modelReset，scan 后 controller 对缓存实例 `setSources` 重挂源，GridView 自动刷新。
- `refreshModel` 中"滚回顶部 + 清高亮"保留（切换标签语义）。

### WallpaperDelegate.qml

```qml
text: model.title          // 原：model.title ?? modelData.title
source: model.preview      // 原：model.preview ?? modelData.preview
opacity: model.pendingDeletion ? 0.5 : 1   // 不变（单路径本就如此）
```

移除双路径兼容（`view.model` 恒为真 QAbstractListModel，role 直接可用）。onClicked（ThumbnailsPanel 内联）：

```qml
onClicked: {
    if (htmlWallpaper && model.path) {
        htmlWallpaper.selectWallpaper = model.file;
        wallpapersGrid.view.currentIndex = index;
    }
}
```

### ScanPathsPanel.qml

- `model: htmlWallpaper.scanPaths`（controller 命名保持，正常）。
- `folderName / parentPath` 调用改到 controller：`htmlWallpaper.folderName(modelData)` / `htmlWallpaper.parentPath(modelData)`（原经 `htmlWallpaper.wallpapers.folderName(...)`）。
- **修复 allTab alias 编译错误（当前 HEAD 遗留）**：`property alias allTab: allAction` 引用的 `allAction` 是 `header: Kirigami.InlineViewHeader { ... actions: [Kirigami.Action { id: allAction }] }` 内嵌 id，对根 `ColumnLayout`（scanPathsPanel）不可见，编译报 `Invalid alias reference`。修复方案：把 `allAction`（及 Add… action）提到 ListView 外部、根组件作用域内定义（`Kirigami.Action` 非 Item，不参与布局），header 的 `actions` 数组改为引用这两个 id；`property alias allTab: allAction` 保持暴露给集成测试驱动。`highlighted: selectedFolder.length === 0` 一并补回。
- 标签 / selectedFolder / 删除回退逻辑不变。

### config.qml

- `View.ScanPathsPanel { id: scanPathsView }`、`cfg_ScanPaths`、`onScanPathsChanged: scan()` 均**保持现有命名**（无需改名）。
- `activeFolder: scanPathsView.selectedFolder` 绑定不变。

## 数据流

```text
config.qml onScanPathsChanged → controller.scan()
  → controller.scanWallpapers(scanPaths)：后台按 root 归组，保序返回 ScanResult.groups
  → finished：逐组 modelFor(key)->addEntries(group.entries)
              → releaseStaleModels（删已移除文件夹的 model）
              → 若已建合并 model 则 setSources 重挂最新源 → scanFinished
  → 各 WallpaperModel 独立 beginResetModel/endResetModel

中栏：点击左栏标签 → selectedFolder → config 绑定 → activeFolder
  → ThumbnailsPanel.refreshModel() → gridModel = allModel() | modelFor(activeFolder)
  → KCM.GridView view.model 绑定 → delegate 单路径 model.xxx
```

## 测试计划

**当前测试基线（修正前 3 失败，均随本任务修复）：**

| 测试 | 当前状态 | 失败根因 |
| ---- | -------- | -------- |
| `tst_Parser` | FAILED | 测 `parser.scanUrls`，生产已改名 `scanPaths`（属性不存在 → undefined） |
| `tst_FolderTabs` | FAILED | `FolderTabsHost.qml` 引用 `View.ScanUrlsPanel`（已改名 ScanPathsPanel.qml）+ mock `scanUrls` 数组 + allAction alias 编译错误 |
| `tst_Smoke` | FAILED | `ScanPathsPanel.qml` allAction alias 编译失败 → `config.qml`/`ScanPathsPanel.qml` 编译用例失败 |

- **C++ `tst_wallpapermodel`**（重写为单文件夹语义）：`addEntries` 整组替换、`count/rowCount/data/get/indexOf`、`clear`、roles 对齐。
- **C++ 新增 controller 用例**（可并入 `tst_wallpapermodel` 或新增 `tst_wallpapercontroller`）：`modelFor` key 归一化去重建、多文件夹分发、`scan` 后模型清空旧组、`allModel` 合并 `rowCount/data` 跨源、`releaseStaleModels` 删已移除文件夹。
- **C++ `tst_WallpaperListModel`**：重写多文件夹语义（原依赖 `wallpapers`/`groupCount`/`keys`/`byKey` 全部删除）——`modelFor(scanPaths[0]).count` 逐组断言、`allModel()` 聚合总数跨源校验。
- **QML `tst_FolderTabs` / `FolderTabsHost`**：mock 改 `scanPaths` 数组 + `modelFor` / `allModel` / `folderName` / `parentPath` 形态，`View.ScanUrlsPanel` → `View.ScanPathsPanel`，`scanUrlsView` → `scanPathsView`；断言 `view.model === modelFor(url)`（单组）与 `view.model === allModel()`（全部）。
- **QML `tst_ThumbnailsBinding` / `tst_ThumbnailsHighlight`**：mock 改 `modelFor` / `allModel`；**去掉 modelData 双路径**，断言回 `model.xxx` 单路径。
- **顺带修复（命名统一为 scanPaths）**：`tst_Parser.qml` 的 `scanUrls` → `scanPaths`；`wallpaperentry.h` 注释 `scanUrls` → `scanPaths`；`tst_Smoke` 全量回归（allAction alias 修复后 `config.qml`/`ScanPathsPanel.qml` 编译恢复）。

## 影响面

| 文件                                    | 改动                                                                                     |
| --------------------------------------- | ---------------------------------------------------------------------------------------- |
| `plugin/wallpapermodel.h/.cpp`          | 重构为单文件夹：删分组存储/扫描，加 key 属性                                            |
| `plugin/wallpapercontroller.h/.cpp`     | 扫描编排上移 + 多 model 容器 + modelFor/allModel/folderName/parentPath（命名保持 scanPaths） |
| `plugin/allwallpapersmodel.h/.cpp`      | 新增：合并 model（"全部"懒建）                                                          |
| `plugin/wallpaperitem.h`                | 不动                                                                                     |
| `plugin/wallpaperentry.h`               | 不动（ScanResult/ScanGroup 保留；仅注释 scanUrls → scanPaths）                          |
| `package/contents/ui/view/ThumbnailsPanel.qml` | gridModel 改 allModel()/modelFor()，删 Connections，onClicked 单路径                      |
| `package/contents/ui/view/WallpaperDelegate.qml` | 移除 modelData 双路径兼容                                                          |
| `package/contents/ui/view/ScanPathsPanel.qml` | folderName/parentPath 调用改 controller + 修复 allTab alias 编译错误                  |
| `package/contents/ui/config.qml`        | 保持 ScanPathsPanel 命名（无类型名修正）                                               |
| `test/tst_wallpapermodel.cpp`           | 重写为单文件夹 + 新增 controller/合并 model 用例                                        |
| `test/tst_Parser.qml`                   | scanUrls → scanPaths（命名统一）                                                        |
| `test/tst_WallpaperListModel.qml`       | 重写多文件夹语义：wallpapers → modelFor/allModel，删 groupCount/keys/byKey 断言        |
| `test/tst_Smoke.qml`                    | 全量回归（allAction alias 修复后编译用例恢复）                                          |
| `test/tst_FolderTabs.qml` / `FolderTabsHost.qml` | 改 scanPaths 命名 + modelFor/allModel 形态 + View.ScanPathsPanel                    |
| `test/tst_ThumbnailsBinding.qml` / `tst_ThumbnailsHighlight.qml` | mock 改 modelFor/allModel + 去双路径                              |
