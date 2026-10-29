**Folio audit — October 29, 2026**

**Overall score: 6/10.** Folio is a thoughtfully structured personal CMS client with a useful native editing workflow and a stronger testing foundation than its companion website. Its main weakness is protecting work across asynchronous operations, environment changes, and partial failures. Several ordinary workflows can lose local edits, act on the wrong server, or misleadingly report that work is safe. Those issues should take precedence over visual polish or new features.

This score evaluates the current working tree as an everyday authoring tool that writes to a live site. It includes existing uncommitted changes. It is a qualitative judgment, not an average of defect counts. Folio's architecture is stronger than its publishing safety. The backend's broader production-security score from the earlier audit is not being assigned to the native app, but backend defects that undermine Folio are included below.

| Area | Score | Assessment |
|---|---:|---|
| Architecture and scope | 8/10 | Clear layers, small dependency footprint, appropriate native integration |
| Editing correctness | 5/10 | Good normal paths; unsafe load/save interleavings and inconsistent app-page updates |
| Drafts and recovery | 4/10 | Useful baseline/staleness design, undermined by identity collisions, silent persistence failures, and incomplete recovery |
| Publishing and environment safety | 4/10 | Requests follow mutable global settings; no conditional writes or complete media transaction |
| Native usability and accessibility | 6/10 | System controls and labels are good; loading, accessible editing, reordering, and preview coverage need work |
| Tests and maintainability | 7/10 | Passing cross-platform regression suite and useful documentation; integration/failure coverage is thin |

I reviewed all 47 Swift application files, the unit/UI test targets, project settings, package lock, app configuration, and project documentation. I traced the corresponding backend handlers and frontend rendering/cache behavior and read the existing [website audit](../AUDIT.md). Application source was not changed. Only this report was added to the repository; diagnostic tests were written into a temporary copy.

The reviewed repositories started at Folio commit `8e389c9` and website commit `3227bcd`, plus their working changes. Other work updated the backend during this audit. A final integration recheck at **01:45 MDT** found new slug/reserved-ID validation, path containment helpers, credential-comparison hardening, image orientation handling, and dependency updates. Those changes were not mine. This report credits the new path/ID protections and does not carry the earlier traversal findings forward as unchanged defects. Their full runtime/security validation remains outside this Folio audit.

**Validation and limits.**

| Check | Result |
|---|---|
| macOS Debug build and existing `FolioTests` | Passed: 39 test declarations, 47 executed invocations including parameterized cases |
| iOS Debug build and existing `FolioTests` | Passed: 47 invocations on iPhone 17 Pro / iOS 26.3 |
| Additional audit probes | 13 passed on macOS in a temporary source copy; 12 assertions document undesirable current behavior, and one confirms fractional-second date decoding works on the tested macOS runtime |
| Date-only frontend behavior | `2026-10-29` renders as October 28, 2026 with the current expression in `America/Denver` |
| Build diagnostics | No application compiler errors; only App Intents metadata-extraction warnings for targets without AppIntents |
| Toolchain | Xcode 27.1; macOS 27.2 host |

The additional probes assert the existing behavior so that failures are demonstrated without modifying the project. A passing defect probe does **not** mean the behavior is correct. They cover cross-repository drafts, the `new` draft-key collision, disk-write failure, lost pending hero images, offline draft recovery, restored upload ownership, orphaned uploads, cancelled initial loads, edits during save, saving after failed load, omitted app contact fields, and restoring a nil creation date.

The original tests use fakes, temporary draft directories, and a stub URL protocol. No live content or production writes were used. The initial build was blocked by sandboxed dependency resolution; it succeeded after authorized access to Xcode services and pinned packages. I did not perform a hands-on VoiceOver audit, measure performance with Instruments, exercise real Photos/Keychain failure modes, validate signing/notarization, run a Release archive, or rerun the prior backend/browser penetration and navigation tests. UI-specific observations below are identified as source-confirmed or risks, not claimed as interactive reproductions.

Reproduction artifacts for this session are `/tmp/folio-audit-tests.log`, `/tmp/folio-audit-ios-tests.log`, `/tmp/folio-audit-probes.log`, and `/tmp/folio-audit-copy/FolioTests/AuditProbeTests.swift`. The temporary directories are not durable project assets. The source references and reproduction descriptions in this report are the durable record. File line numbers refer to the audited working tree; paths in code references below are relative to this Folio directory unless prefixed with `../`.

Folio has several strengths worth preserving:

- **The overall layering is appropriate.** Views delegate work to observable models, repositories isolate endpoints, and `URLProcessor` centralizes transport and serialization. Protocol injection makes the important logic testable without a server. A large framework rewrite would add risk without addressing the actual problems.
- **The draft baseline solves real problems.** `DraftSession` avoids saving untouched server snapshots and avoids writing empty drafts after a cancelled fetch. Existing regression tests protect these behaviors. Atomic file replacement for draft writes is also the right basic mechanism.
- **Post/project updates understand the backend's merge semantics.** Explicit nulls clear optional fields, and server-owned update timestamps are not fabricated by the client. The app-page exception is a specific inconsistency, not a reason to replace the entire repository layer.
- **Relative media paths fit the deployment.** Resolving paths only for display is appropriate when Dev and Prod have different hosts. UUID upload names avoid normal filename collisions, and the cleanup helper limits deletion to the item's folder and preserves references in that item's markdown.
- **Modern SwiftUI is used sensibly.** Observation, `NavigationStack`, the current Tab API, inspectors, and reusable controls are already in place. The project has default MainActor isolation; the absence of repeated `@MainActor` annotations in application types is not a concurrency defect.
- **The custom native text editor has a reason to exist.** Selection-aware markdown actions, undo support on macOS, UTF-16 range handling, delayed application of view updates, and delegate teardown are thoughtful. Replacing it with a basic SwiftUI text field would lose useful functionality.
- **Credentials are in Keychain.** The API key is not embedded in source or ordinary preferences. Write requests authenticate, public reads do not send the token, and ATS is not globally disabled. Keychain failures are surfaced by the settings view model, even though the underlying replacement algorithm needs improvement.
- **Tests and documentation capture prior lessons.** Tests are behavioral, not just snapshots. Documentation explains platform workarounds, draft semantics, dependency injection, and why app slugs are stored locally. Those explanations made it possible to distinguish intentional tradeoffs from defects.

