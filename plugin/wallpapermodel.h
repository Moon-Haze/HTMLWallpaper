/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/** @file wallpapermodel.h
 * 单个文件夹的壁纸列表模型（WallpaperModel）声明。
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集
 * （count / get / data），供 ThumbnailsPanel 与 WallpaperController 消费。
 */

#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <qcontainerfwd.h>
#include <qobject.h>
#include <qtmetamacros.h>

#include "wallpaperentry.h"
#include "wallpaperitem.h"

/**
 * @brief 单个文件夹的壁纸列表模型（WallpaperController::modelFor 的返回）。
 *
 * 以 QAbstractListModel 实现原 QML ListModel 的公开 API 子集：
 * count / get(i) 与 data()。roles 对齐 WallpaperDelegate / ThumbnailsView
 * 使用的字段：name / path / preview / file（file 是目录探测选出的
 * *.html 入口；name 即目录名，title/source/display 为兼容别名，见
 * WallpaperEntry / WallpaperItem）。
 *
 * 单文件夹语义：一个实例只装一个扫描根（key，归一化 URL）的壁纸。
 * setEntries(entries) 整组替换本文件夹条目（同文件夹重扫即覆盖）；
 * addEntries(entries) 追加实体到末尾（不清空已有条目）。
 * 选中行语义：selectedIndex 只记录本文件夹当前选中行（-1 = 无选中），
 * 高亮是纯 UI 态不落盘；WallpaperController 的 activeIndex 派生自它。
 * 无扫描逻辑、无后台线程——扫描编排由 WallpaperController 承担。
 */

class WallpaperModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count CONSTANT) // 本文件夹条目数
    Q_PROPERTY(QString key READ key CONSTANT) // 本文件夹归一化 URL（扫描根）
    Q_PROPERTY(int selectedIndex READ selectedIndex WRITE setSelectedIndex NOTIFY selectedIndexChanged) // 本文件夹选中行（-1 = 无选中）

public:
    /**
     * @brief data() / roleNames() 使用的角色。
     * @note 对齐 QML 侧 WallpaperDelegate 绑定的字段。
     */
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        PreviewRole,
        FileRole,
    };
    Q_ENUM(Roles)
    /**
     * @brief 以扫描根 key 构造单文件夹模型。
     * @param key    本文件夹归一化 URL（归一化规则与
     *               WallpaperController::modelFor 一致，保证按 key 去重/复用）。
     * @param parent Qt 父对象（controller 持有的 model 传 controller）。
     */
    explicit WallpaperModel(const QString &key, QObject *parent = nullptr);

    /**
     * @brief 本文件夹归一化 URL。
     * @return 构造后固定的扫描根 key；controller 按它去重/复用/清理。
     */
    QString key() const;
    /**
     * @brief 本文件夹条目数。
     * @return 等价 rowCount，QML 便捷属性。
     */
    int count() const;
    /**
     * @brief QAbstractListModel 重写：本模型为扁平列表。
     * @param parent 父 index。
     * @return parent 有效时返回 0，否则返回本文件夹条目数。
     */
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    /**
     * @brief 取第 index.row() 项在指定 role 下的字段值。
     * @param index 目标行 index。
     * @param role  取值角色（见 Roles 枚举）。
     * @return 对应字段 QVariant；index 越界或 role 未知返回空 QVariant。
     */
    QVariant data(const QModelIndex &index, int role) const override;
    /**
     * @brief QML 侧可用的 role 名映射。
     * @return {NameRole→"name", PathRole→"path", PreviewRole→"preview", FileRole→"file"}。
     */
    QHash<int, QByteArray> roleNames() const override;

    /**
     * @brief 整组替换本文件夹全部条目（同文件夹重扫即覆盖）。
     * @param wallpapers 新条目列表。
     * @note 主线程调用；reset 一次整表刷新。
     */
    Q_INVOKABLE void setEntries(const QList<WallpaperEntry> &wallpapers);
    /**
     * @brief 追加条目到列表末尾（保留已有条目）。
     * @param wallpapers 待追加条目列表。
     * @note 主线程调用；insertRows 通知视图增量刷新。
     */
    Q_INVOKABLE void addEntries(const QList<WallpaperEntry> &wallpapers);

    /**
     * @brief 清空本文件夹全部条目。
     * @note controller 对"空根/目录删空"调用，防幽灵条目；reset 一次整表刷新。
     */
    void clear();

    /**
     * @brief 兼容原 ListModel：返回第 i 项属性门面对象。
     * @param i 行号。
     * @return QML 侧可用 get(i).source 等；越界返回 nullptr。
     */
    Q_INVOKABLE WallpaperItem *get(int i);

    /**
     * @brief 返回第 i 项在角色 R 下的字符串字段（模板版，无对象开销）。
     * @tparam R 取值角色（见 Roles 枚举）。
     * @param i 行号。
     * @return 对应字段字符串；越界返回空串。
     */
    template<Roles R>
    QString get(int i) const
    {
        if (i < 0 || i >= m_items.size()) {
            return QString();
        }
        switch (R) {
        case NameRole:
            return m_items.at(i)->name();
        case PathRole:
            return m_items.at(i)->path();
        case PreviewRole:
            return m_items.at(i)->preview();
        case FileRole:
            return m_items.at(i)->file();
        }
        return QString();
    }
    /**
     * @brief 返回当前选中行在角色 R 下的字符串字段。
     * @tparam R 取值角色（见 Roles 枚举）。
     * @return 选中行对应字段字符串；无选中返回空串。
     */
    template<Roles R>
    QString get() const
    {
        return get<R>(m_selectedIndex);
    }

    /**
     * @brief 本文件夹当前选中行。
     * @return 选中行行号；-1 = 无选中。
     */
    int selectedIndex() const;

    /**
     * @brief 设置本文件夹选中行。
     * @param index 目标行号（-1 表示清空选中）。
     * @note 越界（< -1 或 ≥ 行数）忽略；等值不触发信号。
     */
    void setSelectedIndex(int index);

    /**
     * @brief 按 file 定位行并设为选中。
     * @param file 目录探测选出的 *.html 入口。
     * @note 未命中不做任何事。
     */
    void setSelectedIndexOfFile(const QString &file);

Q_SIGNALS:
    /**
     * @brief 选中行变化通知。
     * @note controller 的 activeIndex / selectWallpaper 随之刷新。
     */
    void selectedIndexChanged();

private:
    /**
     * @brief 本文件夹归一化 URL。
     * @note 构造后固定；controller 按它去重/复用/清理。
     */
    QString m_key;
    /**
     * @brief 本文件夹的壁纸项列表。
     * @note 每项 QObject parent 均为本 model，随 model 析构统一释放，
     *       替换条目时需先手动 delete（见 setEntries/clear）。
     */
    QList<WallpaperItem *> m_items;
    /**
     * @brief 本文件夹当前选中行。
     * @note -1 = 无选中；高亮为纯 UI 态不落盘。
     */
    int m_selectedIndex = -1;
};
