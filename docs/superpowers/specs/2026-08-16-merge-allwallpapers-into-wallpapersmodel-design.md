# AllWallpapersModel 并入 WallpaperModel 设计

**日期**：2026-08-16（修订：聚合模式方案已放弃，改为独立 allModel 重建）

## 设计转向注记

本文件初版（2026-08-16）设想"聚合能力并入 `WallpaperModel`，以 `setSources()` 启用聚合模式（单类双模式）"。实现完成并经评审后（提交 `ec26817 refactor: 移除聚合模式语义`）**决定放弃聚合模式**：`WallpaperModel` 保持纯单文件夹语义，`allModel()` 返回独立 `WallpaperModel("ALL")`，scan 时 `clear()` + `addEntries` 重建汇总内容。下文为**最终采纳的设计**。

## 背景与目标

当前壁纸数据层有两个模型类：

- `WallpaperModel`（叶子）：单文件夹条目容器，以 `key`（归一化 URL）标识一个扫描根，持有 `QList<WallpaperItem *>`，`selectedIndex` 为**本地行**。
- `AllWallpapersModel`（聚合）：合并多个叶子为扁平视图，`selectedIndex` 为**全局行**，内含跨源选中转发逻辑（`lastChangedSource`、`offsetOf`、单选清空）。

两个类职责差异集中在"聚合"上，但 UI 层（`ThumbnailsPanel` 直接绑 `controller.activeModel`、点击只写 `view.model.selectedIndex = index`）已把两者当同一个东西使用。

**最终决策**：删除 `AllWallpapersModel`；"全部"视图退化为独立 `WallpaperModel("ALL")`，由 scan 用 `clear()` + `addEntries` 重建内容（不引入聚合模式、不做 `setSources` 重挂）。

目标：

1. 类数量减少为一个（`AllWallpapersModel` 删除，文件从构建移除）。
2. controller 接口收紧：`allModel()` / `activeModel` 返回 `WallpaperModel *`。
3. "全部"汇总 model 保活复用（构造即建、scan 重建内容），QML 引用无悬空。
4. 选中行统一为**单 model 本地行**语义（叶子与"全部"走同一套代码路径）。

非目标：不采用聚合模式（`setSources`）、不重构选中逻辑本身。

## 架构

### 类设计

`AllWallpapersModel` 整体删除。`WallpaperModel` 保持**纯单文件夹语义**，"全部"汇总由一个以 `key = "ALL"` 构造的独立 `WallpaperModel` 承担（下称 `allModel`）。

```cpp
class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(QString key READ key CONSTANT)
    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged)

public:
    enum Roles { NameRole = Qt::UserRole + 1, PathRole, PreviewRole, FileRole };   // 现状
    explicit WallpaperModel(const QString &key, QObject *parent = nullptr);

    QString key() const;
    int count() const;
    Q_INVOKABLE void setEntries(const QList<WallpaperEntry> &wallpapers); // 整组替换（重扫覆盖），reset 一次
    Q_INVOKABLE void addEntries(const QList<WallpaperEntry> &wallpapers); // 追加到末尾，insertRows 增量通知
    void clear();                                                          // 清空全部条目，reset 一次
    Q_INVOKABLE WallpaperItem *get(int i);
    template<Roles R> QString get(int i) const;
    template<Roles R> QString get() const;                                 // 当前选中行在角色 R 下的字段
    int selectedIndex() const;
    void setSelectedIndex(int index);
    void setSelectedIndexOfFile(const QString &file);                      // 按 file 定位选中行（未命中忽略）

Q_SIGNALS:
    void selectedIndexChanged();
};
```

- `key`：构造后固定。叶子 = 归一化 URL；`allModel` = `"ALL"`。
- `setEntries`：整组替换本文件夹条目（同文件夹重扫即覆盖）。
- `addEntries`：追加到列表末尾（保留已有条目）。
- `clear`：清空全部条目（目录删空后防幽灵条目）。
- `selectedIndex`：本地行（-1 = 无选中），越界忽略、等值不 emit。

### 关键语义

| 行为 | 叶子 model | allModel（"全部"） |
| --- | --- | --- |
| 内容来源 | `m_items`（本文件夹条目） | scan 时 `clear()` + 各文件夹 `addEntries` 汇总 |
| `key()` | 文件夹 URL | `"ALL"` |
| `rowCount` / `data` | `m_items`（现状） | 同一套实现（复用 WallpaperModel 逻辑） |
| `selectedIndex` | 本地行 | 本地行（汇总视图的行号，同套语义） |
| `addEntries` | 追加 | 追加（scan 逐组调用，构建汇总内容） |
| `clear` | 清空本文件夹 | scan 开始时清空，避免重扫重复/幽灵条目 |
| `setSelectedIndexOfFile` | 按 file 定位行 | 按 file 定位行（scan 后恢复选中） |

