/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QVariantList>

/**
 * @brief 单个可配置属性项（HTMLBackend::currentProperties 的元素）。
 *
 * 以 QObject 形式暴露给 QML 的可观察属性：PropertyPanel 直接读写
 * 这些 Q_PROPERTY（propValue 写回走 setter，C++ 侧数据同步更新，
 * buildPropertiesJson() 才能序列化最新值）。字段与 Wallpaper Engine
 * project.json 的 general.properties 一一对应。
 */
class HTMLPropertyItem : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString key READ key WRITE setKey NOTIFY changed)
    Q_PROPERTY(QString type READ type WRITE setType NOTIFY changed)
    Q_PROPERTY(QString text READ text WRITE setText NOTIFY changed)
    Q_PROPERTY(QVariant propValue READ propValue WRITE setPropValue NOTIFY changed)
    Q_PROPERTY(QVariant min READ min WRITE setMin NOTIFY changed)
    Q_PROPERTY(QVariant max READ max WRITE setMax NOTIFY changed)
    Q_PROPERTY(QVariant step READ step WRITE setStep NOTIFY changed)
    Q_PROPERTY(QVariant fraction READ fraction WRITE setFraction NOTIFY changed)
    Q_PROPERTY(QVariant precision READ precision WRITE setPrecision NOTIFY changed)
    Q_PROPERTY(QVariantList options READ options WRITE setOptions NOTIFY changed)
    Q_PROPERTY(QString condition READ condition WRITE setCondition NOTIFY changed)
    Q_PROPERTY(QString group READ group WRITE setGroup NOTIFY changed)
    Q_PROPERTY(int order READ order WRITE setOrder NOTIFY changed)

public:
    explicit HTMLPropertyItem(QObject *parent = nullptr);

    QString key() const;
    void setKey(const QString &key);
    QString type() const;
    void setType(const QString &type);
    QString text() const;
    void setText(const QString &text);
    QVariant propValue() const;
    void setPropValue(const QVariant &propValue);
    QVariant min() const;
    void setMin(const QVariant &min);
    QVariant max() const;
    void setMax(const QVariant &max);
    QVariant step() const;
    void setStep(const QVariant &step);
    QVariant fraction() const;
    void setFraction(const QVariant &fraction);
    QVariant precision() const;
    void setPrecision(const QVariant &precision);
    QVariantList options() const;
    void setOptions(const QVariantList &options);
    QString condition() const;
    void setCondition(const QString &condition);
    QString group() const;
    void setGroup(const QString &group);
    int order() const;
    void setOrder(int order);

Q_SIGNALS:
    void changed();

private:
    QString m_key;
    QString m_type;
    QString m_text;
    QVariant m_propValue;
    QVariant m_min;
    QVariant m_max;
    QVariant m_step;
    QVariant m_fraction;
    QVariant m_precision;
    QVariantList m_options;
    QString m_condition;
    QString m_group;
    int m_order = 0;
};
