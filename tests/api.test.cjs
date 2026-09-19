// Offline unit tests for the pure functions in Api.js.
// Run with: node tests/api.test.cjs

const fs = require("fs")
const path = require("path")

let src = fs.readFileSync(path.join(__dirname, "..", "Api.js"), "utf8")
src = src.replace(/\.pragma library\n/, "")
global.XMLHttpRequest = function () { throw new Error("no xhr in tests") }
const Api = eval("(function(){" + src + "; return {DEFAULT_PDS, APPVIEW, MAX_GRAPHEMES, MAX_IMAGES, MAX_URLS, MAX_IMAGE_BYTES, pdsRoot, errorText, isAuthError, request, createSession, refreshSession, createRecord, findPostUrl, atUriFor, extractUrls, extractMentions, mentionHandles, extractTags, spanOverlaps, byteOffsets, buildFacets, buildRecord, imagesEmbed, recordEmbed, recordWithMediaEmbed, externalEmbed, graphemeCount, validate, looksLikeAppPassword, decodeEntities, parseOgTags, hostOf, resolveUrl}})()")

let failed = 0
function eq(name, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) console.log("PASS", name)
  else { failed++; console.log("FAIL", name, "\n  got: ", g, "\n  want:", w) }
}

function captureRequest(run) {
  let xhr
  function MockXHR() {
    xhr = this
    this.headers = {}
    this.open = (method, url) => { this.method = method; this.url = url }
    this.setRequestHeader = (name, value) => { this.headers[name] = value }
    this.send = function () { this.sendArgs = Array.from(arguments) }
  }
  MockXHR.DONE = 4
  global.XMLHttpRequest = MockXHR
  run()
  return xhr
}

// Request transport: AT Protocol no-input procedures must receive no body at
// all, while procedures with JSON input must still receive their serialized body.
const refreshXhr = captureRequest(() => Api.refreshSession("https://bsky.social", "refresh-token", () => {}))
eq("refresh sends no body argument", refreshXhr.sendArgs.length, 0)
eq("refresh keeps bearer token", refreshXhr.headers.Authorization, "Bearer refresh-token")

const loginXhr = captureRequest(() => Api.createSession("https://bsky.social", "alice.test", "app-password", () => {}))
eq("login sends one body argument", loginXhr.sendArgs.length, 1)
eq("login sends JSON body", JSON.parse(loginXhr.sendArgs[0]), { identifier: "alice.test", password: "app-password" })

const record = { $type: "app.bsky.feed.post", text: "hello" }
const recordXhr = captureRequest(() => Api.createRecord("https://bsky.social", "access-token", "did:plc:alice", record, () => {}))
eq("record sends one body argument", recordXhr.sendArgs.length, 1)
eq("record sends JSON body", JSON.parse(recordXhr.sendArgs[0]), { repo: "did:plc:alice", collection: "app.bsky.feed.post", record })

// pdsRoot
eq("pdsRoot default", Api.pdsRoot(""), "https://bsky.social")
eq("pdsRoot slash", Api.pdsRoot("https://pds.example.com/"), "https://pds.example.com")

// API errors retain machine-readable codes so auth failures can be routed.
eq("errorText code", Api.errorText(400, { error: "ExpiredToken", message: "Token has expired" }, "failed"),
  { message: "Token has expired", status: 400, code: "ExpiredToken" })
eq("auth error expired token", Api.isAuthError({ status: 400, code: "ExpiredToken" }), true)
eq("auth error unauthorized", Api.isAuthError({ status: 401, code: "" }), true)
eq("auth error network", Api.isAuthError({ status: 0, code: "" }), false)
eq("auth error server", Api.isAuthError({ status: 500, code: "" }), false)