The findings are organized around the files that own each behavior. **High** means a credible data-loss, wrong-target mutation, or publishing-integrity problem; **medium** means a meaningful correctness, recovery, or usability problem; **low** means maintainability or polish. Recommendations are proposals, not changes made by this audit. Short before/after examples are illustrative rather than complete patches.

1. **High — `ServerSettings.swift`, repositories, `PostsView.swift`, and `ProjectsView.swift`: pin operations and loaded content to a server context. Source-confirmed.**

   References: [Folio/ServerSettings.swift:50](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ServerSettings.swift:50), [Folio/URLProcessor.swift:144](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/URLProcessor.swift:144), [Folio/PostRepository.swift:48](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostRepository.swift:48), [Folio/ProjectRepository.swift:56](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectRepository.swift:56), [Folio/PostsView.swift:43](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostsView.swift:43), [Folio/PostsView.swift:78](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostsView.swift:78), [Folio/ProjectsView.swift:78](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectsView.swift:78), [Folio/ContentListViewModel.swift:37](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ContentListViewModel.swift:37).

   Every repository method resolves the active server afresh. Lists keep their loaded items through `hasLoaded`, while the environment subtitle updates independently. There is no environment-keyed reload or invalidation. After loading Dev, switching to Prod can leave Dev rows displayed under a Production subtitle. Deleting one of those rows sends the same ID to Prod. If that ID exists there, the wrong item is deleted.

   An in-progress save also consists of separately configured requests: upload, content write, and cleanup can resolve different environments if settings change between awaits. macOS has a separate Settings scene, so this is not limited to navigating away from an editor. Base URLs also persist on each keystroke, making partially edited configuration immediately active.

   **Improve:** create an immutable server context containing a stable identity, validated URL, and credential reference. Inject a client bound to it into an editing session. Invalidate lists and selection on deliberate context changes, cancel or ignore obsolete results, and keep one context for the entire save. Show the target environment in editors and destructive confirmations.

   Before: `let p = try URLProcessor.fromSettings()` inside every operation. After: `let p = clientForThisEditingSession`, with list loading keyed to the same context identity. Merely adding a refresh after changing the picker does not fix in-flight saves.

2. **High — `DraftStore.swift` and editor `draftKey(for:)`: draft identity is ambiguous. Reproduced.**

   References: [Folio/DraftStore.swift:63](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftStore.swift:63), [Folio/PostEditorViewModel.swift:98](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:98), [Folio/ProjectFormViewModel.swift:100](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:100), [Folio/Resources/FolioApp.swift:9](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/Resources/FolioApp.swift:9).

   Dev and Prod share the same draft directory and keys. Two repositories containing the same ID can restore each other's drafts. The probe loaded a production-titled fixture and restored a development-only title; because the fixtures had the same revision timestamp, no stale warning appeared. A warning based on timestamps would still not be a reliable environment boundary.

   There is also a direct collision: creating a post uses `post-new`, while editing a legitimate post whose ID is `new` uses exactly the same key. Projects have the same collision. All new posts share one draft slot, including separate macOS windows. Editing the same record in two windows likewise has no ownership or merge policy.

   **Improve:** use structured identity: server ID + content kind + persisted item ID, with a separate namespace and UUID for each new draft. Coordinate simultaneous editors of one existing item. Migrate existing drafts explicitly rather than silently assigning ambiguous drafts to the currently selected server.

   Before: `post-new` / `post-<slug>`. After: `<server>/posts/new/<draftUUID>` / `<server>/posts/existing/<encodedID>`. Keep user-controlled identifiers out of raw filesystem path construction.

3. **High — `PostEditorViewModel.swift` and `ProjectFormViewModel.swift`: asynchronous load/save can erase work. Reproduced for posts; matching project implementation.**

   References: [Folio/PostEditorViewModel.swift:122](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:122), [Folio/PostEditorViewModel.swift:143](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:143), [Folio/PostEditorViewModel.swift:160](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:160), [Folio/ProjectFormViewModel.swift:128](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:128), [Folio/ProjectFormViewModel.swift:149](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:149), [Folio/PostEditorView.swift:24](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorView.swift:24), [Folio/ProjectFormView.swift:24](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormView.swift:24), [Folio/SaveToolbarButton.swift:30](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/SaveToolbarButton.swift:30).

   Only the save button is disabled during a save. The fields, image selection, and delete actions remain usable. When the response arrives, the model discards its draft and calls `populate(from:)`, replacing everything with the submitted version. A suspended-repository probe submitted one text, typed another while the request was pending, and resumed the request: the newer text disappeared and no draft remained.

   Loading has the same replacement pattern. Neither form uses `isLoading` to gate editing, and a failed load leaves a usable empty form. A second probe failed the fetch, entered a title, and saved: the existing record's content, tags, and hero image were cleared. In edit mode `currentID` is already populated from the mode, so entering a title satisfies the visible save gate. The app can also launch save/delete/upload operations that overlap; setting a Boolean is not a mutual-exclusion guard.

   **Improve:** represent editor state explicitly as loading, ready, failed, and saving; require a successfully loaded baseline before updating existing content. Either disable editing during submission or snapshot an edit generation and preserve changes made after that snapshot. Coordinate delete and uploads with save. Protect these rules inside the model, not only in the button.

   Before: `populate(from: result); draftSession.setBaseline(currentDraft)`. After: accept the result as the **submitted** baseline, then preserve and persist any later local edits. For a simpler first fix, disable the complete form during load/save and reject mutations unless the model is ready.

