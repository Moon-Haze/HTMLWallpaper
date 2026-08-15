/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

#include "allwallpapersmodel.h"
#include "wallpapercontroller.h"
#include "wallpapermodel.h"

/**
 * WallpaperController 多 model 容器 / 扫描编排的 C++ 单测。
 *
 * modelFor / allModel / releaseStaleModels 用纯内存数据验证；
 * scan 用 test/data/wallpapers fixtures（工作目录即 test/）。
 */
class tst_wallpapercontroller : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void modelForReusesSameKey();
    void modelForCreatesOnePerFolder();
    void allModelAggregatesAcrossSources();
    void scanPopulatesEachFolderModel();
    void scanClearsGhostEntriesWhenFolderEmptied();
    void releaseStaleModelsDropsRemovedFolders();
    void releaseStaleModelsWithAllModelAttached();
    void folderNameAndParentPath();
    void allModelSelectedIndexForwards();
};

void tst_wallpapercontroller::modelForReusesSameKey()
{
    WallpaperController c;
    WallpaperModel *a = c.modelFor(QStringLiteral("file:///root/a"));
    QVERIFY(a != nullptr);
    // 同 key 复用同一实例
    QCOMPARE(c.modelFor(QStringLiteral("file:///root/a")), a);
    // 尾斜杠归一化：目录 URL 斜杠差异不影响匹配（Qt.resolvedUrl 可能带尾斜杠）
    QCOMPARE(c.modelFor(QStringLiteral("file:///root/a/")), a);
    QCOMPARE(c.modelCount(), 1);
}

void tst_wallpapercontroller::modelForCreatesOnePerFolder()
{
    WallpaperController c;
    QVERIFY(c.modelFor(QStringLiteral("file:///root/a")) != nullptr);
    QVERIFY(c.modelFor(QStringLiteral("file:///root/b")) != nullptr);
    QCOMPARE(c.modelCount(), 2);
}

void tst_wallpapercontroller::allModelAggregatesAcrossSources()
{
    WallpaperController c;
    WallpaperModel *a = c.modelFor(QStringLiteral("file:///root/a"));
    WallpaperModel *b = c.modelFor(QStringLiteral("file:///root/b"));
    QList<WallpaperEntry> ea, eb;
    ea.append(WallpaperEntry());
    ea.append(WallpaperEntry());
    // 给源 b 填真实目录探测出的有效条目（name = "b"），使跨源定位断言真正验证
    // AllWallpapersModel::data 的 remaining 递减逻辑（非空值可区分越界空）。
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    const QString dirB = QDir(tmp.path()).filePath(QStringLiteral("b"));
    QVERIFY(QDir().mkpath(dirB));
    QFile index(dirB + QStringLiteral("/index.html"));
    QVERIFY(index.open(QIODevice::WriteOnly));
    index.write("<!doctype html>");
    index.close();
    eb.append(WallpaperEntry(WallpaperPath::toUrl(dirB)));
    a->addEntries(ea);
    b->addEntries(eb);

    QAbstractItemModel *all = c.allModel();
    QVERIFY(all != nullptr);
    QCOMPARE(all->rowCount(), 3);
    // 跨源定位：行 2 落在源 b，返回其非空 name 而非越界空
    QCOMPARE(all->data(all->index(2, 0), WallpaperModel::NameRole).toString(), QStringLiteral("b"));
    // 缓存同一实例
    QCOMPARE(c.allModel(), all);
}

void tst_wallpapercontroller::scanPopulatesEachFolderModel()
{
    WallpaperController c;
    const QString fixture = QDir::current().absoluteFilePath(QStringLiteral("data/wallpapers"));
    c.setScanPaths({fixture});
    c.scan();

    // 扫描完成：modelFor 该 root 返回的 model 应被填充（fixtures 收录 6 个）
    WallpaperModel *m = c.modelFor(fixture);
    QTRY_COMPARE_WITH_TIMEOUT(m->count(), 6, 5000);
}

