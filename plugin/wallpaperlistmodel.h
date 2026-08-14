/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QList>
#include <qtmetamacros.h>

#include "wallpaperentry.h"
#include "wallpaperitem.h"

/**
 * @brief 扫描结果壁纸列表模型（HTMLBackend::wallpapers，列表层）。
 *
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集：
 * count / get(i) 与 data()。roles 对齐 WallpaperDelegate / ThumbnailsView
 * 使用的字段：name / title / path / preview / file（file 是目录探测选出的
 * *.html 入口）。
 * setEntries(QList<WallpaperEntry>) 主线程物化 WallpaperItem*（QObject）。
 */
class WallpaperListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        TitleRole,
        PathRole,
        PreviewRole,
        FileRole,
    };
    Q_ENUM(Roles)

    explicit WallpaperListModel(QObject *parent = nullptr);

    int count() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    bool setData(const QModelIndex &index, const QVariant &value, int role) override;
    QHash<int, QByteArray> roleNames() const override;

    /** 整体替换全部条目（扫描完成时主线程调用）；只发一次 reset + countChanged。 */
    void setEntries(const QList<WallpaperEntry> &projects);

    void clear();

    Q_INVOKABLE int indexOf(const QString &source) const;

    /** 兼容原 ListModel：返回第 i 项元数据对象（含 checked）。 */
    Q_INVOKABLE WallpaperItem *get(int i);

    /** 按 key 返回属性门面对象；不存在返回 nullptr。 */
    Q_INVOKABLE WallpaperItem *byKey(const QString &key);

private:
    QList<WallpaperItem> m_items;
    QHash<QString, int> m_indexByKey;
};
