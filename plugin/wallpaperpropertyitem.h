/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QVariant>
#include <QVariantList>

#include "wallpaperproperty.h"

/**
 * @brief 单个可配置属性的 QObject 门面（接口层）。
 *
 * 唯一成员是 WallpaperProperty 值类型，全部 Q_PROPERTY 委托到它；由
 * WallpaperPropertyModel::setEntries 主线程构造（作为 ListModel 的行），
 * QML 可经 get(i)/byKey 返回的对象做属性访问。
 */
class WallpaperPropertyItem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString key READ key CONSTANT)
    Q_PROPERTY(QString type READ type CONSTANT)
    Q_PROPERTY(QString text READ text CONSTANT)
    Q_PROPERTY(QVariant value READ value CONSTANT)
    Q_PROPERTY(QVariant min READ min CONSTANT)
    Q_PROPERTY(QVariant max READ max CONSTANT)
    Q_PROPERTY(QVariant step READ step CONSTANT)
    Q_PROPERTY(QVariant fraction READ fraction CONSTANT)
    Q_PROPERTY(QVariant precision READ precision CONSTANT)
    Q_PROPERTY(QVariantList options READ options CONSTANT)
    Q_PROPERTY(QString condition READ condition CONSTANT)
    Q_PROPERTY(QString group READ group CONSTANT)
    Q_PROPERTY(int order READ order CONSTANT)

public:
    explicit WallpaperPropertyItem(const WallpaperProperty &property, QObject *parent = nullptr);

    explicit WallpaperPropertyItem(const WallpaperPropertyItem &item, QObject *parent = nullptr);

    WallpaperPropertyItem &operator=(const WallpaperPropertyItem &item);

    QString key() const;
    QString type() const;
    QString text() const;
    QVariant value() const;
    QVariant min() const;
    QVariant max() const;
    QVariant step() const;
    QVariant fraction() const;
    QVariant precision() const;
    QVariantList options() const;
    QString condition() const;
    QString group() const;
    int order() const;

private:
    WallpaperProperty m_property;
};
