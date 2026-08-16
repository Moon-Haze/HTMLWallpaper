# AllWallpapersModel 并入 WallpaperModel 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **设计转向注记（2026-08-16）**：本计划原设想的聚合模式（`setSources()` 单类双模式、`m_isAggregate` / `m_lastChangedSource` 跨源转发、聚合下 `get`/`indexOf` 跨源定位）在实现中**已放弃**（提交 `ec26817 refactor: 移除聚合模式语义`）。`WallpaperModel` 保持纯单文件夹语义；"全部"汇总由独立 `WallpaperModel("ALL")` 承担（构造即建、scan 时 `clear()` + 逐文件夹 `addEntries` 重建）。**Task 1–3 未执行**；实际改动集中在 Task 4（实现形态与原文不同，见下）。最终设计见 [merge spec](../specs/2026-08-16-merge-allwallpapers-into-wallpapersmodel-design.md)。

**Goal（最终采纳）：** 删除 `AllWallpapersModel`；"全部"视图退化为独立 `WallpaperModel("ALL")`，scan 用 `clear()` + `addEntries` 重建内容；controller 接口收紧为 `WallpaperModel *`（`allModel()` / `activeModel`），并新增 `activeIndex` 属性。

**Architecture（最终采纳）：** 不引入聚合模式。`WallpaperModel` 保持纯单文件夹语义（`setEntries` 整组替换 / `addEntries` 追加 / `clear` / `get` 模板 / `selectedIndex`）。controller 的 `m_allModel` 为构造即建的独立 `WallpaperModel(QStringLiteral("ALL"))`，保活复用；scan 时先 `clear()` 再逐文件夹 `addEntries` 重建汇总内容。`activeModel` 初始指向 allModel，`activeIndex` 派生自 activeModel 的 `selectedIndex`，QML `ThumbnailsPanel` 直接绑定。

**Tech Stack:** Qt6 / C++ / QAbstractListModel / CMake（Ninja preset `native`） / QTest。

## Global Constraints

- **QML 生产层联动改动**：`ThumbnailsPanel.qml` 绑 `activeModel` / `activeIndex`、`ScanPathsPanel.qml` 由标签点击驱动 `setActiveModel`（All → `allModel()`）、`config.qml` 加 `cfg_SelectWallpaper` 别名（见 Task 4）。
- 行为等价：单文件夹视图、全部视图、scan 重扫与选中恢复的既有语义必须保持。
- `selectedIndex` 为单 model 本地行（-1 = 无选中），越界忽略、等值不 emit；叶子和"全部"走同一套代码路径。
- **工作树前置**：执行前 `git status` 中 `plugin/wallpapermodel.h/.cpp`、`test/tst_wallpapermodel.cpp` 等存在用户未提交改动（selectedIndex 下沉系列）。执行本计划会改动这些文件，提交时务必只 `git add` 本计划相关改动；若无法分离，先与用户确认现有未提交改动的处理方式（单独提交或暂存），不得一并提交。
- 构建：`cmake --build build`；测试：`ctest --test-dir build -R <name> --output-on-failure`（全量：`ctest --test-dir build`）。

---

### Task 1: WallpaperModel 聚合数据访问层（未执行）

> **未执行（设计转向放弃聚合模式）**：本节描述的 `setSources()` / `m_isAggregate` / `onSourceReset`
> 聚合数据访问层最终未实现。实际 `count`/`rowCount`/`data` 仅走 `m_items`，"全部"汇总复用
> 同一实现（独立 allModel 实例），无跨源分支。下文保留原文供追溯，可跳过。

**Files:**
- Modify: `plugin/wallpapermodel.h`（聚合成员与 `setSources`/`isAggregate`/`onSourceReset` 声明）
- Modify: `plugin/wallpapermodel.cpp`（`count`/`rowCount`/`data` 聚合分支 + `setSources` + `onSourceReset`）
- Test: `test/tst_wallpapermodel.cpp`（改写 `mergeAggregatesAcrossSources`、`mergeResetsOnSourceReset` 为 `WallpaperModel` 聚合）

**Interfaces:**
- Consumes: 现有 `WallpaperModel` 叶子 API（`addEntries`/`get`/`selectedIndex`）。
- Produces: `void setSources(const QList<WallpaperModel *> &sources)`、`bool isAggregate() const`（私有）、聚合模式下的 `rowCount`/`data`/`count`。Task 2 依赖 `setSources` 已存在。

- [ ] **Step 1: 改写测试为 WallpaperModel 聚合模式（红）**

