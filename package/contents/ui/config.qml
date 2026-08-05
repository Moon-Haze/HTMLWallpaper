/*
 * Copyright (C) 2020 by Marcel Richter <Richter02@protonmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Library General Public License as
 * published by the Free Software Foundation; either version 2 or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami


Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout
    property alias cfg_DisplayPage: displayPageField.text
    property alias cfg_ZoomFactor: zoomFactorSlider.value
    property alias cfg_InsecureHTTPS: insecureHTTPSCheckBox.checked

    RowLayout {
        Layout.topMargin: 10
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "URL:")
        }
        TextField {
            id: displayPageField
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: 320
        }
    }

    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "Web:")
        }
        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignLeft

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", " https://yourwebsite.com")
        }
    }

    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "Local:")
        }
        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignLeft

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", " file:///absolute/path/to/your/website.html")
        }
    }
        
    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "Zoom:")
        }
        Slider{
            id: zoomFactorSlider
            from: 0.5
            to: 3.0
            stepSize: 0.5
            snapMode: Slider.SnapAlways
        }
    }

    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight
        }
        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignLeft

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "0.5       1       1.5        2       2.5       3")
        }
    }

    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "Insecure HTTPS")
        }
        CheckBox {
            id: insecureHTTPSCheckBox

            ToolTip {
                text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "Ignore HTTPS errors")
                visible: parent.hovered
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
