# 每文件夹一个 WallpaperModel 设计

**日期**：2026-08-15（修订：2026-08-16 "全部"汇总最终由独立 `WallpaperModel("ALL")` 承担，`AllWallpapersModel` 方案未落地，详见 merge spec）

## 背景与目标

当前 `WallpaperModel` 是**单 QAbstractListModel 内部分组存储**：所有扫描根（文件夹）的壁纸合并在一个 model 里（`m_items: QHash<QString, QList<WallpaperItem*>>` + `m_groupOrder` + `m_flat` 扁平缓存），QML 端通过 `byKey(key)` 切片显示单组。这带来两个痛点：

1. **`byKey` 返回裸指针快照**：`QList<WallpaperItem*>` 在下次 `scan()/addEntries/clear` 前有效，跨重扫持有即悬空，QML 需靠 `Connections onModelReset` 重算兜底。
2. **对象数组作 model 的引擎语义分裂**：单组模式 `QList<QObject*>` 作 model 时 `model.xxx` 为 `undefined`，仅 `modelData.xxx` 可读，被迫在 delegate / `onClicked` 用 `model.xxx ?? modelData.xxx` 双路径兼容。

本次改为**每文件夹一个独立 `WallpaperModel`**（单文件夹语义）：

> 每个扫描根对应一个常驻 `WallpaperModel` 实例；中栏切换文件夹即切换 `view.model` 引用；"全部"标签由独立 `WallpaperModel("ALL")` 承担，scan 时 `clear()` + `addEntries` 重建汇总内容。

收益：`view.model` 恒为真 `QAbstractListModel`，`model.xxx` role 直接可用（**移除双路径兼容**）；无裸指针快照生命周期问题；单文件夹重扫只 reset 对应 model。

## 用户确认的决策

1. **"全部"标签保留**（当前为 ScanPathsPanel header 里的 `Kirigami.Action`，`allAction`）；"全部"汇总由独立 `WallpaperModel("ALL")` 承担，controller 构造即建、scan 重建内容（保活复用，不懒建不销毁）。
2. **改造 WallpaperModel 为单文件夹**，Controller 持 `QList<WallpaperModel*>`。
3. **scan 时全量预扫所有文件夹**：后台一次扫所有扫描根，每文件夹一个常驻 model，切换即时。
4. **不引入聚合 model 类**：`AllWallpapersModel` 在 merge 阶段删除，"全部"复用单文件夹 `WallpaperModel`（`key = "ALL"`），scan 时 `clear()` 后逐组 `addEntries` 重建（无多源聚合、无源 reset 联动）。

## 命名基线（重要）

当前生产代码已统一为 **`scanPaths` / `addScanPath` / `removeScanPath`** 命名（`wallpapercontroller.h/.cpp`、`ScanPathsPanel.qml`、`config.qml` 均已一致）。**本任务不引入 `scanUrls` 命名**；仅**顺带把测试层残留的 `scanUrls` 引用统一为 `scanPaths`**（`tst_Parser.qml`、`FolderTabsHost.qml`、`tst_FolderTabs.qml`、`wallpaperentry.h` 注释），使全仓一致。

## 架构

```text
config.qml onScanPathsChanged → controller.scan()
  → controller 后台 scanWallpapers(scanPaths)（一次扫全部，按 root 归组返回）
  → 每组结果 → modelFor(group.key)->setEntries(group.entries)
  → 同时 m_allModel->clear() + 逐组 addEntries(group.entries)（重建"全部"汇总）
  → 各 model 独立 modelReset；controller 发 scanFinished
  → scan 完成时 releaseStaleModels 清理已移除文件夹的 model（保活复用，QML 引用无悬空）

QML 切换：ScanPathsPanel 标签 → controller.setActiveModel(modelFor(activeFolder) | allModel())
  → ThumbnailsPanel 直接绑 view.model: controller.activeModel
  → view.currentIndex: controller.activeIndex（点击写 activeIndex = index）
```

- **"全部"路径**：`allModel()` 返回独立 `WallpaperModel("ALL")`（controller 构造即建，保活复用）；scan 时 `clear()` + 逐组 `addEntries` 重建内容。
- **单文件夹路径**：`modelFor(url)` 返回该文件夹常驻 `WallpaperModel*`（key 归一化，不存在即新建空 model）。
- **重扫**：`setActiveModel` 切换活动 model；model 实例常驻，`modelReset` 由 GridView 自动响应，无需 `Connections` 兜底。

## WallpaperModel（改造为单文件夹）

**文件**：`plugin/wallpapermodel.h` / `plugin/wallpapermodel.cpp`