在 `test/tst_wallpapermodel.cpp` 中，将 `mergeAggregatesAcrossSources` 与 `mergeResetsOnSourceReset` 的实现改为：

```cpp
void tst_wallpapermodel::mergeAggregatesAcrossSources()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    QList<WallpaperEntry> ea, eb;
    ea.append(WallpaperEntry());
    ea.append(WallpaperEntry());
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    const QString dirB = QDir(tmp.path()).filePath(QStringLiteral("b"));
    QVERIFY(QDir().mkpath(dirB));
    QFile index(dirB + QStringLiteral("/index.html"));
    QVERIFY(index.open(QIODevice::WriteOnly));
    index.write("<!doctype html>");
    index.close();
    eb.append(WallpaperEntry(WallpaperPath::toUrl(dirB)));
    modelA.addEntries(ea);
    modelB.addEntries(eb);

    WallpaperModel merged(QString());
    merged.setSources({&modelA, &modelB});
    QCOMPARE(merged.rowCount(), 3);
    QCOMPARE(merged.count(), 3); // 聚合模式 count 与 rowCount 一致
    QCOMPARE(merged.data(merged.index(2, 0), WallpaperModel::NameRole).toString(), QStringLiteral("b"));

    WallpaperModel merged2(QString());
    merged2.setSources({&modelB});
    QCOMPARE(merged2.rowCount(), 1);
}

void tst_wallpapermodel::mergeResetsOnSourceReset()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel merged(QString());
    merged.setSources({&modelA});

    QSignalSpy resetSpy(&merged, &QAbstractItemModel::modelReset);
    modelA.addEntries({WallpaperEntry()}); // 源重置 → 聚合 model 也应 reset
    QCOMPARE(resetSpy.count(), 1);
}
```

- [ ] **Step 2: 运行构建，验证编译失败（红）**

Run: `cmake --build build`
Expected: FAIL——`WallpaperModel` 尚无 `setSources`，`tst_wallpapermodel` 编译报 `no member named 'setSources'`。

- [ ] **Step 3: 实现聚合数据访问层**

在 `plugin/wallpapermodel.h` 的 `public` 区（`clear()` 之后）加入：

```cpp
    /** 切换为聚合模式：合并多个单文件夹 model 为扁平视图（原 AllWallpapersModel）。 */
    void setSources(const QList<WallpaperModel *> &sources);
```

在 `private` 区加入：

```cpp
    bool isAggregate() const;            // setSources 启用后恒定 true
    void onSourceReset();                // 任一源 modelReset → 自身整体 reset
    QList<WallpaperModel *> m_sources;   // 聚合：源叶子列表
    bool m_isAggregate = false;          // setSources 调用后置 true
```

在 `plugin/wallpapermodel.cpp` 中：

将 `count()` 改为委托 `rowCount()`：

```cpp
int WallpaperModel::count() const
{
    return rowCount();
}
```

将 `rowCount` 改为支持聚合分支：

```cpp
int WallpaperModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    if (m_isAggregate) {
        int total = 0;
        for (const WallpaperModel *src : m_sources) {
            total += src->rowCount();
        }
        return total;
    }
    return m_items.size();
}
```

将 `data` 改为支持聚合分支：

```cpp
QVariant WallpaperModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0) {
        return {};
    }
    if (m_isAggregate) {
        if (index.row() >= rowCount()) {
            return {};
        }
        // remaining 递减跨源定位（原 AllWallpapersModel 逻辑）
        int remaining = index.row();
        for (const WallpaperModel *src : m_sources) {
            const int count = src->rowCount();
            if (remaining < count) {
                return src->data(src->index(remaining, 0), role);
            }
            remaining -= count;
        }
        return {};
    }
    if (index.row() >= m_items.size()) {
        return {};
    }
    auto item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item->name();
    case PathRole:
        return item->path();
    case PreviewRole:
        return item->preview();
    case FileRole:
        return item->file();
    default:
        return {};
    }
}
```

新增 `setSources` 与 `onSourceReset`（放在 `clear()` 实现之后）：

```cpp
void WallpaperModel::setSources(const QList<WallpaperModel *> &sources)
{
    for (WallpaperModel *src : m_sources) {
        disconnect(src, &WallpaperModel::modelReset, this, &WallpaperModel::onSourceReset);
    }
    m_sources = sources;
    m_isAggregate = true;
    for (WallpaperModel *src : m_sources) {
        connect(src, &WallpaperModel::modelReset, this, &WallpaperModel::onSourceReset);
    }
    beginResetModel();
    endResetModel();
}

void WallpaperModel::onSourceReset()
{
    beginResetModel();
    endResetModel();
}
```