4. **High — editor repositories and backend PUT handlers: stale-draft detection is not write conflict protection. Source-confirmed.**

   References: [Folio/DraftSession.swift:39](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftSession.swift:39), [Folio/PostRepository.swift:70](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostRepository.swift:70), [Folio/ProjectRepository.swift:78](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectRepository.swift:78), [../backend/src/routes/posts.ts:100](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/posts.ts:100), [../backend/src/routes/projects.ts:94](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/projects.ts:94), [../backend/src/routes/apps.ts:60](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/apps.ts:60).

   Folio checks a restored draft against the fetched timestamp when an editor opens. It does not check whether the server changes **after** that load. A second device, window, or direct API client can update the record, and the first editor then overwrites every field it owns. The backend accepts this without a revision precondition. App pages do not even have a revision field in their current contract.

   **Improve:** give records a server-generated revision/ETag and require a matching precondition on updates/deletes. Return a distinct conflict response containing enough information to reload or compare versions. Preserve the local draft while resolving it. A fetch immediately before PUT is insufficient because another writer can change the record between those requests.

   Before: unconditional `PUT` with a field payload. After: conditional `PUT` carrying the revision used to start editing, checked atomically with the write. This requires coordinated backend work, but directly improves Folio's core safety.

5. **High — `DraftStore.swift` and `DraftSession.swift`: persistence failure is silently reported as a saved draft. Reproduced.**

   References: [Folio/DraftStore.swift:70](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftStore.swift:70), [Folio/DraftStore.swift:77](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftStore.swift:77), [Folio/DraftStore.swift:87](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftStore.swift:87), [Folio/DraftSession.swift:66](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftSession.swift:66), [Folio/DraftSession.swift:81](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftSession.swift:81).

   Encoding, directory creation, writes, reads, decoding, and deletion all use `try?`. `DraftSession.save` then unconditionally sets `hasDraft = true`. A probe used a regular file where the draft directory should be: the model reported a draft even though no draft file existed. Disk-full or permission failures follow the same ignored-error path. Failed deletion can also leave a draft that the UI claims was discarded. Corrupt drafts are indistinguishable from absent drafts.

   **Improve:** make persistence operations throw a dedicated error, distinguish missing from corrupt/unreadable data, and set saved status only after success. Retain failed/corrupt drafts for recovery or export and provide a persistent warning when local protection is unavailable.

   Before: `store.save(draft, key: key); hasDraft = true`. After: `try store.save(draft, key: key); hasDraft = true`, with the error handled and displayed by the session/editor. Keep atomic writes.

6. **Medium — editor draft snapshots and lifecycle: recovery omits some work and depends on connectivity. Reproduced in part; lifecycle risk source-confirmed.**

   References: [Folio/PostEditorViewModel.swift:29](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:29), [Folio/PostEditorViewModel.swift:105](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:105), [Folio/PostEditorViewModel.swift:122](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:122), [Folio/PostEditorViewModel.swift:242](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:242), [Folio/ProjectFormViewModel.swift:107](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:107), [Folio/ProjectFormViewModel.swift:128](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:128), [Folio/PostEditorView.swift:36](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorView.swift:36), [Folio/ProjectFormView.swift:78](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormView.swift:78).

   Pending hero-image bytes are not included in either draft type and do not trigger `fieldChanged()`. A probe saved and reopened a text draft with a selected hero image: the text returned, the image did not. A hero-only change can leave no draft indicator at all.

   Existing-item drafts are restored only after a successful server fetch. An offline reopen therefore shows an error and empty fields even when the local draft is intact; the probe confirmed the file still existed but was not loaded. This is an access/recovery failure, not evidence that the file was deleted.

   There is no scene-background flush; persistence relies on the two-second debounce and `onDisappear`. Backgrounding an iOS app does not guarantee that the editor disappears before suspension. Recent edits therefore have an avoidable loss window. Separately, `populate(fromDraft:)` only assigns `createdAt` when it is non-nil; the probe showed that a nil baseline cannot restore a changed date. That last edge case has limited normal UI reach but shows that snapshot restoration is incomplete.

   **Improve:** persist selected assets in a draft asset directory, store references in the snapshot, offer local recovery before network validation, flush on lifecycle transitions, and restore every snapshot field exactly. Keep offline editing distinct from permission to overwrite an unverified server version.

7. **Medium — `ContentListViewModel.swift`: cancellation leaves the first-load state stuck, and refresh results have no ordering guard. Cancellation reproduced.**

   References: [Folio/ContentListViewModel.swift:37](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ContentListViewModel.swift:37), [Folio/ContentListViewModel.swift:44](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ContentListViewModel.swift:44), [Folio/ContentListOverlay.swift:27](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ContentListOverlay.swift:27).

   `loadIfNeeded()` sets `hasLoaded` before fetching. On cancellation, `refresh()` returns before setting `hasFinishedLoading`, and `hasLoaded` remains true. The next appearance does not retry, while the empty overlay continues showing its initial spinner. The probe called `loadIfNeeded()` twice after a cancelled first request and observed only one fetch. A manual refresh can recover; automatic reappearance cannot.

   Concurrent refreshes also apply whichever response completes last, even if it was requested first, and can overwrite local list updates after a save/delete. The toolbar disables one trigger, but pull-to-refresh and other entry points are not coordinated by the model.

   **Improve:** mark a load complete only after a relevant completion; allow cancelled loads to retry. Use one active load or a generation token, and reject results for an old context/generation.

   Before: `hasLoaded = true; await refresh()`. After: update the state from the accepted outcome of the fetch, leaving cancellation retryable.

8. **High — `PostsView.swift` and `ProjectsView.swift`: list deletion bypasses the safety present in editors. Source-confirmed.**

   References: [Folio/PostsView.swift:27](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostsView.swift:27), [Folio/PostsView.swift:32](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostsView.swift:32), [Folio/ProjectsView.swift:27](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectsView.swift:27), [Folio/ProjectsView.swift:32](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectsView.swift:32), [Folio/ContentListViewModel.swift:65](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ContentListViewModel.swift:65).

   Context-menu Delete and `onDelete` immediately launch destructive API calls. There is no confirmation or undo at these entry points, although editor deletion correctly asks first. The successful deletion also clears the local draft. A mistake can remove both the published record and the readily accessible local recovery copy. Combined with stale environment rows, the impact is more serious.

   **Improve:** funnel every delete route through one confirmation that names the content and bound server. Prefer server-side trash/revisions if reliable undo is desired. The role `.destructive` styles a button; it does not itself ask for confirmation.

   Before: `Task { await vm.delete(id: post.id) }`. After: set a pending deletion, show a confirmation dialog, and call the same model operation only from its confirmation action.

