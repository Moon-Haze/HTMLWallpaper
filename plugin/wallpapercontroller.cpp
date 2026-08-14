/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapercontroller.h"

#include "wallpaperentry.h"
#include "wallpapermodel.h"

// ---------------------------------------------------------------------------
// WallpaperController
// ---------------------------------------------------------------------------

WallpaperController::WallpaperController(QObject *parent)
    : QObject(parent)
    , m_wallpapers(new WallpaperModel(this))
{
    connect(m_wallpapers, &WallpaperModel::scanFinished, this, &WallpaperController::scanFinished);
    connect(m_wallpapers, &WallpaperModel::scanFailed, this, &WallpaperController::scanFailed);
    connect(m_wallpapers, &WallpaperModel::scanInProgressChanged, this, &WallpaperController::scanInProgressChanged);
}

QString WallpaperController::selectWallpaper() const
{
    return m_selectWallpaper;
}

void WallpaperController::setSelectWallpaper(const QString &wallpaper)
{
    if (m_selectWallpaper == wallpaper) {
        return;
    }
    m_selectWallpaper = wallpaper;
    Q_EMIT selectWallpaperChanged();
}

QStringList WallpaperController::scanPaths() const
{
    return m_scanPaths;
}

void WallpaperController::setScanPaths(const QStringList &paths)
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

WallpaperModel *WallpaperController::wallpapers() const
{
    return m_wallpapers;
}

bool WallpaperController::addScanPath(const QString &path)
{
    const QString p = WallpaperPath::toUrl(path);
    if (m_scanPaths.contains(p)) {
        return false;
    }
    m_scanPaths.append(p);
    Q_EMIT scanPathsChanged();
    return true;
}

void WallpaperController::removeScanPath(const QString &path)
{
    const QString p = WallpaperPath::toUrl(path);
    if (!m_scanPaths.contains(p)) {
        return;
    }
    m_scanPaths.removeAll(p);
    Q_EMIT scanPathsChanged();
}

void WallpaperController::scan()
{
    m_wallpapers->scan(m_scanPaths);
}
