const assert = require("node:assert/strict")
const fs = require("fs")
const path = require("path")
const test = require("node:test")

const root = path.join(__dirname, "..")
const composer = fs.readFileSync(path.join(root, "Composer.qml"), "utf8")
const overlay = fs.readFileSync(path.join(root, "Bsky.qml"), "utf8")

test("composer shows padded Settings and Bluesky links separated by a dot", () => {
  assert.match(composer, /id: navigationLinks\s+[\s\S]*?spacing: Style\.space\(8\)/)
  assert.match(composer, /text: "Settings"[\s\S]*?text: "·"[\s\S]*?text: "Go to Bluesky"/)
  assert.match(composer, /onClicked: c\.goToBlueskyRequested\(\)/)
})

test("Bluesky link closes the overlay before opening Bluesky", () => {
  const handler = overlay.match(/onGoToBlueskyRequested: \{([\s\S]*?)\n\s*\}/)
  assert.ok(handler)
  assert.ok(handler[1].indexOf("root.dismiss()") < handler[1].indexOf('Qt.openUrlExternally("https://bsky.app")'))
})
