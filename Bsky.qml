import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Api.js" as Api

// Bluesky composer overlay. Summoned with a Hyprland binding:
//   omarchy-shell shell toggle thenitai.bsky
//
// Auto-grabs an image from the Wayland clipboard on open, verifies and stores
// an app password on first run, and posts via the user's PDS.

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  // ---- styling (menu surface tokens, same language as omarchy.menu) -------
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color errorColor: Color.urgent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.space(20)
  property int contentSpacing: Style.space(14)
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int cardMaxHeight: Math.max(Style.space(200), panel.height - Style.gapsOut * 2)

  // ---- state ----------------------------------------------------------------
  readonly property string stateDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy-bsky"
  readonly property string pluginDir: {
    var s = Qt.resolvedUrl("Api.js").toString()
    s = s.substring(0, s.lastIndexOf("/") + 1)
    if (s.indexOf("file://") === 0) s = s.substring(7)
    return decodeURIComponent(s)
  }
  property bool storageReady: false
  property bool setupMode: false
  property bool savingSetup: false
  property string handle: ""
  property string pds: Api.DEFAULT_PDS
  property string appPassword: ""
  property var session: null
  property string lang: {
    var l = (Quickshell.env("LANG") || "en").split(".")[0].split("_")[0]
    return l && l.length >= 2 ? l : "en"
  }

  readonly property bool configured: storageReady && handle !== "" && appPassword !== ""

  property string statusText: ""
  property bool statusIsError: false
  property bool sending: false

  property var replyRef: null   // {uri, cid, handle, root?}
  property var quoteRef: null   // {uri, cid, handle}
  property var linkCard: null   // {uri, title, description, image, thumbPath, blob}

  property var tempFiles: []
  property string dimProbePath: ""
  property int dimProbeIndex: -1

  // ---- upload pipeline scratch state -----------------------------------------
  property var uploadQueue: []
  property var uploadedBlobs: []
  property bool uploadRetried: false

  ListModel { id: imageModel }

  // ---- lifecycle ---------------------------------------------------------------

  function applyFocusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var target = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name || "") === target) {
        panel.screen = screens[i]
        return
      }
  }

  function open(payloadJson) {
    root.applyFocusedScreen()
    root.opened = true
    if (root.configured && imageModel.count === 0) root.grabClipboardImage(false)
    Qt.callLater(root.focusDefault)
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function dismiss() {
    if (root.sending) return
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "thenitai.bsky")
  }

  function focusDefault() {
    if (!root.configured || root.setupMode) setup.handleField.forceActiveFocus()
    else composer.textAreaItem.forceActiveFocus()
  }

  // ---- status -------------------------------------------------------------------

  function flash(msg, isError) {
    statusText = msg
    statusIsError = !!isError
    statusClearTimer.restart()
  }

  function setStatus(msg) {
    statusText = msg
    statusIsError = false
    statusClearTimer.stop()
  }

  function clearStatus() {
    statusText = ""
  }

  // ---- clipboard image -----------------------------------------------------------

  function grabClipboardImage(manual) {
    if (imageModel.count >= Api.MAX_IMAGES) {
      if (manual) flash("Bluesky allows up to " + Api.MAX_IMAGES + " images", true)
      return
    }
    grabProc.manual = manual
    grabProc.running = true
  }

  function addImage(mime, path, size) {
    if (size > Api.MAX_IMAGE_BYTES) {
      root.rmFile(path)
      flash("Image is over the 1 MB Bluesky limit", true)
      return
    }
    imageModel.append({ path: path, mime: mime, size: size, alt: "", aspectWidth: 0, aspectHeight: 0 })
    var files = root.tempFiles.slice()
    files.push(path)
    root.tempFiles = files
    root.dimProbeIndex = imageModel.count - 1
    root.dimProbePath = path
  }

  function rmFile(path) {
    if (!path) return
    rmProc.command = ["rm", "-f", path]
    rmProc.running = true
  }

  function removeTempFile(path) {
    var files = []
    for (var i = 0; i < root.tempFiles.length; i++)
      if (root.tempFiles[i] !== path) files.push(root.tempFiles[i])
    root.tempFiles = files
    root.rmFile(path)
  }

  function cleanupTempFiles() {
    if (root.tempFiles.length > 0) {
      rmProc.command = ["rm", "-f"].concat(root.tempFiles)
      rmProc.running = true
    }
    root.tempFiles = []
  }

  // ---- credentials ----------------------------------------------------------------

  function saveCredentials(handle, password, pds) {
    if (root.savingSetup) return
    if (!handle) return setupError("Enter your Bluesky handle")
    if (!Api.looksLikeAppPassword(password))
      return setupError("That doesn't look like an app password. Create one at bsky.app → Settings → App passwords")
    root.savingSetup = true
    setup.statusText = "Verifying…"
    setup.statusError = false
    var pdsUrl = Api.pdsRoot(pds || Api.DEFAULT_PDS)
    Api.createSession(pdsUrl, handle, password, function(err, tokens) {
      root.savingSetup = false
      if (err) return setupError(err.message || "Login failed")
      root.handle = handle
      root.pds = pdsUrl
      root.appPassword = password
      root.applySession(tokens)
      writeFileProc.writeSecret("app-password", password, null)
      prefsView.setText(JSON.stringify({ handle: handle, pds: pdsUrl }))
      setup.statusText = ""
      root.setupMode = false
      root.flash("Signed in as @" + tokens.handle, false)
      Qt.callLater(root.focusDefault)
    })
  }

  function setupError(msg) {
    setup.statusText = msg
    setup.statusError = true
  }

  function applySession(tokens) {
    root.session = tokens
    writeFileProc.writeSecret("session.json", JSON.stringify({
      accessJwt: tokens.accessJwt,
      refreshJwt: tokens.refreshJwt,
      did: tokens.did,
      handle: tokens.handle
    }), null)
  }

  function ensureSession(cb) {
    if (root.session && root.session.accessJwt) return cb(null)
    root.doLogin(cb)
  }

  function doLogin(cb) {
    if (!root.handle || !root.appPassword)
      return cb({ message: "Not signed in", status: 0 })
    Api.createSession(root.pds, root.handle, root.appPassword, function(err, tokens) {
      if (err) return cb(err)
      root.applySession(tokens)
      cb(null)
    })
  }

  function refreshTokens(cb) {
    if (!root.session || !root.session.refreshJwt) return root.doLogin(cb)
    Api.refreshSession(root.pds, root.session.refreshJwt, function(err, tokens) {
      if (err) return root.doLogin(cb)
      root.applySession(tokens)
      cb(null)
    })
  }

  // fn(token, done). Retries once after a session refresh on 401.
  function authedCall(fn, cb, attempt) {
    var tries = attempt || 0
    root.ensureSession(function(err) {
      if (err) return cb(err)
      fn(root.session.accessJwt, function(err2) {
        var rest = Array.prototype.slice.call(arguments, 1)
        if (!err2) return cb.apply(null, [null].concat(rest))
        if (tries < 2 && err2.status === 401) {
          return root.refreshTokens(function(err3) {
            if (err3) return cb(err3)
            root.authedCall(fn, cb, tries + 1)
          })
        }
        cb.apply(null, [err2].concat(rest))
      })
    })
  }

  // ---- references (reply / quote) ---------------------------------------------------

  function resolveRef(mode) {
    var info = composer.postUrl
    if (!info) return
    root.setStatus("Resolving post…")
    var finish = function(err, post) {
      if (err) return root.flash(err.message || "Could not load post", true)
      if (mode === "reply") {
        var ref = { uri: post.uri, cid: post.cid, handle: post.handle }
        if (post.record && post.record.reply && post.record.reply.root)
          ref.root = post.record.reply.root
        root.replyRef = ref
      } else {
        root.quoteRef = { uri: post.uri, cid: post.cid, handle: post.handle }
      }
      root.clearStatus()
    }
    var loadThread = function(err, atUri) {
      if (err) return finish(err, null)
      Api.getPostThread(atUri, finish)
    }
    if (info.atUri) return Api.getPostThread(info.atUri, finish)
    if (String(info.actor).indexOf("did:") === 0)
      return loadThread(null, Api.atUriFor(info.actor, info.rkey))
    Api.getProfile(info.actor, function(err, prof) {
      if (err) return finish(err, null)
      loadThread(null, Api.atUriFor(prof.did, info.rkey))
    })
  }

  // ---- link card ----------------------------------------------------------------------

  function buildLinkCard() {
    var url = composer.cardUrl
    if (!url) return
    if (root.linkCard) return
    root.setStatus("Fetching link card…")
    Api.fetchText(url, function(status, err, html) {
      var og = html ? Api.parseOgTags(html) : { title: "", description: "", image: "" }
      root.linkCard = {
        uri: url,
        title: og.title || Api.hostOf(url),
        description: og.description || "",
        image: "",
        thumbPath: "",
        blob: null
      }
      if (err || status !== 200) root.setStatus("Card ready (page fetch failed)")
      else root.clearStatus()
      if (!og.image) return
      var imgUrl = Api.resolveUrl(url, og.image)
      thumbProc.fetch(imgUrl)
    })
  }

  function clearLinkCard() {
    if (root.linkCard && root.linkCard.thumbPath) root.removeTempFile(root.linkCard.thumbPath)
    root.linkCard = null
  }

  // ---- posting pipeline ------------------------------------------------------------------

  function collectImages() {
    var out = []
    for (var i = 0; i < imageModel.count; i++) {
      var it = imageModel.get(i)
      out.push({
        path: it.path,
        mime: it.mime,
        alt: it.alt || "",
        aspectWidth: it.aspectWidth,
        aspectHeight: it.aspectHeight
      })
    }
    return out
  }

  function startPost() {
    if (root.sending) return
    if (!root.configured) {
      root.setupMode = true
      flash("Sign in first", true)
      return
    }
    var text = composer.text
    var images = root.collectImages()
    var v = Api.validate(text, images.length)
    if (v) return root.flash(v, true)
    root.sending = true
    root.uploadRetried = false
    root.setStatus("Sending…")
    root.ensureSession(function(err) {
      if (err) return root.postFailed(err)
      root.resolveMentions(text, function(err2, didMap) {
        if (err2) return root.postFailed(err2)
        if (images.length > 0) {
          root.uploadQueue = images
          root.uploadedBlobs = []
          root.uploadImages(0, function(err3, blobs) {
            if (err3) return root.postFailed(err3)
            root.createPost(text, didMap, blobs)
          })
        } else {
          root.createPost(text, didMap, [])
        }
      })
    })
  }

  function resolveMentions(text, cb) {
    var handles = Api.mentionHandles(text)
    if (handles.length === 0) return cb(null, {})
    var didMap = {}
    var idx = 0
    var next = function() {
      if (idx >= handles.length) return cb(null, didMap)
      var h = handles[idx++]
      root.setStatus("Resolving @" + h + "…")
      Api.getProfile(h, function(err, prof) {
        if (err) return cb({ message: "Mention lookup failed for @" + h, status: err.status || 0 })
        didMap[h.toLowerCase()] = prof.did
        next()
      })
    }
    next()
  }

  function uploadImages(idx, cb) {
    if (idx >= root.uploadQueue.length) return cb(null, root.uploadedBlobs)
    var img = root.uploadQueue[idx]
    root.setStatus("Uploading image " + (idx + 1) + "/" + root.uploadQueue.length + "…")
    blobProc.start(img.mime, img.path, function(err, blobObj) {
      if (err && err.status === 401 && !root.uploadRetried) {
        root.uploadRetried = true
        return root.refreshTokens(function(e2) {
          if (e2) return cb(e2)
          root.uploadImages(idx, cb)
        })
      }
      if (err) return cb(err)
      root.uploadedBlobs.push({
        blob: blobObj,
        alt: img.alt,
        aspectWidth: img.aspectWidth,
        aspectHeight: img.aspectHeight
      })
      root.uploadImages(idx + 1, cb)
    })
  }

  function createPost(text, didMap, blobs) {
    root.setStatus("Posting…")
    var opts = { text: text, langs: [root.lang] }
    var facets = Api.buildFacets(text, didMap)
    if (facets.length) opts.facets = facets
    if (root.replyRef) {
      var parent = { uri: root.replyRef.uri, cid: root.replyRef.cid }
      var rootRef = root.replyRef.root || parent
      opts.reply = { root: rootRef, parent: parent }
    }
    if (blobs.length > 0 && root.quoteRef)
      opts.embed = Api.recordWithMediaEmbed(
        { uri: root.quoteRef.uri, cid: root.quoteRef.cid }, Api.imagesEmbed(blobs))
    else if (blobs.length > 0)
      opts.embed = Api.imagesEmbed(blobs)
    else if (root.quoteRef)
      opts.embed = Api.recordEmbed({ uri: root.quoteRef.uri, cid: root.quoteRef.cid })
    else if (root.linkCard && root.linkCard.uri)
      opts.embed = Api.externalEmbed(root.linkCard.uri, root.linkCard.title, root.linkCard.description, root.linkCard.blob)
    var record = Api.buildRecord(opts)
    root.authedCall(function(token, done) {
      Api.createRecord(root.pds, token, root.session.did, record, function(err, uri) {
        done(err, uri)
      })
    }, function(err, uri) {
      if (err) return root.postFailed(err)
      root.postSuccess(uri)
    })
  }

  function postFailed(err) {
    root.sending = false
    root.flash(err && err.message ? err.message : "Post failed", true)
  }

  function postSuccess(uri) {
    root.sending = false
    if (root.linkCard && root.linkCard.thumbPath) {
      var files = root.tempFiles.slice()
      files.push(root.linkCard.thumbPath)
      root.tempFiles = files
    }
    root.cleanupTempFiles()
    root.flash("Posted ✓", false)
    Quickshell.execDetached(["notify-send", "Bluesky", "Posted to your timeline ✓"])
    postDoneTimer.restart()
  }

  function clearDraftAndClose() {
    composer.clearDraft()
    imageModel.clear()
    root.replyRef = null
    root.quoteRef = null
    root.clearLinkCard()
    root.clearStatus()
    root.dismiss()
  }

  // ---- processes ---------------------------------------------------------------------------

  Process {
    id: initStorage
    command: ["sh", "-c",
      "umask 077; mkdir -p \"$1\" && chmod 700 \"$1\" && touch \"$1/prefs.json\" \"$1/session.json\" \"$1/app-password\" && chmod 600 \"$1/session.json\" \"$1/app-password\"",
      "bsky-storage", root.stateDir]
    running: true
    onExited: function(code) {
      if (code === 0) root.storageReady = true
      else console.warn("bsky: could not initialize state directory")
    }
  }

  // Generic 0600 secret writer (session tokens, app password). Queued.
  Process {
    id: writeFileProc
    property string payload: ""
    property var onDone: null
    property var writeQueue: []
    stdinEnabled: true
    onStarted: {
      write(payload)
      stdinEnabled = false
    }
    onExited: function(code) {
      stdinEnabled = true
      var f = onDone
      onDone = null
      if (f) f(code)
      var next = writeQueue.shift()
      if (next) writeSecret(next.file, next.content, next.cb)
    }
    function writeSecret(fileName, content, cb) {
      if (running) {
        writeQueue.push({ file: fileName, content: content, cb: cb })
        return
      }
      payload = content
      onDone = cb
      command = ["sh", "-c",
        "umask 077; cat > \"$1.new\" && chmod 600 \"$1.new\" && mv -f \"$1.new\" \"$1\"",
        "bsky-write", root.stateDir + "/" + fileName]
      running = true
    }
  }

  // Reads the clipboard image (grab-image.sh prints "mime\tpath\tsize").
  Process {
    id: grabProc
    property bool manual: false
    command: [root.pluginDir + "bin/grab-image.sh"]
    stdout: StdioCollector {
      id: grabOut
      waitForEnd: true
    }
    onExited: function(code) {
      var out = grabOut.text.trim()
      if (code === 0 && out) {
        var parts = out.split("\t")
        if (parts.length >= 3) root.addImage(parts[0], parts[1], parseInt(parts[2], 10) || 0)
      } else if (grabProc.manual) {
        pasteTextProc.manual = true
        pasteTextProc.running = true
      }
    }
  }

  // Manual Ctrl+V fallback: paste clipboard text at the cursor.
  Process {
    id: pasteTextProc
    property bool manual: false
    command: ["sh", "-c", "wl-paste --type text 2>/dev/null || true"]
    stdout: StdioCollector {
      id: pasteOut
      waitForEnd: true
    }
    onExited: function(code) {
      var t = pasteOut.text
      if (t) {
        composer.insertClipboardText(t)
      } else if (pasteTextProc.manual) {
        root.flash("Nothing to paste", true)
      }
      pasteTextProc.manual = false
    }
  }

  // Generic blob upload (upload-blob.sh prints uploadBlob JSON, "code|body" on stderr).
  Process {
    id: blobProc
    property var cb: null
    command: ["true"]
    stdout: StdioCollector {
      id: blobOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: blobErr
      waitForEnd: true
    }
    onExited: function(code) {
      var f = blobProc.cb
      blobProc.cb = null
      if (!f) return
      if (code === 0) {
        var json = null
        try { json = JSON.parse(blobOut.text) } catch (e) {}
        if (json && json.blob) return f(null, json.blob)
        return f({ message: "Upload returned no blob", status: 0 })
      }
      var e = blobErr.text || ""
      var m = e.match(/^(\d+)\|/)
      var status = m ? parseInt(m[1], 10) : 0
      var msg = (e.split("|")[1] || e || "upload failed").trim()
      f({ message: msg || "upload failed", status: status })
    }
    function start(mime, path, callback) {
      if (running) return callback({ message: "upload busy", status: 0 })
      blobProc.cb = callback
      command = [root.pluginDir + "bin/upload-blob.sh", Api.pdsRoot(root.pds),
        root.stateDir + "/session.json", mime, path]
      running = true
    }
  }

  // Downloads og:image for link cards (fetch-image.sh prints "mime\tpath\tsize").
  Process {
    id: thumbProc
    command: ["true"]
    stdout: StdioCollector {
      id: thumbOut
      waitForEnd: true
    }
    onExited: function(code) {
      var out = thumbOut.text.trim()
      if (code !== 0 || !out) {
        root.setStatus("Card ready (thumbnail unavailable)")
        return
      }
      var parts = out.split("\t")
      if (parts.length < 3) return
      var mime = parts[0]
      var path = parts[1]
      var size = parseInt(parts[2], 10) || 0
      if (root.linkCard) root.linkCard.thumbPath = path
      if (size > Api.MAX_IMAGE_BYTES) {
        root.rmFile(path)
        root.setStatus("Card ready (thumbnail too large)")
        return
      }
      blobProc.start(mime, path, function(err, blobObj) {
        if (!err && root.linkCard) root.linkCard.blob = blobObj
        root.setStatus(root.linkCard ? "Card ready" : "")
      })
    }
    function fetch(targetUrl) {
      if (running) return
      command = [root.pluginDir + "bin/fetch-image.sh", targetUrl]
      running = true
    }
  }

  Process {
    id: rmProc
    command: ["true"]
  }

  // ---- persisted state -------------------------------------------------------------------------

  FileView {
    id: prefsView
    path: root.storageReady ? root.stateDir + "/prefs.json" : ""
    onLoaded: {
      try {
        var data = JSON.parse(text() || "{}")
        if (data && typeof data === "object") {
          root.handle = String(data.handle || "")
          root.pds = Api.pdsRoot(data.pds || "")
        }
      } catch (e) {}
    }
  }

  FileView {
    id: sessionView
    path: root.storageReady ? root.stateDir + "/session.json" : ""
    onLoaded: {
      try {
        var data = JSON.parse(text() || "{}")
        if (data && data.accessJwt && data.refreshJwt && data.did)
          root.session = { accessJwt: data.accessJwt, refreshJwt: data.refreshJwt, did: data.did, handle: data.handle || root.handle }
      } catch (e) {}
    }
  }

  FileView {
    id: passwordView
    path: root.storageReady ? root.stateDir + "/app-password" : ""
    onLoaded: root.appPassword = (text() || "").trim()
  }

  // Reads intrinsic image dimensions for the embed aspectRatio.
  Image {
    id: dimProbe
    visible: false
    width: 0
    height: 0
    source: root.dimProbePath ? Util.fileUrl(root.dimProbePath) : ""
    asynchronous: true
    onStatusChanged: {
      if (status !== Image.Ready && status !== Image.Error) return
      if (status === Image.Ready && root.dimProbeIndex >= 0 && root.dimProbeIndex < imageModel.count) {
        imageModel.setProperty(root.dimProbeIndex, "aspectWidth", sourceSize.width)
        imageModel.setProperty(root.dimProbeIndex, "aspectHeight", sourceSize.height)
      }
      root.dimProbePath = ""
      root.dimProbeIndex = -1
    }
  }

  // ---- timers ------------------------------------------------------------------------------------

  Timer {
    id: statusClearTimer
    interval: 4000
    onTriggered: root.clearStatus()
  }

  Timer {
    id: postDoneTimer
    interval: 700
    onTriggered: root.clearDraftAndClose()
  }

  // ---- window --------------------------------------------------------------------------------------

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "thenitai-bsky"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardMaxHeight,
        card.contentTopInset + card.contentBottomInset + cardColumn.implicitHeight)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: function(mouse) {} }

      Column {
        id: cardColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        anchors.topMargin: card.contentTopInset
        spacing: root.contentSpacing

        Row {
          id: headerRow
          width: parent.width
          spacing: root.contentSpacing
          visible: root.configured

          Text {
            id: headerTitle
            y: (parent.height - height) / 2
            visible: !root.setupMode
            text: "Bluesky"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Item {
            width: Math.max(0, parent.width
              - (headerTitle.visible ? headerTitle.width + parent.spacing : 0)
              - (accountLabel.visible ? accountLabel.width + parent.spacing : 0)
              - settingsButton.width)
            height: 1
          }

          Text {
            id: accountLabel
            y: (parent.height - height) / 2
            visible: !root.setupMode
            text: "@" + root.handle
            color: root.foreground
            opacity: 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            id: settingsButton
            y: (parent.height - height) / 2
            text: root.setupMode ? "Back" : "Settings"
            enabled: !root.savingSetup && !root.sending
            onClicked: {
              root.setupMode = !root.setupMode
              Qt.callLater(root.focusDefault)
            }
          }
        }

        Text {
          visible: root.statusText !== ""
          width: parent.width
          text: root.statusText
          textFormat: Text.PlainText
          color: root.statusIsError ? root.errorColor : root.foreground
          opacity: root.statusIsError ? 1 : 0.62
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Setup {
          id: setup
          visible: !root.configured || root.setupMode
          width: parent.width
          foreground: root.foreground
          errorColor: root.errorColor
          fontFamily: root.fontFamily
          contentSpacing: root.contentSpacing
          busy: root.savingSetup
          onSaved: function(handle, password, pds) { root.saveCredentials(handle, password, pds) }
          onDismissRequested: function() {
            if (root.configured) {
              root.setupMode = false
              Qt.callLater(root.focusDefault)
            } else root.dismiss()
          }
        }

        Composer {
          id: composer
          visible: root.configured && !root.setupMode
          width: parent.width
          imageModel: imageModel
          replyRef: root.replyRef
          quoteRef: root.quoteRef
          linkCard: root.linkCard
          sending: root.sending
          foreground: root.foreground
          errorColor: root.errorColor
          fontFamily: root.fontFamily
          contentSpacing: root.contentSpacing
          onPostRequested: root.startPost()
          onPasteRequested: root.grabClipboardImage(true)
          onDismissRequested: root.dismiss()
          onReplyRequested: root.resolveRef("reply")
          onQuoteRequested: root.resolveRef("quote")
          onClearReplyRequested: root.replyRef = null
          onClearQuoteRequested: root.quoteRef = null
          onLinkCardRequested: root.buildLinkCard()
          onClearLinkCardRequested: root.clearLinkCard()
          onImageRemoved: function(path) { root.removeTempFile(path) }
        }
      }
    }
  }
}
