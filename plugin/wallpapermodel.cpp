/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapermodel.h"

#include "wallpaperitem.h"

WallpaperModel::WallpaperModel(const QString &key, QObject *parent)
    : QAbstractListModel(parent)
    , m_key(key)
{
}

QString WallpaperModel::key() const
{
    return m_key;
}

int WallpaperModel::count() const
{
    return m_items.size();
}

int WallpaperModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_items.size();
}

QVariant WallpaperModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }
    auto item = m_items.at(index.row());
    switch (role) {
    case NameRole:
        return item->name();
    case PathRole:
        return item->path();
    case PreviewRole:
        return item->preview();
    case FileRole:
        return item->file();
    default:
        return {};
    }
}

QHash<int, QByteArray> WallpaperModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {PathRole, "path"},
        {PreviewRole, "preview"},
        {FileRole, "file"},
    };
}

void WallpaperModel::addEntries(const QList<WallpaperEntry> &wallpapers)
{
    beginResetModel();
    for (WallpaperItem *p : m_items) {
        delete p; // 释放旧条目（QObject parent = 本 model）
    }
    m_items.clear();
    for (const WallpaperEntry &entry : wallpapers) {
        m_items.append(new WallpaperItem(entry, this));
    }
    endResetModel();
    resetSelectedIndexIfNeeded();
}

void WallpaperModel::clear()
{
    beginResetModel();
    for (WallpaperItem *p : m_items) {
        delete p;
    }
    m_items.clear();
    endResetModel();
    resetSelectedIndexIfNeeded();
}

// 整组替换后行号身份失效，清选中（仅原值非 -1 时通知，无变化不 emit）
void WallpaperModel::resetSelectedIndexIfNeeded()
{
    if (m_selectedIndex != -1) {
        m_selectedIndex = -1;
        Q_EMIT selectedIndexChanged();
    }
}

int WallpaperModel::selectedIndex() const
{
    return m_selectedIndex;
}

void WallpaperModel::setSelectedIndex(int index)
{
    // 越界忽略，保持不变式 selectedIndex ∈ [-1, count()-1]
    if (index < -1 || index >= m_items.size()) {
        return;
    }
    if (m_selectedIndex == index) {
        return;
    }
    m_selectedIndex = index;
    Q_EMIT selectedIndexChanged();
}

int WallpaperModel::indexOf(const QString &source) const
{
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i)->file() == source) {
            return i;
        }
    }
    return -1;
}

WallpaperItem *WallpaperModel::get(int i)
{
    if (i < 0 || i >= m_items.size()) {
        return nullptr;
    }
    return m_items.at(i);
}
