/* =============================================================================
 * show.qml — Mainstream Dotfiles Installer Slideshow
 *
 * Displayed during the exec (installation) phase.
 * Styled to match the illogical-impulse (ii) dark M3 theme.
 * Uses slideshowAPI: 2 (async load, onActivate / onLeave lifecycle).
 * =========================================================================== */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    // ── M3 dark color tokens ─────────────────────────────────────────────────
    readonly property color colBg:           "#141313"
    readonly property color colSurface:      "#1c1b1c"
    readonly property color colSurfaceHigh:  "#2b2a2a"
    readonly property color colOnSurface:    "#e6e1e1"
    readonly property color colOnSurfaceVar: "#cbc5ca"
    readonly property color colPrimary:      "#cbc4cb"
    readonly property color colSecCont:      "#4d4b4d"
    readonly property color colOnSecCont:    "#ece6e9"
    readonly property color colOutlineVar:   "#49464a"

    // ── Slideshow lifecycle (API v2) ─────────────────────────────────────────
    Timer {
        id: slideTimer
        interval: 6000
        repeat:   true
        running:  false
        onTriggered: presentation.goToNextSlide()
    }

    function onActivate() { slideTimer.running = true  }
    function onLeave()    { slideTimer.running = false }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 1 — Welcome
    // ════════════════════════════════════════════════════════════════════════
    Slide {
        Rectangle {
            anchors.fill: parent
            color: presentation.colBg

            // Faint branded background
            Image {
                anchors.fill:    parent
                source:          "welcome.png"
                fillMode:        Image.PreserveAspectCrop
                opacity:         0.07
                smooth:          true
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing:          20
                width:            Math.min(parent.width * 0.72, 580)

                // Product icon
                Image {
                    Layout.alignment:       Qt.AlignHCenter
                    Layout.preferredWidth:  64
                    Layout.preferredHeight: 64
                    source:                 "logo.png"
                    fillMode:              Image.PreserveAspectFit
                    smooth:                true
                    mipmap:                true
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text:             "Installing Mainstream"
                    font.pixelSize:   26
                    font.weight:      Font.Medium
                    color:            presentation.colOnSurface
                    renderType:       Text.NativeRendering
                }

                Text {
                    Layout.alignment:    Qt.AlignHCenter
                    Layout.fillWidth:    true
                    text:                "Setting up your system with Hyprland + illogical-impulse dotfiles"
                    font.pixelSize:      15
                    color:               presentation.colOnSurfaceVar
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode:            Text.WordWrap
                    renderType:          Text.NativeRendering
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 2 — What's being installed
    // ════════════════════════════════════════════════════════════════════════
    Slide {
        Rectangle {
            anchors.fill: parent
            color: presentation.colBg

            ColumnLayout {
                anchors.centerIn: parent
                spacing:          24
                width:            Math.min(parent.width * 0.72, 560)

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text:             "What's being installed"
                    font.pixelSize:   22
                    font.weight:      Font.Medium
                    color:            presentation.colOnSurface
                    renderType:       Text.NativeRendering
                }

                // Card-style list
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight:   itemCol.implicitHeight + 32
                    color:            presentation.colSurface
                    radius:           17

                    ColumnLayout {
                        id: itemCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 12

                        Repeater {
                            model: [
                                { icon: "desktop_windows", text: "Hyprland window manager"              },
                                { icon: "view_quilt",      text: "Quickshell status bar & shell"        },
                                { icon: "graphic_eq",      text: "PipeWire full audio stack"            },
                                { icon: "bluetooth",       text: "Bluetooth & printing support"         },
                                { icon: "wifi",            text: "NetworkManager for WiFi"              },
                                { icon: "palette",         text: "illogical-impulse dotfiles & themes"  }
                            ]

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Text {
                                    font.family:       "Material Symbols Rounded"
                                    font.pixelSize:    18
                                    font.variableAxes: ({ "FILL": 1, "opsz": 18 })
                                    text:              modelData.icon
                                    color:             presentation.colPrimary
                                    renderType:        Text.NativeRendering
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text:             modelData.text
                                    font.pixelSize:   14
                                    color:            presentation.colOnSurfaceVar
                                    renderType:       Text.NativeRendering
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 3 — After installation
    // ════════════════════════════════════════════════════════════════════════
    Slide {
        Rectangle {
            anchors.fill: parent
            color: presentation.colBg

            ColumnLayout {
                anchors.centerIn: parent
                spacing:          24
                width:            Math.min(parent.width * 0.72, 560)

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text:             "After installation"
                    font.pixelSize:   22
                    font.weight:      Font.Medium
                    color:            presentation.colOnSurface
                    renderType:       Text.NativeRendering
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight:   afterCol.implicitHeight + 32
                    color:            presentation.colSurface
                    radius:           17

                    ColumnLayout {
                        id: afterCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 12

                        Repeater {
                            model: [
                                { icon: "download",         text: "AUR packages install automatically on first boot"   },
                                { icon: "settings_suggest", text: "Services configured: SDDM, NetworkManager, cups…"   },
                                { icon: "wifi_tethering",   text: "Internet required on first boot to finish setup"    },
                                { icon: "open_in_new",      text: "github.com/gregorytrentmartinjr/dots-hyprland"      }
                            ]

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Text {
                                    font.family:       "Material Symbols Rounded"
                                    font.pixelSize:    18
                                    font.variableAxes: ({ "FILL": 1, "opsz": 18 })
                                    text:              modelData.icon
                                    color:             presentation.colPrimary
                                    renderType:        Text.NativeRendering
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text:             modelData.text
                                    font.pixelSize:   14
                                    color:            presentation.colOnSurfaceVar
                                    wrapMode:         Text.WordWrap
                                    renderType:       Text.NativeRendering
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 4 — Key bindings quick reference
    // ════════════════════════════════════════════════════════════════════════
    Slide {
        Rectangle {
            anchors.fill: parent
            color: presentation.colBg

            ColumnLayout {
                anchors.centerIn: parent
                spacing:          24
                width:            Math.min(parent.width * 0.72, 560)

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text:             "Quick reference"
                    font.pixelSize:   22
                    font.weight:      Font.Medium
                    color:            presentation.colOnSurface
                    renderType:       Text.NativeRendering
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight:   keysCol.implicitHeight + 32
                    color:            presentation.colSurface
                    radius:           17

                    ColumnLayout {
                        id: keysCol
                        anchors { fill: parent; margins: 16 }
                        spacing: 10

                        Repeater {
                            model: [
                                { key: "Super + Return",   action: "Open terminal (kitty)"     },
                                { key: "Super + R",        action: "App launcher"               },
                                { key: "Super + Q",        action: "Close window"               },
                                { key: "Super + 1-3",      action: "Switch workspace"           },
                                { key: "Super + Shift + C","action": "Reopen Calamares"         }
                            ]

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                Rectangle {
                                    implicitWidth:  keyLabel.implicitWidth + 16
                                    implicitHeight: keyLabel.implicitHeight + 8
                                    color:          presentation.colSurfaceHigh
                                    radius:         6

                                    Text {
                                        id: keyLabel
                                        anchors.centerIn: parent
                                        text:             modelData.key
                                        font.pixelSize:   12
                                        font.weight:      Font.Medium
                                        color:            presentation.colPrimary
                                        renderType:       Text.NativeRendering
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text:             modelData.action
                                    font.pixelSize:   14
                                    color:            presentation.colOnSurfaceVar
                                    renderType:       Text.NativeRendering
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
