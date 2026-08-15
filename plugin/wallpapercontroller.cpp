/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapercontroller.h"

#include "wallpapermodel.h"

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

QStringList WallpaperController::scanUrls() const
{
    return m_scanUrls;
}

void WallpaperController::setScanUrls(const QStringList &urls)
{
    m_scanUrls = urls;
    Q_EMIT scanUrlsChanged();
}

WallpaperModel *WallpaperController::wallpapers() const
{
    return m_wallpapers;
}

bool WallpaperController::addScanUrl(const QString &url)
{
    if (m_scanUrls.contains(url)) {
        return false;
    }
    m_scanUrls.append(url);
    Q_EMIT scanUrlsChanged();
    return true;
}

void WallpaperController::removeScanUrl(const QString &url)
{
    if (!m_scanUrls.contains(url)) {
        return;
    }
    m_scanUrls.removeAll(url);
    Q_EMIT scanUrlsChanged();
}

void WallpaperController::scan()
{
    m_wallpapers->scan(m_scanUrls);
}
