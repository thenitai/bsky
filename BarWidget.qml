import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "thenitai.bsky"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\ue671"
    tooltipText: "Bluesky composer"
    onPressed: function(mouseButton) {
      if (mouseButton !== Qt.LeftButton || !root.bar || !root.bar.shell) return
      root.bar.shell.toggle("thenitai.bsky", "{}")
    }
  }
}
