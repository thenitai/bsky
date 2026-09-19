const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
const widget = fs.readFileSync(path.join(root, manifest.entryPoints.barWidget), "utf8")

let failed = 0
function ok(name, value) {
  if (value) console.log("PASS", name)
  else { failed++; console.log("FAIL", name) }
}

ok("manifest exposes overlay", manifest.kinds.includes("overlay") && manifest.entryPoints.overlay === "Bsky.qml")
ok("manifest exposes bar widget", manifest.kinds.includes("bar-widget") && manifest.entryPoints.barWidget === "BarWidget.qml")
ok("bar widget defaults right", manifest.barWidget.defaultSection === "right")
ok("bar widget toggles composer through shell", widget.includes('root.bar.shell.toggle("thenitai.bsky", "{}")'))
ok("bar widget only handles left click", widget.includes("mouseButton !== Qt.LeftButton"))

console.log(failed === 0 ? "\nALL TESTS PASSED" : "\n" + failed + " TESTS FAILED")
process.exit(failed === 0 ? 0 : 1)