- [ ] **Step 4: 运行构建与测试，验证通过（绿）**

Run: `cmake --build build && ctest --test-dir build -R tst_wallpapermodel --output-on-failure`
Expected: PASS——`mergeAggregatesAcrossSources`、`mergeResetsOnSourceReset` 及全部叶子测试通过。

- [ ] **Step 5: 提交**

```bash
git add plugin/wallpapermodel.h plugin/wallpapermodel.cpp test/tst_wallpapermodel.cpp
git commit -m "feat: WallpaperModel 增加聚合模式数据访问层(setSources/rowCount/data/count)"
```

---

### Task 2: 聚合模式选中转发（未执行）

> **未执行（设计转向放弃聚合模式）**：`m_lastChangedSource` / `offsetOf` / `onSourceSelectedIndexChanged`
> 跨源选中转发未实现。实际选中语义为单 model 本地行（`setSelectedIndex` 越界忽略、等值不 emit），
> controller 的 `activeIndex` 属性派生自 activeModel 的 `selectedIndex`。下文保留原文供追溯，可跳过。

**Files:**
- Modify: `plugin/wallpapermodel.h`（`m_lastChangedSource`、`onSourceSelectedIndexChanged`、`offsetOf` 声明）
- Modify: `plugin/wallpapermodel.cpp`（`setSources` 补选中连接与末尾同步；`selectedIndex`/`setSelectedIndex` 聚合分支；`onSourceSelectedIndexChanged`；`offsetOf`）
- Test: `test/tst_wallpapermodel.cpp`（改写 6 个 `mergeSelectedIndex*` 测试为 `WallpaperModel` 聚合）

**Interfaces:**
- Consumes: Task 1 的 `setSources`/`m_isAggregate`/`m_sources`。
- Produces: 聚合模式下的 `selectedIndex()`（全局行 getter）与 `setSelectedIndex(int)`（跨源定位 + 单选清空）、`onSourceSelectedIndexChanged()`、`offsetOf()`。Task 3/4 依赖这些。

- [ ] **Step 1: 改写测试为 WallpaperModel 聚合模式（红）**

将 `test/tst_wallpapermodel.cpp` 中 6 个 `mergeSelectedIndex*` 测试实现改为 `WallpaperModel` 聚合：把每个 `AllWallpapersModel merged;` 改为 `WallpaperModel merged(QString());`；`mergeSelectedIndexForwardsSourceSignal` 里的 `QSignalSpy spy(&merged, &AllWallpapersModel::selectedIndexChanged);` 改为 `QSignalSpy spy(&merged, &WallpaperModel::selectedIndexChanged);`。其余断言不变。完整改写后：

```cpp
// A(2 行) + B(1 行)：全局扁平索引写跨源转发到对应源 model 的局部行
void tst_wallpapermodel::mergeSelectedIndexForwardsToSource()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString());
    merged.setSources({&modelA, &modelB});

    merged.setSelectedIndex(0);
    QCOMPARE(modelA.selectedIndex(), 0);
    QCOMPARE(merged.selectedIndex(), 0);
    merged.setSelectedIndex(2);
    QCOMPARE(modelB.selectedIndex(), 0);
    QCOMPARE(merged.selectedIndex(), 2);
}

// 单选语义：设置新源选中时清空其它源选中
void tst_wallpapermodel::mergeSelectedIndexSingleSelectClearsOthers()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString());
    merged.setSources({&modelA, &modelB});

    modelA.setSelectedIndex(1);
    QCOMPARE(modelA.selectedIndex(), 1);
    merged.setSelectedIndex(2);
    QCOMPARE(modelA.selectedIndex(), -1);
    QCOMPARE(modelB.selectedIndex(), 0);
    QCOMPARE(merged.selectedIndex(), 2);
}

// getter 实时聚合：首个非 -1 源映射回全局行
void tst_wallpapermodel::mergeSelectedIndexGetterAggregates()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString());
    merged.setSources({&modelA, &modelB});

    modelA.setSelectedIndex(1);
    QCOMPARE(merged.selectedIndex(), 1);
    // 直接设 B（第二源，offset=2）局部 0 → 全局 2：getter 应反映最后
    // 变化的源（B），而非被首个非 -1 源（A）的残留选中遮蔽
    modelB.setSelectedIndex(0);
    QCOMPARE(merged.selectedIndex(), 2);
}

void tst_wallpapermodel::mergeSelectedIndexMinusOneClearsAll()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString());
    merged.setSources({&modelA, &modelB});

    merged.setSelectedIndex(1);
    QCOMPARE(merged.selectedIndex(), 1);
    merged.setSelectedIndex(-1);
    QCOMPARE(modelA.selectedIndex(), -1);
    QCOMPARE(modelB.selectedIndex(), -1);
    QCOMPARE(merged.selectedIndex(), -1);
}

// 重挂源后聚合值重算：保活源保留选中，删源丢失
void tst_wallpapermodel::mergeSetSourcesRemountRecomputes()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString());

    modelA.setSelectedIndex(0);
    merged.setSources({&modelA});
    QCOMPARE(merged.selectedIndex(), 0);

    merged.setSources({&modelB});
    QCOMPARE(merged.selectedIndex(), -1);
}

// 源 selectedIndexChanged 转发到聚合 model
void tst_wallpapermodel::mergeSelectedIndexForwardsSourceSignal()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    WallpaperModel merged(QString());
    merged.setSources({&modelA});

    QSignalSpy spy(&merged, &WallpaperModel::selectedIndexChanged);
    modelA.setSelectedIndex(0);
    modelA.setSelectedIndex(1);
    modelA.setSelectedIndex(-1);
    QCOMPARE(spy.count(), 3);
}
```