9. **Medium — app-page models and `AppsRepository.swift`: cleared contact fields are omitted from updates. Encoding reproduced; server merge source-confirmed.**

   References: [Folio/Models/App.swift:3](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/Models/App.swift:3), [Folio/AppPrivacyPolicyEditorView.swift:40](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppPrivacyPolicyEditorView.swift:40), [Folio/AppSupportEditorView.swift:34](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppSupportEditorView.swift:34), [Folio/AppsRepository.swift:32](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppsRepository.swift:32), [Folio/AppsRepository.swift:58](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppsRepository.swift:58), [../backend/src/routes/apps.ts:67](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/apps.ts:67), [../backend/src/routes/apps.ts:136](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/apps.ts:136).

   The editors convert empty contact strings to nil, then encode the ordinary Codable page model. Synthesized encoding omits nil fields. The backend merges the body into the old page, preserving the old contact link/text. The probe confirmed both keys were missing from encoded JSON. `TestAppsRepository` replaces the whole object, so its behavior hides this mismatch.

   **Improve:** introduce explicit update payloads for both app-page types, following `PostUpdate` and `ProjectUpdate`. Encode intentional clears as null and make the fake emulate the real wire/merge contract. Test the serialized payload, server merge, and returned page.

   Before: synthesized optional encoding, equivalent to `encodeIfPresent(contactUrl, forKey: .contactUrl)`. After: `try container.encode(contactUrl, forKey: .contactUrl)` in a dedicated update type. Apply the same rule to `contactText`.

10. **Medium — `AppPrivacyPolicyEditorView.swift` and `AppSupportEditorView.swift`: important text has no unsaved-work protection. Source-confirmed.**

    References: [Folio/AppPrivacyPolicyEditorView.swift:4](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppPrivacyPolicyEditorView.swift:4), [Folio/AppPrivacyPolicyEditorView.swift:83](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppPrivacyPolicyEditorView.swift:83), [Folio/AppSupportEditorView.swift:4](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppSupportEditorView.swift:4), [Folio/AppSupportEditorView.swift:80](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppSupportEditorView.swift:80), [Folio/AppsView.swift:103](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppsView.swift:103).

    These forms keep content only in their view models. Unlike posts/projects, they have no draft session, dirty baseline, or leave-with-unsaved-changes prompt. Back navigation, tab changes that clear the app selection, closing the window, or termination can lose substantial support/privacy text. They also remain editable while saving and dismiss on success, so later edits can be discarded after an earlier payload completes.

    **Improve:** reuse the corrected draft/session behavior for app pages, with server/app/page-kind identity and explicit save state. Add a preview for these long markdown documents. Avoid implementing a third independent draft mechanism.

11. **Medium — upload ownership in editor models: the slug lock is transient and begins too late. Restored-state defect reproduced; in-flight race source-confirmed.**

    References: [Folio/PostEditorViewModel.swift:45](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:45), [Folio/PostEditorViewModel.swift:236](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:236), [Folio/ProjectFormViewModel.swift:50](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:50), [Folio/ProjectFormViewModel.swift:266](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:266), [Folio/ProjectFormViewModel.swift:272](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:272), [Folio/ProjectFormView.swift:34](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormView.swift:34).

    `hasUploadedFiles` starts false in every editor and is not restored from drafts. A new project with uploaded gallery images reopens with its slug editable, while the image paths still refer to the old slug; the probe demonstrated exactly this. The flag also becomes true only **after** upload finishes. During the first upload the user can change the ID, and subsequent content/upload requests can use a different ID.

    **Improve:** reserve ownership before starting the first upload, persist it, and use it consistently for all assets and saves. An explicit upload session or an early server-side draft ID is more robust than inferring ownership from a display-field Boolean.

    Before: upload using `currentID`, then set `hasUploadedFiles`. After: capture and lock an upload-owner ID before awaiting, restore that ownership with the draft, and block incompatible slug changes.

12. **Medium, with a high-impact shared-reference risk — `MediaRepository.swift` and editor save methods: cleanup is incomplete and cannot prove that deletion is safe. Partly reproduced.**

    References: [Folio/MediaRepository.swift:21](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MediaRepository.swift:21), [Folio/PostEditorViewModel.swift:170](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:170), [Folio/ProjectFormViewModel.swift:166](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:166), [Folio/ProjectFormViewModel.swift:176](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:176), [Folio/ProjectFormViewModel.swift:226](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:226), [../backend/src/routes/media.ts:141](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/media.ts:141), [../backend/src/routes/posts.ts:124](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/posts.ts:124), [../backend/src/routes/projects.ts:114](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/projects.ts:114).

    Cleanup compares the prior server hero/gallery against the newly saved fields. It never records all uploads made during the editing session. Upload an image, remove it before the first save containing it, and save: the probe observed an upload with no deletion. Abandoned drafts, removed inline images, and content deletion also leave assets behind. The comment above `addMedia` promises removal of uploads saved without them, but this case does not fulfill that promise.

    The folder restriction is valuable but is not a global reference check. Another post or app page can reference an image in this item's folder. Removing the original reference can then delete an image still used elsewhere. This is a conditional integrity risk confirmed by the available operations, not an observed broken live reference.

    Finally, `saved` is assigned and the draft discarded before cleanup. Cleanup failure lands in the same generic catch as publication failure even though content was saved; creation can already have navigated away. On retry, the old candidate list has been replaced by the new server baseline, so the failed deletion is not reliably retried.

    **Improve:** track uploaded assets and a durable cleanup queue, distinguish “saved; cleanup pending” from “save failed,” and move reference-aware deletion to the backend. Stage abandoned-asset collection with a grace period/dry run. Do not fix leakage by blindly deleting an entire item directory.

