// "Now playing" image for sharing: the cover, title, artist and album over a
// blurred, album-tinted backdrop, with the song's progress. Rendered off
// screen and saved as a PNG; never shown in the UI itself.
//
// `ready` turns true once the cover has loaded (or there is none), so the
// caller knows when to grab it.
import QtQuick
import QtQuick.Effects
import qs.Commons
import "Model.js" as Model

Item {
  id: s

  property string source: ""
  property string title: ""
  property string artist: ""
  property string album: ""
  property real position: 0
  property real duration: 0
  property color accent: "white"
  property color accent2: "white"
  property string fontFamily: Style.font.family

  readonly property bool ready: source === ""
    || (cover.status === Image.Ready && backdrop.status === Image.Ready)
    || cover.status === Image.Error

  width: 640
  height: 300

  readonly property color ink: "#f4f4f6"

  // ---- background (rounded; PNG corners stay transparent)
  Item {
    id: bg
    anchors.fill: parent
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: bgMask
    }

    Rectangle { anchors.fill: parent; color: "#111116" }
    Image {
      id: backdrop
      anchors.fill: parent
      source: s.source
      sourceSize: Qt.size(64, 64)
      fillMode: Image.PreserveAspectCrop
      visible: false
    }
    MultiEffect {
      anchors.fill: parent
      anchors.margins: -60
      source: backdrop
      blurEnabled: true
      blur: 1.0
      blurMax: 64
      saturation: 0.3
      opacity: 0.85
    }
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(s.accent.r, s.accent.g, s.accent.b, 0.22) }
        GradientStop { position: 1.0; color: Qt.rgba(s.accent2.r, s.accent2.g, s.accent2.b, 0.18) }
      }
    }
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(0.04, 0.04, 0.06, 0.35) }
        GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.04, 0.06, 0.7) }
      }
    }
  }
  Item {
    id: bgMask
    anchors.fill: bg
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: 28 }
  }

  // ---- cover with its glow
  Rectangle {
    id: glowSrc
    x: coverBox.x + 14; y: coverBox.y + 22
    width: coverBox.width - 28; height: coverBox.height - 28
    radius: 20
    visible: false
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: s.accent }
      GradientStop { position: 1.0; color: s.accent2 }
    }
  }
  MultiEffect {
    anchors.fill: glowSrc
    anchors.margins: -30
    source: glowSrc
    autoPaddingEnabled: true
    blurEnabled: true
    blur: 1.0
    blurMax: 48
    opacity: 0.6
  }
  Item {
    id: coverBox
    x: 32; y: 32
    width: 236; height: 236
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: coverMask
    }
    Rectangle { anchors.fill: parent; color: "#26262c" }
    Image {
      id: cover
      anchors.fill: parent
      source: s.source
      sourceSize: Qt.size(512, 512)
      fillMode: Image.PreserveAspectCrop
    }
  }
  Item {
    id: coverMask
    anchors.fill: coverBox
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: 18 }
  }

  // ---- text
  Column {
    x: 300; y: 46
    width: s.width - x - 34
    spacing: 6

    Text {
      text: "NOW PLAYING"
      color: s.accent
      font.family: s.fontFamily
      font.pixelSize: 13
      font.bold: true
      font.letterSpacing: 2
    }
    Item { width: 1; height: 4 }
    Text {
      width: parent.width
      text: s.title
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      color: s.ink
      font.family: s.fontFamily
      font.pixelSize: 30
      font.bold: true
    }
    Text {
      width: parent.width
      text: s.artist
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Qt.rgba(s.ink.r, s.ink.g, s.ink.b, 0.8)
      font.family: s.fontFamily
      font.pixelSize: 18
    }
    Text {
      width: parent.width
      visible: s.album !== "" && s.album !== s.title
      text: s.album
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Qt.rgba(s.ink.r, s.ink.g, s.ink.b, 0.5)
      font.family: s.fontFamily
      font.pixelSize: 15
    }
  }

  // ---- progress
  Item {
    x: 300
    width: s.width - x - 34
    y: s.height - 32 - height
    height: 40
    visible: s.duration > 0

    Rectangle {
      id: track
      width: parent.width
      height: 5
      radius: 2.5
      color: Qt.rgba(1, 1, 1, 0.15)
      Rectangle {
        height: parent.height
        radius: height / 2
        width: Math.max(height, parent.width * Model.clamp(s.position / Math.max(1, s.duration), 0, 1))
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: s.accent }
          GradientStop { position: 1.0; color: s.accent2 }
        }
      }
    }
    Text {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      text: Model.timestamp(s.position)
      color: Qt.rgba(s.ink.r, s.ink.g, s.ink.b, 0.55)
      font.family: s.fontFamily
      font.pixelSize: 13
      font.features: { "tnum": 1 }
    }
    Text {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      text: Model.timestamp(s.duration)
      color: Qt.rgba(s.ink.r, s.ink.g, s.ink.b, 0.55)
      font.family: s.fontFamily
      font.pixelSize: 13
      font.features: { "tnum": 1 }
    }
  }
}
