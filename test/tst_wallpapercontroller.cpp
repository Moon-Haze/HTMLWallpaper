/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QtTest>

#include "wallpapercontroller.h"
#include "wallpapermodel.h"

/**
 * WallpaperController 多 model 容器 / 扫描编排的 C++ 单测。
 *
 * modelFor / releaseStaleModels 用纯内存数据验证；scan 用
 * test/data/wallpapers fixtures（工作目录即 test/）。
 */
class tst_wallpapercontroller : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void modelForReusesSameKey();
    void modelForCreatesOnePerFolder();
    void scanPopulatesEachFolderModel();
    void scanClearsGhostEntriesWhenFolderEmptied();
    void releaseStaleModelsDropsRemovedFolders();
    void folderNameAndParentPath();
    void activeModelRoundTrip();
    void activeModelClearedOnStaleRelease();
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

void tst_wallpapercontroller::folderNameAndParentPath()
{
    WallpaperController c;
    QCOMPARE(c.folderName(QStringLiteral("file:///home/user/wallpapers/aurora")), QStringLiteral("aurora"));
    QCOMPARE(c.folderName(QStringLiteral("file:///home/user/wallpapers/aurora/")), QStringLiteral("aurora"));
    QCOMPARE(c.parentPath(QStringLiteral("file:///home/user/wallpapers/aurora")), QStringLiteral("file:///home/user/wallpapers"));
    QCOMPARE(c.parentPath(QStringLiteral("file:///home/user/wallpapers/aurora/")), QStringLiteral("file:///home/user/wallpapers"));
}

// activeModel 基本读写 + 信号发射（默认指向"全部"汇总 model；同值幂等不重复 emit）
void tst_wallpapercontroller::activeModelRoundTrip()
{
    WallpaperController c;
    QSignalSpy spy(&c, &WallpaperController::activeModelChanged);
    // 默认活动 model 即"全部"汇总 model（构造时创建，非 nullptr）
    QCOMPARE(c.activeModel(), c.allModel());

    WallpaperModel *a = c.modelFor(QStringLiteral("file:///root/a"));
    c.setActiveModel(a);
    QCOMPARE(c.activeModel(), a);
    QCOMPARE(spy.count(), 1);

    // 同值幂等：不重复 emit
    c.setActiveModel(a);
    QCOMPARE(spy.count(), 1);

    // 置空：activeModel 回退到 nullptr（并发一次 emit）
    c.setActiveModel(nullptr);
    QCOMPARE(c.activeModel(), nullptr);
    QCOMPARE(spy.count(), 2);
}

// releaseStaleModels 释放活动文件夹 model → activeModel 同步置空（防悬空）
void tst_wallpapercontroller::activeModelClearedOnStaleRelease()
{
    WallpaperController c;
    WallpaperModel *a = c.modelFor(QStringLiteral("file:///root/a"));
    c.modelFor(QStringLiteral("file:///root/b"));
    c.setActiveModel(a);
    QCOMPARE(c.activeModel(), a);

    // 释放路径应 emit activeModelChanged（且仅一次），驱动 QML view.model 重新求值
    QSignalSpy spy(&c, &WallpaperController::activeModelChanged);

    // scanPaths 只剩 b；scan 后 a 的 model 被释放，activeModel 应被清空
    c.setScanPaths({QStringLiteral("file:///root/b")});
    c.scan();
    QTRY_COMPARE_WITH_TIMEOUT(c.modelCount(), 1, 5000);
    QCOMPARE(c.activeModel(), nullptr);
    QCOMPARE(spy.count(), 1);
}

QTEST_MAIN(tst_wallpapercontroller)
#include "tst_wallpapercontroller.moc"