13. **Medium — `MediaManagerView.swift`: reordering cannot reliably express the full intended order. Source-confirmed.**

    Reference: [Folio/MediaManagerView.swift:87](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MediaManagerView.swift:87).

    The drop logic always inserts **before** the target. With `[A, B]`, dragging A onto B removes A and reinserts it at zero, producing no change. Dropping onto the last row never inserts after it, and there is no end drop zone. Users can work around some orders by moving other items upward, but the advertised direct drag operation is incomplete. There are also no explicit keyboard/VoiceOver move actions.

    **Improve:** define before/after insertion using drop position or use a container with standard move semantics. Provide Move Up/Move Down actions and an end target. Extract the reorder calculation into a pure helper and test adjacent moves and moves to both ends.

    Before: `media.insert(moved, at: from < to ? to - 1 : to)`. After: calculate a destination insertion slot from the intended before/after position, then adjust that slot for removal. Simply removing `- 1` changes the ambiguity rather than defining the interaction.

14. **Medium — `PendingImage.swift`, image pickers, and multipart encoding: import failure is silent and heavy image work is unbounded on the client. Source-confirmed; performance impact not profiled.**

    References: [Folio/PendingImage.swift:21](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PendingImage.swift:21), [Folio/PendingImage.swift:35](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PendingImage.swift:35), [Folio/PendingImage.swift:52](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PendingImage.swift:52), [Folio/MediaManagerView.swift:45](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MediaManagerView.swift:45), [Folio/HeroImageRow.swift:83](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/HeroImageRow.swift:83), [Folio/URLProcessor.swift:88](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/URLProcessor.swift:88), [Folio/DraftStore.swift:70](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftStore.swift:70), [../backend/src/routes/media.ts:21](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/media.ts:21), [../backend/src/routes/media.ts:47](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/media.ts:47).

    Transfer/file-read errors become nil and are silently skipped. File pickers accept generic images, while the backend has a narrower MIME whitelist and a 25 MB per-file limit. Folio offers no local explanation before uploading an unsupported or oversized asset. The Photos load phase occurs before `isUploadingMedia` is set, leaving weak progress/overlap control.

    macOS `Data(contentsOf:)`, JSON draft I/O, and multipart-body assembly run synchronously under the application's default MainActor isolation. Gallery selection loads a batch of original image bytes before upload; macOS selection has no count limit. The multipart body adds another large in-memory buffer, and the hero preview constructs an image from original data during view evaluation. These are plausible stalls and memory spikes, not measured latency claims.

    **Improve:** surface import errors, preflight actual format/size, show import as well as upload progress, process batches incrementally, and use file-backed uploads where practical. Move disk/byte processing behind an appropriately isolated worker and cache/downsample previews. `Task {}` alone inherits the current actor and does not move synchronous work off the UI actor. Keep the documented `NSOpenPanel` workaround unless a verified replacement works on supported systems.

15. **Medium — form validation and API contracts: users can submit input that the app cannot successfully publish or manage. Source-confirmed.**

    References: [Folio/ProjectFormView.swift:212](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormView.swift:212), [Folio/ProjectFormView.swift:183](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormView.swift:183), [Folio/PostEditorView.swift:168](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorView.swift:168), [Folio/Helpers/String+Slug.swift:8](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/Helpers/String+Slug.swift:8), [Folio/SettingsView.swift:5](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/SettingsView.swift:5), [Folio/URLProcessor.swift:144](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/URLProcessor.swift:144), [../backend/src/routes/projects.ts:67](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/projects.ts:67), [../backend/src/lib/regenerate.ts:10](/Users/jman/Developer/portfolio-attempt-20/backend/src/lib/regenerate.ts:10).

    Project Save requires title and ID in the UI, but create also requires a nonempty tagline on the server. Whitespace-only titles count as valid. Link/contact fields accept arbitrary strings; URL keyboard traits are not validation. Folio's slug normalization allows the backend's now-rejected `index`/`nav` names and does not enforce its new 100-character limit. It also silently changes what the user typed without showing a canonical URL. The `new` draft collision is separate and covered above.

    Settings accepts any string `URL(string:)` can parse, including relative URLs; it does not validate an HTTP(S) scheme, host, unexpected query/fragment, or whether the user entered the site's base rather than `/api`. The active base changes with each keystroke. ATS already restricts transport, so this is not a claim that arbitrary insecure hosts currently receive credentials.

    **Improve:** derive a model-owned validation result with field-specific explanations; share the rules with a documented backend schema. Validate and commit settings atomically, explicitly allowing intended localhost development and HTTPS production. Show the final slug/public URL. Mirror the backend's new reserved-ID and length rules in the client. Do not make empty content invalid unless the product requires it.

16. **Medium — `URLProcessor.swift` and `APIError.swift`: actionable errors become generic failures. Source-confirmed.**

    References: [Folio/URLProcessor.swift:118](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/URLProcessor.swift:118), [Folio/APIError.swift:12](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/APIError.swift:12), [Folio/APIError.swift:18](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/APIError.swift:18), [Folio/PostEditorViewModel.swift:171](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift:171), [Folio/ProjectFormViewModel.swift:183](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift:183), [../backend/src/routes/media.ts:71](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/media.ts:71), [../backend/src/index.ts:30](/Users/jman/Developer/portfolio-attempt-20/backend/src/index.ts:30).

    The transport discards error response bodies and maps all ordinary validation failures to “Server error (400).” The backend already supplies useful messages for oversize/unsupported uploads and missing fields. A 409 always says an ID exists, which is not an adequate future representation of revision conflicts. App-detail loading reduces most errors to a Boolean and a generic Failed to load row.

    Cancellation is filtered in loads but not in editor saves/deletes/uploads, contrary to the documentation's blanket claim. A transport interruption after the server has committed is also inherently ambiguous; the current UI has no reconciliation path and can encourage a blind retry.

    **Improve:** decode a bounded structured error body with code, message, and optional field details; retain numeric status and use sensible fallback text for non-JSON bodies. Distinguish unauthorized, validation, conflict, cancellation, and uncertain mutation outcome. Never automatically retry a creation without an idempotency/reconciliation design.

    Before: `.httpError(statusCode: http.statusCode)`. After: an API failure carrying status plus a validated server error, with cancellation handled consistently and partial-success states represented separately.

