/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperlistmodel.h"

#include "wallpaperitem.h"

#include <QHash>

WallpaperListModel::WallpaperListModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int WallpaperListModel::count() const
{
    return m_items.size();
}

int WallpaperListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_items.size();
}

QVariant WallpaperListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }
    auto &item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item.name();
    case TitleRole:
        return item.title();
    case PathRole:
        return item.path();
    case PreviewRole:
        return item.preview();
    case FileRole:
        return item.file();
    default:
        return {};
    }
}

bool WallpaperListModel::setData(const QModelIndex &index, const QVariant &value, int role)
{
    Q_UNUSED(index);
    Q_UNUSED(value);
    Q_UNUSED(role);
    return false; // 目前仅支持 setProperty / setExclusiveChecked 写回 checked
}

QHash<int, QByteArray> WallpaperListModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {TitleRole, "title"},
        {PathRole, "path"},
        {PreviewRole, "preview"},
        {FileRole, "file"},
    };
}

void WallpaperListModel::setEntries(const QList<WallpaperEntry> &projects)
{
    beginResetModel();
    m_items.clear();
    m_items.reserve(projects.size());

    for (int i = 0; i < projects.size(); ++i) {
        m_items.append(WallpaperItem(projects.at(i), this));
        m_indexByKey.insert(projects.at(i).source(), i);
    }
    endResetModel();
    Q_EMIT dataChanged(index(0, 0),
                       index(qMax(0, m_items.size() - 1), 0),
                       {
                           NameRole,
                           TitleRole,
                           PathRole,
                           PreviewRole,
                           FileRole,
                       });
}

void WallpaperListModel::clear()
{
    beginResetModel();
    m_items.clear();
    endResetModel();
}

int WallpaperListModel::indexOf(const QString &source) const
{
    for (int i = 0; i < m_items.size(); i++) {
        if (m_items.at(i).source() == source) {
            return i;
        }
    }
    return -1;
}

WallpaperItem *WallpaperListModel::get(int i)
{
    if (i < 0 || i >= m_items.size()) {
        return nullptr;
    }
    return &m_items[i];
}

WallpaperItem *WallpaperListModel::byKey(const QString &key)
{
    auto it = m_indexByKey.find(key);
    if (it != m_indexByKey.end()) {
        return &m_items[it.value()];
    }
    return nullptr;
}
