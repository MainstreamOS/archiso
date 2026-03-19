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
    readonly property color colPrimary:      "#cfbcff"
    readonly property color colSecCont:      "#4d4b4d"
    readonly property color colOnSecCont:    "#ece6e9"
    readonly property color colOutlineVar:   "#49464a"

    // ── Background fill ───────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:        "#141313"
        z:            -100
    }

    // ── Slideshow lifecycle (API v2) ─────────────────────────────────────────
    Timer {
        id: slideTimer
        interval: 7000
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

            // Full-bleed welcome image
            Image {
                anchors.fill: parent
                source:       "welcome.png"
                fillMode:     Image.PreserveAspectCrop
                opacity:      0.85
                smooth:       true
                mipmap:       true
            }

            // Subtle dark vignette over bottom third so caption is readable
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: parent.height * 0.35
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "#cc141313"   }
                }
            }

            // Caption
            ColumnLayout {
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 28
                }
                spacing: 6

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text:             "Installing Mainstream"
                    font.pixelSize:   22
                    font.weight:      Font.Medium
                    color:            presentation.colOnSurface
                    renderType:       Text.NativeRendering
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text:             "Hyprland · illogical-impulse · Material Design 3"
                    font.pixelSize:   13
                    color:            presentation.colOnSurfaceVar
                    renderType:       Text.NativeRendering
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 2 — Desktop overview
    // ════════════════════════════════════════════════════════════════════════
    Slide {
        Rectangle {
            anchors.fill: parent
            color: presentation.colBg

            Image {
                anchors.fill: parent
                source:       "slide_desktop.png"
                fillMode:     Image.PreserveAspectFit
                smooth:       true
                mipmap:       true
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 3 — App launcher
    // ════════════════════════════════════════════════════════════════════════
    Slide {
        Rectangle {
            anchors.fill: parent
            color: presentation.colBg

            Image {
                anchors.fill: parent
                source:       "slide_launcher.png"
                fillMode:     Image.PreserveAspectFit
                smooth:       true
                mipmap:       true
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 4 — Status bar tour
    // ════════════════════════════════════════════════════════════════════════
    Slide {
        Rectangle {
            anchors.fill: parent
            color: presentation.colBg

            Image {
                anchors.fill: parent
                source:       "slide_bar.png"
                fillMode:     Image.PreserveAspectFit
                smooth:       true
                mipmap:       true
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 5 — Essential shortcuts
    // ════════════════════════════════════════════════════════════════════════
    Slide {
        Rectangle {
            anchors.fill: parent
            color: presentation.colBg

            Image {
                anchors.fill: parent
                source:       "slide_tips.png"
                fillMode:     Image.PreserveAspectFit
                smooth:       true
                mipmap:       true
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // SLIDE 6 — After installation
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
                    text:             "Almost there!"
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
                        spacing: 14

                        Repeater {
                            model: [
                                { icon: "download",         text: "AUR packages complete on first boot — internet required"  },
                                { icon: "settings_suggest", text: "SDDM, NetworkManager, PipeWire and cups pre-configured"   },
                                { icon: "palette",          text: "Colors adapt to your wallpaper via matugen"               },
                                { icon: "open_in_new",      text: "github.com/gregorytrentmartinjr/dots-hyprland"            }
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

                Text {
                    Layout.alignment:    Qt.AlignHCenter
                    text:                "Your system will be ready shortly — enjoy Mainstream!"
                    font.pixelSize:      13
                    color:               presentation.colPrimary
                    horizontalAlignment: Text.AlignHCenter
                    renderType:          Text.NativeRendering
                }
            }
        }
    }
}
