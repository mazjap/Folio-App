# Folio — Developer Documentation

Folio is a native SwiftUI CMS client for managing the content of a Node.js/Express portfolio site. It targets macOS 26 and iOS 26 from a single build target (not Catalyst).

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Tech Stack & Requirements](#2-tech-stack--requirements)
3. [Architecture](#3-architecture)
4. [File Structure](#4-file-structure)
5. [Configuration & Settings](#5-configuration--settings)
6. [Data Layer](#6-data-layer)
7. [Networking](#7-networking)
8. [View Layer](#8-view-layer)
9. [Markdown Editor](#9-markdown-editor)
10. [Draft System](#10-draft-system)
11. [Media Handling](#11-media-handling)
12. [Apps Feature](#12-apps-feature)
13. [Patterns & Conventions](#13-patterns--conventions)
14. [Known Gotchas](#14-known-gotchas)
15. [Testing](#15-testing)

---

## 1. Project Overview

Folio CMS manages three kinds of content against a REST API:

| Tab | Content | API prefix |
|-----|---------|------------|
| Projects | Portfolio projects with hero image, description, tech stack, links, and media gallery | `/api/projects` |
| Posts | Blog posts with markdown content, tags, series, and hero image | `/api/posts` |
| Apps | Per-app privacy policy and support pages | `/api/apps/:id` |

All three tabs support full CRUD. There is no direct database access — everything goes through the portfolio site's HTTP API.

---

## 2. Tech Stack & Requirements

- **Xcode 26+**, single multiplatform target (iOS and macOS; not Catalyst)
- **Swift 6** language mode (`SWIFT_VERSION = 6.0`) with approachable concurrency (`SWIFT_APPROACHABLE_CONCURRENCY = YES`)
- **SwiftUI** — iOS 26.2 / macOS 26.1 minimum deployment
- **Textual** (SPM) — `StructuredText` component used for markdown preview in the post editor
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in the app target — all types are `@MainActor` by default; no annotation needed. Plain data that crosses isolation is marked `nonisolated` (see §14). The test targets don't set it.
- `PBXFileSystemSynchronizedRootGroup` — new files added to the `Folio/` directory are included in the build automatically; no need to manually add them to the project

**No xcconfig files.** The project previously used `Dev.xcconfig` / `Prod.xcconfig` to inject secrets at build time. This has been removed. All configuration is now entered manually in the Settings tab at runtime.

---

## 3. Architecture

### Layer diagram

```
Views  ──────────►  ViewModels  ──────────►  Repositories  ──────────►  URLProcessor
  │                     │                        │
  │ SwiftUI bindings     │ @Observable             │ typed throws(APIError)
  │ @State / @Binding    │ DraftSession            │ encode / decode JSON
  │                      │ injected repositories   │ multipart upload
  └──────────────────────┴────────────────────────-─┘
```

### Key design decisions

- **Single target** — one binary runs on iOS and macOS. Platform-specific code is gated with `#if os(macOS)`.
- **`@Observable`** — all ViewModels use the `@Observable` macro (not `ObservableObject`/`@Published`). Views observe only what they actually read, so updates are precise.
- **Typed throws** — the networking layer declares `throws(APIError)` throughout, so callers never need to cast errors and the compiler enforces exhaustive handling.
- **No navigation router** — navigation is handled directly by `NavigationStack` + `List(selection:)` + `.navigationDestination(item:)`. State is owned at the list level.
- **No global state** — there is no environment-injected app state. Each tab owns its own ViewModel.
- **Injected dependencies** — view models take their repositories, `DraftStore`, `UserDefaults`, and Keychain through their initializers, with the live ones as defaults. Tests and previews pass the `Test…` fakes that live next to each protocol (see §15).

---

## 4. File Structure

```
Folio/
├── Resources/
│   └── FolioApp.swift              @main entry point, WindowGroup + Settings scene (empty window under tests)
│
├── Models/
│   ├── HTTPRequestMethod.swift      HTTP method enum
│   ├── Media.swift                  MediaType, MediaContext, MediaItem
│   ├── Post.swift                   PostPreview, PostDetail, PostNav
│   ├── Project.swift                ProjectPreview, ProjectDetail, ProjectNav, ProjectStatus
│   └── App.swift                    AppPrivacyPolicy, AppSupport, AppRecord
│
├── Helpers/                         Extensions of other types (Type+Topic.swift)
│   ├── String+Slug.swift            String.slugified
│   ├── View+ErrorAlert.swift        .errorAlert($vm.error)
│   ├── View+StaleDraftAlert.swift   Keep / discard a draft older than the server's version
│   ├── URLRequest+HTTPMethod.swift  URLRequest.httpMethodType
│   ├── Array+Move.swift             Gallery reordering (move onto a target, move up/down)
│   ├── Date+CalendarDay.swift       Date-only values as midnight UTC
│   └── Date+Sample.swift            Date.sampleDate for sample data
│
├── APIError.swift                   Error enum used by all repository calls
├── ServerSettings.swift             FolioStorageKey, FolioEnvironment, ServerSettings, ServerURL (base URL checks)
├── ContentRules.swift               The server's validation rules, checked before saving
├── KeychainService.swift            KeychainStoring, KeychainService, TestKeychain
├── URLProcessor.swift               HTTP client, JSON coder, apiURL, media URL helpers
├── DraftStore.swift                 EditorDraft, the four draft types, DraftStore, line diff
├── DraftSession.swift               One editor's draft: baseline, debounced save, staleness, legacy and offline restore
├── EditorLoadState.swift            loading / loaded / failed, shared by the post and project editors
├── PendingImage.swift               Not-yet-uploaded image: loading from Photos / Files, conversion to a format the server takes
│
├── ProjectRepository.swift          Projects CRUD, ProjectUpdate, TestProjectRepository, ProjectDetail.sample
├── PostRepository.swift             Posts CRUD, PostUpdate, TestPostRepository, PostDetail.sample
├── MediaRepository.swift            Upload / delete, deleteUnusedFiles, TestMediaRepository
├── AppsRepository.swift             App pages CRUD, AppPrivacyPolicyUpdate, AppSupportUpdate, TestAppsRepository, samples
│
├── ContentListViewModel.swift       Generic list VM; PostsViewModel / ProjectsViewModel typealiases
├── ProjectFormViewModel.swift       Edit/Create VM for a single project
├── PostEditorViewModel.swift        Edit/Create VM for a single post
├── AppPrivacyPolicyEditorViewModel.swift
├── AppSupportEditorViewModel.swift
│
├── ContentView.swift                Root TabView (.sidebarAdaptable)
├── ProjectsView.swift               List + NavigationStack for projects
├── ProjectFormView.swift            Form + inspector panel for a project
├── ProjectPreview.swift             ProjectListRow + ProjectStatusBadge
├── PostsView.swift                  List + NavigationStack for posts
├── PostEditorView.swift             Editor + inspector + markdown preview for a post
├── PostListRow.swift                Single row in the posts list
├── HeroImageRow.swift               Hero image preview + picker, shared by both editors
├── MediaManagerView.swift           Drag-to-reorder project gallery
├── MarkdownEditorView.swift         NSViewRepresentable / UIViewRepresentable text editor
├── MarkdownToolbar.swift            Formatting toolbar, MarkdownToolbarLabel, InsertImageButtons
├── MarkdownPreview.swift            Rendered markdown (Textual) for every editor's Preview
├── EditorStatusViews.swift          LoadStateOverlay, LoadProblemBanner, DraftNotSavedLabel
├── ValidationIssuesView.swift       Why an editor can't save yet
├── DraftMenu.swift                  Toolbar menu for an unpublished draft
├── SaveToolbarButton.swift          Prominent Save / Publish button
├── ContentListOverlay.swift         Spinner / error / empty state for the lists
├── AppsView.swift                   Apps list + AppsViewModel (UserDefaults-backed)
├── AppDetailView.swift              Per-app detail: links to privacy + support editors, load errors with Try Again
├── AppPrivacyPolicyEditorView.swift
├── AppSupportEditorView.swift
└── SettingsView.swift               SettingsViewModel + Dev/Prod environment picker, URL/key entry

FolioTests/                          Swift Testing suites, one per type (see §15)
```

---

## 5. Configuration & Settings

### Environments

The app supports two environments switchable at runtime via a segmented picker in Settings. There is no build-time configuration.

| Setting | Storage | Key |
|---------|---------|-----|
| Active environment (`"dev"` or `"prod"`) | UserDefaults | `folio.activeEnvironment` |
| Dev base URL | UserDefaults | `folio.dev.baseURL` |
| Prod base URL | UserDefaults | `folio.prod.baseURL` |
| Dev API key | Keychain | `folio.dev.apiKey` |
| Prod API key | Keychain | `folio.prod.apiKey` |

All constants live in `FolioStorageKey` (in `ServerSettings.swift`); `FolioEnvironment` maps each environment to its keys.

### How the active environment is resolved

`ServerSettings` reads the active `FolioEnvironment` from UserDefaults and returns its base URL (`baseURLString`) and API key (`apiKey()`, from the Keychain, which throws if the Keychain can't be read). It reads fresh on every access. `URLProcessor.fromSettings()` and the URL helper functions (`mediaURL(for:)`, `resolveMarkdownImageURLs(_:)`) use it by default, so switching the picker in Settings takes effect immediately for all subsequent requests; no restart required. The helpers take a `baseURL:` argument so tests don't depend on settings.

Switching environments mustn't change what's already open, though:

- **Lists** remember the environment they loaded from (`loadedEnvironment`). `PostsView` / `ProjectsView` call `environmentDidChange()` when the picker changes, which clears the items and selection and loads the new environment's. Deleting refuses if the environment changed since the list loaded.
- **Editors** record the environment they were opened from (`environment`, shown as the navigation subtitle and in delete confirmations) and call `checkEnvironment()` before every upload, save, delete, and file cleanup. A change throws `APIError.environmentChanged(openedFrom:)` instead of sending anything to the other server. The check runs on the main actor just before each repository call, which builds its `URLProcessor` synchronously, so the request goes to the server that was checked.
- **App pages**: `AppDetailView` reloads when the environment changes, and its editors pin their environment the same way.

### Base URLs

Settings saves a base URL and API key together, only when **Save** is pressed, so a half-typed address never becomes the active server. `ServerURL.normalize(_:)` checks it first: an `https` URL with a host (or `http` for `localhost` / `127.0.0.1`, matching `Info.plist`), no query or fragment, and not ending in `/api` (Folio adds that). It also trims trailing slashes. `URLProcessor.fromSettings()` applies the same check, so a bad stored value throws `.invalidURL`. Saving an empty API key removes the saved one.

### `Info.plist`

Contains only `NSAppTransportSecurity` (allowing HTTP to `localhost` for local dev). There are no build-variable injections.

### Keychain

`KeychainService` (behind the `KeychainStoring` protocol) is a thin wrapper around `SecItemUpdate` / `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`. It stores one string per key under `kSecClassGenericPassword`, identified by account alone (as it always has been; adding a service now would stop finding existing keys). Saving updates the existing item and only adds one when there isn't one, so a failure can't leave the old key deleted. Reads and deletes throw `KeychainError` for anything but success or "not found", so a locked Keychain is reported rather than looking like a missing key. The key is saved only by Settings' explicit **Save**, and a failed save shows the Keychain's error rather than a "saved" confirmation. `SettingsViewModel` holds the fields and does the saving.

---

## 6. Data Layer

### Models overview

**Projects**

```swift
ProjectPreview   // Used in the list: id, title, tagline, heroImage, category, status, featured, createdAt, updatedAt
ProjectDetail    // Full project: everything in Preview + description, media, techStack, links
ProjectNav       // Minimal: id, title, status (used for related-project pickers elsewhere)
ProjectStatus    // .active | .inProgress | .archived
```

`ProjectDetail` extends `ProjectPreview` via a convenience initialiser and exposes `.preview` and `.nav` computed properties to avoid re-fetching when only a subset is needed after a save.

**Posts**

```swift
PostPreview      // id, title, excerpt, heroImage?, tags, createdAt, updatedAt?, readingTime, series?
PostDetail       // Adds: content
PostNav          // id, title, tags, createdAt, series?
```

**Apps**

```swift
AppPrivacyPolicy // id (= app slug), appName, lastUpdated (yyyy-MM-dd string), content (markdown), contactUrl?, contactText?
AppSupport       // id, appName, version, subtitle, content (markdown), contactUrl?, contactText?
AppRecord        // id only — the local list of known app slugs stored in UserDefaults
```

### Dates

All `Date` fields are encoded/decoded as ISO 8601 strings. The `URLProcessor`'s shared encoder/decoder both use `.iso8601` strategy. `AppPrivacyPolicy.lastUpdated` is the exception — it stores a plain `yyyy-MM-dd` string (see §12).

### Update payloads

The server merges a `PUT` body into the stored item (`{ ...existing, ...req.body }`), so a field left out of the request keeps its old value. `ProjectUpdate` and `PostUpdate` therefore send **every field the editor owns**, and their custom `encode(to:)` writes a `nil` optional as `null`, which clears it on the server:

```swift
try container.encode(heroImage, forKey: .heroImage)       // nil → "heroImage": null (clears it)
try container.encodeIfPresent(createdAt, forKey: .createdAt)  // nil → left out (keeps it)
```

`AppPrivacyPolicyUpdate` and `AppSupportUpdate` do the same for app pages, so clearing a contact URL or button title sends `null`. (They used to be saved with the models' synthesized encoding, which leaves `nil` out, so the server kept the old values.)

A project's `heroImage` is a required string, so clearing it sends `""`. Only `createdAt` is left out when `nil`; editing it via the inspector DatePicker sends the new date. The server computes posts' `readingTime` itself on create and update; the client's estimate is only for display.

---

## 7. Networking

### `URLProcessor`

The central HTTP client. Each call requires constructing a fresh `URLProcessor` via `URLProcessor.fromSettings()`, which reads the active environment's URL and API key. This means environment switches take effect immediately without restarting.

```swift
let p = try URLProcessor.fromSettings()  // throws .invalidURL if URL is empty/malformed
let data = try await p.get(p.apiURL("posts", id))   // <base>/api/posts/<id>
let decoded = try p.decode(MyType.self, from: data)
```

Available methods: `get`, `post`, `put`, `delete`, `upload`. All throw `APIError` typed errors. `GET`s are unauthenticated; everything else sends the Bearer token. The `session` defaults to `URLSession.shared`; tests pass one backed by a stub `URLProtocol`.

### `APIError`

```swift
enum APIError: Error {
    case unauthorized                       // 401 — "check your API key in Settings"
    case notFound                           // 404
    case conflict                           // 409 — duplicate ID
    case httpError(statusCode:, message:)   // other 4xx/5xx, with the server's `error` text
    case encodingFailed                     // JSON encode failure
    case decodingFailed                     // JSON decode failure
    case networkFailed                      // URLSession error
    case invalidURL                         // empty or unusable base URL
    case keychain                           // the API key couldn't be read
    case environmentChanged(openedFrom:)    // an editor's environment isn't the active one any more
    case cleanupFailed(count:, underlying:) // saved, but unused files couldn't be deleted
}
```

The server answers a rejected request with `{ "error": "…" }` (like "Invalid project: tagline can't be empty"). `URLProcessor.serverMessage(in:)` decodes it, shortened past 500 characters, and `httpError` shows it as the error's description; without one it says "Server error (<status>)".

`error.isCancellation` returns true when a request was cancelled (the `.task` that loaded it went away). Cancellations are never shown, in loads or in saves, uploads, and deletes.

### Multipart upload

`URLProcessor.upload(to:fileData:fileName:mimeType:context:id:)` constructs a `multipart/form-data` body with three fields: `context` (e.g. `"projects"`), `id` (the resource slug), and `file`. An optional `overwrite: true` field can be included for replace-in-place uploads.

### HTTP method convention

`URLRequest.httpMethodType` is a computed property (defined in `Models/HTTPRequestMethod.swift`) that converts between the `HTTPRequestMethod` enum and the `String`-typed `httpMethod` property.

---

## 8. View Layer

### Navigation structure

```
ContentView  (TabView .sidebarAdaptable)
├── ProjectsView  (NavigationStack)
│   └── ProjectFormView  (edit or create)
│       └── .inspector  ProjectFormView inspector panel
├── PostsView  (NavigationStack)
│   └── PostEditorView  (edit or create)
│       └── .inspector  PostEditorView inspector panel
├── AppsView  (NavigationStack)
│   └── AppDetailView
│       ├── AppPrivacyPolicyEditorView
│       └── AppSupportEditorView
└── SettingsView  (iOS only)
```

On macOS, `SettingsView` is only in the Settings window (`Settings { }`, ⌘,). A tab as well would mean two `SettingsViewModel`s, each with its own copy of the fields, which could save stale values over each other.

### List → detail pattern

`PostsView` and `ProjectsView` each own a `ContentListViewModel<Item>` (`PostsViewModel` / `ProjectsViewModel`), which holds the items and the navigation state:

- `selectedID: String?` — bound to `List(selection:)` and `.navigationDestination(item:)` (the edit form)
- `isCreatingNew` — bound to `.navigationDestination(isPresented:)` (the create form)

**Critical:** open the create form only through `startCreating()`, which clears `selectedID` before setting `isCreatingNew`. With both `navigationDestination` modifiers active at once, SwiftUI resolves to the `item:` destination (the already-selected edit view) instead of the create form.

`.onDisappear { vm.clearSelection() }` clears the selection when switching tabs, preventing stale navigation state from re-opening the detail view when returning to the tab.

Deleting from the list (swipe or context menu) only sets `pendingDeletion`; a confirmation naming the item and environment calls `delete(id:)`. (The dialog's button deletes the item it was presented with, since the dialog clears `pendingDeletion` as it closes.) Deleting also deletes the item's draft.

Loads are ordered by a generation count: `refresh()`, `appendOrReplace(_:)`, and `remove(id:)` each bump it, and a load that finishes after a newer load or local change is ignored, so a slow refresh can't replace a just-saved item with its old version. A cancelled load (like switching tabs before the first load finished) doesn't count as loaded, so `loadIfNeeded()` tries again the next time the list appears.

### ViewModel lifetime

Editor ViewModels are created in the list view's destination closures, with the list's repositories and draft store, and held in `@State private var vm` inside the destination view. Each navigation push creates a fresh VM. The VM's `load()` is called from `.task { await vm.load() }` in the view's body.

### Editor load state

The post and project editors track `loadState` (`EditorLoadState`): `.loading`, `.loaded`, or `.failed(message:showsDraft:)`. Only a loaded item can be saved (`canSave`), so a failed load can never publish empty fields over the server's version (it used to: typing a title into the empty form after a failed load and publishing erased the post). While loading, the form is disabled under a spinner (`LoadStateOverlay`). If the load fails and there's no draft, the overlay shows the error and **Try Again**. If there is a draft, the editor shows it with a banner (`LoadProblemBanner`): it can be edited (and keeps autosaving), but not saved until **Try Again** loads the server's version, which the draft is then restored over.

`canSave` also requires that nothing is saving and that `validationIssues` is empty. The issues come from `ContentRules` (a copy of the server's rules in `backend/src/lib/schemas.ts` and `paths.ts`: required fields, lengths, list sizes, link schemes, slugs that aren't `index`, `nav`, or over 100 characters) and are listed in the editor by `ValidationIssuesView`. New items show their public path (`/blog/<slug>`, `/projects/<slug>`) under the slug field. Keep `ContentRules` in step with the server.

```
List view owns: listVM (items, selectedID, isCreatingNew), repositories, DraftStore
Detail view owns: formVM (fresh per push)
```

### Inspector panel

Both `ProjectFormView` and `PostEditorView` use SwiftUI's `.inspector(isPresented:)` modifier. On macOS this becomes a trailing sidebar panel; on iOS it slides up as a sheet. The inspector contains status controls, date editors, and the delete button. It does not affect the main form — both regions are always live. The Dates section is shown for new items too (showing today until a date is picked), so they can be backdated when they're created.

### `@Observable` ViewModels

All ViewModels use the `@Observable` macro on the class. Properties views shouldn't observe (dependencies, bookkeeping) are `@ObservationIgnored`. Because the project has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, all VM methods and properties are automatically `@MainActor` without annotation.

```swift
@Observable
class ProjectFormViewModel {
    var title = ""   // No @Published needed
    // ...
}
```

---

## 9. Markdown Editor

`MarkdownEditorView` is a `NSViewRepresentable` (macOS) / `UIViewRepresentable` (iOS) that wraps a plain-text `NSTextView` / `UITextView`.

### Public API

```swift
MarkdownEditorView(
    text: $vm.description,            // Binding<String>
    pendingAction: $vm.pendingDescriptionAction,  // Binding<EditorAction?>
    highlightRanges: diffRanges        // [NSRange], default []
)
```

### `EditorAction`

Toolbar buttons communicate with the text view through a `pendingAction` binding rather than direct method calls (which would require storing a reference to the view, which isn't safe in SwiftUI).

```swift
enum EditorAction {
    case insertText(String)                                  // Insert at cursor / replace selection
    case wrap(prefix: String, suffix: String, placeholder: String)  // Bold, italic, code, link
    case prependLine(String)                                 // Heading prefixes (# , ## , etc.)
}
```

`MarkdownToolbar` sends the formatting actions; `InsertImageButtons` (its accessory in the post and project editors) uploads a picked image and the view model sends `.wrap(prefix: "![", suffix: "](path)", placeholder: "Describe the image")`, so the alt text is selected, ready to type over.

On iOS the text view's font is scaled with `UIFontMetrics` for the body style, with `adjustsFontForContentSizeCategory`, so it follows Dynamic Type. Toolbar items are at least 44 points square on iOS (28 on macOS), and the heading labels use a scaled text style.

`updateNSView`/`updateUIView` don't apply the action themselves: applying it changes the text (and, through the delegate, the `text` binding) and clears `pendingAction`, and changing state during a view update makes SwiftUI warn and can loop. `applyAfterUpdate` applies it in a main-actor `Task` right after the update, then clears the binding. The coordinator's `isApplyingAction` flag keeps updates that arrive in between from applying the same action twice.

### Re-entry guard

`Coordinator.isUpdating` is set to `true` while `updateNSView`/`updateUIView` copies the binding's text into the text view. The `textDidChange` / `textViewDidChange` delegate method is a no-op while `isUpdating` is true, so it doesn't write back to the binding and trigger another `updateNSView`.

### macOS teardown

`static func dismantleNSView(_ scrollView:, coordinator:)` nils the `NSTextView`'s delegate before teardown. Without this, AppKit may call delegate methods on a deallocated coordinator, causing `EXC_BAD_ACCESS`.

### Diff highlighting

When **Highlight Changed Lines** (in `DraftMenu`) is on, `highlightRanges` is set to the output of `computeChangedLineRanges(from:to:)`. It marks added and changed lines; deleted lines have nothing to highlight. It's macOS only: the iOS text view ignores `highlightRanges`, so `DraftMenu` doesn't offer it there, nor in app pages (pass no binding). On macOS, `NSLayoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.25))` is used — temporary attributes are display-only and don't affect the underlying `NSTextStorage`, so they're compatible with `isRichText = false`.

The Coordinator caches `lastHighlightRanges` and skips the layout manager call if the ranges haven't changed, avoiding unnecessary redraws on every keystroke.

`computeChangedLineRanges(from:to:)` (in `DraftStore.swift`) uses `CollectionDifference` to find inserted/changed lines, then walks the current text to convert line indices to `NSRange` character offsets.

### Image URL resolution for preview

Markdown content stores images as relative paths: `![alt](/media/posts/slug/uuid.webp)`. The `resolveMarkdownImageURLs(_:)` free function (in `URLProcessor.swift`) rewrites these, and reference definitions like `[hero]: /media/…`, to absolute URLs before passing content to `StructuredText`. It leaves fenced code blocks and inline code alone, since they show markdown rather than render it. Already-absolute URLs pass through unchanged. **Do not store absolute URLs in content** — the base URL changes between dev and prod.

`MarkdownPreview` wraps this for every editor's **Preview** toggle (posts, project descriptions, and both app pages). It's close to the published page, not identical: the site renders with its own Markdown components.

---

## 10. Draft System

Drafts persist in-progress edits to disk so they survive app termination. Each editor ViewModel (posts, projects, and both app pages) owns a `DraftSession<Draft>`, which saves `PostDraft` / `ProjectDraft` / `AppPrivacyPolicyDraft` / `AppSupportDraft` (all `EditorDraft`s) through a `DraftStore` as JSON files in `~/Library/Application Support/Folio/drafts/` (inside the sandbox container on macOS).

### Draft keys

Keys start with the environment (`dev.` or `prod.`), so Development and Production drafts of the same item stay apart (local content is a copy of the live site's, so the same IDs exist on both).

| Context | Key |
|---------|-----|
| New project | `<env>.new-project` |
| Editing project `slug` | `<env>.project-slug` |
| New post | `<env>.new-post` |
| Editing post `slug` | `<env>.post-slug` |
| Privacy policy / support page for app `slug` | `<env>.app-slug-privacy-policy` / `<env>.app-slug-support` |

`PostEditorViewModel.draftKey(for:environment:)` / `ProjectFormViewModel.draftKey(for:environment:)` build them. New items use `new-…`, which no ID can collide with (the old `post-new` was also the key of a post with the ID `new`). When a new item is first saved, its draft moves to the item's key. There's one new-item draft per kind and environment, so two windows creating posts at once share it.

**Legacy drafts.** Drafts saved before keys had an environment (`post-slug`, `post-new`) are found through `legacyDraftKey(for:)`, moved to the current environment's key, and restored as stale (`isLegacy`), so the editor asks whether to keep them: they may have been started on the other server.

### Baseline: only save real changes

The session saves nothing until the editor sets a **baseline**: the fields as loaded from the server, or the empty fields of a new item. After that, saving a draft that matches the baseline deletes the draft file instead of writing one. This is what keeps drafts honest:

- Opening an item and leaving doesn't leave a copy of it behind (a copy would later hide changes made on the server).
- A failed or cancelled load never sets a baseline, so leaving early can't save empty fields.
- Undoing your edits by hand deletes the draft.

`hasDraft` reflects whether a draft file with changes exists, so **Highlight Changed Lines** and **Discard Draft** appear as soon as an edit is autosaved.

### Failures

`DraftStore`'s `save`, `load`, and `clear` throw `DraftStore.DraftError`. The session sets `hasDraft` only after a save succeeds, reports every failure through `onError` (the editor shows it in its error alert), and sets `isFailing` after a failed save, which shows **Draft Not Saved** in the editor's toolbar. A draft that can't be read (like after a change to a draft type that wasn't optional) isn't treated as missing: `load` moves it to `<key>.unreadable-<timestamp>.json` and reports it, so the next autosave can't overwrite it.

### Autosave trigger

Every form field that belongs in drafts has a `didSet` that calls `fieldChanged()`, which hands the current draft to `draftSession.scheduleSave(_:)`. The save is debounced 2 seconds and the task holds the session weakly. The editor also saves immediately when it closes (`saveDraftNow()`, from `.onDisappear`) and when the app leaves the foreground (`scenePhase`), since iOS can suspend or quit an app without its views disappearing. Nothing is saved for an item that was just deleted.

Drafts include a picked hero image that hasn't been uploaded (`pendingHeroImage`, the image data itself) and the files uploaded while editing (`uploadedFiles`, see §11). `uploadedFiles` is stored as `nil` when empty, so drafts saved before it existed still compare as unchanged.

### `isPopulating` flag

`populate(from:)` (server data) and `populate(fromDraft:)` set `isPopulating` while they write fields. `fieldChanged()` and `createdAt.didSet`'s sync logic skip their side effects while it's set. Without it, every assignment during load would schedule a save of partially populated data.

### Load sequence (edit mode)

1. Fetch server data → `populate(from:)` (sets `serverContent`/`serverDescription` for diff, the server's `updatedAt`, and all form fields)
2. `draftSession.setBaseline(currentDraft)`
3. `draftSession.restore()` → if a draft with changes exists, `populate(fromDraft:)` layers it over the server data; a draft identical to the server's version is deleted

If the fetch fails, `draftSession.restoreOffline(empty:)` loads the draft with an empty baseline, so edits keep being saved over it (see "Editor load state" in §8). **Try Again** saves the draft first, then runs the normal sequence, which restores it over the server's version (with the usual stale check).

App pages have nothing to fetch (the detail view already loaded them), so their `load()` just sets the baseline and restores. They have no `updatedAt` on the server, so their drafts can't be detected as stale.

### Stale drafts

Each draft records the server's `updatedAt` for the version it started from (`serverUpdatedAt`; the server sets `updatedAt` on every update). If a restored draft's version doesn't match the server's, `isDraftStale` is set and the editor asks (`.staleDraftAlert`): **Keep Draft** keeps editing (and records the current version, so it doesn't ask again), **Discard Draft** shows the server's version. Publishing a stale draft would undo the newer changes on the server.

### Draft vs. server content

`serverContent` (posts) and `serverDescription` (projects) are `private(set)` properties set during `populate(from:)` but **not** overwritten by `populate(fromDraft:)`. They always reflect the last-saved server state, which is required for `computeDiffRanges()` to show what has changed.

### Save and discard

A successful save deletes the draft, moves to the item's key, repopulates from the server's response, and sets that as the new baseline, so leaving afterwards saves nothing. Edits made while the save was in flight aren't lost: the editor snapshots the fields it submitted, and if they changed by the time the response arrives, it layers the newer fields over the saved version and saves them as a draft. **Discard Draft** deletes the draft and repopulates from the baseline (the version the editor loaded); it doesn't refetch. It also deletes files uploaded for the draft that the baseline doesn't use.

The app page editors are disabled while saving instead, since saving closes them.

---

## 11. Media Handling

### Upload flow

`MediaRepository.upload(_:context:id:)` posts a `PendingImage` to `POST /api/media/upload` with a multipart body, named `<UUID>.<ext>` (`PendingImage.uploadFileName`). The server converts JPEG, PNG, WebP, GIF, and AVIF (up to 25 MB) to WebP named after the uploaded file's base name, and returns `{ "url": "/media/projects/slug/uuid.webp" }`. It rejects HEIC with 415, since prebuilt sharp can't decode it. The returned path is a **relative** server path, stored as-is. The gallery's pickers only offer images.

`PendingImage.prepare(_:)` gets every picked image ready first, off the main actor (`@concurrent`): it reads the actual format with ImageIO, keeps formats the server converts, and converts anything else (HEIC, which iPhone photos usually are, TIFF, …) to JPEG at quality 0.9, keeping metadata like orientation. It throws `PendingImage.ImportError` for unreadable images or ones over 25 MB, which the pickers show in an alert instead of silently skipping. The pickers show progress while preparing (`isImporting`) and are disabled meanwhile.

### New items and IDs

Uploads are stored under the item's ID, so a new post or project can't upload anything until its ID field is a valid slug (`canUploadFiles`; the image buttons and gallery are disabled until then). The ID field locks as soon as an upload starts (`hasUploadedFiles` counts `activeUploads` as well as `uploadedFiles`), since changing it would leave the files under the old ID. The upload captures the ID before it starts, and the lock survives reopening a draft, since `uploadedFiles` is part of it.

### Deleting unused files

Every upload is recorded in `uploadedFiles` (files the server's version doesn't use yet). After a successful save, the editor calls `MediaRepository.deleteUnusedFiles(previous:current:text:context:id:check:)` with the server's previous hero image (and gallery, for projects) plus `uploadedFiles` as candidates, and the saved files plus any edits made during the save as the ones to keep. It deletes candidates that are no longer used, but only files in the item's own folder (`/media/<context>/<id>/`) and not mentioned in its markdown, and ignores files already gone. Nothing is deleted when an image is removed in the editor, only once the save that drops it succeeds, so the live site never points at a deleted file. An image uploaded and removed again before saving is deleted too.

Cleanup runs before `saved` is set, and doesn't fail the save: files that couldn't be deleted stay in `uploadedFiles` (so the item keeps a draft, and the next save tries again), and the editor shows `APIError.cleanupFailed`, which says the item was saved. `check` runs before each deletion (the environment check).

Not covered here: the folder check isn't a check that no other item uses a file (that needs the server), deleting an item leaves its media folder, and uploads in drafts that are abandoned rather than discarded stay on the server. `npm run check` on the backend reports unreferenced media.

### Relative paths

All stored media URLs are relative (e.g. `/media/projects/slug/uuid.webp`). Two helpers resolve them at display time:

- `mediaURL(for path: String) -> URL?` — returns an absolute `URL` for use in `AsyncImage`. Prepends the active environment's base URL.
- `resolveMarkdownImageURLs(_ content: String) -> String` — rewrites `![alt](/path)` patterns in markdown before passing to `StructuredText`.
- `smallerMediaPath(for:width:)` — the server saves 640- and 1280-pixel copies beside each upload (`hero.w640.webp`). `MediaThumbnail` loads the 640 one and falls back to the original for images that don't have one yet.

Never store absolute URLs. The base URL differs between dev and prod, so absolute paths would break when switching environments.

### Hero images

Hero images follow the same relative-path rule. The hero image field stores a path like `/media/projects/slug/uuid.webp`. `ProjectFormView` and `PostEditorView` display it via `AsyncImage(url: mediaURL(for: vm.heroImage))`.

`HeroImageRow` (shared by both editors) shows the hero image and holds a newly picked one as a `PendingImage` until save. Upload happens at save time, not selection time. This avoids uploading images for forms that are never saved.

`PendingImage` holds the data, MIME type, and extension of a picked image, already prepared for upload. `PendingImage.load(from:)` loads one from a `PhotosPickerItem`; on macOS, `PendingImage.chooseFiles(allowsMultipleSelection:)` asks for files with an open panel and `load(contentsOf:)` loads a file (from the panel or a drop). `HeroImageRow` previews a picked image from a downsampled copy (`thumbnail(maxPixelSize:)`), made once per pick. Gallery images (`ProjectFormViewModel.addMedia(_:)`) and inline images upload immediately.

### File picker on macOS

SwiftUI's `.fileImporter` silently fails when nested inside `Form > Section` on macOS (can't find the window context). `PendingImage.chooseFiles()` uses `NSOpenPanel().runModal()` directly instead, for the hero image, inline images, and the gallery.

### Drag-to-reorder in media gallery

`MediaManagerView` renders media rows in a `VStack` (not a `List`, since `List` applies its own layout and doesn't compose well inside a `Form`). Reorder is implemented with `.draggable(item.id)` and `.dropDestination(for: String.self)` on each row, which call `Array.move(id:onto:)` (`Helpers/Array+Move.swift`): the dropped item takes the target's place, after it when moving down the list and before it when moving up. So dropping an item on its neighbor swaps them, and dropping on the last item moves it to the end. (The old `from < to ? to - 1 : to` made dropping on the next item do nothing, and nothing could reach the end.)

Each row also has **Move Up** / **Move Down** in its context menu and as accessibility actions (`move(id:by:)`), for keyboard and VoiceOver users, and a Remove button labeled with the file name.

---

## 12. Apps Feature

### Why UserDefaults for the app list

The portfolio API has no "list all apps" endpoint. The list of known app slugs is stored locally in UserDefaults as JSON-encoded `[AppRecord]` under the key `"folio.apps"`. The user manually adds app slugs via an alert dialog, and removes them with **Remove from List**, which only forgets the bookmark: the app's pages stay on the site. Each `AppRecord` contains only an `id` (the slug).

### Page load

`AppDetailViewModel.load()` fetches the privacy policy and support page **sequentially**, not concurrently. Each fetch can independently fail with `.notFound` (page doesn't exist yet) or another error. The VM tracks four states per page type: `missing`, the error (`privacyPolicyError` / `supportError`, shown with **Try Again**), the loaded value, and loading. The view renders the appropriate UI for each state, and reloads when the environment changes.

The editors (`AppPrivacyPolicyEditorViewModel`, `AppSupportEditorViewModel`) work like the post and project editors: drafts, an environment pin, validation (`ContentRules`), Preview, and update payloads that send cleared contact fields as `null`.

### `lastUpdated` date handling

`AppPrivacyPolicy.lastUpdated` is a `String` in `yyyy-MM-dd` format, not a `Date`, because it's a calendar day, not an instant. `AppPrivacyPolicyEditorViewModel` keeps it as midnight UTC on that day (`Date.calendarDay(in:)`), converting with a static POSIX, UTC `DateFormatter`, and its `DatePicker` shows it in UTC (`.environment(\.timeZone, .gmt)`). Showing a UTC date in the device's time zone used to show it a day early west of UTC, and save a picked date a day late. A new policy starts on today's local date.

---

## 13. Patterns & Conventions

### `saved` and `deleted` properties

Editor ViewModels signal completion via observable properties rather than callbacks in the VM itself:

```swift
var saved: ProjectPreview?   // Set after a successful save
var deleted = false          // Set after a successful delete
```

Views watch these with `.onChange(of:)` and call the appropriate parent callbacks:

```swift
.onChange(of: vm.saved) { _, preview in
    if let preview { onSave(preview) }
}
.onChange(of: vm.deleted) { _, gone in
    if gone { onDelete(); dismiss() }
}
```

This keeps the VM free of SwiftUI dependencies (`dismiss`, closures from parents) and makes it easier to test.

### `appendOrReplace`

List ViewModels expose `appendOrReplace(_ preview:)` to handle both create and update from the same callback:

```swift
func appendOrReplace(_ preview: ProjectPreview) {
    if let idx = projects.firstIndex(where: { $0.id == preview.id }) {
        projects[idx] = preview   // Update in place
    } else {
        projects.insert(preview, at: 0)   // Newly created
    }
}
```

### `createdAt` / `updatedAt` editing

Both posts and projects allow editing `createdAt` via a `DatePicker` in the inspector. `updatedAt` is read-only. When `createdAt` is changed to a date newer than `updatedAt`, the VM automatically sets `updatedAt = createdAt`:

```swift
var createdAt: Date? {
    didSet {
        if !isPopulating, let created = createdAt, let updated = updatedAt, created > updated {
            updatedAt = created
        }
        fieldChanged()
    }
}
```

The `isPopulating` guard prevents this sync from firing during the initial data load (where `createdAt` is set before `updatedAt`).

### Error display

All errors surface through an `error` property on the ViewModel: `APIError?` in the lists, `KeychainService.KeychainError?` in Settings, and `(any LocalizedError)?` in the editors, which also show draft errors (`DraftStore.DraftError`). Views show it with `.errorAlert($vm.error)` (`Helpers/View+ErrorAlert.swift`, with an overload for `any LocalizedError`), which presents an alert while the error is set and clears it when dismissed. Cancellations (`error.isCancellation`) are never assigned. Image import errors are shown by the picker views themselves.

### Task cancellation

Loads run from `.task` modifiers, which are cancelled when the view disappears. Saves, uploads, and deletes run from unstructured `Task {}`s in button actions, so they finish even if the editor closes. Cancellation errors are detected with `error.isCancellation` and silently discarded either way. The draft autosave task holds its `DraftSession` weakly, so it does nothing if the editor has gone away; there are no `deinit`s, since a main-actor class's `deinit` can't touch its stored properties in Swift 6.

---

## 14. Known Gotchas

### SourceKit incremental analysis errors

After editing any Swift file, SourceKit often reports "Cannot find type X in scope" errors in other files. These are incremental analysis artifacts. A full build (`⌘B`) always succeeds and clears them. Do not treat them as real compilation errors.

### `navigationDestination` conflict

Having both `navigationDestination(item:)` and `navigationDestination(isPresented:)` active simultaneously on the same `NavigationStack` causes SwiftUI to resolve to the `item:` destination. Open the create form only through `ContentListViewModel.startCreating()`, which clears `selectedID` first.

### `.fileImporter` in nested views on macOS

SwiftUI's `.fileImporter` cannot find its window context when applied inside `Form > Section`. Use `NSOpenPanel().runModal()` directly. This affects any file-picker button that lives inside a form.

### `.onMove` requires `List`

`.onMove` only works on `ForEach` inside a `List`. In `MediaManagerView`, media rows are in a `VStack` inside a `Form`, so drag-to-reorder is implemented with `.draggable` / `.dropDestination` instead.

### `NSTextView` delegate and teardown

Always nil the delegate in `dismantleNSView`. If the delegate is still set when AppKit tears down the scroll view, a delegate callback fires on a deallocated coordinator, causing `EXC_BAD_ACCESS`.

### Inline image paths must be relative

When inserting an image into post or project markdown content, the path must be relative (`/media/posts/slug/uuid.webp`), not absolute. The base URL is prepended at display time by `resolveMarkdownImageURLs`. Storing absolute URLs breaks when switching environments.

### Swift 6 isolation

- Types that conform to a protocol used across isolation (like `EditorDraft`, which `DraftSession` decodes generically) must be `nonisolated`, or their synthesized `Codable`/`Equatable` conformances become main-actor-isolated and don't compile.
- `PhotosPicker`'s label closure is `Sendable` and runs off the main actor. Compute anything it needs before the picker (`let hasHeroImage = …`), and give views created there a `nonisolated init` (`MarkdownToolbarLabel`).
- A Binding to a property of a `let` reference inside a view model (`$vm.draftSession.isStale`) doesn't compile; forward it through a computed property (`isDraftStale`).

### `.dropDestination` overloads

On macOS 26, `.dropDestination(for:)` has a `Void`-returning overload. A single-expression closure that evaluates to a `Bool` picks it and drops the result; write `return` explicitly to get the `Bool` version.

### Draft fields and schema evolution

The draft types are `Codable` structs stored as JSON. New optional fields can be added without breaking existing saved drafts — the decoder will set them to `nil` (as with `ProjectDraft.media`, `serverUpdatedAt`, `pendingHeroImage`, and `uploadedFiles`). Store "empty" as `nil` too, or an old draft won't compare equal to an unchanged editor. A draft that fails to decode is moved aside as `.unreadable-…` (see §10), not lost, but non-optional new fields still need a default value or a migration strategy.

---

## 15. Testing

`FolioTests` is a Swift Testing target hosted in the app (which shows an empty window under tests, so nothing loads from the server). Suites are `@MainActor`, one per type: `PostEditorViewModelTests`, `ProjectFormViewModelTests`, `ContentListViewModelTests`, `SettingsViewModelTests`, `AppPrivacyPolicyEditorViewModelTests` and `AppSupportEditorViewModelTests` (in one file), `URLProcessorTests`, and `HelperTests` (slugs and content rules, update payload encoding, URL helpers, markdown image resolution, reordering, calendar days, image preparation, line diff, unused-file cleanup).

### Fakes

Each protocol has a fake in the app target, in the same file, so previews can use them too:

| Fake | Records / controls |
|------|--------------------|
| `TestPostRepository`, `TestProjectRepository` | In-memory items; merge updates like the server; `updates`, `deletedIDs`, `fetchError`, `updateDate`. Posts also have `listError`, and `beforeList` / `beforeWrite` hooks to hold a request open |
| `TestMediaRepository` | `uploads`, `deletedFiles`, `uploadError`, `deleteError`, `beforeUpload` |
| `TestAppsRepository` | In-memory privacy policies and support pages; merges updates like the server (`null` clears); `privacyPolicyUpdates`, `supportUpdates`, `fetchError` |
| `TestKeychain` | `values`, `saveError`, `readError` |
| `DraftStore.temporary()` | An empty draft folder in the temporary directory |

`TestHelpers.swift` (test target) adds `makeUserDefaults()` (a fresh suite) and `makeUserDefaults(environment:)`, `sampleImage`, `StubURLProtocol` for testing `URLProcessor` against canned responses, and `Gate`, which a fake's `before…` hook awaits so a test can act while a request is in flight (`await gate.untilArrived()`, act, `gate.open()`). Editor and list view models take `userDefaults:` for their environment; pass a test suite so tests can switch environments. Sample data: `PostDetail.sample`, `ProjectDetail.sample`, `AppPrivacyPolicy.sample`, `AppSupport.sample`, `Date.sampleDate`.

### Regression tests

Every bug fix gets a test that fails without the fix, marked with a `/// Regression test: …` doc comment.
