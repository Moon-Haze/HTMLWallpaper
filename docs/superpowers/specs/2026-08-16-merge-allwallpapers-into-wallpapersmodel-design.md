# AllWallpapersModel 并入 WallpaperModel 设计

**日期**：2026-08-16

## 背景与目标

当前壁纸数据层有两个模型类：

- `WallpaperModel`（叶子）：单文件夹条目容器，以 `key`（归一化 URL）标识一个扫描根，持有 `QList<WallpaperItem *>`，`selectedIndex` 为**本地行**。
- `AllWallpapersModel`（聚合）：合并多个叶子为扁平视图，`selectedIndex` 为**全局行**，内含跨源选中转发逻辑（`lastChangedSource`、`offsetOf`、单选清空）。

两个类职责差异集中在"聚合"上，但 UI 层（`ThumbnailsPanel` 直接绑 `controller.activeModel`、点击只写 `view.model.selectedIndex = index`）已把两者当同一个东西使用。用户决策：**保留"每文件夹一个叶子 model + 一个聚合 model"的结构，但将两类合并为单一 `WallpaperModel`，聚合能力以 `setSources()` 启用（单类双模式）**。

目标：
1. 类数量减少为一个（`AllWallpapersModel` 删除，文件从构建移除）。
2. 选中转发逻辑（含"最后变化源"语义）原样搬入 `WallpaperModel`，行为零回归。
3. QML 生产层零改动。

非目标：不采用"彻底扁平化"（一个 model + 过滤键切视图）路线，不重构选中逻辑本身。

## 架构

### 类设计

`AllWallpapersModel` 整体删除，聚合能力并入 `WallpaperModel`，成为其**聚合模式**（`m_isAggregate` 由 `setSources()` 首次调用置 `true`，之后恒定）。

```cpp
class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(QString key READ key CONSTANT)
    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged)

public:
    enum Roles { NameRole, PathRole, PreviewRole, FileRole };   // 现状
    explicit WallpaperModel(const QString &key, QObject *parent = nullptr);

    // 叶子模式（现状不变）
    QString key() const;
    int count() const;
    Q_INVOKABLE void addEntries(const QList<WallpaperEntry> &wallpapers);
    void clear();
    Q_INVOKABLE WallpaperItem *get(int i);
    Q_INVOKABLE int indexOf(const QString &source) const;

    // 聚合模式（原 AllWallpapersModel）
    void setSources(const QList<WallpaperModel *> &sources);

    // selectedIndex：叶子=本地行；聚合=全局行（QML 视角都是"当前视图行号"）
    int selectedIndex() const;
    void setSelectedIndex(int index);

Q_SIGNALS:
    void selectedIndexChanged();

private:
    bool isAggregate() const;           // setSources 启用后恒定 true（含空源）
    void onSourceReset();
    void onSourceSelectedIndexChanged();
    int offsetOf(const WallpaperModel *src) const;

    QString m_key;
    QList<WallpaperItem *> m_items;             // 叶子：本文件夹条目
    QList<WallpaperModel *> m_sources;          // 聚合：源叶子列表
    WallpaperModel *m_lastChangedSource = nullptr;
    int m_selectedIndex = -1;
    bool m_isAggregate = false;                 // setSources 调用后置 true
};
```

### 关键语义

| 行为 | 叶子模式（`m_isAggregate == false`） | 聚合模式（`m_isAggregate == true`） |
|---|---|---|
| `rowCount` / `data` | 走 `m_items`（现状） | 跨源求和 / remaining 递减透传（原 AllWallpapersModel） |
| `count()` | `m_items.size()`（现状） | 跨源行数和（与 `rowCount` 一致） |
| `selectedIndex` getter | 直接返回 `m_selectedIndex` | `lastChangedSource` 优先 + 兜底遍历（原逻辑原样搬） |
| `setSelectedIndex` | 本地越界忽略 | 跨源定位 + 单选清空其它源，自身不 emit |
| `get` / `indexOf` | 现状 | 跨源定位后转调源（聚合视图全局行语义） |
| `addEntries` / `clear` | 正常 | 忽略（非法调用，防御） |
| `key()` | 文件夹 URL | 空字符串（仅叶子有意义） |
| `roleNames` | 现状 | 同一套 `Roles`，透传源数据 |

### 数据流（不变式保持）

1. scan → controller 对每个 group `obtainModel(key)->addEntries(entries)`（叶子，不变）。
2. scan 完成 → `m_allModel->setSources(keptModels)` 重挂最新源（逻辑不变，类型收紧为 `WallpaperModel *`）。
3. QML 点击 → `view.model.selectedIndex = index`：叶子直接写；聚合跨源定位写入目标叶子并清空其它源。
4. 删除当前选中文件夹 → 回退"全部"（QML 层逻辑不变）。

### Controller 接口收敛

- `m_allModel` 与 `allModel()` 返回 `WallpaperModel *`（去 `QAbstractItemModel *` 泛型）。
- `activeModel` 属性收紧为 `WallpaperModel *`。
- `wallpapercontroller.cpp` 删除 `static_cast<AllWallpapersModel *>` 与对应 include。

## 错误处理

| 场景 | 处理 |
|---|---|
| 聚合模式下调用 `addEntries`/`clear` | 入口 `if (m_isAggregate) return;` 直接忽略（防御性，正常流程不会发生） |
| `setSelectedIndex` 越界（`< -1 || >= rowCount`） | 忽略，保持现有不变量（叶子与聚合都适用） |
| `setSources` 重挂 | 先 `disconnect` 旧源再 `connect` 新源（沿用现状顺序，controller 保证旧源此刻存活） |
| `get`/`indexOf` 聚合模式越界 | 跨源定位后转调叶子方法的既有越界保护（`nullptr` / `-1`） |

## 测试策略

- [tst_wallpapermodel.cpp](../../test/tst_wallpapermodel.cpp)：叶子测试不动；原 `AllWallpapersModel merged` 系列测试改为 `WallpaperModel` 聚合模式（`setSources` 后断言），并新增"聚合模式下 `addEntries`/`clear` 被忽略"用例。
- [tst_wallpapercontroller.cpp](../../test/tst_wallpapercontroller.cpp)：删除 `static_cast<AllWallpapersModel *>`，`allModel()` 直接返回 `WallpaperModel *`。
- QML 测试（`tst_FolderTabs.qml` 等）用 mock 数组，不受影响。
- 构建：`test/CMakeLists.txt` 移除两处 `allwallpapersmodel.cpp` 编译项。

## 文件改动

| 操作 | 文件 |
|---|---|
| 删除 | `plugin/allwallpapersmodel.h`、`plugin/allwallpapersmodel.cpp` |
| 修改 | `plugin/wallpapermodel.h/.cpp`（聚合成员 + `setSources` + 私有方法） |
| 修改 | `plugin/wallpapercontroller.h/.cpp`（`allModel`/`activeModel` 收紧为 `WallpaperModel *`、去 static_cast、去 include） |
| 修改 | `plugin/CMakeLists.txt`、`test/CMakeLists.txt`（移除 allwallpapersmodel.cpp） |
| 修改 | `test/tst_wallpapermodel.cpp`、`test/tst_wallpapercontroller.cpp` |
| 不动 | `package/contents/ui/**`（QML 层零改动） |

## 验证标准

- 全部单元测试（`ctest`）通过，含重写的聚合测试。
- 运行时行为等价：单文件夹视图、全部视图、跨源选中、scan 重挂无回归。