- [ ] **Step 2: 运行构建，验证编译失败（红）**

Run: `cmake --build build`
Expected: FAIL——`WallpaperModel` 尚无 `m_lastChangedSource` 相关实现，聚合 `selectedIndex` 仍返回叶子 `m_selectedIndex`（`mergeSelectedIndexForwardsSourceSignal` 等断言不成立）。

- [ ] **Step 3: 实现聚合选中转发**

在 `plugin/wallpapermodel.h` 的 `private` 区补充成员与方法声明：

```cpp
    void onSourceSelectedIndexChanged(); // 源选中变化转发（记录最后变化源 + 缓存去重）
    int offsetOf(const WallpaperModel *src) const; // src 在 m_sources 前的行数偏移
    WallpaperModel *m_lastChangedSource = nullptr; // 最后变化的源（getter 优先返回）
```

将 `setSources` 改为补上选中连接与末尾聚合值同步：

```cpp
void WallpaperModel::setSources(const QList<WallpaperModel *> &sources)
{
    for (WallpaperModel *src : m_sources) {
        disconnect(src, &WallpaperModel::modelReset, this, &WallpaperModel::onSourceReset);
        disconnect(src, &WallpaperModel::selectedIndexChanged, this, &WallpaperModel::onSourceSelectedIndexChanged);
    }
    m_sources = sources;
    m_isAggregate = true;
    // 重挂后旧 lastChanged 源可能已释放或不再是源，先重置（getter 走兜底遍历）
    m_lastChangedSource = nullptr;
    for (WallpaperModel *src : m_sources) {
        connect(src, &WallpaperModel::modelReset, this, &WallpaperModel::onSourceReset);
        connect(src, &WallpaperModel::selectedIndexChanged, this, &WallpaperModel::onSourceSelectedIndexChanged);
    }
    beginResetModel();
    endResetModel();
    // 重挂后聚合值可能变化（保活源保留 / 删源丢失），与缓存同步
    const int idx = selectedIndex();
    if (idx != m_selectedIndex) {
        m_selectedIndex = idx;
        Q_EMIT selectedIndexChanged();
    }
}
```

将 `selectedIndex()` 改为支持聚合分支：

```cpp
int WallpaperModel::selectedIndex() const
{
    if (m_isAggregate) {
        // 优先"最后变化的源"：直接操作源 model 制造多源选中时，getter 反映
        // 最新一次写入，而非被首个非 -1 源的残留选中遮蔽
        if (m_lastChangedSource && m_sources.contains(m_lastChangedSource) && m_lastChangedSource->selectedIndex() >= 0) {
            return offsetOf(m_lastChangedSource) + m_lastChangedSource->selectedIndex();
        }
        // 兜底：单选不变量（合并 setter 写路径保证）下遍历首个非 -1 源即可
        int offset = 0;
        for (const WallpaperModel *src : m_sources) {
            const int local = src->selectedIndex();
            if (local >= 0) {
                return offset + local;
            }
            offset += src->rowCount();
        }
        return -1;
    }
    return m_selectedIndex;
}
```

将 `setSelectedIndex()` 改为支持聚合分支：

