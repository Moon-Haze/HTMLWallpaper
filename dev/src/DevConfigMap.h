/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QString>
#include <QVariant>

/**
 * KConfigPropertyMap 的 dev mock（开发分支 dev/config-app）。
 *
 * 真实环境里 wallpaper.configuration 是 KConfigPropertyMap：它通过 QObject
 * 的**动态属性**提供大写开头的配置键（SelectWallpaper / PreviewImage / Image…）。
 * QML 静态属性不允许大写开头（`property string SelectWallpaper` 会让整个组件
 * 静默加载失败），所以 mock 不能写成纯 QML QtObject，必须用 C++ QObject：
 * 构造时 setProperty 预注册全部键，QML 即可 `cfg.PreviewImage` 点访问 / 赋值，
 * 行为与真实 KConfigPropertyMap 基本一致（仅内存，不持久化）。
 */
class DevConfigMap : public QObject
{
    Q_OBJECT

public:
    explicit DevConfigMap(QObject *parent = nullptr);

    // 运行时读写任意配置键（KConfigPropertyMap 风格）
    Q_INVOKABLE void setValue(const QString &key, const QVariant &value);
    Q_INVOKABLE QVariant value(const QString &key) const;
    // 真实环境 writeConfig() 持久化；dev 仅内存，空实现
    Q_INVOKABLE void writeConfig()
    {
    }
};