17. **Medium — `KeychainService.swift`: replacement deletes the working credential before the new one is safe. Source-confirmed; real Keychain failure not injected.**

    Reference: [Folio/KeychainService.swift:30](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/KeychainService.swift:30).

    Saving calls `SecItemDelete` before `SecItemAdd`. If deletion succeeds and addition fails, the previous working key is gone. The settings fake throws before changing its dictionary, so its failed-save test does not model this destructive failure. Reads and deletes also collapse all statuses into missing/silent behavior, making locked/unavailable Keychain conditions difficult to diagnose.

    **Improve:** update an existing item with `SecItemUpdate`, add only when not found, and report meaningful statuses. Scope queries consistently with an explicit service/account identity. Offer deliberate credential removal rather than an empty field that cannot be saved.

    Before: delete then add. After: update, falling back to add only for `errSecItemNotFound`. Apple's guidance explicitly recommends updating existing items instead of deleting/recreating them: [Updating and deleting keychain items](https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items).

18. **Medium — privacy-policy date handling across native and web views: a calendar day is treated as an instant. Frontend expression reproduced; native display mismatch source-confirmed.**

    References: [Folio/AppPrivacyPolicyEditorView.swift:20](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppPrivacyPolicyEditorView.swift:20), [Folio/AppPrivacyPolicyEditorView.swift:88](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppPrivacyPolicyEditorView.swift:88), [../frontend/src/pages/AppPage.tsx:20](/Users/jman/Developer/portfolio-attempt-20/frontend/src/pages/AppPage.tsx:20).

    Folio parses `yyyy-MM-dd` at UTC midnight, then binds the resulting Date to a DatePicker using the ambient local timezone. In timezones west of UTC, that instant belongs to the previous calendar day. The browser does the same conversion through `new Date(iso).toLocaleDateString(...)`; the checked expression rendered `2026-10-29` as October 28 in Denver. A date-only privacy-page update can therefore appear inconsistent between its stored value and displayed day.

    **Improve:** model a calendar date explicitly, or consistently use UTC for this date-only picker and web formatting. Test west/east-of-UTC zones and daylight-saving boundaries. Keep timestamp fields such as post `updatedAt` separate from this contract.

    Before: UTC parsing plus local display. After: date-component parsing/display, or `.environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)` scoped to the date-only picker and matching web formatting. This is a UI/data-format issue; the audit makes no assessment of policy text or legal compliance.

19. **Medium — `MarkdownEditorView.swift`, toolbar controls, and gallery actions: accessibility is incomplete in the main editing surface. Source-confirmed; assistive-technology testing still needed.**

    References: [Folio/MarkdownEditorView.swift:150](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MarkdownEditorView.swift:150), [Folio/MarkdownToolbar.swift:79](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MarkdownToolbar.swift:79), [Folio/MarkdownToolbar.swift:82](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MarkdownToolbar.swift:82), [Folio/MediaManagerView.swift:31](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MediaManagerView.swift:31), [Folio/ProjectFormView.swift:125](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormView.swift:125).

    The iOS text view uses a fixed system-size monospaced font and does not configure Dynamic Type scaling or automatic size updates. Toolbar heading labels are fixed at 13 points, and borderless toolbar labels are only 28-by-28 minimum, with no explicit larger iOS touch target. Repeated Remove buttons in tech/link/media rows lack item-specific labels. Gallery reordering has no explicit non-drag alternative.

    Existing named buttons, accessibility labels on formatting actions, decorative thumbnail hiding, and textual status badges are positives. The missing work is concentrated rather than app-wide neglect.

    **Improve:** scale the editor font with `UIFontMetrics` and enable content-size-category updates, use semantic/scaled toolbar typography, give iOS controls adequate hit areas, label destructive controls with their item, and add reorder accessibility actions. Test keyboard access, VoiceOver, large text, contrast, and Reduce Motion on both layouts. Apple's [Scaling fonts automatically](https://developer.apple.com/documentation/uikit/scaling-fonts-automatically) documents the scaled-font and automatic-update combination.

    Before: `tv.font = .monospacedSystemFont(ofSize: UIFont.systemFontSize, weight: .regular)`. After: a monospaced font scaled for `.body`, together with `tv.adjustsFontForContentSizeCategory = true`.

20. **Medium — `DraftMenu.swift`, `MarkdownEditorView.swift`, and preview paths: the UI promises more review capability than is implemented. Source-confirmed.**

    References: [Folio/DraftMenu.swift:15](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftMenu.swift:15), [Folio/MarkdownEditorView.swift:148](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MarkdownEditorView.swift:148), [Folio/MarkdownEditorView.swift:160](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MarkdownEditorView.swift:160), [Folio/DraftStore.swift:100](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/DraftStore.swift:100), [Folio/PostEditorView.swift:117](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorView.swift:117), [Folio/URLProcessor.swift:170](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/URLProcessor.swift:170), [../frontend/src/components/shared/MarkdownRenderer.tsx:13](/Users/jman/Developer/portfolio-attempt-20/frontend/src/components/shared/MarkdownRenderer.tsx:13).

    Highlight Changes is shown on iOS, but the iOS wrapper never applies `highlightRanges`. Even on macOS, the algorithm highlights inserted/changed current lines; pure deletions have no visible range. It should not be presented as a complete diff. Computing the line diff synchronously on every text change while enabled may also become expensive for long documents; this was not benchmarked.

    Only posts have rendered preview. Projects and app pages have no equivalent. The post preview uses Textual while the website uses ReactMarkdown/GFM and custom render overrides, so it is a content preview rather than a guarantee of the published layout. The relative-image rewrite is a regex for inline image syntax; reference-style images are not resolved, and matching markdown inside a code block is also rewritten. These are authoring-fidelity limitations, not a request to replace the markdown stack.

    **Improve:** hide or implement unsupported iOS highlighting, label the current feature accurately, and add a real before/after review when deletions matter. Provide preview/Open Published Page for all content kinds. Share a markdown fixture corpus across renderers and use parser-aware/base-URL-aware resource resolution instead of blanket text substitution. Add an accessible alt-text authoring path; inserted inline images currently start with empty alt text.