```cpp
void WallpaperModel::setSelectedIndex(int index)
{
    if (index < -1 || index >= rowCount()) {
        return; // 越界忽略，语义对齐（叶子与聚合）
    }
    if (m_isAggregate) {
        WallpaperModel *target = nullptr;
        int localRow = -1;
        if (index >= 0) {
            int remaining = index;
            for (WallpaperModel *src : m_sources) {
                const int count = src->rowCount();
                if (remaining < count) {
                    target = src;
                    localRow = remaining;
                    break;
                }
                remaining -= count;
            }
        }
        // 单选语义：清除非目标源选中；index == -1 时 target 为空 → 清空全部
        for (WallpaperModel *src : m_sources) {
            if (src != target && src->selectedIndex() >= 0) {
                src->setSelectedIndex(-1);
            }
        }
        if (target) {
            target->setSelectedIndex(localRow);
        }
        return; // 源 setter 触发的 selectedIndexChanged 经转发统一收敛
    }
    if (m_selectedIndex == index) {
        return;
    }
    m_selectedIndex = index;
    Q_EMIT selectedIndexChanged();
}
```

新增 `offsetOf` 与 `onSourceSelectedIndexChanged`（放在 `setSelectedIndex` 之后）：

```cpp
int WallpaperModel::offsetOf(const WallpaperModel *src) const
{
    int offset = 0;
    for (const WallpaperModel *s : m_sources) {
        if (s == src) {
            break;
        }
        offset += s->rowCount();
    }
    return offset;
}

void WallpaperModel::onSourceSelectedIndexChanged()
{
    // 记录最后变化的源，供 getter 优先返回（多源残留选中时反映最新写入）
    m_lastChangedSource = qobject_cast<WallpaperModel *>(sender());
    // 源选中变化转发，缓存去重（setter 跨源切换时可能瞬时 emit -1 再终值，可接受）
    const int idx = selectedIndex();
    if (idx != m_selectedIndex) {
        m_selectedIndex = idx;
        Q_EMIT selectedIndexChanged();
    }
}
```

- [ ] **Step 4: 运行构建与测试，验证通过（绿）**

Run: `cmake --build build && ctest --test-dir build -R tst_wallpapermodel --output-on-failure`
Expected: PASS——6 个 `mergeSelectedIndex*` 聚合测试与既有测试全部通过。

- [ ] **Step 5: 提交**

```bash
git add plugin/wallpapermodel.h plugin/wallpapermodel.cpp test/tst_wallpapermodel.cpp
git commit -m "feat: WallpaperModel 聚合模式选中转发(全局行换算+单选清空+lastChangedSource)"
```

---

### Task 3: 聚合模式 get/indexOf 与 addEntries/clear 防御（未执行）

> **未执行（设计转向放弃聚合模式）**：聚合 `get`/`indexOf` 跨源定位与 `addEntries`/`clear`
> 聚合防御未实现。`get` 仅本地越界判空（越界返回 `nullptr`）；`addEntries`/`clear` 无聚合分支
> （allModel 为独立实例，正常接收追加/清空）。下文保留原文供追溯，可跳过。

**Files:**
- Modify: `plugin/wallpapermodel.cpp`（`get`/`indexOf` 聚合分支；`addEntries`/`clear` 聚合防御）
- Test: `test/tst_wallpapermodel.cpp`（新增 `mergeGetCrossesSources`、`mergeIndexOfCrossesSources`、`mergeRejectsAddEntriesAndClear`）

**Interfaces:**
- Consumes: Task 1/2 的聚合模式基础与 `m_sources`。
- Produces: 聚合模式下 `get(int)`（跨源返回 `WallpaperItem *`）、`indexOf(source)`（跨源返回全局行）、`addEntries`/`clear` 聚合忽略。Task 4 不依赖这些（controller 只走 `setSources`），但保证类自洽。

- [ ] **Step 1: 新增测试（红）**

在 `test/tst_wallpapermodel.cpp` 类声明 `Q_SLOTS` 区追加：

```cpp
    void mergeGetCrossesSources();
    void mergeIndexOfCrossesSources();
    void mergeRejectsAddEntriesAndClear();
```

在文件末尾（`mergeSelectedIndexForwardsSourceSignal` 之后）追加实现：