```cpp
class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(QString key READ key CONSTANT)   // 本文件夹归一化 URL
    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged)
public:
    enum Roles { NameRole = Qt::UserRole + 1, PathRole, PreviewRole, FileRole };
    Q_ENUM(Roles)

    explicit WallpaperModel(const QString &key, QObject *parent = nullptr);

    QString key() const;
    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 整组替换本文件夹全部条目；同文件夹重扫即整组覆盖。主线程调用；reset 一次。 */
    Q_INVOKABLE void setEntries(const QList<WallpaperEntry> &wallpapers);
    /** 追加条目到列表末尾（保留已有条目）；insertRows 增量通知。 */
    Q_INVOKABLE void addEntries(const QList<WallpaperEntry> &wallpapers);
    void clear();
    Q_INVOKABLE WallpaperItem *get(int i);
    int selectedIndex() const;
    void setSelectedIndex(int index);
    void setSelectedIndexOfFile(const QString &file);

private:
    QString m_key;                 // 本文件夹归一化 URL（调试/容器映射用）
    QList<WallpaperItem *> m_items; // 本文件夹的壁纸项（QObject parent = 本 model）
    int m_selectedIndex = -1;       // 本文件夹选中行（-1 = 无选中）
};
```

- **删除**：`m_items`(QHash) / `m_groupOrder` / `m_flat`（扁平化缓存）、`byKey / keys / groupCount / folderName / parentPath / scan() / scanInProgress / m_watcher / indexOf`。
- **保留**：roles 四字段、`count / rowCount / data / roleNames / get / clear`；新增 `setEntries / selectedIndex / setSelectedIndexOfFile`。
- `setEntries` 去掉 key 参数，内部直接 `qDeleteAll` 旧 `m_items` 后重建，`beginResetModel()/endResetModel()`；`addEntries` 改为纯追加（insertRows）。
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
    Q_PROPERTY(WallpaperModel *activeModel READ activeModel WRITE setActiveModel NOTIFY activeModelChanged)
    Q_PROPERTY(int activeIndex READ activeIndex WRITE setActiveIndex NOTIFY activeIndexChanged)

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
    /** 返回"全部"汇总 model（独立 WallpaperModel("ALL")，构造即建、保活复用）。 */
    Q_INVOKABLE WallpaperModel *allModel();
    Q_INVOKABLE QString folderName(const QString &url) const;
    Q_INVOKABLE QString parentPath(const QString &url) const;

Q_SIGNALS:
    void selectWallpaperChanged();
    void scanPathsChanged();
    void scanFinished();
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();
    void activeModelChanged();
    void activeIndexChanged();

private:
    WallpaperModel *obtainModel(const QString &url); // 内部：创建/复用（modelFor 的实现）
    void releaseStaleModels(const QStringList &kept); // 销毁已不在 scanPaths 的 model
    QString m_selectWallpaper;
    QStringList m_scanPaths;
    QList<WallpaperModel *> m_models;    // 按 key 缓存（key = WallpaperPath::toUrl 归一化）
    WallpaperModel *m_allModel = new WallpaperModel(QStringLiteral("ALL"), this); // 保活复用
    WallpaperModel *m_activeModel = m_allModel; // 当前活动壁纸集合（防悬空见 releaseStaleModels）
    bool m_scanning = false;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
