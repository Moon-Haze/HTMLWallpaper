# HTMLWallpaper:WallpaperModel 按扫描路径分组存储设计

日期:2026-08-15
状态:待评审

## 背景与目标

当前 `WallpaperModel` 的条目存储是扁平的单层 `QList<WallpaperItem>`(值类型),扫描时整体替换。
用户已把头文件声明改为 `QHash<QString, QList<WallpaperItem *>> m_items` 并把 `setEntries(projects)`
改名 `addEntries(key, wallpapers)`,但实现、消费方、测试均未跟上(当前编译不过)。

目标:

1. **按扫描路径分类存储** —— `WallpaperItem*` 按每个扫描根 URL(root)分组,同 key 覆盖
2. **增量语义铺路** —— `addEntries` 可按 key 替换单组,为将来局部重扫某 root 打基础
3. **对外扁平 API 不变** —— `count/get(i)/data/roles` 保持兼容,UI 暂不做分组展示
4. **生命周期明确** —— 指针化后逐组显式释放,不依赖 QObject parent 自动回收
5. **索引/查找优化** —— `byKey` 改为按扫描路径取整组,新增 `keys()/groupCount()`

## 决策记录

| 决策点 | 结论 |
|---|---|
| 扫描工作流 | 一次性全量扫(scan(roots) 一次后台扫完),结果按 root 分组返回,完成后逐 key addEntries |
| UI 分组展示 | 本次不做,存储层分组 + 预留接口,UI 仍为单一扁平网格 |
| `byKey` 语义 | 由"按条目 source 返回单 item"改为"按扫描路径返回整组 QList<WallpaperItem*>" |
| `indexOf(source)` | 保留原语义(按 html 文件找扁平行号) |
| 新增接口 | `keys()`(保序)、`groupCount()` |
| 扁平顺序 | `QHash` + `m_groupOrder` 保序,`m_flat` 扁平视图缓存(扁平 API O(1)) |
| `m_indexByKey` | 删除(byKey 改语义后冗余,indexOf 改遍历) |
| 生命周期 | `WallpaperItem*` 由 Model 显式所有,addEntries 覆盖 / clear 时 `qDeleteAll`;parent 仍为 model(指针存活期保证) |
| `ScanResult` 结构 | `projects` 扁平列表改为 `QList<ScanGroup>`(key + entries),保序 |
| `WallpaperItem` 拷贝语义 | 删除拷贝构造 / `operator=`(指针化后不再需要) |

## 存储结构(wallpapermodel.h)

```cpp
QHash<QString, QList<WallpaperItem *>> m_items;  // 分类存储:key = 扫描根 URL
QStringList m_groupOrder;                        // key 插入顺序(roots 遍历序),驱动 keys() 与扁平化
QList<WallpaperItem *> m_flat;                   // 扁平视图缓存:rowCount/data/get/indexOf 直接索引
// 删除 m_indexByKey
```

- **保序理由**:`QAbstractListModel` 的扁平 API 需要稳定行号;QHash 无序,故用 `m_groupOrder` 记 key 顺序。
  扁平顺序 = `m_groupOrder` 顺序 × 各组内部顺序。单 root 时即现有子目录字母序,
  `tst_WallpaperListModel` 的 `get(0).name === "aurora"` 继续成立。
- **m_flat 理由**:扁平 API 全部 O(1),且 addEntries/clear 都是整体重建,一致性维护成本为零。
  三成员在 addEntries / clear 时同步更新。

## addEntries 语义与生命周期

```cpp
/** 替换 key 对应扫描路径的整组条目;同 key 覆盖。 */
void addEntries(const QString &key, const QList<WallpaperEntry> &wallpapers);
```

行为:

1. 若 `m_items` 中已存在 `key`:`qDeleteAll` 旧组所有 `WallpaperItem*`,删除旧组
2. `new WallpaperItem(entry, this)` 逐个构造,填入 `m_items[key]`;`m_groupOrder` 追加新 key
3. 重建 `m_flat`(按 `m_groupOrder` 顺序拼接各组)
4. `beginResetModel()/endResetModel()` 刷新

- `WallpaperItem` 的 QObject parent = model:`byKey` 返回的指针在 model 存活期内有效;
  显式 delete 由 addEntries 覆盖 / clear 负责,不依赖 parent 自动回收。
- scan 流程:`clear()`(reset 一次)→ 逐组 `addEntries`(各 reset 一次)。模型小,多次 reset 可接受;
  将来局部重扫某 root 时直接 `addEntries(该key)` 单组替换。

## ScanResult 分组(wallpaperentry.h)

```cpp
struct ScanGroup {
    QString key;                        // 扫描根 URL
    QList<WallpaperEntry> entries;      // 该根下的壁纸目录
};
struct ScanResult {
    QList<ScanGroup> groups;            // 按 roots 遍历顺序保序
    QList<QPair<QString, QString>> failures;
};
```

`scanWallpapers` 遍历 roots 时按 root 归组(现为扁平 `projects`,丢失 root 归属)。

## 扁平 API(对外不变)

- `count()/rowCount()` = `m_flat.size()`
- `data(row)` 从 `m_flat[row]` 取 roles(name/title/path/preview/file 不变)
- `get(i)` 返回 `m_flat[i]`,越界 null
- `indexOf(source)` 遍历 `m_flat` 按 `source()` 找行号

## 分组接口(预留,Q_INVOKABLE)

```cpp
Q_INVOKABLE QStringList keys() const;                          // 保序的分组 key
Q_INVOKABLE int groupCount() const;                            // 分组数
Q_INVOKABLE QList<WallpaperItem *> byKey(const QString &key);  // 整组;不存在返回空
Q_INVOKABLE int indexOf(const QString &source) const;          // 保留原语义
```

`byKey` 返回 `QList<WallpaperItem*>` 在 QML 中即对象数组,将来可直接作嵌套模型 model。

## WallpaperItem 清理

删除拷贝构造 / `operator=`(指针化后值拷贝语义不再需要);QObject 与 Q_PROPERTY 保持不动。

## 数据流

```
config.qml onScanUrlsChanged → controller.scan()
  → model.scan(scanUrls)
    → 后台 scanWallpapers(roots):按 root 归组,保序返回 ScanResult.groups
    → 完成回调:clear() → 逐组 addEntries(group.key, group.entries) → scanFinished
```

`scan()` 签名不变;controller / config.qml / ThumbnailsPanel 均不需改动。

## 测试计划

- **回归**:现有单 root 用例继续通过(`count=6`、`get(0).name==="aurora"`、越界 null、file 探测)
- **新增(多 root 分组)**:`keys()` 保序、`groupCount`、`count` 汇总、`byKey(root)` 成员正确、`indexOf` 仍命中
- **新增(addEntries 同 key 覆盖)**:组内容替换、条目总数不变
- **顺带修复**:`tst_Smoke.qml` 对已删除 `ScanPathsPanel.qml` 的残留引用

## 影响面

| 文件 | 改动 |
|---|---|
| `plugin/wallpapermodel.h` | 保留 m_items 声明,新增 m_groupOrder/m_flat,删 m_indexByKey,改 byKey 签名,加 keys/groupCount |
| `plugin/wallpapermodel.cpp` | 重写 addEntries/clear/count/data/get/indexOf/scan,删 setEntries |
| `plugin/wallpaperentry.h` | ScanResult → QList<ScanGroup> |
| `plugin/wallpaperitem.h` | 删拷贝构造 / operator= |
| `test/tst_WallpaperListModel.qml` | 回归 + 新增分组/覆盖用例 |
| `test/tst_Smoke.qml` | 修 ScanPathsPanel 残留引用 |
