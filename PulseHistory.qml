// "Recently played": a row of small covers. Hover one to see what it was,
// click it to play it again.
import QtQuick
import QtQuick.Effects
import qs.Commons

Item {
  id: h

  property var items: []             // newest first, current track excluded
  property bool live: false          // card open: load the covers
  property color fg: "white"
  property color accent: "white"
  property string fontFamily: Style.font.family

  signal play(string uri)

  readonly property real thumb: Style.space(44)
  readonly property real gap: Style.space(8)
  readonly property int fits: Math.max(1, Math.floor((width + gap) / (thumb + gap)))
  readonly property var shown: items.slice(0, fits)
  property var hovered: null

  implicitHeight: caption.implicitHeight + Style.space(6) + thumb

  Text {
    id: caption
    width: parent.width
    text: h.hovered ? h.hovered.title + (h.hovered.artist ? "  —  " + h.hovered.artist : "") : "Recently played"
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: Util.alpha(h.fg, h.hovered ? 0.85 : 0.5)
    font.family: h.fontFamily
    font.pixelSize: Style.font.caption
    Behavior on color { ColorAnimation { duration: Style.duration(160) } }
  }

  Row {
    anchors.bottom: parent.bottom
    spacing: h.gap

    Repeater {
      model: h.shown

      Item {
        id: tile
        required property var modelData
        required property int index
        width: h.thumb
        height: h.thumb
        scale: area.pressed ? 0.9 : (area.containsMouse ? 1.08 : 1)
        Behavior on scale { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutBack; easing.overshoot: 2.5 } }

        Item {
          id: art
          anchors.fill: parent
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: tileMask
          }
          Rectangle {
            anchors.fill: parent
            color: Util.alpha(h.fg, 0.08)
            Text {
              anchors.centerIn: parent
              text: "󰝚"
              color: Util.alpha(h.fg, 0.35)
              font.family: h.fontFamily
              font.pixelSize: Style.font.icon
            }
          }
          Image {
            anchors.fill: parent
            source: h.live ? String(tile.modelData.art || "") : ""
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(240) } }
          }
          // Play hint on hover.
          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
            opacity: area.containsMouse ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
            Text {
              anchors.centerIn: parent
              text: "󰐊"
              color: "white"
              font.family: h.fontFamily
              font.pixelSize: Style.font.icon
            }
          }
        }
        Item {
          id: tileMask
          anchors.fill: parent
          layer.enabled: true
          visible: false
          Rectangle { anchors.fill: parent; radius: Math.max(Style.space(8), Style.cornerRadius / 2) }
        }
        Rectangle {
          anchors.fill: parent
          anchors.margins: -Style.space(2)
          radius: Math.max(Style.space(8), Style.cornerRadius / 2) + Style.space(2)
          color: "transparent"
          border.width: Style.space(2)
          border.color: h.accent
          opacity: area.containsMouse ? 0.9 : 0
          Behavior on opacity { NumberAnimation { duration: Style.duration(140) } }
        }

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: h.hovered = tile.modelData
          onExited: if (h.hovered === tile.modelData) h.hovered = null
          onClicked: h.play(String(tile.modelData.uri))
        }
      }
    }
  }
}