```

- **扫描编排上移**：`scanWallpapers`（现位于 wallpapermodel.cpp 匿名命名空间）移至 controller.cpp；`ScanResult/ScanGroup`（wallpaperentry.h）不动。单 `QFutureWatcher` 后台扫全部 roots，`finished` 回调中逐组 `modelFor(group.key)->setEntries(group.entries)`，同时 `m_allModel->clear()` + 逐组 `addEntries(group.entries)` 重建"全部"汇总，再 `releaseStaleModels(scanPaths)` 清理已删文件夹的 model（若释放的正是 activeModel 则置空并 emit），发 `scanFinished`。
- **命名保持**：`scanPaths / addScanPath / removeScanPath` 沿用当前生产命名，**不改名**（`Q_PROPERTY WallpaperModel *wallpapers` 删除，改为 `modelFor`/`allModel`）。
- `folderName / parentPath` 从 WallpaperModel 移入 controller（URL 工具，与单个 model 无关）。
- `scanInProgress / scanFinished / scanFailed` 信号保留（controller 原转发自 WallpaperModel，现直接持有）。

## "全部"汇总 model（复用 WallpaperModel）

**不新增聚合类**：`AllWallpapersModel` 最终未创建，已在 merge 阶段删除。controller 构造即持 `m_allModel = new WallpaperModel("ALL", this)`，scan 时 `clear()` + 逐组 `addEntries` 重建内容（保活复用，QML 引用无悬空）。

```cpp
WallpaperModel *m_allModel = new WallpaperModel(QStringLiteral("ALL"), this); // 保活复用
```

- `key = "ALL"` 标识汇总 model；内容 = 各文件夹条目顺序拼接（scan 逐组 addEntries）。
- 无多源聚合逻辑、无 `setSources`、无源 reset 联动——同一套单文件夹实现即可承担。

## QML 层

### ThumbnailsPanel.qml

```qml
// 当前网格 model 与选中行：直接绑 controller 的活动集合与选中行
view.model: wallpaperController.activeModel
view.currentIndex: wallpaperController.activeIndex
```

- **不再用 gridModel/refreshModel**：中栏直接绑 `view.model: controller.activeModel`，切换由 ScanPathsPanel 点击 → `controller.activeModel = modelFor(activeFolder)|allModel()` 驱动（见下 ScanPathsPanel 段）。
- **删除** `Connections onModelReset`：model 实例常驻，`modelReset` 由 GridView 自动响应；scan 后 controller 重建各文件夹 model 与 allModel 内容，GridView 自动刷新。全部模式无需监听 scanFinished。
- 选中行由 `view.currentIndex: controller.activeIndex` 承担（点击 delegate → `activeIndex = index`），不再手动 `positionViewAtIndex`。

### WallpaperDelegate.qml

```qml
text: model.name          // 原：model.name ?? modelData.name
source: model.preview     // 原：model.preview ?? modelData.preview
opacity: model.pendingDeletion ? 0.5 : 1   // 不变（单路径本就如此）
```

移除双路径兼容（`view.model` 恒为真 QAbstractListModel，role 直接可用）。onClicked（ThumbnailsPanel 内联）：

```qml
onClicked: {
    wallpaperController.activeIndex = index;
}
```

### ScanPathsPanel.qml

- `model: htmlWallpaper.scanPaths`（controller 命名保持，正常）。
- `folderName / parentPath` 调用改到 controller：`htmlWallpaper.folderName(modelData)` / `htmlWallpaper.parentPath(modelData)`（原经 `htmlWallpaper.wallpapers.folderName(...)`）。
- **修复 allTab alias 编译错误（当前 HEAD 遗留）**：`property alias allTab: allAction` 引用的 `allAction` 是 `header: Kirigami.InlineViewHeader { ... actions: [Kirigami.Action { id: allAction }] }` 内嵌 id，对根 `ColumnLayout`（scanPathsPanel）不可见，编译报 `Invalid alias reference`。修复方案：把 `allAction`（及 Add… action）提到 ListView 外部、根组件作用域内定义（`Kirigami.Action` 非 Item，不参与布局），header 的 `actions` 数组改为引用这两个 id；`property alias allTab: allAction` 保持暴露给集成测试驱动。激活态语义用 `checkable + checked: selectedFolder.length === 0`（Kirigami.Action 无 highlighted，上游 plasma-workspace 同款）。
- **标签点击驱动 activeModel**：文件夹项 `onClicked` → `selectedFolder = modelData; wallpaperController.activeModel = wallpaperController.modelFor(modelData)`；All 动作 → `selectedFolder = ""; activeModel = allModel()`。删除当前选中文件夹 → 回退"全部"。selectedFolder 仅用于列表高亮。

### config.qml

- `View.ScanPathsPanel { id: scanPathsView }`、`cfg_ScanPaths`、`onScanPathsChanged: scan()` 均**保持现有命名**（无需改名）。
- `property alias cfg_SelectWallpaper: wallpaperController.selectWallpaper`（选中壁纸属性透传给 KConfig）。

## 数据流

```text
config.qml onScanPathsChanged → controller.scan()
  → controller.scanWallpapers(scanPaths)：后台按 root 归组，保序返回 ScanResult.groups
  → finished：逐组 modelFor(key)->setEntries(group.entries)
              + m_allModel->clear() + 逐组 addEntries（重建"全部"汇总）
              → releaseStaleModels（删已移除文件夹的 model；若释放 activeModel 则置空+emit）
              → 恢复选中（setSelectedIndexOfFile）→ scanFinished
  → 各 WallpaperModel 独立 beginResetModel/endResetModel

中栏：点击左栏标签 → selectedFolder + controller.activeModel = modelFor(activeFolder) | allModel()
  → ThumbnailsPanel view.model: activeModel / view.currentIndex: activeIndex
  → KCM.GridView view.model 绑定 → delegate 单路径 model.xxx
