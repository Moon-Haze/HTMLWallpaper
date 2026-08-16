/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/** @file wallpapercontroller.cpp
 * WallpaperController 实现：后台并发扫描（QtConcurrent）、按扫描根缓存
 * 文件夹 model、"全部"汇总 model 重建、选中行同步与 stale model 清理。
 */

#include "wallpapercontroller.h"
#include "wallpapermodel.h"

#include <QDir>
#include <QFutureWatcher>
#include <QSet>
#include <QString>
#include <QUrl>
#include <QtConcurrent>
#include <qvariant.h>
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
    // activeModel 初始即指向 allModel()，保证属性始终非空、无悬空风险。
}

QString WallpaperController::selectWallpaper() const
{
    return m_activeModel ? m_activeModel->get<WallpaperModel::FileRole>() : QString();
}

void WallpaperController::setSelectWallpaper(const QString &paper)
{
    // 按 file 定位 activeModel 的选中行（未命中忽略），再统一发属性变化信号
    if (m_activeModel) {
        m_activeModel->setSelectedIndexOfFile(paper);
    }
    Q_EMIT selectWallpaperChanged();
}

int WallpaperController::activeIndex() const
{
    return m_activeModel ? m_activeModel->selectedIndex() : -1; // 触发聚合 getter，优先返回最后变化源的选中行
}

void WallpaperController::setActiveIndex(int index)
{
    if (m_activeModel) {
        m_activeModel->setSelectedIndex(index);
    }
    Q_EMIT activeIndexChanged();
    Q_EMIT selectWallpaperChanged();
}

WallpaperModel *WallpaperController::activeModel() const
{
    return m_activeModel;
}

void WallpaperController::setActiveModel(WallpaperModel *model)
{
    if (m_activeModel == model) {
        return;
    }
    m_activeModel = model;

    Q_EMIT activeModelChanged();
    Q_EMIT activeIndexChanged(); // 触发聚合 getter，优先返回最后变化源的选中行
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
        return false; // 去重：已存在不重复添加
    }
    m_scanPaths.append(url);
    Q_EMIT scanPathsChanged();
    return true;
}

void WallpaperController::removeScanPath(const QString &url)
{
    if (!m_scanPaths.contains(url)) {
        return; // 不存在则无操作
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
            // 汇总 model（"全部"标签）在构造时创建；每次 scan 重建内容：
            // 先清空再逐组追加，避免重扫重复、目录移除后残留幽灵条目。
            m_allModel->clear();
            // 本次产生数据的文件夹 key 集合（归一化后与 m->key() 可比）。
            QSet<QString> updatedKeys;
            for (const auto &group : result.groups) {
                updatedKeys.insert(normalizeKey(group.key));
                WallpaperModel *model = obtainModel(group.key);
                model->setEntries(group.entries);
                m_allModel->addEntries(group.entries);
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
            QString selectWallpaper = this->selectWallpaper(); // 先缓存，避免扫描后清空选中行，导致幽灵条目残留
            if (m_activeModel != m_allModel) {
                m_allModel->setSelectedIndexOfFile(selectWallpaper); // 扫描后清空选中行，避免残留幽灵条目
            }
            for (WallpaperModel *model : m_models) {
                if (model != m_activeModel) {
                    model->setSelectedIndexOfFile(selectWallpaper); // 扫描后清空选中行，避免残留幽灵条目
                }
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
    // key 与 m_models 中现有 model 均按同一规则归一化，保证按 key 去重
    const QString key = normalizeKey(WallpaperPath::toUrl(url));
    for (WallpaperModel *m : m_models) {
        if (m->key() == key) {
            return m;
        }
    }
    auto *model = new WallpaperModel(key, this); // 未命中 → 新建并缓存
    m_models.append(model);
    return model;
}

WallpaperModel *WallpaperController::modelFor(const QString &url)
{
    return obtainModel(url);
}

WallpaperModel *WallpaperController::allModel()
{
    return m_allModel;
}

void WallpaperController::releaseStaleModels(const QStringList &kept)
{
    QSet<QString> keptKeys;
    for (const QString &u : kept) {
        keptKeys.insert(normalizeKey(WallpaperPath::toUrl(u)));
    }
    for (int i = m_models.size() - 1; i >= 0; --i) {
        WallpaperModel *m = m_models.at(i);
        if (!keptKeys.contains(m->key())) {
            // 释放的正是当前活动文件夹 model → 同步置空并 emit，防 activeModel 悬空
            // （view.model 直接绑定 activeModel，置空不发信号会导致 QML 继续持有已 delete 指针）
            if (m_activeModel == m) {
                m_activeModel = nullptr;
                Q_EMIT activeModelChanged();
            }
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
