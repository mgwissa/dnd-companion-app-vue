# TTRPG Companion

Vue app for **campaigns, notes, characters, links, and party HP**—system-neutral tabletop RPG session tools.

## Stack

Vue 3, Vite, Pinia, Vue Router, Supabase.

This project began as a Vite + Vue template; see Vue / Vite docs for generic tooling notes below.

## Recommended IDE Setup

[VSCode](https://code.visualstudio.com/) + [Volar](https://marketplace.visualstudio.com/items?itemName=Vue.volar) (and disable Vetur).

## Type Support for `.vue` Imports in TS

TypeScript cannot handle type information for `.vue` imports by default, so we replace the `tsc` CLI with `vue-tsc` for type checking. In editors, we need [Volar](https://marketplace.visualstudio.com/items?itemName=Vue.volar) to make the TypeScript language service aware of `.vue` types.

## Customize configuration

See [Vite Configuration Reference](https://vite.dev/config/).

## Project Setup

```sh
npm install
```

### Compile and Hot-Reload for Development

```sh
npm run dev
```

### Type-Check, Compile and Minify for Production

```sh
npm run build
```

### Run Unit Tests with [Vitest](https://vitest.dev/)

```sh
npm run test:unit
```

### Lint with [ESLint](https://eslint.org/)

```sh
npm run lint
```


## Reviewed session imports

Apply `supabase/migrations/012_session_import.sql` before deploying the session UI. The migration adds explicit `notes.note_type` (`note`, `session`, `transcript`), `played_on`, `resume_point`, `session_import_key`, and `parent_session_id`. Existing notes stay ordinary notes; no dates or session types are inferred from titles. New sessions created from Notes or the hub are typed sessions. The hub queries sessions separately from recent notes, ordered by played date then creation date, and displays the latest session’s stopping point. Undated sessions sort after dated sessions.

Notes → **Import session** accepts a version 1 `dnd-session` JSON object. Required fields: `id` (stable source identifier), `title`, `recap`, `resumePoint`, and `threads` (string array). Optional text fields: `discoveries`, `npcsAndLocations`, `loot`, `uncertainties`, `transcript`; `playedOn` is `YYYY-MM-DD` or null when unknown. A first real session is in `session-imports/unicorn-gate-river-session.json`; it contains the unedited private source transcript, so it is deliberately outside public assets.

The preview lets the user edit all sections and suggested thread titles, choose a played date, choose sharing, and select threads (unchecked initially). Selected threads are campaign-shared even when the recap is private. `import_session_pack` runs as the authenticated caller under RLS and saves the recap, a separate permanently private transcript note, and selected threads in one transaction. Re-importing the same pack ID for the same user/campaign is rejected, and existing open thread titles are matched case-insensitively. Source notes link to their session and cascade on deletion. Sessions remain editable in Notes, including played date and stopping point. HP, character inventory, and conditions are never inferred or changed. Legacy note JSON import/export remains available separately; it imports notes privately.


Session notes also offer **Create recap link**, **Copy link**, and **Revoke link**. The root URL `?recap=<random UUID>` works on a fresh GitHub Pages visit without a sign-in or campaign membership. `LandingView` selects `SharedRecapView` for that query; it renders plain text headings, paragraphs, and lists without HTML injection. The `get_shared_recap` RPC uses a narrow security-definer projection (title, body, stopping point, played date only); it never returns source notes or account data. The link is separate from campaign sharing and follows saved recap edits. `notes.recap_share_token` can be set only through normal owner RLS; a constraint limits tokens to session notes. Revocation clears the token, making subsequent reads unavailable. No broad anonymous note SELECT policy is added.


### Journal reading view

Saved notes open in a formatted reading view; owners can switch between Read and Edit without discarding the current draft. New notes open in Edit. Source transcripts stay literal plain text. `MarkdownContent.vue` is the shared GFM renderer for notes, import previews, stopping points, and public recaps; it uses Marked and sanitizes every result with DOMPurify (HTML profile, inline styles and forms excluded). Headings, emphasis, nested lists, links, tables, blockquotes, and fenced code use the existing light/dark theme tokens. Session import has one visible picker backed by a native `hidden` input; scoped `visually-hidden` classes from other views are not available inside this component.
