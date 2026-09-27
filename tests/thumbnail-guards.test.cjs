const assert = require('node:assert/strict')
const test = require('node:test')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const root = path.join(__dirname, '..')
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bsky-thumb-test-'))
const log = path.join(dir, 'curl.json')
// Isolated processes retain real OS limits. Only DNS and the remote server are
// simulated; curl's output attempts still hit the real filesystem write limit.
fs.writeFileSync(path.join(dir, 'python3'), `#!/usr/bin/python3
import os, sys, socket, runpy
socket.getaddrinfo = lambda *a, **k: [(socket.AF_INET, socket.SOCK_STREAM, 6, '', (ip, 443)) for ip in os.environ['TEST_IPS'].split(',')]
sys.argv = sys.argv[1:]
runpy.run_path(sys.argv[0], run_name='__main__')
`, { mode: 0o755 })
fs.writeFileSync(path.join(dir, 'curl'), `#!/usr/bin/python3
import json, os, sys, time
if os.environ.get('TEST_STALL'): time.sleep(40)
args = sys.argv[1:]
with open(os.environ['TEST_LOG'], 'w') as log: json.dump(args, log)
with open(args[args.index('--output') + 1], 'wb') as output:
    output.write(b'A' * int(os.environ.get('TEST_BYTES', '20')))
sys.stdout.write(os.environ.get('TEST_STATUS', '200'))
`, { mode: 0o755 })
fs.writeFileSync(path.join(dir, 'file'), '#!/bin/sh\nprintf "%s\\n" "$TEST_MIME"\n', { mode: 0o755 })
const env = { ...process.env, PATH: dir + ':' + process.env.PATH, TEST_LOG: log, TEST_IPS: '93.184.216.34', TEST_MIME: 'image/png' }
test.after(() => fs.rmSync(dir, { recursive: true, force: true }))

test('rejects private, special, mixed DNS and non-HTTP thumbnail targets before curl', () => {
  for (const ips of ['127.0.0.1', '10.1.2.3', '172.16.0.1', '192.168.1.1', '169.254.169.254', '100.64.0.1', '0.0.0.0', '224.0.0.1', '::1', 'fd00::1', 'fe80::1', '::ffff:127.0.0.1', '64:ff9b::7f00:1', '2002:7f00:1::', '93.184.216.34,127.0.0.1']) {
    fs.rmSync(log, { force: true })
    const result = spawnSync(path.join(root, 'bin/fetch-image.sh'), ['https://image.example/a.png'], { env: { ...env, TEST_IPS: ips } })
    assert.notEqual(result.status, 0, ips)
    assert.equal(result.stdout.length, 0)
    assert.equal(fs.existsSync(log), false)
  }
  for (const url of ['file:///etc/passwd', 'ftp://image.example/a', 'https://user:password@image.example/a']) {
    const result = spawnSync(path.join(root, 'bin/fetch-image.sh'), [url], { env })
    assert.notEqual(result.status, 0)
    assert.equal(fs.existsSync(log), false)
  }
})

test('pins public DNS, ignores proxy/config/redirects, and retains successful image', () => {
  const result = spawnSync(path.join(root, 'bin/fetch-image.sh'), ['https://image.example/a.png'], { env, encoding: 'utf8' })
  assert.equal(result.status, 0, result.stderr)
  const args = JSON.parse(fs.readFileSync(log))
  assert.equal(args[0], '--disable')
  assert.equal(args[args.indexOf('--resolve') + 1], 'image.example:443:93.184.216.34')
  assert.equal(args[args.indexOf('--proxy') + 1], '')
  assert.equal(args[args.indexOf('--noproxy') + 1], '*')
  assert.equal(args.includes('--location'), false)
  assert.equal(args[args.indexOf('--max-time') + 1], '20')
  const [mime, filename, size] = result.stdout.trim().split('\t')
  assert.equal(mime, 'image/png')
  assert.equal(size, '20')
  assert.equal(fs.statSync(filename).size, 20)
  fs.unlinkSync(filename)
})

test('rejects redirects, unsupported formats and oversized writes; cleans files', () => {
  const before = fs.readdirSync('/tmp').filter(name => name.startsWith('omarchy-bsky-card.')).sort()
  for (const override of [{ TEST_STATUS: '302' }, { TEST_MIME: 'image/gif' }, { TEST_MIME: 'text/html' }, { TEST_BYTES: '1100000' }]) {
    const result = spawnSync(path.join(root, 'bin/fetch-image.sh'), ['https://image.example/a'], { env: { ...env, ...override } })
    assert.notEqual(result.status, 0)
    assert.equal(result.stdout.length, 0)
  }
  assert.deepEqual(fs.readdirSync('/tmp').filter(name => name.startsWith('omarchy-bsky-card.')).sort(), before)
})

 test('stalled thumbnail download is terminated and cleaned up', () => {
  const before = fs.readdirSync('/tmp').filter(name => name.startsWith('omarchy-bsky-card.')).sort()
  const started = Date.now()
  const result = spawnSync(path.join(root, 'bin/fetch-image.sh'), ['https://image.example/a'], { env: { ...env, TEST_STALL: '1' }, timeout: 28000 })
  assert.notEqual(result.status, 0)
  assert.equal(result.error, undefined)
  assert.equal(result.stdout.length, 0)
  assert.ok(Date.now() - started < 27000)
  assert.deepEqual(fs.readdirSync('/tmp').filter(name => name.startsWith('omarchy-bsky-card.')).sort(), before)
})
