/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperentry.h"

#include <QDir>
#include <QFile>
#include <QUrl>

namespace
{
QString basename(const QString &url)
{
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s.mid(s.lastIndexOf(QLatin1Char('/')) + 1);
}

QString findPreview(const QString &dirUrl)
{
    static const QStringList candidates = {
        QStringLiteral("preview.png"),
        QStringLiteral("preview.jpg"),
        QStringLiteral("preview.jpeg"),
        QStringLiteral("preview.gif"),
        QStringLiteral("preview.webp"),
        QStringLiteral("default.png"),
        QStringLiteral("thumbnail.png"),
    };
    const QString dir = QUrl(dirUrl).toLocalFile();
    for (const QString &c : candidates) {
        if (QFile::exists(dir + QLatin1Char('/') + c)) {
            return WallpaperPath::pathJoin(dirUrl, c);
        }
    }
    return {};
}

// 入口选择：常用名优先，否则字典序第一个 *.html。
QString findEntry(const QString &dirUrl)
{
    const QString dir = QUrl(dirUrl).toLocalFile();
    static const QStringList common = {
        QStringLiteral("index.html"),
        QStringLiteral("index.htm"),
        QStringLiteral("main.html"),
        QStringLiteral("main.htm"),
        QStringLiteral("start.html"),
    };
    for (const QString &c : common) {
        if (QFile::exists(dir + QLatin1Char('/') + c)) {
            return WallpaperPath::pathJoin(dirUrl, c);
        }
    }
    const QStringList html = QDir(dir).entryList({QStringLiteral("*.html"), QStringLiteral("*.htm")}, QDir::Files, QDir::Name);
    if (!html.isEmpty()) {
        return WallpaperPath::pathJoin(dirUrl, html.first());
    }
    return {};
}
} // namespace

namespace WallpaperPath
{
QString toUrl(const QString &path)
{
    return path.contains(QLatin1String("://")) ? path : QStringLiteral("file://") + path;
}

QString pathJoin(const QString &a, const QString &b)
{
    QString sa = a;
    while (sa.endsWith(QLatin1Char('/'))) {
        sa.chop(1);
    }
    QString sb = b;
    while (sb.startsWith(QLatin1Char('/'))) {
        sb.remove(0, 1);
    }
    return sa + QLatin1Char('/') + sb;
}
} // namespace WallpaperPath

WallpaperEntry::WallpaperEntry(const QString &url)
{
    QDir dir(QUrl(url).toLocalFile());
    if (!dir.exists()) {
        return;
    }
    const QString entry = findEntry(url);
    if (entry.isEmpty()) {
        return; // 无 *.html → 不收录
    }
    m_name = basename(url);
    m_path = url;
    m_file = entry;
    m_preview = findPreview(url);
    m_valid = true;
}

bool WallpaperEntry::isValid() const
{
    return m_valid;
}
QString WallpaperEntry::name() const
{
    return m_name;
}
QString WallpaperEntry::title() const
{
    return m_name;
}
QString WallpaperEntry::path() const
{
    return m_path;
}
QString WallpaperEntry::file() const
{
    return m_file;
}
QString WallpaperEntry::source() const
{
    return m_file;
}
QString WallpaperEntry::display() const
{
    return m_name;
}
QString WallpaperEntry::preview() const
{
    return m_preview;
}
