/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "DevConfigMap.h"

#include <QColor>
#include <QStringList>

DevConfigMap::DevConfigMap(QObject* parent)
    : QObject(parent)
{
    // 预注册动态属性：QML 点访问（cfg.PreviewImage）与赋值都要求属性已存在，
    // 否则运行时报 "Cannot assign to non-existent property"。
    // 键与 package/contents/config/main.xml 一致，大写开头（动态属性允许，
    // 静态属性不允许）。
    setProperty("DisplayPage", QString());
    setProperty("ZoomFactor", 1.0);
    setProperty("InsecureHTTPS", false);
    setProperty("WallpaperProperties", QStringLiteral("{}"));
    setProperty("FillMode", 2); // Image.Stretch
    setProperty("SlidePaths", QStringList { });
    setProperty("SlideInterval", 900);
    setProperty("UncheckedSlides", QStringList { });
    setProperty("SlideshowMode", 0);
    setProperty("SlideshowFoldersFirst", false);
    setProperty("DynamicMode", 0u);
    setProperty("DarkLightScheduleState", QStringLiteral("light"));
    setProperty("ForceImageAnimation", false);
    // 内部预览标记：config.qml 会读写（"null" 表示未指定）
    setProperty("PreviewImage", QStringLiteral("null"));
}

void DevConfigMap::setValue(const QString& key, const QVariant& value)
{
    setProperty(key.toUtf8().constData(), value);
}

QVariant DevConfigMap::value(const QString& key) const
{
    return property(key.toUtf8().constData());
}
