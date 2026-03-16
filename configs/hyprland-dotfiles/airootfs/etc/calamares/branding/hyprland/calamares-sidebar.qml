/* =============================================================================
 * calamares-sidebar.qml
 * Mainstream Dotfiles Installer — Top Navigation Rail
 *
 * Styled to match the illogical-impulse (ii) dots-hyprland NavigationRail
 * found in modules/common/widgets/NavigationRailButton.qml and
 * modules/common/widgets/NavigationRailTabArray.qml.
 *
 * Color system: Material Design 3 dark scheme (from ii Appearance.qml).
 * Icons: Material Symbols Rounded (variable font, ligature rendering).
 *        Provided by the illogical-impulse-fonts-themes package on the live ISO.
 * =========================================================================== */

import QtQuick 2.15
import QtQuick.Layouts 1.15
import io.calamares.core 1.0
import io.calamares.ui 1.0

Rectangle {
    id: root

    // ── M3 dark color tokens (ii dots — Appearance.qml m3colors / colors) ──
    readonly property color colBg:           "#1c1b1c"   // surfaceContainerLow
    readonly property color colOnSurface:    "#e6e1e1"   // onBackground
    readonly property color colOnSurfaceVar: "#cbc5ca"   // onSurfaceVariant
    readonly property color colSecCont:      "#4d4b4d"   // secondaryContainer
    readonly property color colOnSecCont:    "#ece6e9"   // onSecondaryContainer
    readonly property color colOutlineVar:   "#49464a"   // outlineVariant
    readonly property color colOutline:      "#948f94"   // outline
    readonly property color colPrimary:      "#cbc4cb"   // primary

    // ── Icon mapping by step index — names come dynamically from ViewManager ─
    // Icons correspond to the `show` sequence in settings.conf:
    //   0=welcome 1=locale 2=keyboard 3=partition 4=users 5=summary 6=finished
    readonly property var stepIcons: [
        "waving_hand",   // Welcome
        "language",      // Location
        "keyboard",      // Keyboard
        "storage",       // Partitions
        "person",        // Users
        "fact_check",    // Summary
        "check_circle"   // Finish
    ]

    // Current step from Calamares — updates automatically as user progresses
    readonly property int currentStep: ViewManager.currentStepIndex

    // ── Root geometry ────────────────────────────────────────────────────────
    implicitHeight: 56
    color: colBg

    // Bottom separator — mirrors the outlineVariant divider in ii panels
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: root.colOutlineVar
    }

    // ── Layout ───────────────────────────────────────────────────────────────
    RowLayout {
        anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
        spacing: 0

        // ── Logo + product name (left) ────────────────────────────────────
        RowLayout {
            Layout.preferredWidth: 175
            Layout.alignment:      Qt.AlignVCenter
            spacing: 10

            Image {
                Layout.preferredWidth:  26
                Layout.preferredHeight: 26
                fillMode:  Image.PreserveAspectFit
                source:    Qt.resolvedUrl("logo.png")
                smooth:    true
                mipmap:    true
            }

            Text {
                text:            "Mainstream"
                font.pixelSize:  14
                font.weight:     Font.Medium
                color:           root.colOnSurface
                renderType:      Text.NativeRendering
            }
        }

        // ── Left flex spacer ──────────────────────────────────────────────
        Item { Layout.fillWidth: true }

        // ── Step pills (centered) ─────────────────────────────────────────
        // Each delegate is an Item containing: [pill rectangle] + [connector]
        // The animated sliding highlight beneath the active pill is handled
        // by the pill's own color Behavior, matching NavigationRailTabArray.
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing:          0

            Repeater {
                model: ViewManager

                delegate: Item {
                    id: stepDel

                    // Per-step state — all bindings re-evaluate when currentStep changes
                    readonly property int  stepIdx:     index
                    readonly property bool isCurrent:   stepIdx === root.currentStep
                    readonly property bool isCompleted: stepIdx <  root.currentStep
                    readonly property bool isFuture:    stepIdx >  root.currentStep

                    // Size: pill + optional right connector
                    implicitWidth:  stepPill.implicitWidth
                                    + (stepIdx < ViewManager.count - 1
                                       ? connector.implicitWidth + 4
                                       : 0)
                    implicitHeight: 56

                    // ── Step pill ─────────────────────────────────────────
                    Rectangle {
                        id: stepPill
                        anchors {
                            left:           parent.left
                            verticalCenter: parent.verticalCenter
                        }
                        implicitWidth:  pillContent.implicitWidth + 24
                        implicitHeight: 36
                        radius:         9999    // full pill — Appearance.rounding.full

                        // Active → secondaryContainer fill; idle → transparent
                        color: stepDel.isCurrent ? root.colSecCont : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }

                        // ── Icon + label row (mirrors NavigationRailButton expanded mode)
                        Row {
                            id: pillContent
                            anchors.centerIn:      parent
                            spacing:               6
                            verticalItemAlignment: Qt.AlignVCenter

                            // Material Symbols Rounded icon via OpenType ligature
                            Text {
                                font.family:       "Material Symbols Rounded"
                                font.pixelSize:    18
                                // Variable-font axes: FILL animates outline↔filled
                                font.variableAxes: ({
                                    "FILL": (stepDel.isCurrent || stepDel.isCompleted) ? 1 : 0,
                                    "opsz": 18
                                })
                                renderType:        Text.NativeRendering
                                text:              root.stepIcons[stepDel.stepIdx] || "radio_button_unchecked"
                                color:             stepDel.isCurrent   ? root.colOnSecCont
                                                 : stepDel.isCompleted ? root.colOnSurface
                                                 :                       root.colOnSurfaceVar
                                opacity:           stepDel.isFuture ? 0.45 : 1.0
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            // Step label — name comes directly from ViewManager model
                            Text {
                                text:            display
                                font.pixelSize:  13
                                font.weight:     stepDel.isCurrent ? Font.Medium : Font.Normal
                                renderType:      Text.NativeRendering
                                color:           stepDel.isCurrent   ? root.colOnSecCont
                                               : stepDel.isCompleted ? root.colOnSurface
                                               :                       root.colOnSurfaceVar
                                opacity:         stepDel.isFuture ? 0.45 : 1.0
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }
                    }

                    // ── Connector line between steps ──────────────────────
                    // Mirrors the progress line pattern in the ii settings panel
                    Rectangle {
                        id: connector
                        visible:        stepDel.stepIdx < ViewManager.count - 1
                        anchors {
                            left:           stepPill.right
                            leftMargin:     4
                            verticalCenter: parent.verticalCenter
                        }
                        implicitWidth:  18
                        height:         1
                        radius:         1
                        color:          stepDel.isCompleted ? root.colOutline : root.colOutlineVar
                        opacity:        stepDel.isFuture    ? 0.3            : 1.0
                        Behavior on color   { ColorAnimation { duration: 200 } }
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }
            }
        }

        // ── Right flex spacer ─────────────────────────────────────────────
        Item { Layout.fillWidth: true }

        // ── Right balance — mirrors the logo area width so steps stay centred
        Item { Layout.preferredWidth: 175 }
    }
}
