/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QDir>
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
    void releaseStaleModelsDropsRemovedFolders();
    void releaseStaleModelsWithAllModelAttached();
    void folderNameAndParentPath();
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
    eb.append(WallpaperEntry());
    a->addEntries(ea);
    b->addEntries(eb);

    QAbstractItemModel *all = c.allModel();
    QVERIFY(all != nullptr);
    QCOMPARE(all->rowCount(), 3);
    // 跨源定位：行 2 落在源 b（返回空字符串而非越界空）
    QCOMPARE(all->data(all->index(2, 0), WallpaperModel::NameRole).toString(), QString());
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

QTEST_MAIN(tst_wallpapercontroller)
#include "tst_wallpapercontroller.moc"