// byteOffsets: "ab é 😀 cd" → a(1)b(1)' '(1)é(2)' '(1)😀(4)' '(1)c(1)d(1) = 13 bytes
// indices:      a=0 b=1 ' '=2 é=3 ' '=4 😀=5 ' '=6 c=7 d=8
const t1 = "ab é 😀 cd"
const cum = Api.byteOffsets(t1)
eq("byteOffsets length", cum.length, t1.length + 1)
eq("byteOffsets total", cum[cum.length - 1], 13)
eq("byteOffsets é start", cum[3], 3)
eq("byteOffsets emoji start", cum[5], 6)
eq("byteOffsets after emoji", cum[6], 10)
eq("byteOffsets d start", cum[8], 11)

// findPostUrl
eq("findPostUrl bsky", Api.findPostUrl("see https://bsky.app/profile/alice.bsky.social/post/3kxv2abc123 nice"),
  { actor: "alice.bsky.social", rkey: "3kxv2abc123", atUri: null })
eq("findPostUrl did", Api.findPostUrl("https://bsky.app/profile/did:plc:abcdef123/post/3kxv2abc123"),
  { actor: "did:plc:abcdef123", rkey: "3kxv2abc123", atUri: null })
eq("findPostUrl aturi", Api.findPostUrl("quote at://did:plc:xyz/app.bsky.feed.post/3lmnop"),
  { actor: "did:plc:xyz", rkey: "3lmnop", atUri: "at://did:plc:xyz/app.bsky.feed.post/3lmnop" })
eq("findPostUrl none", Api.findPostUrl("just https://example.com/foo"), null)

// atUriFor
eq("atUriFor", Api.atUriFor("did:plc:abc", "3k"), "at://did:plc:abc/app.bsky.feed.post/3k")

// extractUrls with trailing punctuation
const urls = Api.extractUrls("go to https://example.com/x?y=1, and http://a.b/c.")
eq("extractUrls count", urls.length, 2)
eq("extractUrls trim", urls[0].url, "https://example.com/x?y=1")
eq("extractUrls trim2", urls[1].url, "http://a.b/c")

// mentions
const mens = Api.extractMentions("hi @alice.bsky.social and @bob.example.com! text@not.mention and @did:plc:xyz")
eq("mentions count", mens.length, 3)
eq("mentions first", mens[0].handle, "alice.bsky.social")
eq("mentions last", mens[2].handle, "did:plc:xyz")
eq("mentionHandles", Api.mentionHandles("hi @alice.bsky.social and @did:plc:xyz"), ["alice.bsky.social"])

// facets byte offsets with unicode before the link
const text2 = "héllo https://x.example 😀 @carol.bsky.social end"
const facets = Api.buildFacets(text2, { "carol.bsky.social": "did:plc:carol" })
eq("facets count", facets.length, 2)
const linkF = facets[0], menF = facets[1]
const bytes = Buffer.from(text2, "utf8")
eq("facet link slice", bytes.slice(linkF.index.byteStart, linkF.index.byteEnd).toString(), "https://x.example")
eq("facet link feature", linkF.features[0], { $type: "app.bsky.richtext.facet#link", uri: "https://x.example" })
eq("facet mention slice", bytes.slice(menF.index.byteStart, menF.index.byteEnd).toString(), "@carol.bsky.social")
eq("facet mention did", menF.features[0], { $type: "app.bsky.richtext.facet#mention", did: "did:plc:carol" })

// hashtags
const t3 = "loving #omarchy on #bsky!"
const tags = Api.extractTags(t3)
eq("tags count", tags.length, 2)
eq("tag first", tags[0], { tag: "omarchy", start: 7, end: 15 })
eq("tag slice", t3.slice(tags[1].start, tags[1].end), "#bsky")
eq("tag at string start", Api.extractTags("#top ")[0].tag, "top")
eq("midword tag ignored", Api.extractTags("foo#bar").length, 0)
eq("numeric tag ignored", Api.extractTags("#123 ok").length, 0)
eq("mixed tag kept", Api.extractTags("#a12 ok")[0].tag, "a12")
eq("underscore tag kept", Api.extractTags("#hello_world")[0].tag, "hello_world")
const f3 = Api.buildFacets(t3, {})
const tagF = f3[0]
eq("tag facet feature", tagF.features[0], { $type: "app.bsky.richtext.facet#tag", tag: "omarchy" })
eq("tag facet slice", Buffer.from(t3, "utf8").slice(tagF.index.byteStart, tagF.index.byteEnd).toString(), "#omarchy")
// url fragment must not become a tag
const t4 = "see https://x.com/#anchor and #real"
const f4 = Api.buildFacets(t4, {})
const f4tags = f4.filter(function(f) { return f.features[0].$type.indexOf("#tag") !== -1 })
eq("url anchor not a tag", f4tags.length, 1)
eq("real tag after url", f4tags[0].features[0].tag, "real")