21. **Medium — `FolioTests` and `FolioUITests`: the suite passes but misses the highest-risk boundaries. Verified.**

    References: [FolioTests/URLProcessorTests.swift:7](/Users/jman/Developer/portfolio-attempt-20/Folio/FolioTests/URLProcessorTests.swift:7), [FolioTests/PostEditorViewModelTests.swift:7](/Users/jman/Developer/portfolio-attempt-20/Folio/FolioTests/PostEditorViewModelTests.swift:7), [FolioTests/ProjectFormViewModelTests.swift:7](/Users/jman/Developer/portfolio-attempt-20/Folio/FolioTests/ProjectFormViewModelTests.swift:7), [FolioTests/TestHelpers.swift:17](/Users/jman/Developer/portfolio-attempt-20/Folio/FolioTests/TestHelpers.swift:17), [FolioUITests/FolioUITests.swift:18](/Users/jman/Developer/portfolio-attempt-20/Folio/FolioUITests/FolioUITests.swift:18), [Folio/AppsRepository.swift:104](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppsRepository.swift:104).

    The 39 test declarations are a useful foundation. However, most fake calls return immediately, so they cannot expose edits during save, out-of-order loads, or environment changes between awaits. The app fake replaces records instead of matching merge semantics. The suite has no app editor tests, draft I/O fault tests, ownership/multi-window tests, multipart assertions, or representative serialized backend response fixtures. UI tests are Xcode launch/performance templates without feature assertions. There is no checked-in CI workflow or shared custom scheme/test plan establishing the validation matrix.

    **Improve:** add controllable suspended fakes, wire-contract fixtures, failure injection, and a few offline UI scenarios. Highest-value regressions are the reproduced cases in this report, plus actual editor navigation, confirmation, toolbar insertion, and gallery ordering. Make UI-test mode explicitly inject test dependencies; do not rely on ordinary app launches being isolated. The current unit-test host guard is useful and should remain.

    One suspected issue was **not** confirmed: the configured ISO-8601 decoder accepted a backend-style fractional-second timestamp on the tested macOS runtime. Do not change date decoding based only on older platform anecdotes; put timestamp fixtures in the cross-platform suite and verify the supported OS matrix.

22. **Low/medium — repository, editor, and view organization: duplication is causing behavior to drift. Source-confirmed.**

    References: [Folio/PostEditorViewModel.swift](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostEditorViewModel.swift), [Folio/ProjectFormViewModel.swift](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectFormViewModel.swift), [Folio/AppPrivacyPolicyEditorView.swift](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppPrivacyPolicyEditorView.swift), [Folio/AppSupportEditorView.swift](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppSupportEditorView.swift), [Folio/PostRepository.swift](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/PostRepository.swift), [Folio/ProjectRepository.swift](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectRepository.swift), [Folio/AppsRepository.swift](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppsRepository.swift), [Folio/ProjectPreview.swift](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/ProjectPreview.swift), [DEVDOC.md:170](/Users/jman/Developer/portfolio-attempt-20/Folio/DEVDOC.md:170).

    The clearest smells are behavioral duplication, hidden global dependencies in otherwise injectable code, and too many independent booleans for mutually exclusive states. Both main editors repeat lifecycle/upload/save logic; app pages repeat a less capable version. This has already produced inconsistent null encoding, draft coverage, cancellation behavior, and save protection. Several views also contain view-model classes and helper controls, while test fakes/sample fixtures live in production repository files. `ProjectPreview.swift` contains list-row/status views rather than the model its filename suggests. Navigation-model fetch APIs have no current application call sites, despite documentation mentioning related pickers.

    **Improve:** first consolidate the corrected lifecycle, server context, update semantics, and media ownership. Then organize files by feature and move substantial types into clearly named files. Keep useful previews, but place fixtures/fakes in a deliberate shared test/debug support layer. Remove unused APIs when they have no planned consumer. Extract focused editor subviews where that narrows observation and gives reusable behavior; do not introduce a universal form engine merely to reduce line count.

    Documentation also overstates cancellation filtering and cleanup guarantees, and the app target enables incoming network connections although this client has no listener ([Folio.xcodeproj/project.pbxproj:420](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio.xcodeproj/project.pbxproj:420) and `:474`). Update those claims and remove the unused entitlement. The app icon set has slots but no images; finish that for distribution. These are lower priority than data integrity.

23. **High — backend storage and payload integrity remain Folio release dependencies. Source rechecked; destructive HTTP reproductions belong to the prior audit.**

    References: [../backend/src/lib/files.ts:16](/Users/jman/Developer/portfolio-attempt-20/backend/src/lib/files.ts:16), [../backend/src/lib/regenerate.ts:8](/Users/jman/Developer/portfolio-attempt-20/backend/src/lib/regenerate.ts:8), [../backend/src/routes/projects.ts:49](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/projects.ts:49), [../backend/src/routes/projects.ts:103](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/projects.ts:103), [../backend/src/routes/posts.ts:54](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/posts.ts:54), [../backend/src/routes/apps.ts:67](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/apps.ts:67), [../backend/src/routes/media.ts:148](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/media.ts:148), [prior audit](../AUDIT.md).

    The backend still writes live JSON files directly and performs read/merge/write/regeneration without transaction or multi-process coordination. Full payload validation is also absent, and PUT bodies can still overwrite fields such as `id` without renaming the backing file. These matter to Folio because successful edits can be lost, malformed content can make strict Swift decoding reject an entire list, and an advertised ID can stop matching the detail endpoint's filename.

    The final recheck found new `paths.ts` and `validateParams.ts` protections applied to route parameters, create IDs, and media paths. They reject reserved content IDs and constrain path construction. This is a meaningful improvement over the earlier website audit. I have therefore removed the earlier uncontained-path/reserved-ID server defects from the current outstanding assessment; Folio still needs to mirror the new validation rules for useful feedback.

    Content writes happen before regeneration; a later failure returns 500 even if the edit persisted. Folio's generic retry experience cannot resolve that inconsistency. A failed first creation followed by retry can become a conflict, while index/detail views disagree. These behaviors were reproduced by the earlier website audit; this audit rechecked their source paths but did not repeat those server mutations.

    **Improve:** validate full schemas and immutable IDs at the server, retain and test the new path protections, serialize mutations across all writer processes, and use atomic file replacement plus an explicit publication/recovery protocol. Add revisions, idempotent creation/reconciliation, and tested content/media backup and restore. Preserve the small file-based deployment if desired: a database migration is not a prerequisite, but atomic rename alone is not a complete concurrency fix.

