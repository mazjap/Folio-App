# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Folio is a native SwiftUI CMS client for the user's portfolio site (a Node.js/Express REST API at jordan-christensen.com). It manages three kinds of content: **Projects** (`/api/projects`), **Posts** (`/api/posts`, markdown blog posts), and **Apps** (`/api/apps/:id/privacy-policy` and `/support`). There's no database access; everything goes through the site's HTTP API with a Bearer token.

One multiplatform target for iOS 26.2 and macOS 26.1 (not Catalyst). The only package dependency is [Textual](https://github.com/gonzalezreal/textual) (`StructuredText(markdown:)` with `.textual.structuredTextStyle(.gitHub)`) for the markdown preview.

The server is `~/Developer/Web Development/portfolio-attempt-20/backend` (routes in `src/routes/`). Read its handlers when a change depends on how the API behaves; don't change it from here.

`DEVDOC.md` is the detailed developer documentation (architecture, draft system, media, gotchas). Read the relevant section before changing a subsystem, and update it when you change how one works.

## Build settings that matter

- `SWIFT_VERSION = 6.0` with `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app target only; the test targets aren't main-actor by default, so test suites that touch app types are `@MainActor`). Everything in the app is `@MainActor` by default; don't add the annotation. Plain data that crosses isolation needs `nonisolated` (like `EditorDraft` and its conforming drafts, whose `Codable` conformances otherwise become main-actor-isolated). A main-actor class's `deinit` can't touch its stored properties.
- `PBXFileSystemSynchronizedRootGroup`: new files in `Folio/` join the build automatically. Don't edit `project.pbxproj` to add files.
- The macOS app is sandboxed with outgoing network connections and read-only user-selected files.

## Setup

There's no build-time configuration. Base URLs and API keys are entered at runtime in Settings, per environment (Dev/Prod): URLs in UserDefaults, keys in the Keychain (`KeychainService`), all keys named in `FolioStorageKey`. `Info.plist` only allows plain HTTP to `localhost`. `*.xcconfig` is gitignored. **Never hardcode or commit an API key or base URL.**

**Folio writes to the live portfolio site.** Never run the app, a test, or a `curl` against the Prod environment or jordan-christensen.com in a way that creates, updates, deletes, or uploads anything without asking the user and getting an explicit yes, every time. Read-only `GET`s are fine. Tests must never touch the network (use fakes; see Testing).

## Commands

There's no linter or formatter. Build and test with `xcodebuild` (or Xcode):

```sh
# Build (macOS is fastest)
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=macOS'

# Build for iOS
xcodebuild build -project Folio.xcodeproj -scheme Folio -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3'

# Unit tests (Swift Testing)
xcodebuild test -project Folio.xcodeproj -scheme Folio -destination 'platform=macOS' -only-testing:FolioTests

# One suite, or one test (Swift Testing functions include their parentheses)
xcodebuild test ... -only-testing:'FolioTests/PostEditorViewModelTests'
xcodebuild test ... -only-testing:'FolioTests/PostEditorViewModelTests/openingAndLeavingDoesNotSaveADraft()'
```

A destination with a name alone only looks at the newest iOS runtime, which has no iPhone 17 Pro here, so give the OS version. xcodebuild prints Swift Testing results as `Test case '…' passed/failed` lines, and its "Failing tests:" list at the end is the reliable summary (individual lines can be interleaved with other output).

Build both macOS and iOS after touching anything behind `#if os(macOS)` or in `MarkdownEditorView` (it's two separate implementations). SourceKit often reports "Cannot find type X in scope" across files after an edit; trust `xcodebuild`, not the editor diagnostics.

## Git workflow

`main` is the only branch, and for now the user wants commits straight to `main`. Commit only when the user asks.

The user edits in this checkout too, and often has staged and unstaged work in progress. Commit only your own files, by explicit path (never `git add -A` or `git commit -a`), and leave changes you didn't make alone. If they'd block switching branches, ask instead of stashing or discarding them.

## Architecture

```
Views ──► ViewModels (@Observable) ──► Repositories ──► URLProcessor ──► URLSession
```

Files are flat in `Folio/` (models in `Folio/Models/`, extensions of other types in `Folio/Helpers/`, the `@main` app in `Folio/Resources/FolioApp.swift`).

- **Settings.** `ServerSettings` reads the active `FolioEnvironment` (Dev/Prod) and its base URL from UserDefaults and its API key from the Keychain (`KeychainStoring`), fresh on every access, so switching environments takes effect immediately. Keys are named in `FolioStorageKey`. `SettingsViewModel` edits them.
- **Networking.** `URLProcessor.fromSettings()` builds a client per request; `apiURL("posts", id)` builds endpoint URLs. Everything in the networking layer uses typed throws: `throws(APIError)`. `GET`s are unauthenticated; `POST`/`PUT`/`DELETE` and uploads send the Bearer token. `APIError.isCancellation` filters out cancelled requests, which are never shown to the user.
- **Repositories** (`ProjectRepository`, `PostRepository`, `MediaRepository`, `AppsRepository`) are stateless, map one method to one endpoint, and each has a protocol and a `Test…` fake in the same file.
- **Updates replace every field the editor owns.** The server merges a `PUT` body into the stored item (`{ ...existing, ...body }`), so a field left out keeps its old value. `PostUpdate` / `ProjectUpdate` encode every field, with `nil` as `null` to clear it (`heroImage`, `series`, `category`); only `createdAt` is left out when `nil`. Don't switch them back to `encodeIfPresent`. The server also computes `readingTime`.
- **List → detail.** `PostsView` / `ProjectsView` (tabs of a `.sidebarAdaptable` `TabView` in `ContentView`) each own a `ContentListViewModel<Item>` (`PostsViewModel`, `ProjectsViewModel`) holding the items, `selectedID`, and `isCreatingNew`. Edit opens through `.navigationDestination(item:)`, create through `.navigationDestination(isPresented:)`. Open the create form only through `startCreating()`, which clears the selection first; with both destinations active, SwiftUI shows the selected item's editor instead. Deleting from the list deletes the item's draft too.
- **Editors** (`PostEditorViewModel`, `ProjectFormViewModel`) are created per push with the list's repositories and draft store, and loaded in `.task { await vm.load() }`. They report back through observable `saved` / `deleted` properties that the view forwards to `onSave` / `onDelete` with `.onChange`, so view models never hold SwiftUI closures or `dismiss`. The inspector (`.inspector(isPresented:)`) holds status, dates, and Delete.
- **Drafts.** Each editor has a `DraftSession`, which saves `PostDraft` / `ProjectDraft` JSON through a `DraftStore` (Application Support, `post-<id>`, `project-new`, …). Fields call `fieldChanged()` in `didSet`, which schedules a save (debounced 2 s); `saveDraftNow()` runs when the editor closes. The session saves nothing until the editor sets a **baseline** (the fields as loaded, or empty for a new item), and deletes the draft instead of saving it when the fields match the baseline, so opening an item and leaving, or a cancelled load, never leaves a draft behind. Drafts record the server's `updatedAt` they started from (`serverUpdatedAt`); a restored draft from an older version sets `isDraftStale`, and the editor asks whether to keep or discard it. Code that sets fields programmatically goes through `populate(from:)` / `populate(fromDraft:)`, which set `isPopulating` so nothing is scheduled mid-update. `serverContent` / `serverDescription` keep the server's text for **Show Changes** (`computeChangedLineRanges(from:to:)`). Drafts are Codable: add new fields as optionals so existing drafts still decode.
- **Markdown editing.** `MarkdownEditorView` wraps `NSTextView` (macOS) / `UITextView` (iOS); `MarkdownToolbar` (with `InsertImageButtons` as an accessory) sends it `EditorAction`s through the `pendingAction` binding. The editor applies an action just after SwiftUI's view update (`applyAfterUpdate`), never during it. The coordinator's `isUpdating` flag suppresses the text-changed callback during programmatic edits, and `dismantleNSView` must nil the delegate. Diff highlighting is macOS only (layout manager temporary attributes).
- **Media.** The server accepts images only (JPEG, PNG, WebP, GIF, AVIF, HEIC), converts them to WebP named after the uploaded file's base name, and stores them at `/media/<context>/<id>/<name>.webp`. Store these paths as-is, in model fields and inside markdown, never with a base URL (dev and prod differ). Resolve them only for display: `mediaURL(for:)` for `AsyncImage`, `resolveMarkdownImageURLs(_:)` before `StructuredText`. Pictures are loaded into a `PendingImage` (`load(from:)` for Photos, `chooseFiles()` / `init(contentsOf:)` on macOS). Hero images (`HeroImageRow`) upload on save; inline and gallery images upload immediately. A new item can't upload until it has an ID (`canUploadFiles`), and its ID field locks once anything is uploaded (`hasUploadedFiles`). After a save, `deleteUnusedFiles` deletes the replaced hero image and removed gallery images, but only files in the item's own folder and not mentioned in its markdown.
- **Apps.** The API has no "list apps" endpoint, so the app slugs live in UserDefaults (`folio.apps`, `AppsViewModel`). Privacy policies store `lastUpdated` as a `yyyy-MM-dd` string, converted with a POSIX, UTC `DateFormatter`.
- **Slugs** come from `String.slugified` (lowercase ASCII letters and digits, hyphens between).
- **macOS file pickers** use `NSOpenPanel().runModal()` (`PendingImage.chooseFiles`), because `.fileImporter` inside `Form > Section` silently does nothing on macOS. Media reordering uses `.draggable` / `.dropDestination`, since `.onMove` needs a `List`.

## Testing

`FolioTests` (Swift Testing, hosted in the app) holds unit tests of view models and helpers, one suite per type (`PostEditorViewModelTests`, `ProjectFormViewModelTests`, `ContentListViewModelTests`, `SettingsViewModelTests`, `URLProcessorTests`, `HelperTests`). `FolioUITests` (XCTest) has only Xcode's templates. The app shows an empty window while tests run (`isTesting` in `FolioApp`), so the real tabs don't load anything underneath them.

### Rules

- **Every bug fix includes a test that fails without the fix and passes with it**, to prevent regressions. Add it to the existing suite for the affected type, or create `FolioTests/<TypeName>Tests.swift`. Mark it with a `/// Regression test: …` doc comment explaining the bug. If the logic lives in a view, move it into a view model or a free function first. Changing copy isn't a bug fix and gets no test.
- Everything a view model depends on comes in through its initializer, with the live one as the default: repositories (`any PostRepositoryProtocol`, …), `DraftStore`, `UserDefaults`, `KeychainStoring`. Tests and previews pass the fakes from the app target: `TestPostRepository`, `TestProjectRepository`, `TestMediaRepository`, `TestAppsRepository`, `TestKeychain`, `DraftStore.temporary()`, and `makeUserDefaults()` (in `TestHelpers.swift`). The repository fakes merge updates the way the server does and record what they were sent (`updates`, `uploads`, `deletedFiles`, …). New code that touches a system API or the server should follow this pattern.
- Test `URLProcessor` itself through `StubURLProtocol.session` (`TestHelpers.swift`); its suite is `.serialized` because the stub's handler is shared.
- Tests never hit the network or the real Keychain, and never write drafts into the real Application Support folder.
- Sample data: `PostDetail.sample`, `ProjectDetail.sample`, `AppPrivacyPolicy.sample`, `AppSupport.sample`, `sampleImage`, and `Date.sampleDate` (noon UTC, so formatted dates don't depend on the machine's time zone).
- Run the affected suite, on macOS and iOS when the change touches platform code, before calling a change done.

## Style guide

These conventions come from TrekPoint. Match them.

### Whitespace and formatting

- Indent with **4 spaces**, never tabs.
- **Blank lines are indented to match the next non-blank line** (this is Xcode's behavior). A blank line between two statements indented 8 spaces contains 8 spaces, not zero. Only blank lines at file scope (between top-level declarations) are truly empty. The Edit tool can strip this whitespace from blank lines in `new_string`, so check `git diff` for added blank lines with no indentation. Never strip the whitespace from lines you didn't change. For example (the blank lines below contain 4 and 8 spaces):

  ```swift
  func save() async {
      isSaving = true
      
      if let pending = pendingHeroImage {
          heroImage = try await upload(pending)
          
          pendingHeroImage = nil
      }
  }
  ```
- One blank (indented) line between members, and between logical groups of statements inside a function.
- Long initializers and calls with many arguments may stay on one line. Break them onto one-argument-per-line when that reads better.

### Comments

- Use `// MARK: - Section` to organize files, and put extensions under `// MARK: - Functions` / `// MARK: - Computed Properties`.
- Use `// TODO: - Description` for known follow-ups and `// NOTE: - Description` for non-obvious explanations. Keep the `: - ` form so they show up in Xcode's jump bar.
- Use `///` doc comments on non-obvious helpers and on anything with a warning (e.g. `/// > Warning:`).

### Swift idioms

- View models are `@Observable class`. (TrekPoint writes `@Observable @MainActor class`; here `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` makes the annotation redundant, so leave it off.) Dependencies come in through the initializer with the live one as the default (`init(repo: any PostRepositoryProtocol = PostRepository())`) and are stored as `private let`. Properties that views shouldn't observe are `@ObservationIgnored`.
- Views declare an explicit `init` and store their inputs as `private let` properties. Callbacks are named `onX` (`onSave`, `onDelete`, `onSelect`). A view that creates its view model holds it in `@State private var vm`; one that's handed a view model takes it as `@Bindable private var vm`.
- Prefer `if` / `switch` **expressions** and implicit returns (computed properties returning a `switch` directly).
- Use `case let .foo(bar)` for pattern binding, not `case .foo(let bar)`.
- Use `[weak self]` in closures and tasks stored on view models.
- Nested types for scoped helpers, `fileprivate` / `private struct` for view-local subviews.
- Extensions of other types go in `Folio/Helpers/Type+Topic.swift` (e.g. `String+Slug.swift`, `View+ErrorAlert.swift`).
- Platform differences go behind `#if os(macOS)`; iOS-only modifiers (`.keyboardType`, `.textInputAutocapitalization`) behind `#if !os(macOS)`.
- Prefer one shared implementation over copies: posts, projects, and app pages share `MarkdownToolbar`, `HeroImageRow`, `PendingImage` loading, `String.slugified`, and `DraftSession`. Extend those rather than adding another copy.

### Errors and user feedback

- Throw typed errors (`throws(APIError)`, `KeychainService.KeychainError`). View models catch them into `var error: (any LocalizedError)?` (or `APIError?`), and views show it with `.errorAlert($vm.error)`. Cancellations (`APIError.isCancellation`) are never shown.
- Destructive actions go through a `.confirmationDialog`.
- Don't swallow errors the user would want to know about (saving, uploading, deleting) with `try?`, and don't use `print` for error handling.

### Accessibility and input

- Icon-only buttons use `Button("Title", systemImage:)` with `.labelStyle(.iconOnly)`, so they keep an accessibility label.
- Primary actions have keyboard shortcuts (⌘S save/publish, ⌘R refresh, ⌘⌫ delete); keep them when adding actions.

### Previews

Every view file ends with a `#Preview`, using `@Previewable @State` for bindings and the `Test…` fakes (`TestPostRepository`, `TestProjectRepository`, `TestMediaRepository`, …) for view models, so previews never reach a server.

## Gotchas

- Use `url.path(percentEncoded: false)` with `FileManager`, not `url.path()`, which percent-encodes spaces (like in "Application Support") so files never seem to exist.
- Never change `@State` or other observed state from inside `body` or `updateNSView` / `updateUIView`; it causes "Modifying state during view update" warnings and update loops. Defer it, like `MarkdownEditorView.applyAfterUpdate`.
- `FlowLayout` (in `PostEditorView.swift`) must return the proposed width from `sizeThatFits`; returning anything else causes an infinite layout loop on macOS.
- The `createdAt` `didSet` bumps `updatedAt` when the new date is later. It's skipped while `isPopulating`, so set both only inside a `populate` function.
- `PhotosPicker`'s label closure is `Sendable` and runs off the main actor. Compute anything it needs from a view model before the picker (`let hasHeroImage = …`), and give views used there a `nonisolated init` (like `MarkdownToolbarLabel`).
- On macOS 26, `.dropDestination(for:)` has a `Void`-returning overload; a single-expression closure that returns a `Bool` picks it and drops the result. Write `return` explicitly for the `Bool` version.
- Binding to a property of a `let` reference inside a view model (`$vm.draftSession.isStale`) doesn't compile; forward it through a computed property on the view model (`isDraftStale`).
