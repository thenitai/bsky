// Offline unit tests for the pure functions in Api.js.
// Run with: node tests/api.test.cjs

const fs = require("fs")
const path = require("path")

let src = fs.readFileSync(path.join(__dirname, "..", "Api.js"), "utf8")
src = src.replace(/\.pragma library\n/, "")
global.XMLHttpRequest = function () { throw new Error("no xhr in tests") }
const Api = eval("(function(){" + src + "; return {DEFAULT_PDS, APPVIEW, MAX_GRAPHEMES, MAX_IMAGES, MAX_URLS, MAX_IMAGE_BYTES, pdsRoot, errorText, findPostUrl, atUriFor, extractUrls, extractMentions, mentionHandles, byteOffsets, buildFacets, buildRecord, imagesEmbed, recordEmbed, recordWithMediaEmbed, externalEmbed, graphemeCount, validate, looksLikeAppPassword, decodeEntities, parseOgTags, hostOf, resolveUrl}})()")

let failed = 0
function eq(name, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g === w) console.log("PASS", name)
  else { failed++; console.log("FAIL", name, "\n  got: ", g, "\n  want:", w) }
}

// pdsRoot
eq("pdsRoot default", Api.pdsRoot(""), "https://bsky.social")
eq("pdsRoot slash", Api.pdsRoot("https://pds.example.com/"), "https://pds.example.com")

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
