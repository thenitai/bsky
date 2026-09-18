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
  property bool signedIn: false
  property string currentHandle: ""
  property string currentPassword: ""
  property string currentPds: ""
  property string shortcutValue: ""
  property bool shortcutBusy: false
  property bool shortcutOk: true
  property string shortcutMessage: ""
  property string statusText: ""
  property bool statusError: false

  signal saved(string handle, string password, string pds)
  signal shortcutApply(string value)
  signal backRequested()
  signal dismissRequested()

  property alias handleField: handleField

  function clearStatus() {
    statusText = ""
  }

  function prefill() {
    shortcutField.text = setup.shortcutValue
    handleField.text = setup.currentHandle
    appPasswordField.text = setup.currentPassword
    pdsField.text = setup.currentPds
  }

  onVisibleChanged: if (visible) prefill()

  Text {
    text: setup.signedIn ? "Bluesky settings" : "Sign in to Bluesky"
    color: setup.foreground
    font.family: setup.fontFamily
    font.pixelSize: Style.font.heading
    font.bold: true
  }

  // ---- global shortcut ------------------------------------------------------

  Text {
    text: "Global shortcut"
    color: setup.foreground
    font.family: setup.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  Row {
    width: parent.width
    spacing: setup.contentSpacing

    TextField {
      id: shortcutField
      width: parent.width - shortcutApplyButton.width - parent.spacing
      enabled: !setup.shortcutBusy
      placeholderText: "Disabled"
      color: setup.foreground
      font.family: setup.fontFamily
      onAccepted: setup.shortcutApply(text)
      Keys.onEscapePressed: function(event) {
        if (!setup.shortcutBusy) setup.dismissRequested()
        event.accepted = true
      }
    }

    Button {
      id: shortcutApplyButton
      height: Style.space(30)
      text: setup.shortcutBusy ? "Applying…" : "Apply"
      bordered: true
      enabled: !setup.shortcutBusy
      onClicked: setup.shortcutApply(shortcutField.text)
    }
  }

  Text {
    width: parent.width
    text: "Super, Ctrl, Alt, Shift + a key. Leave empty to disable."
    color: setup.foreground
    opacity: 0.5
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    visible: setup.shortcutMessage !== ""
    width: parent.width
    text: setup.shortcutMessage
    textFormat: Text.PlainText
    color: setup.shortcutOk ? setup.foreground : setup.errorColor
    opacity: setup.shortcutOk ? 0.7 : 1
    font.family: setup.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
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

  Item {
    width: parent.width
    height: Style.space(32)

    Button {
      id: backButton
      anchors.left: parent.left
      height: parent.height
      visible: setup.canGoBack
      text: "Back"
      enabled: !setup.busy
      onClicked: setup.backRequested()
    }

    Row {
      anchors.right: parent.right
      spacing: setup.contentSpacing
      height: parent.height

      Button {
        id: clearButton
        height: parent.height
        enabled: !setup.busy
        visible: setup.statusText !== "" && setup.statusError
        text: "Clear"
        onClicked: {
          handleField.text = ""
          appPasswordField.text = ""
          pdsField.text = ""
          setup.clearStatus()
          handleField.forceActiveFocus()
        }
      }

      Button {
        id: saveButton
        height: parent.height
        text: setup.busy ? "Verifying…" : "Save & verify"
        selected: true
        enabled: !setup.busy && handleField.text.trim() !== "" && appPasswordField.text.trim() !== ""
        onClicked: {
          if (setup.busy) return
          setup.saved(handleField.text.trim(), appPasswordField.text.trim(), pdsField.text.trim())
        }
      }
    }
  }
}
