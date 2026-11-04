# Annotation workflow follow-up

This draft continues from the working text-arrow implementation at base commit
80132b454909fcf21aff747a7c5e9753fd5023b9. The user authorized callout polish and
controls, more shapes, customized steps, non-destructive Simplify and validation.

## Delivered code

- Eight callout choices: Block Arrow (Text), Box + Arrow, Speech Bubble, rounded
  Rectangle, Oval, Cloud, Thought Bubble and Burst. The legacy square rectangle
  stays decodable but is hidden from new-object choices.
- Shape-specific inscribed text regions. Canvas, native input and export use the
  same fonts, layout, rotation and paths. Existing immediate-focus typing, native
  undo/IME input and one-object editing remain the basis.
- Green whole-object rotation handle and a keyboard-accessible rotation slider.
  Block arrows keep their separate size and bend controls, with slider equivalents.
- Up to three additional independently movable tails on Box + Arrow, Speech
  Bubble and Thought Bubble. Closed-path union prevents overlapping body outlines
  or double-stroked attachment seams. Labels/block arrows retain but hide unused
  extra targets when switching variants.
- Automatic/manual attachment position for Box + Arrow and Speech Bubble.
- Circle, Rounded Square, Pin and Outline Circle steps. Font, size, bold, padding,
  colors, border, shadow and opacity are editable and work with My Styles. Pins
  have an independently movable target. A manual label override does not change
  sequence identity; deletion does not renumber others, and copies use the next
  sequence value.
- Simplify Region: draw a live preview, then place one editable rounded block
  using sampled surrounding background or a chosen color. Blocks are selectable,
  resizable, restylable, undoable and serialized as normal filled rect annotations.
- Simplify Full Image retains the existing local noise reduction/posterization
  algorithm, with preview, adjustable layer blending and cancel/apply. It becomes
  a movable image layer while the original base stays intact. This is visual
  abstraction; the separate Redact tools remain appropriate for sensitive data.
- Atomic saved-style application, native input focus retry on attachment/layout,
  protection of active IME composition, and keyboard shortcuts yielding to actual
  inspector/native text fields.

## Architecture and compatibility

SnapCore owns geometry, Codable appearance data, bounds/hits, handles, background
sampling and tests. App owns native input, rendering, inspectors and previews.
The existing AnnotationDocument array, object IDs, ordering, snapshot history,
image-layer storage and SavedStyles store are reused. No alternate scene graph,
detached label objects or remote screenshot processing were introduced.

New optional fields carry additional targets, callout rotation, step appearance
and Simplify corner radius. Copies and transforms carry them explicitly. Image
quarter-turns/flips preserve callout local dimensions and visible targets; pin
markers materialize their default tip before image transforms. Rotated body
resizing and automatic text growth keep their world-space targets fixed.

New projects write version 7. Readers continue to accept earlier versions; the
header check rejects future versions before decoding unfamiliar shape enums.
Legacy callouts/steps without new appearance data retain their original renderer
until explicitly restyled. Preferences store custom structs as JSON Data so they
remain valid UserDefaults values. The base screenshot remains separate from
flattened output and live project data.

## Build/test entry point

On macOS 14+ with Xcode 16+ and XcodeGen:

```sh
bash scripts/verify-annotations.sh
```

It runs snapverify, generates the project, builds unsigned, runs the new native
unit-test target and prints the xcresult path. The tests use synthetic images;
render attachments can be opened in Xcode. The script stops on the first failure.

For a clean local preview without disturbing earlier uncommitted patches:

```sh
cd ~/Documents/snappilot-source
git fetch origin
git worktree add ../snappilot-annotation-preview origin/feature/annotation-workflow
cd ../snappilot-annotation-preview
bash scripts/verify-annotations.sh
open Snappilot.xcodeproj
```

Use a different worktree directory if that name already exists. Launch with an
appropriate local signing team and Command+R. No main-branch changes are required.

CI runs snapverify, the unsigned app build and native annotation tests, retaining
`.xcresult` render attachments. It supports PRs, the working feature branch, main
and manual dispatch. GitHub Actions must be enabled for the repository/workflow.

## Validation state

The earlier baseline and several callout iterations were exercised on the user's
Mac. The latest additions have passed whitespace checks, Swift grammar parsing,
YAML structure checks and patch/source comparison in the Linux workspace.

This workspace cannot run Apple's toolchain. At preparation time GitHub's PR-run
connector still exposed no macOS CI runs despite pushing feature commits. The
user enabled Actions permissions; native run results remain unconfirmed. Syntax
parsing is not compilation or proof of native behavior. Keep the PR in draft
until real snapverify/build/native-test results and manual acceptance are recorded.
No real older-release project fixture was available; legacy checks are synthetic.

Automated checks added include shape text bounds, rotations and coordinate round
trips, extra-tail handles, target-preserving resize, copy/save compatibility,
step shapes/sequences/overrides and preference storage, background sampling and
Simplify style isolation. Hosted native tests cover first responder/first key,
commit/cancel/text undo and shape metrics/export attachments. A test-host-only
startup guard prevents global hotkeys and welcome/permission dialogs during tests.

## Manual acceptance still required

1. Draw each callout and type immediately, including multiline paste, emoji,
   accented text and IME composition. Check Return, Command+Return, Escape, outside
   click, double-click reopen, and text versus document undo.
2. Make up-left and left-facing block arrows: confirm larger, correctly angled,
   upright text and smoothly aimed heads. Exercise very short/thick arrows, manual
   font sizes, bend limits, resize and all zoom/display scales.
3. Rotate objects and move each tail independently. Resize a rotated text body;
   targets should stay fixed. Test overlapping objects and outline/shadow output.
4. Place at least 12 numeric and AA alphabetic steps; mix shapes, adjust a pin and
   override one label. Delete/copy/style/undo/save/reopen without renumbering others.
5. Draw multiple Simplify regions; compare preview with committed blocks. Adjust
   fill/radius/opacity, move/resize, undo and reopen. Preview/cancel/apply the full
   image effect and edit its image layer; the source must remain available.
6. Compare canvas, active rotated input and PNG/JPEG/HEIC/clipboard output. Test
   saved styles, Annotate Again, Save as New, crop, image resize/rotation/flip and
   real older projects when available. Confirm plain arrows, text, pen and blur.

This is original Snappilot geometry and UX inspired by the reference workflow,
not a claim of complete Snagit parity. Rich-text spans, automated Simplify object
recognition, step-guide export and multi-selection/grouping remain outside this
request. No remote image upload was added.
