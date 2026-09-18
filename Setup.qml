import QtQuick
import qs.Commons
import qs.Ui

// First-run account setup: handle + app password + optional PDS override.
// Verified with createSession before anything is persisted.

Column {
  id: setup

  spacing: Style.space(16)

  property color foreground: Color.menu.text
  property color errorColor: Color.urgent
  property string fontFamily: Style.font.menuFamily
  property int contentSpacing: Style.space(16)
  property bool busy: false
  property bool canGoBack: false
  property string statusText: ""
  property bool statusError: false

  signal saved(string handle, string password, string pds)
  signal backRequested()
  signal dismissRequested()

  property alias handleField: handleField

  function clearStatus() {
    statusText = ""
  }

  Text {
    text: "Sign in to Bluesky"
    color: setup.foreground
    font.family: setup.fontFamily
    font.pixelSize: Style.font.heading
    font.bold: true
  }

  TextField {
    id: handleField
    width: parent.width
    enabled: !setup.busy
    placeholderText: "your handle — e.g. alice.bsky.social"
    color: setup.foreground
    font.family: setup.fontFamily
    Keys.onReturnPressed: appPasswordField.forceActiveFocus()
    Keys.onEnterPressed: appPasswordField.forceActiveFocus()
    Keys.onEscapePressed: function(event) { setup.dismissRequested(); event.accepted = true }
  }

  TextField {
    id: appPasswordField
    width: parent.width
    enabled: !setup.busy
    password: true
    placeholderText: "app password — xxxx-xxxx-xxxx-xxxx"
    color: setup.foreground
    font.family: setup.fontFamily
    Keys.onReturnPressed: saveButton.clicked()
    Keys.onEnterPressed: saveButton.clicked()
    Keys.onEscapePressed: function(event) { setup.dismissRequested(); event.accepted = true }
  }

  TextField {
    id: pdsField
    width: parent.width
    enabled: !setup.busy
    placeholderText: "PDS URL (optional — default https://bsky.social)"
    color: setup.foreground
    opacity: 0.9
    font.family: setup.fontFamily
    font.pixelSize: Style.font.bodySmall
    Keys.onReturnPressed: saveButton.clicked()
    Keys.onEnterPressed: saveButton.clicked()
    Keys.onEscapePressed: function(event) { setup.dismissRequested(); event.accepted = true }
  }

  Row {
    spacing: setup.contentSpacing

    Button {
      id: saveButton
      text: setup.busy ? "Verifying…" : "Save & verify"
      selected: true
      enabled: !setup.busy && handleField.text.trim() !== "" && appPasswordField.text.trim() !== ""
      onClicked: {
        if (setup.busy) return
        setup.saved(handleField.text.trim(), appPasswordField.text.trim(), pdsField.text.trim())
      }
    }

    Button {
      text: "Clear"
      enabled: !setup.busy
      visible: setup.statusText !== "" && setup.statusError
      onClicked: {
        handleField.text = ""
        appPasswordField.text = ""
        pdsField.text = ""
        setup.clearStatus()
        handleField.forceActiveFocus()
      }
    }
  }

  Text {
    visible: setup.statusText !== ""
    width: parent.width
    text: setup.statusText
    textFormat: Text.PlainText
    color: setup.statusError ? setup.errorColor : setup.foreground
    opacity: setup.statusError ? 1 : 0.62
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    visible: setup.canGoBack
    text: "← Back"
    color: setup.foreground
    opacity: backLinkMouse.containsMouse ? 1 : 0.55
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption

    MouseArea {
      id: backLinkMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: setup.backRequested()
    }
  }
}
