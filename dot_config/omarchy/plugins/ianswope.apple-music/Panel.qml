import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar button plus popup for Apple Music. Shows what Apple Music is playing and
// nothing else, because the player it reads is scoped to Apple Music's own
// browser process rather than to the browser as a whole.
Panel {
  id: root
  moduleName: "ianswope.apple-music"
  ipcTarget: "ianswope.apple-music"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)

  // Dimmed while Apple Music is not running, so the bar says at a glance
  // whether there is anything to control.
  readonly property color barIconColor: music.running ? barForeground : Qt.darker(barForeground, 1.7)
  readonly property bool labelVisible: music.barLabel !== ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    music.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: music
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { music.refresh(); return "ok" }
    function status(): string { return music.headline }
    function track(): string {
      if (!music.hasMedia) return ""
      return music.trackArtist === "" ? music.trackTitle : music.trackTitle + " · " + music.trackArtist
    }
    function playpause(): string { music.playPause(); return "ok" }
    function next(): string { music.next(); return "ok" }
    function previous(): string { music.previous(); return "ok" }
    function launch(): string { music.open(); return "ok" }
  }

  TextMetrics {
    id: labelMetrics
    font.family: root.fontFamily
    font.pixelSize: Style.bar.iconFont
    text: music.barLabel
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.iconSlot + (root.labelVisible ? labelMetrics.width + Style.space(3) : 0)
    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.space(3)

          NoteIcon {
            anchors.verticalCenter: parent.verticalCenter
            iconSize: Style.space(11)
            color: root.barIconColor
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.labelVisible
            text: music.barLabel
            textFormat: Text.PlainText
            color: root.barIconColor
            font.family: root.fontFamily
            font.pixelSize: Style.bar.iconFont
            renderType: Text.NativeRendering
          }
        }
      }
    }
    // Right click is the one control worth having without opening anything.
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) music.playPause()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight + Style.space(30), Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: music.open()
      onTextKey: function(t) {
        if (t === "p") music.playPause()
        else if (t === "n") music.next()
        else if (t === "b") music.previous()
        else if (t === "o") music.open()
        else if (t === "r") music.refresh()
      }

      Column {
        id: column
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Apple Music"
          meta: music.headline
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            NoteIcon {
              iconSize: Style.font.display
              color: root.foreground
            }
          }
        }

        // Now playing. Artwork comes from a local file the browser writes, so
        // showing it costs a file read rather than a request back to Apple.
        Row {
          width: parent.width
          visible: music.hasMedia
          spacing: Style.space(12)

          Rectangle {
            id: artFrame
            width: Style.space(74)
            height: width
            radius: Style.space(6)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
            visible: music.showArtwork
            clip: true

            Image {
              id: albumArt
              anchors.fill: parent
              source: music.showArtwork && music.artUrl !== "" ? music.artUrl : ""
              fillMode: Image.PreserveAspectCrop
              sourceSize.width: 148
              sourceSize.height: 148
              asynchronous: true
              cache: false
              visible: status === Image.Ready
            }

            // A placeholder rather than an empty square: a track can arrive
            // before its artwork does, and sometimes without any.
            NoteIcon {
              anchors.centerIn: parent
              iconSize: Style.space(22)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
              // Covers no artwork, artwork that has not arrived, and artwork
              // that failed to load, rather than only the first of the three.
              visible: albumArt.status !== Image.Ready
            }
          }

          Column {
            width: parent.width - (artFrame.visible ? artFrame.width + Style.space(12) : 0)
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: music.trackTitle
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              maximumLineCount: 2
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: music.trackArtist
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              visible: music.trackArtist !== ""
            }

            Text {
              width: parent.width
              text: music.trackAlbum
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              visible: music.trackAlbum !== ""
            }
          }
        }

        // Progress, only when the player actually reports a position.
        Column {
          width: parent.width
          visible: music.hasMedia && music.positionKnown
          spacing: Style.space(4)

          Rectangle {
            width: parent.width
            height: Style.space(3)
            radius: height / 2
            visible: music.lengthKnown
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

            Rectangle {
              width: parent.width * Model.progressFraction(music.trackPosition, music.trackLength)
              height: parent.height
              radius: parent.radius
              color: root.foreground
            }
          }

          Item {
            width: parent.width
            height: elapsed.implicitHeight

            Text {
              id: elapsed
              anchors.left: parent.left
              text: Model.formatDuration(music.trackPosition)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              visible: music.lengthKnown
              text: Model.formatDuration(music.trackLength)
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Nothing playing. Say which of the two reasons it is, because they need
        // different things from the reader.
        Text {
          width: parent.width
          visible: !music.hasMedia
          text: music.running
            ? "Apple Music is open but has not played anything yet."
            : "Apple Music is not running. Press enter to open it."
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSeparator {
          width: parent.width
          foreground: root.foreground
        }

        // Transport. The same glyphs the first-party media widget uses, so the
        // controls do not read as a different kind of thing in the same bar.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          PanelActionButton {
            iconText: "󰒮"
            tooltipText: "Previous"
            foreground: music.canGoPrevious ? root.foreground : root.dim
            fontFamily: root.fontFamily
            enabled: music.canGoPrevious
            onClicked: music.previous()
          }

          PanelActionButton {
            iconText: music.isPlaying ? "󰏤" : "󰐊"
            tooltipText: music.isPlaying ? "Pause" : "Play"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: music.playPause()
          }

          PanelActionButton {
            iconText: "󰒭"
            tooltipText: "Next"
            foreground: music.canGoNext ? root.foreground : root.dim
            fontFamily: root.fontFamily
            enabled: music.canGoNext
            onClicked: music.next()
          }

          PanelActionButton {
            iconText: "󰖟"
            tooltipText: music.running ? "Focus the window" : "Open Apple Music"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: music.open()
          }
        }

        Text {
          width: parent.width
          visible: music.actionStatus !== "" || music.lastError !== ""
          text: music.actionStatus !== "" ? music.actionStatus : music.lastError
          textFormat: Text.PlainText
          color: music.lastError !== "" && music.actionStatus === "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: "p play or pause · n next · b back · o window · esc close"
          textFormat: Text.PlainText
          color: Qt.darker(root.dim, 1.15)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
