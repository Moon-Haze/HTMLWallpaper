/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/**
 * HTMLWallpaper 配置界面的独立调试入口（开发分支 dev/config-app）。
 *
 * 真实环境里 config.qml 由 plasmashell/KCM 加载并注入 wallpaper、
 * configDialog、cfg_* 等上下文；本程序用 DevShell.qml 在 QML 层 mock 掉
 * 这些注入，让 config.qml 原样跑在一个普通 Qt 桌面窗口里，附带一个
 * WebEngine 预览面板实时渲染选中的 HTML 壁纸，便于脱离 KDE 快速迭代。
 *
 * 用法：
 *   htmlwallpaper-config-dev                      # 交互式窗口
 *   htmlwallpaper-config-dev --screenshot out.png # 渲染稳定后自截图退出（离屏验证）
 *
 * QML import 路径：系统 KDE 模块（Kirigami/KCMUtils/plasma.wallpapers.image
 * 等）在标准 Qt QML 路径下自动解析；config.qml 及其子组件用相对路径加载。
 */
#include "DevConfigMap.h"

#include <QGuiApplication>
#include <QImage>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlError>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>

// 说明：HTMLBackend（C++）内部用 QFile 直接读 project.json，不再需要旧的
// fileReader QML XHR hack（HtmlWallpaperParser 时代 dev 环境 XHR 的 file://
// 回调不触发才需要注入同步读取器）。

int main(int argc, char* argv[])
{
    // WebEngine 沙箱在部分环境（容器 / 无 user namespaces）会启动失败；
    // dev 工具直接关闭，避免启动即崩。
    qputenv("QTWEBENGINE_DISABLE_SANDBOX", "1");
    // 本会话 Qt 日志被重定向，QML console.log 默认不可见；强制打到 stderr
    qputenv("QT_FORCE_STDERR_LOGGING", "1");
    qputenv("QT_LOGGING_TO_CONSOLE", "1");
    QGuiApplication app(argc, argv);
    // 不依赖 KDE 桌面风格，dev 程序用 Qt 自带 Fusion 即可
    QQuickStyle::setStyle(QStringLiteral("Fusion"));

    // --screenshot <path>：渲染稳定后自截图保存并退出（外部截图工具在
    // Wayland 下不可靠，用 Qt 自身 grabWindow 离屏抓取）。
    QString shotPath;
    if (argc >= 3 && QString::fromLatin1(argv[1]) == QLatin1String("--screenshot")) {
        shotPath = QString::fromLocal8Bit(argv[2]);
    }

    QQmlApplicationEngine engine;
    // config.qml import com.github.moon_haze.htmlwallpaper（backend QML 模块，
    // 构建产物在 build/bin/<URI>）；显式加 import 路径，与系统 Qt QML 路径并存
    engine.addImportPath(QStringLiteral(HTMLWALLPAPER_IMPORT_DIR));
    // mock wallpaper.configuration（KConfigPropertyMap）：C++ 动态属性提供
    // 大写 key（DisplayPage/PreviewImage/…），纯 QML QtObject 做不到。
    engine.rootContext()->setContextProperty(QStringLiteral("devConfigMap"),
        new DevConfigMap(&engine));
    // 加载失败时打印每个 QML 错误（默认只打一行到 stderr，信息不足）
    QObject::connect(&engine, &QQmlApplicationEngine::warnings,
        [](const QList<QQmlError>& warnings) {
            for (const QQmlError& e : warnings) {
                qWarning().noquote() << "[dev] QML 警告:" << e.toString();
            }
        });
    engine.load(QUrl::fromLocalFile(QStringLiteral(DEV_QML_DIR "/DevShell.qml")));
    if (engine.rootObjects().isEmpty()) {
        qWarning().noquote() << "[dev] DevShell.qml 加载失败";
        return -1;
    }
    qWarning().noquote() << "[dev] DevShell.qml 加载成功";

    if (!shotPath.isEmpty()) {
        QTimer::singleShot(5000, [&]() {
            if (auto* w = qobject_cast<QQuickWindow*>(engine.rootObjects().first())) {
                const QImage img = w->grabWindow();
                const bool ok = img.save(shotPath);
                qWarning().noquote() << "[dev] 截图保存:" << shotPath << ok
                                     << img.size().width() << "x" << img.size().height();
            } else {
                qWarning().noquote() << "[dev] 未找到窗口对象，无法截图";
            }
            app.exit(0);
        });
    }
    return app.exec();
}
