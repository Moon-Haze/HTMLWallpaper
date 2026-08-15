/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QHash>
#include <QList>
#include <QStringList>
#include <qobject.h>
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
 * 条目按扫描路径（每个扫描根 URL）分组存储于 m_items（QHash<QString,
 * QList<WallpaperItem *>>），m_groupOrder 记录分组 key 插入顺序，m_flat 为
 * 扁平视图缓存（对外的 rowCount/data/get 直接索引）。addEntries(key, ...)
 * 替换 key 对应整组（同 key 覆盖）；scan() 后台一次性扫完所有 root，
 * 完成后 clear() + 逐组 addEntries。byKey(key) 返回整组，keys() 返回保序
 * 分组列表，为将来 UI 分组 / 局部重扫预留。
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

    /** 替换 key（扫描根 URL）对应整组条目；同 key 覆盖（先 delete 旧组指针）。
     *  主线程调用；每次完整重置模型。 */
    Q_INVOKABLE void addEntries(const QString &key, const QList<WallpaperEntry> &wallpapers);

    void clear();

    /** 兼容原 ListModel：返回第 i 项属性门面对象；越界返回 nullptr。 */
    Q_INVOKABLE WallpaperItem *get(int i);

    /** 按条目 source（html 文件 URL）返回扁平行号；未找到返回 -1。 */
    Q_INVOKABLE int indexOf(const QString &source) const;

    /** 按扫描路径（归一化 URL）返回该组全部 WallpaperItem*；不存在返回空列表。 */
    Q_INVOKABLE QList<WallpaperItem *> byKey(const QString &key);

    /** 保序的分组 key（扫描根 URL）列表。 */
    Q_INVOKABLE QStringList keys() const;

    /** 分组数。 */
    Q_INVOKABLE int groupCount() const;

    // —— 自治扫描 ——
    /** 后台扫描 roots 下各壁纸目录并按 root 分组填充模型；完成后发 scanFinished。 */
    Q_INVOKABLE void scan(const QStringList &roots);

Q_SIGNALS:
    /** 扫描全部完成（可能部分子目录解析失败，已发 scanFailed）。 */
    void scanFinished();
    /** 某个根目录无法读取时发出（path：根目录 url，error：底层错误字符串）。 */
    void scanFailed(const QString &path, const QString &error);
    void scanInProgressChanged();

private:
    void setScanInProgress(bool inProgress);
    /** 按 m_groupOrder 顺序重建 m_flat（m_items 变化后调用）。 */
    void rebuildFlat();

    QHash<QString, QList<WallpaperItem *>> m_items; // 分类存储：key = 扫描根 URL
    QStringList m_groupOrder;                       // key 插入顺序，驱动 keys() 与扁平化
    QList<WallpaperItem *> m_flat;                  // 扁平视图缓存
    bool m_scanning = false;
    QFutureWatcher<ScanResult> *m_watcher = nullptr;
};
