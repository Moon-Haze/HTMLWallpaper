/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/** @file wallpaperitem.h
 * 单条壁纸元数据的 QObject 门面（WallpaperItem）声明。
 * 包装 WallpaperEntry 值类型为只读 Q_PROPERTY，供 QML 的 get(i).xxx 使用。
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
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString file READ file CONSTANT)
    Q_PROPERTY(QString preview READ preview CONSTANT)

public:
    /**
     * @brief 用后台探测的元数据构造门面对象。
     * @param entry  目录探测产物（WallpaperEntry 值类型）。
     * @param parent Qt 父对象（通常为所属 WallpaperModel，随其析构回收）。
     */
    explicit WallpaperItem(const WallpaperEntry &entry, QObject *parent = nullptr);

    /**
     * @brief 壁纸目录名（兼容别名为 title）。
     * @return 目录名；条目无效时为空串。
     */
    QString name() const
    {
        return m_entry.name();
    }
    /**
     * @brief 壁纸目录 URL。
     * @return 目录 URL；条目无效时为空串。
     */
    QString path() const
    {
        return m_entry.path();
    }
    /**
     * @brief 选出的 *.html 入口 URL（兼容别名为 source）。
     * @return 入口文件 URL；条目无效时为空串。
     */
    QString file() const
    {
        return m_entry.file();
    }
    /**
     * @brief 预览图 URL（无预览返回空串）。
     * @return 预览图 URL；无预览或条目无效时为空串。
     */
    QString preview() const
    {
        return m_entry.preview();
    }

private:
    /**
     * @brief 数据层值类型（唯一数据来源）。
     * @note 全部属性只读（Q_PROPERTY CONSTANT），属性变更即重建对象。
     */
    WallpaperEntry m_entry;
};
