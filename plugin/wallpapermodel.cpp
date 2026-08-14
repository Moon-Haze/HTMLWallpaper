/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapermodel.h"

#include "wallpaperitem.h"

#include <QDir>
#include <QFutureWatcher>
#include <QHash>
#include <QPair>
#include <QUrl>
#include <QtConcurrent>

namespace
{

// 后台扫描 worker：只读 QDir + WallpaperEntry 构造，不触碰 QObject。
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
        const QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &sub : subdirs) {
            const QString dirUrl = WallpaperPath::pathJoin(baseUrl, sub);
            WallpaperEntry entry(dirUrl);
            if (entry.isValid()) {
                result.projects.append(entry);
            }
        }
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
    return m_items.size();
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
    return m_items.size();
}

QVariant WallpaperModel::data(const QModelIndex &index, int role) const
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

void WallpaperModel::setEntries(const QList<WallpaperEntry> &projects)
{
    beginResetModel();
    m_items.clear();
    m_indexByKey.clear();
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

void WallpaperModel::clear()
{
    beginResetModel();
    m_items.clear();
    m_indexByKey.clear();
    endResetModel();
}

int WallpaperModel::indexOf(const QString &source) const
{
    for (int i = 0; i < m_items.size(); i++) {
        if (m_items.at(i).source() == source) {
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
    return &m_items[i];
}

WallpaperItem *WallpaperModel::byKey(const QString &key)
{
    auto it = m_indexByKey.find(key);
    if (it != m_indexByKey.end()) {
        return &m_items[it.value()];
    }
    return nullptr;
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
            setEntries(result.projects);
            setScanInProgress(false);
            Q_EMIT scanFinished();
        });
    }
    m_watcher->setFuture(QtConcurrent::run(scanWallpapers, roots));
}
