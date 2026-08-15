/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>

#include "wallpaperentry.h"

/**
 * @brief 单个壁纸元数据的 QObject 门面（接口层，WallpaperModel::get(i)
 * 的返回值，主线程构造）。数据成员是 WallpaperEntry 值类型（后台线程目录
 * 探测的产物），全部 Q_PROPERTY 委托到它。source/display 是 file/title
 * 的兼容别名（对齐 slideFilterModel 与 ThumbnailsView 的 get(i).source）。
 */
class WallpaperItem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString file READ file CONSTANT)
    Q_PROPERTY(QString source READ source CONSTANT)
    Q_PROPERTY(QString display READ display CONSTANT)
    Q_PROPERTY(QString preview READ preview CONSTANT)

public:
    explicit WallpaperItem(const WallpaperEntry &entry, QObject *parent = nullptr);

    QString name() const { return m_entry.name(); }
    QString title() const { return m_entry.title(); }
    QString path() const { return m_entry.path(); }
    QString file() const { return m_entry.file(); }
    QString source() const { return m_entry.source(); }
    QString display() const { return m_entry.display(); }
    QString preview() const { return m_entry.preview(); }

private:
    WallpaperEntry m_entry; // 数据层（唯一数据来源）
};