```cpp
// 聚合模式 get 跨源定位：全局行 → 所属源的本地 WallpaperItem*
void tst_wallpapermodel::mergeGetCrossesSources()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    modelB.addEntries({WallpaperEntry()});
    WallpaperModel merged(QString());
    merged.setSources({&modelA, &modelB});

    QVERIFY(merged.get(0) == modelA.get(0));
    QVERIFY(merged.get(1) == modelA.get(1));
    QVERIFY(merged.get(2) == modelB.get(0));
    QCOMPARE(merged.get(-1), nullptr);
    QCOMPARE(merged.get(3), nullptr);
}

// 聚合模式 indexOf 跨源定位：source URL → 全局行
void tst_wallpapermodel::mergeIndexOfCrossesSources()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    WallpaperModel modelB(QStringLiteral("file:///root/b"));
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    const QString dirA = QDir(tmp.path()).filePath(QStringLiteral("a"));
    QVERIFY(QDir().mkpath(dirA));
    const QString dirB = QDir(tmp.path()).filePath(QStringLiteral("b"));
    QVERIFY(QDir().mkpath(dirB));
    QFile idxA(dirA + QStringLiteral("/index.html"));
    QVERIFY(idxA.open(QIODevice::WriteOnly));
    idxA.write("<!doctype html>");
    idxA.close();
    QFile idxB(dirB + QStringLiteral("/index.html"));
    QVERIFY(idxB.open(QIODevice::WriteOnly));
    idxB.write("<!doctype html>");
    idxB.close();

    modelA.addEntries({WallpaperEntry(WallpaperPath::toUrl(dirA))});
    modelB.addEntries({WallpaperEntry(WallpaperPath::toUrl(dirB))});
    WallpaperModel merged(QString());
    merged.setSources({&modelA, &modelB});

    QCOMPARE(merged.indexOf(WallpaperPath::toUrl(dirA)), 0);
    QCOMPARE(merged.indexOf(WallpaperPath::toUrl(dirB)), 1);
    QCOMPARE(merged.indexOf(QStringLiteral("file:///nonexistent.html")), -1);
}

// 聚合模式是只读视图：addEntries/clear 非法调用被忽略
void tst_wallpapermodel::mergeRejectsAddEntriesAndClear()
{
    WallpaperModel modelA(QStringLiteral("file:///root/a"));
    modelA.addEntries({WallpaperEntry(), WallpaperEntry()});
    WallpaperModel merged(QString());
    merged.setSources({&modelA});
    QCOMPARE(merged.rowCount(), 2);

    merged.addEntries({WallpaperEntry()});
    QCOMPARE(merged.rowCount(), 2);
    merged.clear();
    QCOMPARE(merged.rowCount(), 2);
    QCOMPARE(modelA.rowCount(), 2);
}
```

- [ ] **Step 2: 运行构建，验证测试失败（红）**

Run: `cmake --build build && ctest --test-dir build -R tst_wallpapermodel --output-on-failure`
Expected: FAIL——聚合模式下 `get`/`indexOf` 仍走 `m_items`（空 → 返回 `nullptr`/`-1`），`addEntries`/`clear` 未忽略。断言不成立。

- [ ] **Step 3: 实现聚合 get/indexOf 与防御**

将 `indexOf` 改为支持聚合分支：

```cpp
int WallpaperModel::indexOf(const QString &source) const
{
    if (m_isAggregate) {
        int offset = 0;
        for (const WallpaperModel *src : m_sources) {
            const int local = src->indexOf(source);
            if (local >= 0) {
                return offset + local;
            }
            offset += src->rowCount();
        }
        return -1;
    }
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i)->file() == source) {
            return i;
        }
    }
    return -1;
}
```

将 `get` 改为支持聚合分支：

```cpp
WallpaperItem *WallpaperModel::get(int i)
{
    if (m_isAggregate) {
        if (i < 0 || i >= rowCount()) {
            return nullptr;
        }
        int remaining = i;
        for (WallpaperModel *src : m_sources) {
            const int count = src->rowCount();
            if (remaining < count) {
                return src->get(remaining);
            }
            remaining -= count;
        }
        return nullptr;
    }
    if (i < 0 || i >= m_items.size()) {
        return nullptr;
    }
    return m_items.at(i);
}
```

在 `addEntries` 与 `clear` 的入口各加一行聚合防御：

```cpp
void WallpaperModel::addEntries(const QList<WallpaperEntry> &wallpapers)
{
    if (m_isAggregate) {
        return; // 聚合模式只读视图，非法调用忽略
    }
    // …现有实现不变…
}

void WallpaperModel::clear()
{
    if (m_isAggregate) {
        return; // 聚合模式只读视图，非法调用忽略
    }
    // …现有实现不变…
}
```

