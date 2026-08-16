/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/** @file wallpaperitem.cpp
 * 单条壁纸元数据的 QObject 门面实现：仅转存 WallpaperEntry，无额外逻辑。
 */

#include "wallpaperitem.h"

WallpaperItem::WallpaperItem(const WallpaperEntry &entry, QObject *parent)
    : QObject(parent)
    , m_entry(entry)
{
    // 属性全部只读（CONSTANT）；元数据变更时由上层重建对象而非改属性。
}
