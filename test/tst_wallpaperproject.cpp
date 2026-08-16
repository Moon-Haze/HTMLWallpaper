/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QtTest>

#include "wallpaperentry.h"

#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QUrl>

class tst_WallpaperEntry : public QObject
{
    Q_OBJECT
private:
    static QString fixtureUrl(const QString &name);
    static QString tmpUrl(QTemporaryDir &dir, const QStringList &files);
private Q_SLOTS:
    void entryDetectsIndexHtml();
    void entryPrefersIndexOverOthers();
    void entryFallsBackToFirstHtml();
    void entryInvalidWithoutHtml();
    void entryProbesPreview();
    void titleEqualsName();
    void toUrlAndPathJoin();
};

QString tst_WallpaperEntry::fixtureUrl(const QString &name)
{
    return QUrl::fromLocalFile(QFileInfo(QStringLiteral("data/wallpapers/") + name).absoluteFilePath()).toString();
}

QString tst_WallpaperEntry::tmpUrl(QTemporaryDir &dir, const QStringList &files)
{
    for (const QString &f : files) {
        QFile file(dir.filePath(f));
        file.open(QIODevice::WriteOnly);
        file.close();
    }
    return QUrl::fromLocalFile(dir.path()).toString();
}

void tst_WallpaperEntry::entryDetectsIndexHtml()
{
    WallpaperEntry p(fixtureUrl(QStringLiteral("aurora")));
    QVERIFY(p.isValid());
    QCOMPARE(p.name(), QStringLiteral("aurora"));
    QVERIFY(p.file().endsWith(QStringLiteral("/data/wallpapers/aurora/index.html")));
}

void tst_WallpaperEntry::entryPrefersIndexOverOthers()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    WallpaperEntry p(tmpUrl(dir, {QStringLiteral("zzz.html"), QStringLiteral("index.html")}));
    QVERIFY(p.isValid());
    QVERIFY(p.file().endsWith(QStringLiteral("/index.html")));
}

void tst_WallpaperEntry::entryFallsBackToFirstHtml()
{
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    WallpaperEntry p(tmpUrl(dir, {QStringLiteral("zzz.html"), QStringLiteral("aaa.html")}));
    QVERIFY(p.isValid());
    QVERIFY(p.file().endsWith(QStringLiteral("/aaa.html"))); // 字典序第一个
}

void tst_WallpaperEntry::entryInvalidWithoutHtml()
{
    WallpaperEntry fetch(fixtureUrl(QStringLiteral("fetch"))); // 目录无 html
    QVERIFY(!fetch.isValid());

    WallpaperEntry missing(fixtureUrl(QStringLiteral("does-not-exist")));
    QVERIFY(!missing.isValid());
}

void tst_WallpaperEntry::entryProbesPreview()
{
    WallpaperEntry nova(fixtureUrl(QStringLiteral("nova")));
    QVERIFY(nova.isValid());
    QVERIFY(nova.preview().endsWith(QStringLiteral("/data/wallpapers/nova/preview.jpg")));

    WallpaperEntry aurora(fixtureUrl(QStringLiteral("aurora"))); // 无 preview 文件
    QVERIFY(aurora.isValid());
    QVERIFY(aurora.preview().isEmpty());
}

void tst_WallpaperEntry::titleEqualsName()
{
    WallpaperEntry matrix(fixtureUrl(QStringLiteral("matrix")));
    QVERIFY(matrix.isValid());
    QVERIFY(matrix.file().endsWith(QStringLiteral("/data/wallpapers/matrix/main.html")));
}

void tst_WallpaperEntry::toUrlAndPathJoin()
{
    QCOMPARE(WallpaperPath::toUrl(QStringLiteral("/a/b")), QStringLiteral("file:///a/b"));
    QCOMPARE(WallpaperPath::toUrl(QStringLiteral("https://x/")), QStringLiteral("https://x/"));
    QCOMPARE(WallpaperPath::pathJoin(QStringLiteral("file:///a/"), QStringLiteral("/b")), QStringLiteral("file:///a/b"));
    QCOMPARE(WallpaperPath::pathJoin(QStringLiteral("file:///a"), QStringLiteral("b")), QStringLiteral("file:///a/b"));
}

QTEST_MAIN(tst_WallpaperEntry)
#include "tst_wallpaperproject.moc"