- [ ] **Step 4: 运行构建与测试，验证通过（绿）**

Run: `cmake --build build && ctest --test-dir build -R tst_wallpapermodel --output-on-failure`
Expected: PASS——3 个新测试与既有测试全部通过。

- [ ] **Step 5: 提交**

```bash
git add plugin/wallpapermodel.cpp test/tst_wallpapermodel.cpp
git commit -m "feat: WallpaperModel 聚合模式 get/indexOf 跨源定位，addEntries/clear 聚合忽略"
```

---

### Task 4: 删除 AllWallpapersModel，controller 收紧为独立 allModel 重建（实际执行）

**Files:**
- Delete: `plugin/allwallpapersmodel.h`、`plugin/allwallpapersmodel.cpp`
- Modify: `plugin/wallpapermodel.h/.cpp`（setEntries/addEntries/clear/get 模板/selectedIndex 维护，聚合无关）
- Modify: `plugin/wallpapercontroller.h`（`allModel`/`activeModel` 类型收紧、新增 `activeIndex`）
- Modify: `plugin/wallpapercontroller.cpp`（去 include、去 static_cast、scan 重建 allModel）
- Modify: `plugin/CMakeLists.txt`、`test/CMakeLists.txt`（移除 allwallpapersmodel.cpp）
- Modify: `package/contents/ui/config.qml`（cfg_SelectWallpaper 别名、onScanPathsChanged: scan）
- Modify: `package/contents/ui/view/ThumbnailsPanel.qml`（`view.model: activeModel`、`view.currentIndex: activeIndex`）
- Modify: `package/contents/ui/view/ScanPathsPanel.qml`（标签点击 → `setActiveModel`；All → `allModel()`）
- Test: `test/tst_wallpapermodel.cpp`、`test/tst_wallpapercontroller.cpp`（删 include、去 static_cast、增 activeModel/activeIndex 用例）

**Interfaces:**
- Consumes: 既有 `WallpaperModel` 单文件夹 API（`setEntries`/`addEntries`/`clear`/`get` 模板/`selectedIndex`/`setSelectedIndexOfFile`）。
- Produces: `WallpaperController::allModel()` 返回 `WallpaperModel *`（构造即建、保活复用）、`activeModel`/`activeIndex` Q_PROPERTY（`WallpaperModel *` / `int`）。QML 层绑定上述属性。

- [ ] **Step 1: 收紧 controller 头文件**

`plugin/wallpapercontroller.h` 中：

```cpp
    Q_PROPERTY(WallpaperModel *activeModel READ activeModel WRITE setActiveModel NOTIFY activeModelChanged) // 类型收紧
    Q_PROPERTY(int activeIndex READ activeIndex WRITE setActiveIndex NOTIFY activeIndexChanged) // 新增：activeModel.selectedIndex 派生
```

```cpp
    /** 当前活动壁纸集合（初始指向 allModel；由 ScanPathsPanel 点击驱动）。 */
    WallpaperModel *activeModel() const;
    void setActiveModel(WallpaperModel *model);
    int activeIndex() const;
    void setActiveIndex(int index);
```

```cpp
    /** 返回"全部"汇总 model（构造即建、保活复用；scan 时 clear + addEntries 重建）。 */
    Q_INVOKABLE WallpaperModel *allModel();
```

```cpp
    WallpaperModel *m_allModel = new WallpaperModel(QStringLiteral("ALL"), this); // 构造即建，保活复用
    WallpaperModel *m_activeModel = m_allModel; // 当前活动壁纸集合（防悬空见 releaseStaleModels）
```

同步更新 `m_activeModel` 相关的 `releaseStaleModels` 注释引用即可（类型即 `WallpaperModel *`）。

- [ ] **Step 2: 收紧 controller 实现**

`plugin/wallpapercontroller.cpp`：

删除 `#include "allwallpapersmodel.h"`。

`scan()` 的 lambda 中不再 `setSources` 重挂，改整表重建（先清空再逐文件夹追加，防重扫重复/幽灵条目）：

```cpp
            // 汇总 model（"全部"标签）构造即建；每次 scan 重建内容
            m_allModel->clear();
            QSet<QString> updatedKeys;
            for (const auto &group : result.groups) {
                updatedKeys.insert(normalizeKey(group.key));
                WallpaperModel *model = obtainModel(group.key);
                model->setEntries(group.entries);     // 叶子：整组覆盖
                m_allModel->addEntries(group.entries); // 全部：逐组追加累计
            }
            // 仍在 scanPaths 但本次无 group 的文件夹显式 clear（防幽灵，含 failures 分支）
            // ...（对 m_models 中未更新者 clear）
            // 恢复选中：先缓存 selectWallpaper()，再对非 activeModel 的 model
            // 与 allModel 调 setSelectedIndexOfFile
            // ...
            releaseStaleModels(m_scanPaths);
```

