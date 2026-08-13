/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "htmlbackend.h"

#include "wallpaperitem.h"
#include "wallpaperlistmodel.h"
#include "wallpaperproject.h"

#include <QDir>
#include <QFutureWatcher>
#include <QPair>
#include <QUrl>
#include <QtConcurrent>

namespace
{

// 后台扫描 worker：只做纯数据读取（QDir + WallpaperProject 构造），
// 不触碰任何 QObject，可安全地在后台线程执行。
ScanResult scanWallpapers(const QStringList &roots, bool requireWebType, const QStringList &nonHtmlTypes)
{
    using namespace WallpaperProjectJson;
    ScanResult result;
    for (const QString &base : roots) {
        const QString baseUrl = toUrl(base);
        QDir dir(QUrl(baseUrl).toLocalFile());
        if (!dir.exists()) {
            result.failures.append({base, QStringLiteral("cannot list directory")});
            continue;
        }
        const QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QString &sub : subdirs) {
            const QString dirUrl = pathJoin(baseUrl, sub);
            WallpaperProject proj(dirUrl);
            if (!proj.isValid()) {
                continue; // 无 project.json / 解析失败 → 静默跳过（与旧实现一致）
            }
            if (requireWebType && !isHtmlType(proj.type(), nonHtmlTypes)) {
                continue; // 非 HTML 类型过滤
            }
            result.projects.append(proj);
        }
    }
    return result;
}

} // namespace

// ---------------------------------------------------------------------------
// HTMLBackend
// ---------------------------------------------------------------------------

HTMLBackend::HTMLBackend(QObject *parent)
    : QObject(parent)
    , m_wallpapers(new WallpaperListModel(this))
{
}
QString HTMLBackend::selectWallpaper() const
{
    return m_selectWallpaper;
}
void HTMLBackend::setSelectWallpaper(const QString &wallpaper)
{
    if (m_selectWallpaper == wallpaper) {
        return;
    }
    m_selectWallpaper = wallpaper;
    Q_EMIT selectWallpaperChanged();
}

QStringList HTMLBackend::scanPaths() const
{
    return m_scanPaths;
}

void HTMLBackend::setScanPaths(const QStringList &paths)
{
    QStringList normalized;
    normalized.reserve(paths.size());
    for (const QString &p : paths) {
        normalized.append(WallpaperProjectJson::toUrl(p));
    }
    if (m_scanPaths == normalized) {
        return;
    }
    m_scanPaths = normalized;
    Q_EMIT scanPathsChanged();
}

bool HTMLBackend::requireWebType() const
{
    return m_requireWebType;
}

void HTMLBackend::setRequireWebType(bool requireWebType)
{
    if (m_requireWebType == requireWebType) {
        return;
    }
    m_requireWebType = requireWebType;
    Q_EMIT requireWebTypeChanged();
}

QStringList HTMLBackend::nonHtmlTypes() const
{
    return m_nonHtmlTypes;
}

void HTMLBackend::setNonHtmlTypes(const QStringList &nonHtmlTypes)
{
    if (m_nonHtmlTypes == nonHtmlTypes) {
        return;
    }
    m_nonHtmlTypes = nonHtmlTypes;
    Q_EMIT nonHtmlTypesChanged();
}

bool HTMLBackend::scanInProgress() const
{
    return m_scanning;
}

void HTMLBackend::setScanInProgress(bool inProgress)
{
    if (m_scanning == inProgress) {
        return;
    }
    m_scanning = inProgress;
    Q_EMIT scanInProgressChanged();
}

WallpaperListModel *HTMLBackend::wallpapers() const
{
    return m_wallpapers;
}

bool HTMLBackend::addScanPath(const QString &path)
{
    const QString p = WallpaperProjectJson::toUrl(path);
    if (m_scanPaths.contains(p)) {
        return false;
    }
    m_scanPaths.append(p);
    Q_EMIT scanPathsChanged();
    return true;
}

void HTMLBackend::removeScanPath(const QString &path)
{
    const QString p = WallpaperProjectJson::toUrl(path);
    if (!m_scanPaths.contains(p)) {
        return;
    }
    m_scanPaths.removeAll(p);
    Q_EMIT scanPathsChanged();
}

void HTMLBackend::scan()
{
    if (m_scanning) {
        return;
    }
    setScanInProgress(true);
    m_wallpapers->clear();

    // 快照传给后台线程：worker 只读这些值拷贝，绝不触碰任何 QObject 成员。
    const QStringList roots = m_scanPaths;
    const bool requireWebType = m_requireWebType;
    const QStringList nonHtmlTypes = m_nonHtmlTypes;

    if (!m_watcher) {
        m_watcher = new QFutureWatcher<ScanResult>(this);
        QObject::connect(m_watcher, &QFutureWatcher<ScanResult>::finished, this, [this]() {
            const ScanResult result = m_watcher->result();
            for (const auto &failure : result.failures) {
                Q_EMIT scanFailed(failure.first, failure.second);
            }
            m_wallpapers->setEntries(result.projects);
            setScanInProgress(false);
            Q_EMIT scanFinished();
        });
    }
    m_watcher->setFuture(QtConcurrent::run(scanWallpapers, roots, requireWebType, nonHtmlTypes));
}
