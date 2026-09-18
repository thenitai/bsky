// AT Proto (Bluesky) client helpers for thenitai.bsky.
.pragma library

var DEFAULT_PDS = "https://bsky.social"
var APPVIEW = "https://public.api.bsky.app"
var MAX_GRAPHEMES = 300
var MAX_IMAGES = 4
var MAX_URLS = 5
var MAX_IMAGE_BYTES = 1000000
var CLIENT = "thenitai.bsky (Omarchy)"

function pdsRoot(pds) {
  var s = String(pds || "").trim()
  if (!s) s = DEFAULT_PDS
  while (s.slice(-1) === "/") s = s.slice(0, -1)
  return s
}

function errorText(status, json, fallback) {
  if (json && json.message) return { message: String(json.message), status: status }
  if (json && json.error) return { message: String(json.error), status: status }
  if (status) return { message: fallback + " (HTTP " + status + ")", status: status }
  return { message: fallback, status: 0 }
}

// Generic request. cb(status, json, err, rawText) — err is {message, status} or null.
function request(opts, cb) {
  var xhr = new XMLHttpRequest()
  var settled = false
  function done(status, json, err, raw) {
    if (settled) return
    settled = true
    cb(status, json, err, raw)
  }
  xhr.timeout = opts.timeoutMs || 15000
  xhr.ontimeout = function() { done(0, null, { message: "network timeout", status: 0 }, "") }
  xhr.onerror = function() { done(0, null, { message: "network error", status: 0 }, "") }
  xhr.onabort = function() { done(0, null, { message: "aborted", status: 0 }, "") }
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== XMLHttpRequest.DONE) return
    var status = xhr.status
    var text = xhr.responseText || ""
    var json = null
    if (text) {
      try { json = JSON.parse(text) } catch (e) { json = null }
    }
    done(status, json, null, text)
  }
  try {
    xhr.open(opts.method || "GET", opts.url, true)
    var hs = opts.headers || {}
    for (var k in hs) if (hs[k]) xhr.setRequestHeader(k, hs[k])
    xhr.send(opts.body ? opts.body : null)
  } catch (e) {
    done(0, null, { message: String(e), status: 0 }, "")
  }
}

function createSession(pds, identifier, password, cb) {
  request({
    url: pdsRoot(pds) + "/xrpc/com.atproto.server.createSession",
    method: "POST",
    timeoutMs: 15000,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ identifier: identifier, password: password })
  }, function(status, json, err) {
    if (err) return cb(err)
    if (status === 200 && json && json.accessJwt)
      return cb(null, { accessJwt: json.accessJwt, refreshJwt: json.refreshJwt, did: json.did, handle: json.handle })
    cb(errorText(status, json, "login failed"))
  })
}

function refreshSession(pds, refreshJwt, cb) {
  request({
    url: pdsRoot(pds) + "/xrpc/com.atproto.server.refreshSession",
    method: "POST",
    timeoutMs: 15000,
    headers: { "Authorization": "Bearer " + refreshJwt }
  }, function(status, json, err) {
    if (err) return cb(err)
    if (status === 200 && json && json.accessJwt)
      return cb(null, { accessJwt: json.accessJwt, refreshJwt: json.refreshJwt, did: json.did, handle: json.handle })
    cb(errorText(status, json, "session refresh failed"))
  })
}

function createRecord(pds, token, did, record, cb) {
  request({
    url: pdsRoot(pds) + "/xrpc/com.atproto.repo.createRecord",
    method: "POST",
    timeoutMs: 20000,
    headers: { "Content-Type": "application/json", "Authorization": "Bearer " + token },
    body: JSON.stringify({ repo: did, collection: "app.bsky.feed.post", record: record })
  }, function(status, json, err) {
    if (err) return cb(err)
    if (status === 200 && json && json.uri) return cb(null, json.uri, json.cid)
    cb(errorText(status, json, "post failed"))
  })
}

// AppView reads below work unauthenticated for public data.

function getProfile(actor, cb) {
  request({
    url: APPVIEW + "/xrpc/app.bsky.actor.getProfile?actor=" + encodeURIComponent(actor),
    method: "GET",
    timeoutMs: 12000
  }, function(status, json, err) {
    if (err) return cb(err)
    if (status === 200 && json && json.did)
      return cb(null, { did: json.did, handle: json.handle || actor, displayName: json.displayName || "" })
    cb(errorText(status, json, "profile lookup failed"))
  })
}

