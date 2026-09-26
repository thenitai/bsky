const assert = require('node:assert/strict')
const test = require('node:test')
const http = require('node:http')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawn, spawnSync } = require('node:child_process')
const root = path.join(__dirname, '..')

test('HTTP transport bounds chunked success/error responses and preserves small responses', async () => {
  const server = http.createServer((req, res) => {
    if (req.url === '/stall') return
    if (req.url === '/small') return res.end('{"ok":true}')
    if (req.url === '/redirect') { res.writeHead(302, { Location: '/small' }); return res.end() }
    res.writeHead(req.url === '/error' ? 500 : 200)
    for (let i = 0; i < 40; i++) res.write(Buffer.alloc(8192, 65))
    res.end()
  })
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  try {
    for (const route of ['/small', '/large', '/error', '/redirect']) {
      const result = await new Promise((resolve, reject) => {
        const child = spawn('timeout', ['--kill-after=1', '3', 'python3', path.join(root, 'bin/request.py')])
        let output = ''
        child.stdout.on('data', data => { output += data })
        child.on('error', reject)
        child.on('close', code => code === 0 ? resolve(JSON.parse(output)) : reject(new Error('exit ' + code)))
        child.stdin.end(JSON.stringify({ url: `http://127.0.0.1:${server.address().port}${route}` }))
      })
      if (route === '/small') assert.equal(result.text, '{"ok":true}')
      else if (route === '/redirect') assert.equal(result.status, 302)
      else { assert.equal(result.text, ''); assert.match(result.error, /exceeded/) }
    }
    await new Promise((resolve, reject) => {
      const started = Date.now()
      const child = spawn('timeout', ['--kill-after=1', '1', 'python3', path.join(root, 'bin/request.py')])
      let output = ''
      child.stdout.on('data', data => { output += data })
      child.on('error', reject)
      child.on('close', code => {
        assert.equal(code, 124)
        assert.equal(output, '')
        assert.ok(Date.now() - started < 3000)
        resolve()
      })
      child.stdin.end(JSON.stringify({ url: `http://127.0.0.1:${server.address().port}/stall` }))
    })
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)) }
})

test('clipboard limits reject overflow before output, clean up, and terminate stalled readers', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bsky-input-'))
  const command = path.join(dir, 'wl-paste')
  const env = { ...process.env, PATH: dir + ':' + process.env.PATH }
  const before = fs.readdirSync(os.tmpdir()).filter(name => name.startsWith('omarchy-bsky-clip.')).sort()
  try {
    for (const mode of ['small', 'text-overflow', 'image-overflow', 'types-overflow', 'conversion-overflow', 'conversion-stall', 'stall']) {
      fs.writeFileSync(command, `#!/bin/bash\nif [[ "$1" == --list-types ]]; then\n${mode === 'types-overflow' ? 'head -c 70000 /dev/zero' : 'echo image/png'}\nelse\n${mode === 'stall' ? 'sleep 30' : mode.includes('overflow') ? 'head -c 2000000 /dev/zero' : "printf 'hello'"}\nfi\n`, { mode: 0o755 })
      if (mode.startsWith('conversion')) {
        fs.writeFileSync(command, '#!/bin/bash\nif [[ "$1" == --list-types ]]; then echo image/gif; else printf gif; fi\n', { mode: 0o755 })
        fs.writeFileSync(path.join(dir, 'ffmpeg'), '#!/bin/bash\n' + (mode.endsWith('stall') ? 'sleep 30' : 'head -c 2000000 /dev/zero > "${@: -1}"') + '\n', { mode: 0o755 })
      }
      const args = mode.startsWith('conversion') || mode.startsWith('image') || mode.startsWith('types') ? [] : ['text']
      const result = spawnSync(path.join(root, 'bin/grab-image.sh'), args, { env, encoding: 'utf8', timeout: 13000 })
      if (mode === 'small') { assert.equal(result.status, 0); assert.equal(result.stdout, 'hello') }
      else { assert.notEqual(result.status, 0); assert.equal(result.stdout, ''); assert.equal(result.error, undefined) }
    }
    assert.deepEqual(fs.readdirSync(os.tmpdir()).filter(name => name.startsWith('omarchy-bsky-clip.')).sort(), before)
  } finally { fs.rmSync(dir, { recursive: true, force: true }) }
})