// did-mention passes through
const f2 = Api.buildFacets("ping @did:plc:direct", {})
eq("did mention", f2[0].features[0], { $type: "app.bsky.richtext.facet#mention", did: "did:plc:direct" })

// graphemeCount
eq("graphemes ascii", Api.graphemeCount("hello"), 5)
eq("graphemes zwj family", Api.graphemeCount("👨‍👩‍👧‍👦"), 1)
eq("graphemes flag+ascii", Api.graphemeCount("🇩🇪 ok"), 4)

// validate
eq("validate empty", Api.validate("", 0), "Write something first")
eq("validate long", Api.validate("x".repeat(301), 0), "Over the 300 character limit")
eq("validate ok", Api.validate("hi", 0), "")
eq("validate many images", Api.validate("hi", 5), "Bluesky allows up to 4 images")

// app password format
eq("app password ok", Api.looksLikeAppPassword("abcd-efgh-ijkl-mnop"), true)
eq("app password bad", Api.looksLikeAppPassword("hunter2"), false)

// record building
const rec = Api.buildRecord({ text: "hi", langs: ["en"], facets: [{ x: 1 }], embed: { e: 1 } })
eq("record shape", rec, { $type: "app.bsky.feed.post", text: "hi", createdAt: rec.createdAt, via: "thenitai.bsky (Omarchy)", langs: ["en"], facets: [{ x: 1 }], embed: { e: 1 } })
eq("imagesEmbed", Api.imagesEmbed([{ blob: { $type: "blob" }, alt: "a pic", aspectWidth: 2, aspectHeight: 1 }]),
  { $type: "app.bsky.embed.images", images: [{ alt: "a pic", image: { $type: "blob" }, aspectRatio: { width: 2, height: 1 } }] })
eq("recordWithMedia", Api.recordWithMediaEmbed({ uri: "u", cid: "c" }, { m: 1 }),
  { $type: "app.bsky.embed.recordWithMedia", record: { $type: "app.bsky.embed.record", record: { uri: "u", cid: "c" } }, media: { m: 1 } })
eq("externalEmbed no thumb", Api.externalEmbed("u", "t", "d", null),
  { $type: "app.bsky.embed.external", external: { uri: "u", title: "t", description: "d" } })

// OG parsing
const html = '<html><head><meta charset="utf-8"><meta property="og:title" content="A &amp; B"><meta name="twitter:description" content="desc here"><meta property="og:image" content="/img/cover.png"></head></html>'
const og = Api.parseOgTags(html)
eq("og title entities", og.title, "A & B")
eq("og twitter desc fallback", og.description, "desc here")
eq("og image relative", og.image, "/img/cover.png")

// hostOf / resolveUrl
eq("hostOf", Api.hostOf("https://sub.example.com/path?q=1"), "sub.example.com")
eq("resolveUrl absolute", Api.resolveUrl("https://a.com/p", "https://b.com/x.png"), "https://b.com/x.png")
eq("resolveUrl proto-relative", Api.resolveUrl("https://a.com/p", "//cdn.a.com/x.png"), "https://cdn.a.com/x.png")
eq("resolveUrl root-relative", Api.resolveUrl("https://a.com/p", "/x.png"), "https://a.com/x.png")
eq("resolveUrl relative", Api.resolveUrl("https://a.com/p", "x.png"), "https://a.com/x.png")

console.log(failed === 0 ? "\nALL TESTS PASSED" : "\n" + failed + " TESTS FAILED")
process.exit(failed === 0 ? 0 : 1)
