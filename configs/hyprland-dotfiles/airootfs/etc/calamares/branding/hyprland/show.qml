/* =============================================================================
 * show.qml — Mainstream OS installer slideshow.
 *
 * Each slide is a self-contained 3696x2016 PNG (1.833:1 — exactly 3× the
 * 1232x672 slideshow pane Calamares allocates inside our 1500x800 branded
 * window; see render-slides.sh for the full geometry breakdown) rendered
 * from the SVG masters in ./sources/. The PNGs bake in their own titles,
 * body copy, tickers, and brand-mark composition (Stream gradient,
 * Abyss/Night palette, DM Sans / Google Sans Flex, JetBrains Mono). The
 * QML side just rotates them — no overlay text, no per-slide layout.
 * To edit a slide:
 *   1. Edit the SVG in ./sources/.
 *   2. Run ./sources/render-slides.sh to re-export the PNG.
 *
 * slideshowAPI: 2 — onActivate / onLeave fire from Calamares.
 * =========================================================================== */

import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    readonly property color colBg: "#0B0D12"

    Rectangle {
        anchors.fill: parent
        color:        presentation.colBg
        z:            -100
    }

    Timer {
        id: slideTimer
        interval: 9000
        repeat:   true
        running:  false
        onTriggered: presentation.goToNextSlide()
    }

    function onActivate() { slideTimer.running = true  }
    function onLeave()    { slideTimer.running = false }

    // ──────────────────────────────────────────────────────────────────────
    // Slide.qml in the Calamares QML library positions every Slide as a
    // "content area" with 20% top margin, 10% bottom, and 5% left/right
    // (see src/qml/calamares-qt6/slideshow/Slide.qml lines 89–93). Our
    // PNGs are designed to fill the *entire* slideshow pane, so we override
    // x/y/width/height in each Slide to defeat those defaults — otherwise
    // the Image (which anchors to the Slide, not the Presentation) renders
    // into only the middle 70% × 90% of the pane and leaves black bars.
    // ──────────────────────────────────────────────────────────────────────

    Slide {
        x: 0; y: 0; width: parent.width; height: parent.height
        Image {
            anchors.fill: parent
            source:       "slide_welcome.png"
            fillMode:     Image.PreserveAspectCrop
            smooth:       true
            mipmap:       true
        }
    }

    Slide {
        x: 0; y: 0; width: parent.width; height: parent.height
        Image {
            anchors.fill: parent
            source:       "slide_themes.png"
            fillMode:     Image.PreserveAspectCrop
            smooth:       true
            mipmap:       true
        }
    }

    Slide {
        x: 0; y: 0; width: parent.width; height: parent.height
        Image {
            anchors.fill: parent
            source:       "slide_layouts.png"
            fillMode:     Image.PreserveAspectCrop
            smooth:       true
            mipmap:       true
        }
    }

    Slide {
        x: 0; y: 0; width: parent.width; height: parent.height
        Image {
            anchors.fill: parent
            source:       "slide_keybinds.png"
            fillMode:     Image.PreserveAspectCrop
            smooth:       true
            mipmap:       true
        }
    }

    Slide {
        x: 0; y: 0; width: parent.width; height: parent.height
        Image {
            anchors.fill: parent
            source:       "slide_maintenance.png"
            fillMode:     Image.PreserveAspectCrop
            smooth:       true
            mipmap:       true
        }
    }

    Slide {
        x: 0; y: 0; width: parent.width; height: parent.height
        Image {
            anchors.fill: parent
            source:       "slide_almost_there.png"
            fillMode:     Image.PreserveAspectCrop
            smooth:       true
            mipmap:       true
        }
    }
}
