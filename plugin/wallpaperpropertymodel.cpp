/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpaperpropertymodel.h"

#include "wallpaperpropertyitem.h"

WallpaperPropertyModel::WallpaperPropertyModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

void WallpaperPropertyModel::setEntries(const QList<WallpaperProperty> &properties)
{
    beginResetModel();
    m_items.clear();
    m_indexByKey.clear();
    m_items.reserve(properties.size());

    for (int i = 0; i < properties.size(); ++i) {
        m_items.append(WallpaperPropertyItem(properties.at(i), this));
        m_indexByKey.insert(properties.at(i).key(), i);
    }
    endResetModel();
}

int WallpaperPropertyModel::count() const
{
    return m_items.size();
}

int WallpaperPropertyModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_items.size();
}

QVariant WallpaperPropertyModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) {
        return {};
    }
    auto &item = m_items.at(index.row());
    switch (role) {
    case KeyRole:
        return item.key();
    case TypeRole:
        return item.type();
    case TextRole:
        return item.text();
    case ValueRole:
        return item.value();
    case MinRole:
        return item.min();
    case MaxRole:
        return item.max();
    case StepRole:
        return item.step();
    case FractionRole:
        return item.fraction();
    case PrecisionRole:
        return item.precision();
    case OptionsRole:
        return item.options();
    case ConditionRole:
        return item.condition();
    case GroupRole:
        return item.group();
    case OrderRole:
        return item.order();
    default:
        return {};
    }
}

QHash<int, QByteArray> WallpaperPropertyModel::roleNames() const
{
    return {
        {KeyRole, "key"},
        {TypeRole, "type"},
        {TextRole, "text"},
        {ValueRole, "value"},
        {MinRole, "min"},
        {MaxRole, "max"},
        {StepRole, "step"},
        {FractionRole, "fraction"},
        {PrecisionRole, "precision"},
        {OptionsRole, "options"},
        {ConditionRole, "condition"},
        {GroupRole, "group"},
        {OrderRole, "order"},
    };
}
WallpaperPropertyItem *WallpaperPropertyModel::get(int i)
{
    if (i < 0 || i >= m_items.size()) {
        return nullptr;
    }
    return &m_items[i];
}
WallpaperPropertyItem *WallpaperPropertyModel::byKey(const QString &key)
{
    const int i = m_indexByKey.value(key, -1);
    if (i < 0) {
        return nullptr;
    }
    return &m_items[i];
}
