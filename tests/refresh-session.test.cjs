const fs = require("fs")
const path = require("path")

const root = path.join(__dirname, "..")
const script = fs.readFileSync(path.join(root, "bin", "refresh-session.sh"), "utf8")
const qml = fs.readFileSync(path.join(root, "Bsky.qml"), "utf8")

let failed = 0
function ok(name, value) {
  if (value) console.log("PASS", name)
  else { failed++; console.log("FAIL", name) }
}

ok("refresh uses bodyless POST", script.includes("--request POST") && !script.includes("--data"))
ok("refresh token comes from session file", script.includes("refreshJwt") && script.includes('header "@$header_file"'))
ok("refresh token is absent from process command", qml.includes('"bin/refresh-session.sh", root.stateDir + "/session.json", Api.pdsRoot(root.pds)'))
ok("composer uses refresh process", qml.includes("refreshSessionProc.start(function(err, tokens)"))

console.log(failed === 0 ? "\nALL TESTS PASSED" : "\n" + failed + " TESTS FAILED")
process.exit(failed === 0 ? 0 : 1)
