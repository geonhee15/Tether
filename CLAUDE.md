# Tether — working notes

macOS notes app (SwiftUI + AppKit), built with `swiftc` via `./build.sh`. There is no Xcode project.

## Every change

1. Bump `VERSION` (`major.minor.patch`) — patch for fixes and small polish, minor for a new feature
   or a visible redesign, major for a milestone or a breaking change to saved data.
2. Run `./build.sh` — a release build that also installs to `/Applications/Tether.app`.
   (`./build.sh debug` builds `build/Tether.app` without installing; use it for screenshots.)
3. If the interface changed, regenerate the README images: `./build.sh debug && Scripts/screenshots.sh`.

## Conventions

- **Strings**: every user-facing string goes through `L("English", "한국어")`.
- **Surfaces**: `.glass(...)` (Liquid Glass / material) only for floating chrome — rail, toolbar, menus,
  sheets; add `frost:` when it floats above text. Content uses `.card()`, and things inserted into a
  page use `Theme.embedFill`. The writing surface is `Theme.pageFill`.
- **Motion**: use the `Motion` presets (`spring`, `snappy`, `smooth`, `gentle`) so the
  "Animations" setting and Reduce Motion are honoured.
- **Fonts**: `Font.app(...)` for interface text, `Font.doc(...)` for anything inside a node.
- **Text model**: text is saved as `[TextRun]`; fonts/colours are derived in `TextCodec`. Style changes
  go through `TetherTextView.mutateStyle`.
- **Links**: reference links live in `SpaceModel.links`; value links are `ActionItem.effects` and are
  applied on read (`SpaceModel.contributions()`), never written into the target.
- **Charts**: colours come from `Theme.chartPalette` slots stored on each point — never by rank.
- **Undo**: there is one history per Space (`SpaceHistory`, whole-content snapshots fed by the same
  observation that drives autosave). Anything that edits the observed model is undoable for free —
  don't add `NSUndoManager` registrations, and keep `allowsUndo` off on the text views.

## Credits

`AppInfo.aiCredits` lists the AI models that worked on the app, in order. When the model or effort
level changes, append an entry (it renders as `With A / B / C`) and update the last line of the README.

## Data and privacy

User data lives in `~/Library/Application Support/Tether/` and must never be committed, quoted in
docs or used for screenshots. README images come only from the fictional content in
`Sources/Tether/App/Demo.swift` (`TETHER_DATA_DIR` + `TETHER_DEMO=1`), which also uses a separate
preferences suite. Keep docs about what the app does, not about how any one person uses it.

## Checking without a human

`TETHER_SCENE=selftest` types, styles, inserts at the caret and merges; `TETHER_SCENE=authtest`
exercises sign-in, duplicates, the 10-account limit and password replacement (the macOS owner
prompt in `MacAuth` cannot be driven from a script); `TETHER_SCENE=undotest` makes five edits and
undoes/redoes them; `TETHER_SCENE=awaketest` checks the power assertion with `pmset`. All print to stdout:

```bash
D=$(mktemp -d); TETHER_DATA_DIR=$D TETHER_DEMO=1 TETHER_SCENE=selftest \
  TETHER_SNAPSHOT=$D/shot.png build/Tether.app/Contents/MacOS/Tether
```
