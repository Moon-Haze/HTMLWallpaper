/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperitem.h"

WallpaperItem::WallpaperItem(const WallpaperProject &project, QObject *parent)
    : QObject(parent)
    , m_project(project)
    , m_properties(this)
{
    m_properties.setEntries(m_project.properties());
}
