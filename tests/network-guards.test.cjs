const assert = require("node:assert/strict")
const fs = require("fs")
const os = require("os")
const path = require("path")
const { spawnSync } = require("child_process")
const test = require("node:test")

const root = path.join(__dirname, "..")
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "bsky-network-guards-"))
const curlPath = path.join(tempDir, "curl")
const sessionPath = path.join(tempDir, "session.json")
const imagePath = path.join(tempDir, "image.png")

fs.writeFileSync(curlPath, `#!/bin/bash
set -euo pipefail
output=""
while (($# > 0)); do
  case "$1" in
    --output|-o)
      output="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done
dd if=/dev/zero of="$output" bs=1024 count=300 status=none
printf '200'
`)
fs.chmodSync(curlPath, 0o755)
fs.writeFileSync(sessionPath, JSON.stringify({ accessJwt: "access", refreshJwt: "refresh" }))
fs.writeFileSync(imagePath, "image")

const env = { ...process.env, PATH: tempDir + path.delimiter + process.env.PATH }

test.after(() => fs.rmSync(tempDir, { recursive: true, force: true }))

test("session refresh fails closed when the response exceeds the cap", () => {
  const result = spawnSync(path.join(root, "bin", "refresh-session.sh"), [sessionPath, "https://example.test"], { encoding: "utf8", env })
  assert.equal(result.status, 1)
  assert.match(result.stderr, /response exceeded 262144 bytes/)
})

test("blob upload fails closed when the response exceeds the cap", () => {
  const result = spawnSync(path.join(root, "bin", "upload-blob.sh"), ["https://example.test", sessionPath, "image/png", imagePath], { encoding: "utf8", env })
  assert.equal(result.status, 1)
  assert.match(result.stderr, /response exceeded 262144 bytes/)
})
