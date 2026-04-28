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

    // ── Mainstream OS brand tokens (see brand.html) ─────────────────────────
    readonly property color colBg:           "#0B0D12"   // Abyss
    readonly property color colSurface:      "#191A1F"   // Night
    readonly property color colSurfaceHigh:  "#2A2B32"   // Slate
    readonly property color colOnSurface:    "#ECE9E3"   // Ink
    readonly property color colOnSurfaceVar: "#9397A0"   // Mist
    readonly property color colPrimary:      "#1F87D8"   // Stream B
    readonly property color colSecCont:      "#2A2B32"   // Slate
    readonly property color colOnSecCont:    "#C9CCD4"   // Bone
    readonly property color colOutlineVar:   "#40434A"   // Graphite

    // ── Background fill ───────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color:        "#0B0D12"
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
                    GradientStop { position: 1.0; color: "#cc0B0D12"   }
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
                    text:             "Hyprland · Mainstream OS · Material Design 3"
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
                                { icon: "open_in_new",      text: "github.com/MainstreamOS/dots-hyprland"                    }
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