function getPostThread(atUri, cb) {
  request({
    url: APPVIEW + "/xrpc/app.bsky.feed.getPostThread?uri=" + encodeURIComponent(atUri),
    method: "GET",
    timeoutMs: 12000
  }, function(status, json, err) {
    if (err) return cb(err)
    if (status === 200 && json && json.thread && json.thread.post) {
      var p = json.thread.post
      return cb(null, { uri: p.uri, cid: p.cid, handle: p.author ? p.author.handle || "" : "", record: p.record || null })
    }
    cb(errorText(status, json, "could not load post"))
  })
}

// Fetches a page as text (for OpenGraph parsing). cb(status, err, rawText)
function fetchText(url, cb) {
  request({
    url: url,
    method: "GET",
    timeoutMs: 12000,
    headers: { "Accept": "text/html" }
  }, function(status, json, err, raw) {
    cb(status, err, raw || "")
  })
}

// ---- URL / mention extraction -------------------------------------------

// Detects a Bluesky post reference: a bsky.app web URL or a raw at:// URI.
// Returns {actor, rkey, atUri} or null.
function findPostUrl(text) {
  var t = String(text || "")
  var m = t.match(/https?:\/\/[^\s]+\/profile\/([^\/\s?#]+)\/post\/([A-Za-z0-9]+)/)
  if (m) return { actor: m[1], rkey: m[2], atUri: null }
  m = t.match(/at:\/\/([A-Za-z0-9:._-]+)\/app\.bsky\.feed\.post\/([A-Za-z0-9]+)/)
  if (m) return { actor: m[1], rkey: m[2], atUri: m[0] }
  return null
}

function atUriFor(actor, rkey) {
  return "at://" + actor + "/app.bsky.feed.post/" + rkey
}

function extractUrls(text) {
  var t = String(text || "")
  var out = []
  var re = /https?:\/\/[^\s<>"')\]]+/g
  var m
  while ((m = re.exec(t)) !== null) {
    var url = m[0]
    while (/[.,;:!?]+$/.test(url)) url = url.slice(0, -1)
    if (url.length > 3) {
      out.push({ url: url, start: m.index, end: m.index + url.length })
      if (out.length >= MAX_URLS) break
    }
  }
  return out
}

var HANDLE_SRC = "[a-zA-Z0-9][a-zA-Z0-9.-]*\\.[a-zA-Z]{2,}"

function extractMentions(text) {
  var t = String(text || "")
  var out = []
  var re = new RegExp("(^|[^\\w@.])@(did:[a-zA-Z0-9:.-]+|" + HANDLE_SRC + ")", "g")
  var m
  while ((m = re.exec(t)) !== null) {
    var handle = m[2]
    var start = m.index + m[1].length
    out.push({ handle: handle, start: start, end: start + handle.length + 1 })
  }
  return out
}

// Unique handles that need DID resolution (did: mentions resolve as themselves).
function mentionHandles(text) {
  var mens = extractMentions(text)
  var seen = {}
  var out = []
  for (var i = 0; i < mens.length; i++) {
    var h = mens[i].handle
    if (h.indexOf("did:") === 0) continue
    var key = h.toLowerCase()
    if (seen[key]) continue
    seen[key] = true
    out.push(h)
  }
  return out
}

// ---- UTF-8 byte offsets for facets ---------------------------------------

// cum[i] = UTF-8 byte offset of code-unit i; cum[n] = total byte length.
function byteOffsets(text) {
  var t = String(text)
  var cum = new Array(t.length + 1)
  var byte = 0
  var i = 0
  while (i < t.length) {
    cum[i] = byte
    var code = t.charCodeAt(i)
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < t.length) {
      var low = t.charCodeAt(i + 1)
      if (low >= 0xDC00 && low <= 0xDFFF) {
        byte += 4
        cum[i + 1] = byte
        i += 2
        continue
      }
    }
    if (code < 0x80) byte += 1
    else if (code < 0x800) byte += 2
    else byte += 3
    i += 1
  }
  cum[t.length] = byte
  return cum
}

// didMap: lowercase handle -> did. Returns app.bsky.richtext.facet[].
function buildFacets(text, didMap) {
  var t = String(text || "")
  if (!t) return []
  var cum = byteOffsets(t)
  var facets = []
  var urls = extractUrls(t)
  for (var i = 0; i < urls.length; i++) {
    var u = urls[i]
    facets.push({
      index: { byteStart: cum[u.start], byteEnd: cum[u.end] },
      features: [{ $type: "app.bsky.richtext.facet#link", uri: u.url }]
    })
  }
  var mens = extractMentions(t)
  for (var j = 0; j < mens.length; j++) {
    var me = mens[j]
    var did = null
    if (me.handle.indexOf("did:") === 0) did = me.handle
    else if (didMap) did = didMap[me.handle.toLowerCase()]
    if (!did) continue
    // me.start points at '@', so the span is one unit longer than the handle.
    facets.push({
      index: { byteStart: cum[me.start], byteEnd: cum[me.start + me.handle.length + 1] },
      features: [{ $type: "app.bsky.richtext.facet#mention", did: did }]
    })
  }
  return facets
}

// ---- record construction --------------------------------------------------

function buildRecord(opts) {
  var record = {
    "$type": "app.bsky.feed.post",
    text: String(opts.text || ""),
    createdAt: new Date().toISOString(),
    via: CLIENT
  }
  if (opts.langs && opts.langs.length) record.langs = opts.langs
  if (opts.facets && opts.facets.length) record.facets = opts.facets
  if (opts.reply) record.reply = opts.reply
  if (opts.embed) record.embed = opts.embed
  return record
}

function imagesEmbed(blobs) {
  var images = []
  for (var i = 0; i < blobs.length; i++) {
    var b = blobs[i]
    var img = { alt: String(b.alt || ""), image: b.blob }
    if (b.aspectWidth > 0 && b.aspectHeight > 0)
      img.aspectRatio = { width: b.aspectWidth, height: b.aspectHeight }
    images.push(img)
  }
  return { "$type": "app.bsky.embed.images", images: images }
}

function recordEmbed(ref) {
  return { "$type": "app.bsky.embed.record", record: ref }
}

function recordWithMediaEmbed(ref, media) {
  return { "$type": "app.bsky.embed.recordWithMedia", record: recordEmbed(ref), media: media }
}

function externalEmbed(uri, title, description, thumbBlob) {
  var external = { uri: uri, title: String(title || ""), description: String(description || "") }
  if (thumbBlob) external.thumb = thumbBlob
  return { "$type": "app.bsky.embed.external", external: external }
}

// ---- validation & counting -------------------------------------------------

function graphemeCount(text) {
  var t = String(text || "")
  if (typeof Intl !== "undefined" && Intl.Segmenter) {
    var seg = new Intl.Segmenter(undefined, { granularity: "grapheme" })
    var segs = seg.segment(t)
    var iter = typeof segs[Symbol.iterator] === "function" ? segs[Symbol.iterator]() : segs
    var n = 0
    var r = iter.next()
    while (!r.done) {
      n++
      r = iter.next()
    }
    return n
  }
  return Array.from(t).length
}

function validate(text, imageCount) {
  if (!String(text || "").trim() && imageCount === 0) return "Write something first"
  if (graphemeCount(text) > MAX_GRAPHEMES) return "Over the " + MAX_GRAPHEMES + " character limit"
  if (imageCount > MAX_IMAGES) return "Bluesky allows up to " + MAX_IMAGES + " images"
  if (extractUrls(text).length > MAX_URLS) return "Bluesky allows up to " + MAX_URLS + " links per post"
  return ""
}

function looksLikeAppPassword(password) {
  return /^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$/.test(String(password || "").trim())
}

// ---- OpenGraph helpers -----------------------------------------------------

function decodeEntities(s) {
  return String(s || "")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&#0?39;/g, "'")
    .replace(/&#x27;/g, "'")
}

function parseOgTags(html) {
  var out = { title: "", description: "", image: "" }
  var tags = String(html || "").match(/<meta\b[^>]*>/gi) || []
  for (var i = 0; i < tags.length; i++) {
    var tag = tags[i]
    var prop = (tag.match(/(?:property|name)\s*=\s*["']([^"']+)["']/i) || [])[1] || ""
    var content = (tag.match(/content\s*=\s*["']([^"']*)["']/i) || [])[1] || ""
    if (!prop || !content) continue
    var p = prop.toLowerCase()
    if ((p === "og:title" || p === "twitter:title") && !out.title) out.title = decodeEntities(content)
    else if ((p === "og:description" || p === "twitter:description") && !out.description) out.description = decodeEntities(content)
    else if ((p === "og:image" || p === "og:image:secure_url" || p === "twitter:image") && !out.image) out.image = decodeEntities(content)
    if (out.title && out.description && out.image) break
  }
  return out
}

function hostOf(url) {
  var m = String(url || "").match(/^https?:\/\/([^\/?#]+)/i)
  return m ? m[1] : String(url || "")
}

function resolveUrl(base, rel) {
  if (!rel) return ""
  if (/^https?:\/\//i.test(rel)) return rel
  if (rel.indexOf("//") === 0) return "https:" + rel
  var m = String(base).match(/^https?:\/\/[^\/]+/i)
  if (!m) return rel
  if (rel.indexOf("/") === 0) return m[0] + rel
  return m[0] + "/" + rel
}
