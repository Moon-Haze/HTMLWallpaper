/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperitem.h"

WallpaperItem::WallpaperItem(const WallpaperEntry &entry, QObject *parent)
    : QObject(parent)
    , m_entry(entry)
{
}
