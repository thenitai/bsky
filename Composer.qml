import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Api.js" as Api

// The post composer: text area, attached images with alt text, reply/quote
// chips, link card, character counter and the Post action.

Column {
  id: c

  spacing: c.contentSpacing

  property var imageModel: null
  property var replyRef: null
  property var quoteRef: null
  property var linkCard: null
  property bool sending: false

  property color foreground: Color.menu.text
  property color errorColor: Color.urgent
  property string fontFamily: Style.font.menuFamily
  property int contentSpacing: Style.space(14)
  readonly property int footerHeight: Style.space(32)

  signal postRequested()
  signal pasteRequested()
  signal dismissRequested()
  signal settingsRequested()
  signal replyRequested()
  signal quoteRequested()
  signal clearReplyRequested()
  signal clearQuoteRequested()
  signal linkCardRequested()
  signal clearLinkCardRequested()
  signal imageRemoved(string path)

  readonly property alias text: textArea.text
  readonly property alias textAreaItem: textArea
  readonly property int graphemes: Api.graphemeCount(textArea.text)
  readonly property int remaining: Api.MAX_GRAPHEMES - graphemes
  readonly property bool overLimit: remaining < 0
  readonly property var postUrl: Api.findPostUrl(textArea.text)
  readonly property string cardUrl: {
    var urls = Api.extractUrls(textArea.text)
    for (var i = 0; i < urls.length; i++)
      if (!Api.findPostUrl(urls[i].url)) return urls[i].url
    return ""
  }
  readonly property bool linkCardAvailable: cardUrl !== "" && !replyRef && !quoteRef
    && (!imageModel || imageModel.count === 0) && !linkCard
  readonly property bool canPost: !sending && !overLimit
    && (textArea.text.trim() !== "" || (imageModel && imageModel.count > 0))

  function insertClipboardText(t) {
    if (!t) return
    textArea.insert(textArea.cursorPosition, t)
    textArea.forceActiveFocus()
  }

  function clearDraft() {
    textArea.clear()
  }

  TextArea {
    id: textArea
    width: parent.width
    height: Style.space(120)
    enabled: !c.sending
    wrapMode: TextEdit.Wrap
    clip: true
    placeholderText: "What's up?"
    placeholderTextColor: Qt.darker(c.foreground, 1.6)
    color: c.foreground
    selectionColor: Style.selectionFillFor(c.foreground, Color.accent)
    selectedTextColor: c.foreground
    font.family: c.fontFamily
    font.pixelSize: Style.font.body

    background: BorderSurface {
      color: Style.controlFill(textArea.activeFocus, textArea.hovered, c.foreground, Color.accent)
      borderSpec: Border.controlSpec(textArea.activeFocus ? "focus" : (textArea.hovered ? "hover-cursor" : "normal"), c.foreground, Color.accent)
      radius: Style.cornerRadius
    }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        c.dismissRequested()
        event.accepted = true
      } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                 && (event.modifiers & Qt.ControlModifier)) {
        c.postRequested()
        event.accepted = true
      } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
        c.pasteRequested()
        event.accepted = true
      }
    }
  }

  // ---- attached images ----------------------------------------------------

  Repeater {
    model: c.imageModel

    Rectangle {
      id: imgRow
      required property int index
      required property string path
      required property string mime
      required property int size
      required property string alt
      required property int aspectWidth
      required property int aspectHeight

      width: parent ? parent.width : 0
      height: Style.space(50)
      radius: Style.cornerRadius
      color: Color.menu.selectedBackground

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(4)
        anchors.topMargin: Style.space(4)
        anchors.bottomMargin: Style.space(4)
        spacing: Style.space(8)

        Rectangle {
          width: Style.space(42)
          height: Style.space(42)
          radius: Style.space(4)
          color: "transparent"
          clip: true

          Image {
            anchors.fill: parent
            anchors.margins: 1
            source: Util.fileUrl(imgRow.path)
            fillMode: Image.PreserveAspectFit
            smooth: true
            sourceSize.width: 256
            asynchronous: true
          }
        }

        TextField {
          width: parent.width - parent.spacing * 2 - Style.space(42) - Style.space(26)
          height: Style.space(42)
          enabled: !c.sending
          placeholderText: "Alt text — describe the image"
          color: c.foreground
          font.family: c.fontFamily
          font.pixelSize: Style.font.bodySmall
          verticalPadding: 4
          Component.onCompleted: text = imgRow.alt
          onTextEdited: c.imageModel.setProperty(imgRow.index, "alt", text)
        }

        Button {
          width: Style.space(26)
          height: Style.space(42)
          horizontalPadding: 0
          text: "×"
          enabled: !c.sending
          tooltipText: "Remove image"
          iconSize: Style.font.bodySmall
          onClicked: {
            var p = imgRow.path
            c.imageModel.remove(imgRow.index)
            c.imageRemoved(p)
          }
        }
      }
    }
  }

  // ---- link card preview ----------------------------------------------------

  Rectangle {
    visible: c.linkCard !== null
    width: parent.width
    height: visible ? cardPreviewColumn.implicitHeight + Style.space(12) : 0
    radius: Style.cornerRadius
    color: Color.menu.selectedBackground

    Column {
      id: cardPreviewColumn
      anchors.fill: parent
      anchors.margins: Style.space(6)
      spacing: 2

      Text {
        width: parent.width
        text: c.linkCard ? (c.linkCard.title || c.linkCard.uri) : ""
        color: c.foreground
        font.family: c.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: c.linkCard ? c.linkCard.description : ""
        visible: c.linkCard && c.linkCard.description !== ""
        color: c.foreground
        opacity: 0.7
        font.family: c.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        maximumLineCount: 2
        wrapMode: Text.WordWrap
      }
    }

    MouseArea {
      anchors.fill: parent
      enabled: !c.sending
      onClicked: c.clearLinkCardRequested()
      cursorShape: Qt.PointingHandCursor
    }
  }

  // ---- footer actions -------------------------------------------------------

  Row {
    width: parent.width
    height: c.footerHeight
    spacing: c.contentSpacing

    Row {
      id: actionButtons
      height: parent.height
      spacing: Style.space(6)

      Text {
        id: settingsLink
        y: (parent.height - height) / 2
        text: "Settings"
        color: c.foreground
        opacity: settingsLinkMouse.containsMouse ? 1 : 0.55
        font.family: c.fontFamily
        font.pixelSize: Style.font.caption

        MouseArea {
          id: settingsLinkMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: c.settingsRequested()
        }
      }

      Button {
        visible: c.postUrl && !c.replyRef
        text: "Reply"
        height: parent.height
        enabled: !c.sending
        tooltipText: "Reply to the bsky.app post in your text"
        onClicked: c.replyRequested()
      }

      Button {
        visible: c.postUrl && !c.quoteRef
        text: "Quote"
        height: parent.height
        enabled: !c.sending
        tooltipText: "Quote the bsky.app post in your text"
        onClicked: c.quoteRequested()
      }

      Button {
        visible: c.replyRef !== null
        selected: true
        text: "Replying to @" + (c.replyRef ? c.replyRef.handle : "")
        height: parent.height
        enabled: !c.sending
        onClicked: c.clearReplyRequested()
      }

      Button {
        visible: c.quoteRef !== null
        selected: true
        text: "Quoting @" + (c.quoteRef ? c.quoteRef.handle : "")
        height: parent.height
        enabled: !c.sending
        onClicked: c.clearQuoteRequested()
      }

      Button {
        visible: c.linkCardAvailable
        text: "Link card"
        height: parent.height
        enabled: !c.sending
        tooltipText: "Attach an OpenGraph card for the pasted link"
        onClicked: c.linkCardRequested()
      }
    }

    Item {
      width: Math.max(0, parent.width - actionButtons.implicitWidth - rightControls.implicitWidth - 2 * parent.spacing)
      height: 1
    }

    Row {
      id: rightControls
      height: parent.height
      spacing: Style.space(10)

      Text {
        y: (parent.height - height) / 2
        text: c.overLimit ? (c.remaining + " over") : (c.remaining + " left")
        color: c.overLimit ? c.errorColor : c.foreground
        opacity: c.overLimit ? 1 : 0.55
        font.family: c.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        id: pasteGlyph
        y: (parent.height - height) / 2
        text: "\uF03E"
        color: c.foreground
        opacity: !pasteMouse.enabled ? 0.3 : (pasteMouse.containsMouse ? 1 : 0.55)
        font.family: c.fontFamily
        font.pixelSize: Style.font.iconSmall

        ToolTip.visible: pasteMouse.containsMouse
        ToolTip.delay: 400
        ToolTip.text: "Paste image from clipboard"

        MouseArea {
          id: pasteMouse
          anchors.fill: parent
          hoverEnabled: true
          enabled: !c.sending && (!c.imageModel || c.imageModel.count < Api.MAX_IMAGES)
          cursorShape: Qt.PointingHandCursor
          onClicked: c.pasteRequested()
        }
      }

      Button {
        id: postButton
        height: parent.height
        text: c.sending ? "Sending…" : "Post"
        selected: true
        enabled: c.canPost
        onClicked: c.postRequested()
      }
    }
  }
}
