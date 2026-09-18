// Offline unit tests for ShortcutModel.js.
// Run with: node tests/shortcut.test.cjs

const fs = require("fs")
const path = require("path")

let src = fs.readFileSync(path.join(__dirname, "..", "ShortcutModel.js"), "utf8")
src = src.replace(/\.pragma library\n/, "")
const Model = eval("(function(){" + src + "; return {DEFAULT, DESCRIPTION, COMMAND, MODIFIERS, parse, bindings, same, conflict, registerCode, releaseCode}})()")

let failed = 0
function eq(name, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) console.log("PASS", name)
  else { failed++; console.log("FAIL", name, "\n  got: ", g, "\n  want:", w) }
}

// parse
eq("parse default", Model.parse(Model.DEFAULT), { text: "SUPER + B", mask: 64, key: "B" })
eq("parse multi", Model.parse("super + shift + p"), { text: "SUPER + SHIFT + P", mask: 65, key: "P" })
eq("parse control alias", Model.parse("CONTROL + SPACE"), { text: "CTRL + SPACE", mask: 4, key: "SPACE" })
eq("parse empty is disabled", Model.parse(""), { text: "", mask: 0, key: "" })
eq("parse null on empty-ish", Model.parse("   "), { text: "", mask: 0, key: "" })
eq("parse rejects bare key", Model.parse("B"), null)
eq("parse rejects unknown modifier", Model.parse("HYPER + B"), null)
eq("parse rejects duplicate modifier", Model.parse("SUPER + SUPER + B"), null)
eq("parse rejects bad key", Model.parse("SUPER + FOO"), null)
eq("parse allows F keys", Model.parse("SUPER + F12"), { text: "SUPER + F12", mask: 64, key: "F12" })

// bindings parser (hyprctl binds text blocks)
const sample = `
modmask: 64
key: B
description: Post to Bluesky

modmask: 65
key: S
description: Save

modmask: 0
key: mouse:button:273812
`
const list = Model.bindings(sample.trim())
eq("bindings count", list.length, 3)
eq("bindings parse first", { key: list[0].key, modmask: list[0].modmask, description: list[0].description },
  { key: "B", modmask: 64, description: "Post to Bluesky" })

// conflict
eq("conflict with other bind", Model.conflict(list, Model.parse("SUPER + SHIFT + S"))?.description, "Save")
eq("no conflict with own bind", Model.conflict(list, Model.parse("SUPER + B")), null)
eq("no conflict for disabled", Model.conflict(list, Model.parse("")), null)

// registerCode
const code = Model.registerCode(list, "SUPER + B", "SUPER + SHIFT + P", "owner-1")
eq("registerCode unbinds previous", code.includes('hl.unbind("SUPER + B");'), true)
eq("registerCode binds next", code.includes('hl.bind("SUPER + SHIFT + P"'), true)
eq("registerCode uses command", code.includes('"omarchy-shell shell toggle thenitai.bsky"'), true)
eq("registerCode stamps owner", code.includes('_G.__bsky_shortcut_owner = "owner-1"'), true)
eq("registerCode disabled only unbinds", Model.registerCode(list, "SUPER + B", "", "owner-1").includes("hl.bind"), false)

// releaseCode guards on ownership
const release = Model.releaseCode("SUPER + B", "owner-1")
eq("releaseCode checks owner", release.includes('if _G.__bsky_shortcut_owner == "owner-1"'), true)

console.log(failed === 0 ? "\nALL TESTS PASSED" : "\n" + failed + " TESTS FAILED")
process.exit(failed === 0 ? 0 : 1)
