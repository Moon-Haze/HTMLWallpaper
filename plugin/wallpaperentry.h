/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/** @file wallpaperentry.h
 * HTML 壁纸元数据值类型（WallpaperEntry）与目录探测辅助接口
 * （WallpaperPath / ScanGroup / ScanResult）声明。
 * 全部为纯值类型，后台扫描线程可安全构造。
 */

#pragma once

#include <QList>
#include <QPair>
#include <QString>
#include <QStringList>

/**
 * @brief 通用路径工具：目录 URL 归一化与拼接。
 * @note 被 WallpaperController 与数据层复用；URL 形如 file:///path/to/dir。
 */
namespace WallpaperPath
{
/**
 * @brief 把本地路径归一化为 URL（已含 :// 则原样返回，否则前缀 file://）。
 * @param path 本地路径或已归一化的 URL。
 * @return 归一化后的 URL 字符串。
 */
QString toUrl(const QString &path);
/**
 * @brief 拼接两个 URL 段，自动去掉 a 的末尾斜杠与 b 的前导斜杠。
 * @param a 前段 URL。
 * @param b 后段路径/URL。
 * @return 拼接后的 URL，形如 a/b。
 */
QString pathJoin(const QString &a, const QString &b);
} // namespace WallpaperPath

class WallpaperEntry;

/**
 * @brief 单个扫描根（文件夹）在目录探测后产生的壁纸分组。
 */
struct ScanGroup {
    QString key; // 扫描根 URL（WallpaperPath::toUrl 归一化）
    QList<WallpaperEntry> entries; // 该根下探测到的壁纸
};

/**
 * @brief 一次全量扫描的结果：按 roots 遍历顺序归组 + 失败路径列表。
 */
struct ScanResult {
    QList<ScanGroup> groups; // 按 roots 遍历顺序保序
    QList<QPair<QString, QString>> failures; // (path, error)
};

/**
 * @brief 单个 HTML 壁纸的元数据（值类型，目录探测产物）。
 *
 * 无 QObject、可拷贝/移动，后台线程可安全构造。默认构造 = 无效标记；
 * 显式构造时枚举 <dir>/ 下的 *.html 选入口、探测预览图，目录缺失或无 html
 * → 保持无效。title 即目录名；source/display 为 file/title 兼容别名。
 */
class WallpaperEntry
{
public:
    /**
     * @brief 默认构造：仅置无效标记，等价"探测失败"的空对象。
     */
    WallpaperEntry() = default;
    /**
     * @brief 从目录 URL 探测元数据（选入口、找预览图）。
     * @param dirUrl 目录 URL（形如 file:///.../壁纸目录）。
     * @note 目录缺失或目录下无 *.html 时保持无效（isValid() == false）。
     */
    explicit WallpaperEntry(const QString &dirUrl);
    /**
     * @brief 该条目是否有效（目录存在且选到了 *.html 入口）。
     * @return true 有效 / false 无效（默认构造或探测失败）。
     */
    bool isValid() const;

    /**
     * @brief 目录名（basename；兼容别名为 title）。
     * @return 目录名。
     */
    QString name() const;
    /**
     * @brief 目录 URL（构造时原样保留）。
     * @return 目录 URL。
     */
    QString path() const;
    /**
     * @brief 探测选出的 *.html 入口 URL（兼容别名为 source）。
     * @return 入口文件 URL。
     */
    QString file() const;
    /**
     * @brief 探测到的预览图 URL（preview.png 等常用名）；无预览返回空串。
     * @return 预览图 URL；无预览时为空串。
     */
    QString preview() const;

private:
    QString m_name; // 目录名
    QString m_path; // 目录 URL
    QString m_file; // 选出的 *.html 入口 URL
    QString m_preview; // 预览图 URL（可能为空）
    bool m_valid = false; // 探测成功标记（默认构造/失败 = false）
};
