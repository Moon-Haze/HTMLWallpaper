/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperpropertyitem.h"

WallpaperPropertyItem::WallpaperPropertyItem(const WallpaperProperty &property, QObject *parent)
    : QObject(parent)
    , m_property(property)
{
}