void tst_wallpapercontroller::scanClearsGhostEntriesWhenFolderEmptied()
{
    WallpaperController c;
    QTemporaryDir tmp;
    QVERIFY(tmp.isValid());
    const QString root = tmp.path();
    const QString wallADir = QDir(root).filePath(QStringLiteral("wallA"));
    QVERIFY(QDir().mkpath(wallADir));
    QFile index(wallADir + QStringLiteral("/index.html"));
    QVERIFY(index.open(QIODevice::WriteOnly));
    index.write("<!doctype html>");
    index.close();

    c.setScanPaths({root});
    c.scan();
    // 首次扫描：root 下 wallA 一个壁纸
    QTRY_COMPARE_WITH_TIMEOUT(c.modelFor(root)->count(), 1, 5000);

    // 删除 wallA 子目录后重扫：空文件夹应清空旧壁纸，不再残留幽灵条目
    QVERIFY(QDir(wallADir).removeRecursively());
    c.scan();
    QTRY_COMPARE_WITH_TIMEOUT(c.modelFor(root)->count(), 0, 5000);
}

void tst_wallpapercontroller::releaseStaleModelsDropsRemovedFolders()
{
    WallpaperController c;
    c.modelFor(QStringLiteral("file:///root/a"));
    c.modelFor(QStringLiteral("file:///root/b"));
    QCOMPARE(c.modelCount(), 2);

    // scanPaths 只剩 b；scan 完成后 a 的 model 应被释放
    c.setScanPaths({QStringLiteral("file:///root/b")});
    c.scan();
    QTRY_COMPARE_WITH_TIMEOUT(c.modelCount(), 1, 5000);
    // 保活：仍可 modelFor(b)
    QVERIFY(c.modelFor(QStringLiteral("file:///root/b")) != nullptr);
}

void tst_wallpapercontroller::releaseStaleModelsWithAllModelAttached()
{
    WallpaperController c;
    c.modelFor(QStringLiteral("file:///root/a"));
    c.modelFor(QStringLiteral("file:///root/b"));
    QCOMPARE(c.modelCount(), 2);

    // 先建合并 model（连接源），触发 use-after-free 修复路径：
    // setSources 重挂源必须先于 releaseStaleModels 删除 stale model，
    // 否则 disconnect 会解引用已释放源。
    QAbstractItemModel *all = c.allModel();
    QVERIFY(all != nullptr);

    // scanPaths 只剩 b；scan 完成后 a 的 model 应被释放且无崩溃
    c.setScanPaths({QStringLiteral("file:///root/b")});
    c.scan();
    QTRY_COMPARE_WITH_TIMEOUT(c.modelCount(), 1, 5000);

    // 合并 model 仍存活且缓存同一实例；保留源 b 仍可 modelFor
    QCOMPARE(c.allModel(), all);
    QVERIFY(c.modelFor(QStringLiteral("file:///root/b")) != nullptr);
}

void tst_wallpapercontroller::folderNameAndParentPath()
{
    WallpaperController c;
    QCOMPARE(c.folderName(QStringLiteral("file:///home/user/wallpapers/aurora")), QStringLiteral("aurora"));
    QCOMPARE(c.folderName(QStringLiteral("file:///home/user/wallpapers/aurora/")), QStringLiteral("aurora"));
    QCOMPARE(c.parentPath(QStringLiteral("file:///home/user/wallpapers/aurora")), QStringLiteral("file:///home/user/wallpapers"));
    QCOMPARE(c.parentPath(QStringLiteral("file:///home/user/wallpapers/aurora/")), QStringLiteral("file:///home/user/wallpapers"));
}

// controller 层集成：合并 model 的 selectedIndex 跨源转发 + 单选清他源
void tst_wallpapercontroller::allModelSelectedIndexForwards()
{
    WallpaperController c;
    WallpaperModel *a = c.modelFor(QStringLiteral("file:///root/a"));
    WallpaperModel *b = c.modelFor(QStringLiteral("file:///root/b"));
    a->addEntries({WallpaperEntry(), WallpaperEntry()});
    b->addEntries({WallpaperEntry()});

    auto *merged = static_cast<AllWallpapersModel *>(c.allModel());
    QCOMPARE(merged->selectedIndex(), -1);

    // 全局行 2 落在 B 局部 0；A 选中被清空
    merged->setSelectedIndex(2);
    QCOMPARE(merged->selectedIndex(), 2);
    QCOMPARE(b->selectedIndex(), 0);
    QCOMPARE(a->selectedIndex(), -1);
}

QTEST_MAIN(tst_wallpapercontroller)
#include "tst_wallpapercontroller.moc"
