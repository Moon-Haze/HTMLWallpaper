/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/** @file wallpapermodel.cpp
 * 单个文件夹的壁纸列表模型实现：条目整组替换/追加、行字段查询与选中行维护。
 * 数据来源是 WallpaperEntry（后台线程目录探测的产物），本文件只做主线程
 * 组装与 QAbstractListModel 通知（reset / insertRows）。
 */

#include "wallpapermodel.h"

#include "wallpaperitem.h"

WallpaperModel::WallpaperModel(const QString &key, QObject *parent)
    : QAbstractListModel(parent)
    , m_key(key)
{
    // 条目在首次 setEntries/addEntries 时填充；key 构造后固定。
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
        return 0; // 扁平列表：不处理层级 index
    }
    return m_items.size();
}

QVariant WallpaperModel::data(const QModelIndex &index, int role) const
{
    // 防御性边界检查：视图可能携带过期/越界 index 请求数据
    if (!index.isValid() || index.row() < 0) {
        return {};
    }
    if (index.row() >= m_items.size()) {
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

void WallpaperModel::setEntries(const QList<WallpaperEntry> &wallpapers)
{
    beginResetModel(); // reset 通知：视图整表刷新（同文件夹重扫即覆盖）
    for (WallpaperItem *p : m_items) {
        delete p; // 释放旧条目（QObject parent = 本 model）
    }
    m_items.clear();
    for (const WallpaperEntry &entry : wallpapers) {
        m_items.append(new WallpaperItem(entry, this));
    }
    endResetModel();
}

void WallpaperModel::addEntries(const QList<WallpaperEntry> &wallpapers)
{
    if (wallpapers.isEmpty()) {
        return; // 无实体不触发信号
    }
    const int first = m_items.size();
    beginInsertRows(QModelIndex(), first, first + wallpapers.size() - 1); // 行插入通知：视图增量刷新
    for (const WallpaperEntry &entry : wallpapers) {
        m_items.append(new WallpaperItem(entry, this));
    }
    endInsertRows();
}

void WallpaperModel::clear()
{
    beginResetModel(); // reset 通知：视图整表刷新（目录删空后防幽灵条目）
    for (WallpaperItem *p : m_items) {
        delete p;
    }
    m_items.clear();
    endResetModel();
}

WallpaperItem *WallpaperModel::get(int i)
{
    if (i < 0 || i >= m_items.size()) {
        return nullptr; // 越界返回 nullptr，QML 侧需判空
    }
    return m_items.at(i);
}

int WallpaperModel::selectedIndex() const
{
    return m_selectedIndex;
}

void WallpaperModel::setSelectedIndex(int index)
{
    // 越界忽略（-1 清空选中也放行）；叶子 model 与"全部"汇总 model 共用同一语义
    if (index < -1 || index >= rowCount()) {
        return;
    }
    if (m_selectedIndex == index) {
        return;
    }
    m_selectedIndex = index;
    Q_EMIT selectedIndexChanged();
}

void WallpaperModel::setSelectedIndexOfFile(const QString &file)
{
    // 线性查找 file 定位选中行；用于 setSelectWallpaper 与扫描后恢复选中
    for (int i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i)->file() == file) {
            setSelectedIndex(i);
            return;
        }
    }
}