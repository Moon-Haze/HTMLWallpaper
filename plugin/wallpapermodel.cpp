/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapermodel.h"

#include "wallpaperitem.h"

#include <QDir>
#include <QFutureWatcher>
#include <QtAlgorithms>
#include <QtConcurrent>
#include <QUrl>

namespace
{

// 后台扫描 worker：只读 QDir + WallpaperEntry 构造，不触碰 QObject。
// 按扫描根归组，保留 roots 遍历顺序。
ScanResult scanWallpapers(const QStringList &roots)
{
    ScanResult result;
    for (const QString &base : roots) {
        const QString baseUrl = WallpaperPath::toUrl(base);
        QDir dir(QUrl(baseUrl).toLocalFile());
        if (!dir.exists()) {
            result.failures.append({base, QStringLiteral("cannot list directory")});
            continue;
        }
        ScanGroup group;
        group.key = baseUrl;
        const QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &sub : subdirs) {
            const QString dirUrl = WallpaperPath::pathJoin(baseUrl, sub);
            WallpaperEntry entry(dirUrl);
            if (entry.isValid()) {
                group.entries.append(entry);
            }
        }
        result.groups.append(group);
    }
    return result;
}

} // namespace

WallpaperModel::WallpaperModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int WallpaperModel::count() const
{
    return m_flat.size();
}

bool WallpaperModel::scanInProgress() const
{
    return m_scanning;
}

void WallpaperModel::setScanInProgress(bool inProgress)
{
    if (m_scanning == inProgress) {
        return;
    }
    m_scanning = inProgress;
    Q_EMIT scanInProgressChanged();
}

int WallpaperModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_flat.size();
}

QVariant WallpaperModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_flat.size()) {
        return {};
    }
    auto item = m_flat.at(index.row());
    switch (role) {
    case NameRole:
        return item->name();
    case TitleRole:
        return item->title();
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
        {TitleRole, "title"},
        {PathRole, "path"},
        {PreviewRole, "preview"},
        {FileRole, "file"},
    };
}

void WallpaperModel::addEntries(const QString &key, const QList<WallpaperEntry> &wallpapers)
{
    const QString normKey = WallpaperPath::toUrl(key);
    beginResetModel();
    auto it = m_items.find(normKey);
    if (it != m_items.end()) {
        qDeleteAll(it.value()); // 释放旧组所有 WallpaperItem*（QObject parent 为本模型）
        it.value().clear();
    }
    QList<WallpaperItem *> &group = m_items[normKey];
    for (const WallpaperEntry &entry : wallpapers) {
        group.append(new WallpaperItem(entry, this));
    }
    if (!m_groupOrder.contains(normKey)) {
        m_groupOrder.append(normKey);
    }
    rebuildFlat();
    endResetModel();
}

void WallpaperModel::clear()
{
    beginResetModel();
    for (auto it = m_items.begin(); it != m_items.end(); ++it) {
        qDeleteAll(it.value());
    }
    m_items.clear();
    m_groupOrder.clear();
    m_flat.clear();
    endResetModel();
}

void WallpaperModel::rebuildFlat()
{
    m_flat.clear();
    for (const QString &key : m_groupOrder) {
        m_flat += m_items.value(key);
    }
}

int WallpaperModel::indexOf(const QString &source) const
{
    for (int i = 0; i < m_flat.size(); ++i) {
        if (m_flat.at(i)->source() == source) {
            return i;
        }
    }
    return -1;
}

WallpaperItem *WallpaperModel::get(int i)
{
    if (i < 0 || i >= m_flat.size()) {
        return nullptr;
    }
    return m_flat.at(i);
}

QList<WallpaperItem *> WallpaperModel::byKey(const QString &key)
{
    return m_items.value(WallpaperPath::toUrl(key));
}

QStringList WallpaperModel::keys() const
{
    return m_groupOrder;
}

int WallpaperModel::groupCount() const
{
    return m_items.size();
}

void WallpaperModel::scan(const QStringList &roots)
{
    if (m_scanning) {
        return;
    }
    setScanInProgress(true);
    clear();

    if (!m_watcher) {
        m_watcher = new QFutureWatcher<ScanResult>(this);
        QObject::connect(m_watcher, &QFutureWatcher<ScanResult>::finished, this, [this]() {
            const ScanResult result = m_watcher->result();
            for (const auto &failure : result.failures) {
                Q_EMIT scanFailed(failure.first, failure.second);
            }
            for (const auto &group : result.groups) {
                addEntries(group.key, group.entries);
            }
            setScanInProgress(false);
            Q_EMIT scanFinished();
        });
    }
    m_watcher->setFuture(QtConcurrent::run(scanWallpapers, roots));
}