`allModel()` 不再懒建（成员已初始化 `new WallpaperModel(QStringLiteral("ALL"), this)`），直接返回 `m_allModel`。

`setActiveModel` / `setActiveIndex`：等值忽略、按序 emit；`activeIndex` 读写转发到 activeModel 的 `selectedIndex`。

`releaseStaleModels`：释放的正是 `m_activeModel` 时置空并 `Q_EMIT activeModelChanged()`（防 QML 悬空）。

- [ ] **Step 3: 删除类文件与构建条目**

删除文件：

```bash
git rm plugin/allwallpapersmodel.h plugin/allwallpapersmodel.cpp
```

`plugin/CMakeLists.txt` 的 `target_sources(plasma_wallpaper_htmlwallpaperplugin PRIVATE ...)` 中移除一行 `allwallpapersmodel.cpp`。

`test/CMakeLists.txt` 中 `tst_wallpapermodel` 与 `tst_wallpapercontroller` 两处 `target_sources` 各移除一行 `../plugin/allwallpapersmodel.cpp`。

- [ ] **Step 4: 更新测试文件**

`test/tst_wallpapermodel.cpp`：删除 `#include "allwallpapersmodel.h"`；`setEntries`/`addEntries`/`clear`/`selectedIndex` 用例按单文件夹语义维护（无聚合用例）。

`test/tst_wallpapercontroller.cpp`：删除 `#include "allwallpapersmodel.h"`；不再有 `static_cast<AllWallpapersModel *>` 引用。用例为实际落地的形态：

```cpp
    // activeModel 基本读写 + 信号发射（默认指向"全部"汇总 model；同值幂等不重复 emit）
    void tst_wallpapercontroller::activeModelRoundTrip()
    // releaseStaleModels 释放活动文件夹 model → activeModel 同步置空并 emit（防悬空）
    void tst_wallpapercontroller::activeModelClearedOnStaleRelease()
```

- [ ] **Step 5: 全量构建与测试（绿）**

Run: `cmake --build build && ctest --test-dir build --output-on-failure`
Expected: PASS——全部 C++ 单测（`tst_wallpaperproject`/`tst_wallpapermodel`/`tst_wallpapercontroller`）通过；无 `AllWallpapersModel` 残留引用（可 `grep -rn AllWallpapersModel plugin test` 复核为空，仅剩计划/设计文档提及）。QML 测试已知遗留：`tst_FolderTabs`/`tst_ThumbnailsHighlight` 在 HEAD 失败（activeModel/activeIndex 绑定层问题），与 C++ 数据层改动无关。

- [ ] **Step 6: 提交**

```bash
git add plugin/wallpapermodel.h plugin/wallpapermodel.cpp plugin/wallpapercontroller.h plugin/wallpapercontroller.cpp plugin/CMakeLists.txt test/CMakeLists.txt test/tst_wallpapermodel.cpp test/tst_wallpapercontroller.cpp package/contents/ui/config.qml package/contents/ui/view/ThumbnailsPanel.qml package/contents/ui/view/ScanPathsPanel.qml
git commit -m "refactor: 删除 AllWallpapersModel，controller 接口收紧为 WallpaperModel"
```

---

## 自审记录

- **Spec 覆盖**：删除 AllWallpapersModel、allModel/activeModel 收紧为 `WallpaperModel *`、activeIndex 新增、scan 重建 allModel、QML 绑定切换（ThumbnailsPanel/ScanPathsPanel/config），逐项对应 merge spec"文件改动"与"测试策略"。
- **转向记录**：Task 1–3 聚合模式未执行（提交 `ec26817` 放弃，原文保留供追溯）；Task 4 为本计划实际落地形态（独立 allModel 重建，非聚合重挂）。
- **占位符**：所有步骤含完整代码/命令，无 TBD/TODO。
- **类型一致性**：`allModel()`/`activeModel` 均返回 `WallpaperModel *`；`activeIndex` 派生自 activeModel 的 `selectedIndex`，QML 绑 `view.currentIndex`；`setEntries`/`addEntries`/`clear`/`selectedIndex` 语义与 merge spec"关键语义"表一致。
