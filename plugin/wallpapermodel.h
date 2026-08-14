/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QStringList>
#include <qtmetamacros.h>

#include "wallpaperentry.h"
#include "wallpaperitem.h"

template<typename T>
class QFutureWatcher;

/**
 * @brief 扫描结果壁纸列表模型（WallpaperController::wallpapers，列表层，自治扫描）。
 *
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集：
 * count / get(i) 与 data()。roles 对齐 WallpaperDelegate / ThumbnailsView
 * 使用的字段：name / title / path / preview / file（file 是目录探测选出的
 * *.html 入口）。
 *
 * setEntries(QList<WallpaperEntry>) 主线程物化 WallpaperItem*（QObject）。
 * 扫描逻辑（scan()）也下沉到本模型：后台线程执行 scanWallpapers worker，
 * 完成后在本线程聚合 ScanResult 并发出 scanFinished / scanFailed。
 */
class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(bool scanInProgress READ scanInProgress NOTIFY scanInProgressChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        TitleRole,
        PathRole,
        PreviewRole,
        FileRole,
    };
    Q_ENUM(Roles)

    explicit WallpaperModel(QObject *parent = nullptr);

    int count() const;
    bool scanInProgress() const;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    /** 整体替换全部条目（扫描完成时主线程调用）；只发一次 reset + countChanged。 */
    void setEntries(const QList<WallpaperEntry> &projects);

    void clear();

    Q_INVOKABLE int indexOf(const QString &source) const;

    /** 兼容原 ListModel：返回第 i 项元数据对象（含 checked）。 */
    Q_INVOKABLE WallpaperItem *get(int i);

    /** 按 key 返回属性门面对象；不存在返回 nullptr。 */
    Q_INVOKABLE WallpaperItem *byKey(const QString &key);

    // —— 自治扫描 ——
    /** 后台扫描 roots 下各壁纸目录并填充模型；完成后发 scanFinished。 */
    Q_INVOKABLE void scan(const QStringList &roots);

Q_SIGNALS:
    /** 扫描全部完成（可能部分子目录解析失败，已发 scanFailed）。 */
    void scanFinished();
    /** 某个根目录无法读取时发出（path：根目录 url，error：底层错误字符串）。 */
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    void setScanInProgress(bool inProgress);

    QList<WallpaperItem> m_items;
    QHash<QString, int> m_indexByKey;
    bool m_scanning = false;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
