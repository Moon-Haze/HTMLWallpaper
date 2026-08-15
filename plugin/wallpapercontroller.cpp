/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapercontroller.h"

#include "wallpapermodel.h"

WallpaperController::WallpaperController(QObject *parent)
    : QObject(parent)
{
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

void WallpaperController::setScanPaths(const QStringList &urls)
{
    m_scanPaths = urls;
    Q_EMIT scanPathsChanged();
}

bool WallpaperController::addScanPath(const QString &url)
{
    if (m_scanPaths.contains(url)) {
        return false;
    }
    m_scanPaths.append(url);
    Q_EMIT scanPathsChanged();
    return true;
}

void WallpaperController::removeScanPath(const QString &url)
{
    if (!m_scanPaths.contains(url)) {
        return;
    }
    m_scanPaths.removeAll(url);
    Q_EMIT scanPathsChanged();
}
