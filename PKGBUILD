# Maintainer: Moon-Haze <swx1126200515@outlook.com>
# 原始项目作者: Marcel Richter <Richter02@protonmail.com>
# 上游: https://github.com/Marcel1202/HTMLWallpaper

pkgname=plasma-htmlwallpaper
pkgver=1.0.0
pkgrel=1
pkgdesc="KDE Plasma 6 HTML wallpaper plugin - set any HTML page as desktop wallpaper with mouse interaction"
arch=('x86_64')
url="https://github.com/Moon-Haze/HTMLWallpaper"
license=('LGPL-2.1-or-later')
depends=(
  'libplasma>=6.6.90'
  'qt6-base>=6.10.0'
  'qt6-declarative>=6.10.0'
  'qt6-webengine>=6.10.0'
)
makedepends=(
  'extra-cmake-modules>=6.26.0'
  'cmake'
  'ninja'
)
source=("${pkgname}::git+https://github.com/Moon-Haze/HTMLWallpaper.git")
sha256sums=('SKIP')

# 注意：pkgver 固定为 1.0.0。若改为动态版本号（基于 git tag/commit），
# 需要添加 pkgver() 函数并确保其返回非空值。

build() {
  cd "$pkgname"
  cmake -B build \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib
  cmake --build build
}

package() {
  cd "$pkgname"
  DESTDIR="$pkgdir" cmake --install build
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
