/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QPair>
#include <QString>
#include <QStringList>

// 通用路径工具（scanPaths 归一化 + 目录拼接），被 Controller 与数据层复用。
namespace WallpaperPath
{
QString toUrl(const QString &path);
QString pathJoin(const QString &a, const QString &b);
} // namespace WallpaperPath

class WallpaperEntry;

struct ScanResult {
    QList<WallpaperEntry> projects; // 解析结果
    QList<QPair<QString, QString>> failures; // (path, error)
};

/**
 * 单个 HTML 壁纸的元数据（值类型，目录探测）。
 * 无 QObject、可拷贝/移动，后台线程可安全构造。默认构造 = 无效标记；
 * 显式构造时枚举 <dir>/ 下的 *.html 选入口、探测预览图，目录缺失或无 html
 * → 保持无效。title 即目录名；source/display 为 file/title 兼容别名。
 */
class WallpaperEntry
{
public:
    WallpaperEntry() = default;
    explicit WallpaperEntry(const QString &dirUrl);
    bool isValid() const;

    QString name() const;
    QString title() const;
    QString path() const;
    QString file() const;
    QString source() const;
    QString display() const;
    QString preview() const;

private:
    QString m_name;
    QString m_path;
    QString m_file;
    QString m_preview;
    bool m_valid = false;
};
