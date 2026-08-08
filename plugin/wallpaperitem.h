/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QVariantMap>

/**
 * @brief 单个壁纸的元数据（HTMLBackend::currentWallpaper 与
 * WallpaperListModel::get(i) 的返回值）。
 *
 * 以 QObject 形式暴露，使 QML 里 `parser.currentWallpaper === null`（未解析
 * 时返回 nullptr）与 `currentWallpaper.title` 等属性访问都符合直觉。
 * display/source 是对齐 slideFilterModel 的只读别名（display=title、
 * source=entry），WallpaperDelegate 无需区分数据源即可渲染。
 */
class WallpaperItem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString title READ title CONSTANT)
    Q_PROPERTY(QString description READ description CONSTANT)
    Q_PROPERTY(QString tags READ tags CONSTANT)
    Q_PROPERTY(QString type READ type CONSTANT)
    Q_PROPERTY(QString visibility READ visibility CONSTANT)
    Q_PROPERTY(QString workshopid READ workshopid CONSTANT)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(QString entry READ entry CONSTANT)
    Q_PROPERTY(QString preview READ preview CONSTANT)
    Q_PROPERTY(QString display READ title CONSTANT)
    Q_PROPERTY(QString source READ entry CONSTANT)
    Q_PROPERTY(bool checked READ checked WRITE setChecked NOTIFY checkedChanged)

public:
    explicit WallpaperItem(const QVariantMap &meta, QObject *parent = nullptr);

    QString name() const;
    QString title() const;
    QString description() const;
    QString tags() const;
    QString type() const;
    QString visibility() const;
    QString workshopid() const;
    QString path() const;
    QString entry() const;
    QString preview() const;
    bool checked() const;
    void setChecked(bool checked);

Q_SIGNALS:
    void checkedChanged();

private:
    QString m_name;
    QString m_title;
    QString m_description;
    QString m_tags;
    QString m_type;
    QString m_visibility;
    QString m_workshopid;
    QString m_path;
    QString m_entry;
    QString m_preview;
    bool m_checked = false;
};
