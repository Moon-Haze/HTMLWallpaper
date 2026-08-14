/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "htmlbackend.h"

#include "wallpaperentry.h"
#include "wallpaperitem.h"
#include "wallpapermodel.h"

// ---------------------------------------------------------------------------
// HTMLBackend
// ---------------------------------------------------------------------------

HTMLBackend::HTMLBackend(QObject *parent)
    : QObject(parent)
    , m_wallpapers(new WallpaperModel(this))
{
    connect(m_wallpapers, &WallpaperModel::scanFinished, this, &HTMLBackend::scanFinished);
    connect(m_wallpapers, &WallpaperModel::scanFailed, this, &HTMLBackend::scanFailed);
    connect(m_wallpapers, &WallpaperModel::scanInProgressChanged, this, &HTMLBackend::scanInProgressChanged);
}

QString HTMLBackend::selectWallpaper() const
{
    return m_selectWallpaper;
}

void HTMLBackend::setSelectWallpaper(const QString &wallpaper)
{
    if (m_selectWallpaper == wallpaper) {
        return;
    }
    m_selectWallpaper = wallpaper;
    Q_EMIT selectWallpaperChanged();
}

QStringList HTMLBackend::scanPaths() const
{
    return m_scanPaths;
}

void HTMLBackend::setScanPaths(const QStringList &paths)
{
    QStringList normalized;
    normalized.reserve(paths.size());
    for (const QString &p : paths) {
        normalized.append(WallpaperPath::toUrl(p));
    }
    if (m_scanPaths == normalized) {
        return;
    }
    m_scanPaths = normalized;
    Q_EMIT scanPathsChanged();
}

bool HTMLBackend::requireWebType() const
{
    return m_requireWebType;
}

void HTMLBackend::setRequireWebType(bool requireWebType)
{
    if (m_requireWebType == requireWebType) {
        return;
    }
    m_requireWebType = requireWebType;
    Q_EMIT requireWebTypeChanged();
}

QStringList HTMLBackend::nonHtmlTypes() const
{
    return m_nonHtmlTypes;
}

void HTMLBackend::setNonHtmlTypes(const QStringList &nonHtmlTypes)
{
    if (m_nonHtmlTypes == nonHtmlTypes) {
        return;
    }
    m_nonHtmlTypes = nonHtmlTypes;
    Q_EMIT nonHtmlTypesChanged();
}

bool HTMLBackend::scanInProgress() const
{
    return m_wallpapers->scanInProgress();
}

WallpaperModel *HTMLBackend::wallpapers() const
{
    return m_wallpapers;
}

bool HTMLBackend::addScanPath(const QString &path)
{
    const QString p = WallpaperPath::toUrl(path);
    if (m_scanPaths.contains(p)) {
        return false;
    }
    m_scanPaths.append(p);
    Q_EMIT scanPathsChanged();
    return true;
}

void HTMLBackend::removeScanPath(const QString &path)
{
    const QString p = WallpaperPath::toUrl(path);
    if (!m_scanPaths.contains(p)) {
        return;
    }
    m_scanPaths.removeAll(p);
    Q_EMIT scanPathsChanged();
}

void HTMLBackend::scan()
{
    m_wallpapers->scan(m_scanPaths);
}
