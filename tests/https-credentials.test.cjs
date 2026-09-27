const assert = require('node:assert/strict')
const test = require('node:test')
const http = require('node:http')
const path = require('node:path')
const { spawn } = require('node:child_process')
const root = path.join(__dirname, '..')

test('HTTP PDS never receives passwords or tokens, including saved sessions', async () => {
  let hits = 0
  const server = http.createServer((req, res) => { hits++; req.resume(); res.end('{}') })
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  const url = `http://127.0.0.1:${server.address().port}`
  try {
    for (const options of [
      { method: 'POST', body: JSON.stringify({ identifier: 'alice', password: 'secret' }) },
      { method: 'POST', headers: { Authorization: 'Bearer access' }, body: '{}' },
      { headers: { authorization: 'Bearer access' } },
      { body: 'secret' }
    ]) {
      const output = await new Promise((resolve, reject) => {
        const proc = spawn('python3', [path.join(root, 'bin/request.py')])
        let data = ''
        proc.stdout.on('data', chunk => { data += chunk })
        proc.on('error', reject)
        proc.on('close', code => code === 0 ? resolve(JSON.parse(data)) : reject(new Error('exit ' + code)))
        proc.stdin.end(JSON.stringify({ url, ...options }))
      })
      assert.equal(output.status, 0)
      assert.equal(output.text, '')
      assert.match(output.error, /require HTTPS/)
    }
    for (const [script, args] of [
      ['refresh-session.sh', ['/nonexistent/session.json', url]],
      ['upload-blob.sh', [url, '/nonexistent/session.json', 'image/png', '/nonexistent/image.png']]
    ]) {
      await new Promise((resolve, reject) => {
        const proc = spawn(path.join(root, 'bin', script), args)
        let error = ''
        proc.stderr.on('data', data => { error += data })
        proc.on('error', reject)
        proc.on('close', code => {
          assert.equal(code, 1)
          assert.match(error, /PDS URL must use HTTPS/)
          resolve()
        })
      })
    }
    assert.equal(hits, 0)
  } finally { await new Promise(resolve => server.close(resolve)) }
})

test('HTTPS credentials succeed with trusted TLS and reject untrusted certificates', async () => {
  const fs = require('node:fs')
  const os = require('node:os')
  const https = require('node:https')
  const { spawnSync } = require('node:child_process')
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'bsky-tls-'))
  const key = path.join(dir, 'key.pem'), cert = path.join(dir, 'cert.pem')
  const generated = spawnSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, '-out', cert, '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1'])
  assert.equal(generated.status, 0)
  let hits = 0
  const server = https.createServer({ key: fs.readFileSync(key), cert: fs.readFileSync(cert) }, (req, res) => {
    hits++
    req.resume()
    req.on('end', () => res.end('{"accessJwt":"fresh","blob":{}}'))
  })
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve))
  const url = `https://127.0.0.1:${server.address().port}`
  fs.writeFileSync(path.join(dir, 'session.json'), '{"accessJwt":"access","refreshJwt":"refresh"}')
  fs.writeFileSync(path.join(dir, 'image.png'), 'image')
  try {
    for (const trusted of [false, true]) {
      const env = { ...process.env, ...(trusted ? { SSL_CERT_FILE: cert, CURL_CA_BUNDLE: cert } : { SSL_CERT_FILE: '/nonexistent', CURL_CA_BUNDLE: '/nonexistent' }) }
      for (const [command, args, input] of [
        ['python3', [path.join(root, 'bin/request.py')], JSON.stringify({ url, method: 'POST', body: '{"password":"secret"}' })],
        [path.join(root, 'bin/refresh-session.sh'), [path.join(dir, 'session.json'), url]],
        [path.join(root, 'bin/upload-blob.sh'), [url, path.join(dir, 'session.json'), 'image/png', path.join(dir, 'image.png')]]
      ]) {
        const result = await new Promise((resolve, reject) => {
          const proc = spawn(command, args, { env })
          let output = ''
          proc.stdout.on('data', chunk => { output += chunk })
          proc.on('error', reject)
          proc.on('close', code => resolve({ code, output }))
          proc.stdin.end(input)
        })
        if (trusted) { assert.equal(result.code, 0); assert.match(result.output, /fresh/) }
        else assert.doesNotMatch(result.output, /fresh/)
      }
      assert.equal(hits, trusted ? 3 : 0)
    }
  } finally {
    await new Promise(resolve => server.close(resolve))
    fs.rmSync(dir, { recursive: true, force: true })
  }
})
