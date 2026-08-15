/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "wallpapercontroller.h"

#include "allwallpapersmodel.h"

#include <QDir>
#include <QFutureWatcher>
#include <QSet>
#include <QUrl>
#include <QtConcurrent>

namespace
{

// 文件夹 key 归一化：去末尾斜杠（Qt.resolvedUrl 对目录可能带尾斜杠，
// 与 scan 生成的 key 差异会影响 modelFor 匹配）。
QString normalizeKey(const QString &url)
{
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s;
}

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
        // 存在但无壁纸子目录的空根不进分组
        if (!group.entries.isEmpty()) {
            result.groups.append(group);
        }
    }
    return result;
}

} // namespace

WallpaperController::WallpaperController(QObject *parent)
    : QObject(parent)
{
}

QString WallpaperController::selectWallpaper() const
{
    return m_selectWallpaper;
}

void WallpaperController::setSelectWallpaper(const QString &wallpaper)
{
    if (m_selectWallpaper == wallpaper) {
        return;
    }
    m_selectWallpaper = wallpaper;
    Q_EMIT selectWallpaperChanged();
}

QStringList WallpaperController::scanPaths() const
{
    return m_scanPaths;
}

void WallpaperController::setScanPaths(const QStringList &urls)
{
    m_scanPaths = urls;
    Q_EMIT scanPathsChanged();
}

bool WallpaperController::scanInProgress() const
{
    return m_scanning;
}

void WallpaperController::setScanInProgress(bool inProgress)
{
    if (m_scanning == inProgress) {
        return;
    }
    m_scanning = inProgress;
    Q_EMIT scanInProgressChanged();
}

int WallpaperController::modelCount() const
{
    return m_models.size();
}

bool WallpaperController::addScanPath(const QString &url)
{
    if (m_scanPaths.contains(url)) {
        return false;
    }
    m_scanPaths.append(url);
    Q_EMIT scanPathsChanged();
    return true;
}

void WallpaperController::removeScanPath(const QString &url)
{
    if (!m_scanPaths.contains(url)) {
        return;
    }
    m_scanPaths.removeAll(url);
    Q_EMIT scanPathsChanged();
}

void WallpaperController::scan()
{
    if (m_scanning) {
        return;
    }
    setScanInProgress(true);

    if (!m_watcher) {
        m_watcher = new QFutureWatcher<ScanResult>(this);
        QObject::connect(m_watcher, &QFutureWatcher<ScanResult>::finished, this, [this]() {
            const ScanResult result = m_watcher->result();
            for (const auto &failure : result.failures) {
                Q_EMIT scanFailed(failure.first, failure.second);
            }
            // 本次产生数据的文件夹 key 集合（归一化后与 m->key() 可比）。
            QSet<QString> updatedKeys;
            for (const auto &group : result.groups) {
                updatedKeys.insert(normalizeKey(group.key));
                obtainModel(group.key)->addEntries(group.entries);
            }
            // 对仍在 scanPaths、但本次未产生 group 的文件夹（目录被删空或被删除，
            // 或存在但无任何 *.html 入口）显式清空，避免旧壁纸残留成幽灵条目。
            // 即将被 releaseStaleModels 删除的 stale model 也走 clear 无害，
            // 统一覆盖"目录删空"与"目录删除→failures 分支"两种情况。
            for (WallpaperModel *m : m_models) {
                if (!updatedKeys.contains(m->key())) {
                    m->clear();
                }
            }
            // 合并 model 保活复用：先重挂最新源（此刻旧源全部存活，
            // setSources 内 disconnect 安全），再清理已移除文件夹的 model，
            // 避免对已释放源解引用（use-after-free）。
            if (m_allModel) {
                QSet<QString> keptKeys;
                for (const QString &u : m_scanPaths) {
                    keptKeys.insert(normalizeKey(WallpaperPath::toUrl(u)));
                }
                QList<WallpaperModel *> keptModels;
                for (WallpaperModel *m : m_models) {
                    if (keptKeys.contains(m->key())) {
                        keptModels.append(m);
                    }
                }
                static_cast<AllWallpapersModel *>(m_allModel)->setSources(keptModels);
            }
            releaseStaleModels(m_scanPaths);
            setScanInProgress(false);
            Q_EMIT scanFinished();
        });
    }
    m_watcher->setFuture(QtConcurrent::run(scanWallpapers, m_scanPaths));
}

WallpaperModel *WallpaperController::obtainModel(const QString &url)
{
    const QString key = normalizeKey(WallpaperPath::toUrl(url));
    for (WallpaperModel *m : m_models) {
        if (m->key() == key) {
            return m;
        }
    }
    auto *model = new WallpaperModel(key, this);
    m_models.append(model);
    return model;
}

WallpaperModel *WallpaperController::modelFor(const QString &url)
{
    return obtainModel(url);
}

QAbstractItemModel *WallpaperController::allModel()
{
    if (!m_allModel) {
        auto *merged = new AllWallpapersModel(this);
        merged->setSources(m_models);
        m_allModel = merged;
    }
    return m_allModel;
}

void WallpaperController::releaseStaleModels(const QStringList &kept)
{
    QSet<QString> keptKeys;
    for (const QString &u : kept) {
        keptKeys.insert(normalizeKey(WallpaperPath::toUrl(u)));
    }
    for (int i = m_models.size() - 1; i >= 0; --i) {
        if (!keptKeys.contains(m_models.at(i)->key())) {
            delete m_models.takeAt(i);
        }
    }
}

QString WallpaperController::folderName(const QString &url) const
{
    // 与 wallpaperentry.cpp 的 basename 一致：去末尾斜杠后取最后一段
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s.mid(s.lastIndexOf(QLatin1Char('/')) + 1);
}

QString WallpaperController::parentPath(const QString &url) const
{
    // 去末尾斜杠后去掉最后一段（保留父目录完整路径）
    QString s = url;
    while (s.endsWith(QLatin1Char('/'))) {
        s.chop(1);
    }
    return s.left(s.lastIndexOf(QLatin1Char('/')));
}