### 数据流（不变式保持）

1. scan → controller 对每个 group `obtainModel(key)->setEntries(entries)`（叶子，整组覆盖）。
2. 同时 `m_allModel->clear()` + 逐组 `m_allModel->addEntries(group.entries)`（重建汇总）。
3. 对仍在 scanPaths、但本次未产生 group 的文件夹 `clear()`（防幽灵条目，含 failures 分支）。
4. 恢复选中：对非当前 activeModel 的 model 与 allModel 调 `setSelectedIndexOfFile(selectWallpaper)`。
5. `releaseStaleModels` 清理已移除文件夹的 model；若释放的正是 activeModel，置空并 emit。
6. QML 点击 → `wallpaperController.activeIndex = index`（写入 activeModel 的选中行）。

### Controller 接口收敛

- `m_allModel` 与 `allModel()` 返回 `WallpaperModel *`（去 `QAbstractItemModel *` 泛型）。
- `m_allModel` 构造即建（成员初始化 `new WallpaperModel("ALL")`），**非懒建**——保活复用，避免 QML 引用悬空。
- `activeModel` 属性收紧为 `WallpaperModel *`（初始指向 allModel）。
- 新增 `activeIndex` 属性（activeModel 的 `selectedIndex` 派生），QML `view.currentIndex` 直接绑定。
- `wallpapercontroller.cpp` 删除 `static_cast<AllWallpapersModel *>` 与对应 include。

## 错误处理

| 场景 | 处理 |
| --- | --- |
| `setSelectedIndex` 越界（`< -1 \|\| >= rowCount`） | 忽略，保持现有不变量 |
| `setSelectedIndexOfFile` 未命中 | 不做任何事 |
| scan 时扫描根目录失效 | `scanFailed` 信号；该文件夹走 `clear()` 防幽灵 |
| `releaseStaleModels` 释放的是 activeModel | 置空 `m_activeModel` 并 emit `activeModelChanged`（防 QML 悬空） |
| `addScanPath` 重复添加 | 返回 false，不重复添加 |

## 测试策略

- [tst_wallpapermodel.cpp](../../test/tst_wallpapermodel.cpp)：纯单文件夹语义——`keyRoundTrip` / `addEntriesAppends` / `clearEmptiesAll` / `dataRolesAndGet` / `getRTemplateByRole` / `selectedIndex*`（无聚合用例）。
- [tst_wallpapercontroller.cpp](../../test/tst_wallpapercontroller.cpp)：`modelForReusesSameKey` / `modelForCreatesOnePerFolder` / `scanPopulatesEachFolderModel` / `scanClearsGhostEntriesWhenFolderEmptied` / `releaseStaleModelsDropsRemovedFolders` / `folderNameAndParentPath` / `activeModelRoundTrip` / `activeModelClearedOnStaleRelease`。
- 构建：`test/CMakeLists.txt` 移除两处 `allwallpapersmodel.cpp` 编译项。

## 文件改动

| 操作 | 文件 |
| --- | --- |
| 删除 | `plugin/allwallpapersmodel.h`、`plugin/allwallpapersmodel.cpp` |
| 修改 | `plugin/wallpapermodel.h/.cpp`（setEntries/addEntries/clear/get 模板/selectedIndex 维护） |
| 修改 | `plugin/wallpapercontroller.h/.cpp`（allModel/activeModel 收紧为 `WallpaperModel *`、activeIndex、去 static_cast、去 include） |
| 修改 | `plugin/CMakeLists.txt`、`test/CMakeLists.txt`（移除 allwallpapersmodel.cpp） |
| 修改 | `test/tst_wallpapermodel.cpp`、`test/tst_wallpapercontroller.cpp` |
| 修改 | `package/contents/ui/config.qml`（cfg_SelectWallpaper/cfg_ScanPaths 别名、onScanPathsChanged: scan） |
| 修改 | `package/contents/ui/view/ThumbnailsPanel.qml`（`view.model: activeModel`、`view.currentIndex: activeIndex`） |

## 验证标准

- C++ 单元测试（`ctest` 中 `tst_wallpapermodel` / `tst_wallpapercontroller`）通过。
- 运行时行为等价：单文件夹视图、全部视图、scan 重扫无回归。
- 已知遗留：QML 测试（`tst_FolderTabs` / `tst_ThumbnailsHighlight`）在 HEAD 失败，根因在 activeModel/activeIndex 绑定层（activeIndex mock 缺失 / activeModel 绑定循环），与 C++ 数据层改动无关。
