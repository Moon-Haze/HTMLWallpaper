/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapergeneral.h"

#include <QStringLiteral>

WallpaperGeneral::WallpaperGeneral(const QVariantMap &general, QObject *parent)
    : QObject(parent)
    , m_properties(new WallpaperPropertyModel(general.value(QStringLiteral("properties")).toMap(), this))
    , m_supportsaudioprocessing(general.value(QStringLiteral("supportsaudioprocessing")).toBool())
{
}

WallpaperPropertyModel *WallpaperGeneral::properties() const
{
    return m_properties;
}

bool WallpaperGeneral::supportsaudioprocessing() const
{
    return m_supportsaudioprocessing;
}