24. **Medium — frontend cache and navigation behavior make publication verification unreliable. Source rechecked; browser failures were reproduced in the prior audit.**

    References: [../frontend/src/hooks/useCache.ts:1](/Users/jman/Developer/portfolio-attempt-20/frontend/src/hooks/useCache.ts:1), [../frontend/src/hooks/usePosts.ts:12](/Users/jman/Developer/portfolio-attempt-20/frontend/src/hooks/usePosts.ts:12), [../frontend/src/hooks/useProjects.ts:12](/Users/jman/Developer/portfolio-attempt-20/frontend/src/hooks/useProjects.ts:12), [../frontend/src/components/blog/PostDetail.tsx:19](/Users/jman/Developer/portfolio-attempt-20/frontend/src/components/blog/PostDetail.tsx:19), [../frontend/src/components/projects/ProjectDetail.tsx:51](/Users/jman/Developer/portfolio-attempt-20/frontend/src/components/projects/ProjectDetail.tsx:51), [../frontend/src/components/projects/MediaCarousel.tsx:14](/Users/jman/Developer/portfolio-attempt-20/frontend/src/components/projects/MediaCarousel.tsx:14).

    The five-minute localStorage cache is only consulted when the hooks run; expiration does not itself trigger a refresh while a view remains mounted. A successful Folio publish can therefore coexist with an older public list/navigation view. Detail requests can also apply obsolete results after navigating, and the gallery retains an index that can be out of range for a new project. The previous audit reproduced the latter navigation failures, and the source still contains those patterns.

    **Improve:** revalidate public data on appropriate focus/navigation events, version resources by revision, reject stale responses, and reset/bound gallery state when project identity changes. Give Folio a direct “View published page” action and distinguish API save acknowledgment from verified public presentation. Fix these website behaviors as part of authoring verification; unrelated portfolio redesign does not improve Folio's reliability.

25. **Medium — the end-to-end authoring contract needs explicit limits, app discovery, and media capabilities. Source-confirmed product gaps.**

    References: [../backend/src/index.ts:30](/Users/jman/Developer/portfolio-attempt-20/backend/src/index.ts:30), [../backend/src/routes/media.ts:21](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/media.ts:21), [../backend/src/routes/media.ts:125](/Users/jman/Developer/portfolio-attempt-20/backend/src/routes/media.ts:125), [Folio/AppsView.swift:14](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppsView.swift:14), [Folio/AppsView.swift:30](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/AppsView.swift:30), [Folio/Models/Media.swift:3](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/Models/Media.swift:3), [Folio/MediaManagerView.swift:40](/Users/jman/Developer/portfolio-attempt-20/Folio/Folio/MediaManagerView.swift:40).

    Folio allows arbitrarily long markdown, while the backend uses the default JSON parser limit; the earlier audit reproduced a 413 for a 110 KB payload. The native UI gives no size budget or meaningful explanation. Gallery models support videos, but the upload endpoint and current native creation controls only support images. The backend converts original-size images to WebP without thumbnail derivatives, while Folio displays many small thumbnails from those same assets.

    The local Apps list is a reasonable workaround for the missing server list endpoint, not an architectural mistake. Its current Delete action only removes a local bookmark; it does not remove public support/privacy pages. The name is misleading compared with the destructive content tabs, and app slugs must be re-entered on every device.

    **Improve:** document and enforce compatible content limits, expose useful validation errors, add an authenticated app index, and rename local app removal to “Remove from this device/list.” Decide explicitly whether video authoring is in scope; if not, explain existing video preservation and management. Generate bounded image derivatives and return metadata usable by the native app and website. Do not add a full media-management platform just to solve these concrete gaps.

The practical improvement sequence is:

| Priority | Work | Acceptance evidence |
|---|---|---|
| 1 — protect the destination and current edits | Bind a server context to each session; invalidate old lists; fix loading/saving state; confirm all deletes | Delayed operations and environment switches cannot mutate another server or erase newer local text; failed loads cannot save |
| 2 — make recovery trustworthy | Namespace drafts; support multiple new drafts; surface persistence failure; persist pending assets; recover offline; protect app-page edits | Cross-server and `new` collisions disappear; disk failure never reports success; all supported draft fields/assets survive reopen |
| 3 — make publication atomic enough to trust | Full backend payload validation, regression checks for new path protections, coordinated writes, revisions, explicit partial outcomes, and backup/restore | Competing writers receive a conflict instead of lost edits; interrupted writes preserve valid content; retry/recovery is deterministic |
| 4 — repair the wire/media contract | Explicit app update payloads; stable upload ownership; tracked/reference-aware cleanup; clear error messages and payload limits | Cleared fields stay cleared; upload/remove/discard/retry cases do not leak or break referenced media |
| 5 — improve review and daily use | Date-only consistency, functional accessible reorder/highlighting, preview for all content, publish verification, search and draft discovery | Cross-platform UI scenarios pass with large text/keyboard/VoiceOver; published pages match intended content |
| 6 — reduce maintenance drift | Feature-oriented files, focused shared lifecycle helpers, test support separation, CI and updated docs | One documented contract and failure matrix protects both platforms and all content types |

Search/filtering, a visible recoverable-drafts list, app discovery, export/import, and revision history would add more value than a cosmetic redesign. Scheduling, collaboration, and sophisticated rich-text editing can wait until the current save/recovery guarantees are dependable. Most improvements fit the existing architecture. Resolving the high-severity integrity issues and adding the missing contract/failure tests would make an 8/10 assessment realistic without replacing the stack.
