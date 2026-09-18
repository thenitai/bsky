# bsky

Post to Bluesky from anywhere on Omarchy. Hit a global shortcut, type (or paste
a screenshot), Enter. A tiny composer overlay for the Omarchy Quattro shell.

![preview](preview.png)

## Features

- **Global shortcut** composer overlay — summon from any workspace, Esc closes
- **Text posts** with a 300-character grapheme counter, link and `@mention`
  facets (clickable on Bluesky)
- **Clipboard images** — an image on the clipboard is auto-attached when the
  composer opens; up to 4 images per post, each with alt text and correct
  aspect ratio. GIF/BMP clipboard images are converted to PNG via ffmpeg.
- **Reply & quote** — include a `bsky.app` post URL in your text, then hit
  *Reply* or *Quote*
- **Link cards** — with a plain URL and no image, *Link card* fetches
  OpenGraph data (title, description, thumbnail) for an embed
- **Session management** — access tokens are cached and refreshed
  automatically; the app password is only used to (re-)login

## Install

```sh
omarchy plugin add https://github.com/thenitai/bsky.git --enable
```

## Setup

1. Create an app password at **bsky.app → Settings → App passwords** (never
   use your main password).
2. Press the composer shortcut — the first run shows the sign-in form.
   Enter your handle (e.g. `alice.bsky.social`) and the app password.
3. Optional: enter a custom PDS URL if your account is not on `bsky.social`.

Credentials are stored in `~/.config/omarchy-bsky/` (directory mode `0700`,
secret files `0600`), never in `shell.json`.

## Global shortcut

Plugins cannot edit Hyprland config themselves, so add one line to
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + B", "Post to Bluesky", "omarchy-shell shell toggle thenitai.bsky")
```

Pick any free combo you like.

## Keyboard

| Key | Action |
| --- | --- |
| `Esc` | Close (draft is kept) |
| `Ctrl+Enter` | Post |
| `Ctrl+V` | Attach clipboard image, or paste text at the cursor |
| Click outside | Close |

## API notes

Everything goes through the standard AT Protocol XRPC endpoints on your PDS
(`createSession`, `refreshSession`, `uploadBlob`, `createRecord`) plus
unauthenticated AppView reads (`getProfile`, `getPostThread`) on
`public.api.bsky.app` for reply/quote resolution and mention DIDs. The access
JWT is handed to `curl` through a `0600` temp header file, never through argv
or the environment.

Limits enforced client-side: 300 graphemes, 4 images, 5 links, images under
1 MB in JPEG/PNG/WebP.

Not implemented (yet): video embeds (requires the separate video upload
service), self-labels, scheduled posts.

## Remove

```sh
omarchy plugin remove thenitai.bsky
rm -rf ~/.config/omarchy-bsky   # credentials
```

Revoke the app password in bsky.app settings when you're done.

## License

MIT