```

## 测试计划

**当前测试基线（修正前 3 失败，均随本任务修复）：**

| 测试 | 当前状态 | 失败根因 |
| ---- | -------- | -------- |
| `tst_Parser` | FAILED | 测 `parser.scanUrls`，生产已改名 `scanPaths`（属性不存在 → undefined） |
| `tst_FolderTabs` | FAILED | `FolderTabsHost.qml` 引用 `View.ScanUrlsPanel`（已改名 ScanPathsPanel.qml）+ mock `scanUrls` 数组 + allAction alias 编译错误 |
| `tst_Smoke` | FAILED | `ScanPathsPanel.qml` allAction alias 编译失败 → `config.qml`/`ScanPathsPanel.qml` 编译用例失败 |

- **C++ `tst_wallpapermodel`**（重写为单文件夹语义）：`setEntries` 整组替换、`addEntries` 追加、`count/rowCount/data/get` 模板、`clear`、`selectedIndex` 越界/等值/`setSelectedIndexOfFile`、roles 对齐。
- **C++ `tst_wallpapercontroller`**：`modelFor` key 归一化去重建、多文件夹分发、`scan` 填充各文件夹与 allModel、空文件夹 `clear()` 防幽灵、`releaseStaleModels` 删已移除文件夹（含 activeModel 置空 emit）、`folderName/parentPath`、`activeModel` 往返。
- **QML `tst_FolderTabs` / `FolderTabsHost`**：mock 改 `scanPaths` 数组 + `modelFor` / `allModel` / `folderName` / `parentPath` 形态，`View.ScanUrlsPanel` → `View.ScanPathsPanel`，`scanUrlsView` → `scanPathsView`；断言 `view.model === modelFor(url)`（单组）与 `view.model === allModel()`（全部）。
- **QML `tst_ThumbnailsBinding` / `tst_ThumbnailsHighlight`**：mock 改 `modelFor` / `allModel` / `activeModel` / `activeIndex`；**去掉 modelData 双路径**，断言回 `model.xxx` 单路径与 `view.model === activeModel`。
- **已知遗留**：HEAD 上 `tst_FolderTabs` / `tst_ThumbnailsHighlight` 仍失败（mock 缺 `activeIndex` 属性 / activeModel 绑定循环），与 C++ 数据层无关，待 QML 测试层同步修复。
- **顺带修复（命名统一为 scanPaths）**：`tst_Parser.qml` 的 `scanUrls` → `scanPaths`；`wallpaperentry.h` 注释 `scanUrls` → `scanPaths`；`tst_Smoke` 全量回归（allAction alias 修复后 `config.qml`/`ScanPathsPanel.qml` 编译恢复）。

## 影响面

| 文件                                    | 改动                                                                                     |
| --------------------------------------- | ---------------------------------------------------------------------------------------- |
| `plugin/wallpapermodel.h/.cpp`          | 重构为单文件夹：删分组存储/扫描，加 key 属性 + setEntries/selectedIndex                  |
| `plugin/wallpapercontroller.h/.cpp`     | 扫描编排上移 + 多 model 容器 + modelFor/allModel/folderName/parentPath + activeModel/activeIndex |
| `plugin/allwallpapersmodel.h/.cpp`      | 不创建（merge 阶段删除，"全部"复用 WallpaperModel("ALL")）                              |
| `plugin/wallpaperitem.h`                | 不动                                                                                     |
| `plugin/wallpaperentry.h`               | 不动（ScanResult/ScanGroup 保留；仅注释 scanUrls → scanPaths）                          |
| `package/contents/ui/view/ThumbnailsPanel.qml` | view.model: activeModel / view.currentIndex: activeIndex，删 gridModel/refreshModel     |
| `package/contents/ui/view/WallpaperDelegate.qml` | 移除 modelData 双路径兼容，onClicked → activeIndex = index                              |
| `package/contents/ui/view/ScanPathsPanel.qml` | folderName/parentPath 调用改 controller + 修复 allTab alias 编译错误 + activeModel 驱动 |
| `package/contents/ui/config.qml`        | 保持 ScanPathsPanel 命名 + cfg_SelectWallpaper 别名                                     |
| `test/tst_wallpapermodel.cpp`           | 重写为单文件夹语义（setEntries/selectedIndex 等）                                        |
| `test/tst_wallpapercontroller.cpp`      | 新增 controller 用例（scan 填充/防幽灵/releaseStale/activeModel）                       |
| `test/tst_Parser.qml`                   | scanUrls → scanPaths（命名统一）                                                        |
| `test/tst_WallpaperListModel.qml`       | 重写多文件夹语义：wallpapers → modelFor/allModel，删 groupCount/keys/byKey 断言        |
| `test/tst_Smoke.qml`                    | 全量回归（allAction alias 修复后编译用例恢复）                                          |
| `test/tst_FolderTabs.qml` / `FolderTabsHost.qml` | 改 scanPaths 命名 + modelFor/allModel 形态 + View.ScanPathsPanel                    |
| `test/tst_ThumbnailsBinding.qml` / `tst_ThumbnailsHighlight.qml` | mock 改 modelFor/allModel + activeModel/activeIndex + 去双路径          |
