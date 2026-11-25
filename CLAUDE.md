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

- **Accounts and Spaces**: an account owns up to `AppInfo.maxSpaces` Spaces (`Account.spaceIDs`, in
  rail order). `Store.spaces` is keyed by Space id; the first Space of an account shares the
  account's id, which is how data from before 0.5.0 is read. Create and delete Spaces through
  `Store.addSpace` / `deleteSpace` (UI: `SpaceActions`) — never by editing `spaceIDs` directly.
- **Saved data**: anything added to `SpaceSnapshot` or `Account` must decode when the key is missing
  (see their `init(from:)`); a Space file that fails to decode is copied aside before it is replaced.
- **Categories**: `SpaceModel.categories` plus `NodeModel.categoryID`. A node whose category no
  longer exists counts as unfiled; deleting a category never deletes nodes.
- **Files**: a file node is a `NodeDoc` with `file` set; its `blocks` are the notes shown beside the
  file (text only — the compact `FormatToolbar` has no Insert); the bytes live in
  `files/<spaceID>/<uuid>.<ext>` and are shown with Quick Look. Deleting the node keeps the copy so
  Undo works; `Store.purgeOrphanFiles` removes leftovers when the history ends (launch, sign-out, quit).

- **Assistant** (`Sources/Tether/AI`): four adapters behind `AIProvider` — Claude (Messages API),
  ChatGPT (Responses API), Gemini (generateContent) and Ollama (`/api/chat`), all raw HTTP with
  streaming. Earlier turns go to every service as plain text with the author in brackets, which is
  what lets one conversation move between services. Inside the reply being written, what the model
  returned is replayed to the same service verbatim (`AIRound.raw`) — it carries thinking blocks,
  reasoning items and thought signatures; never rebuild or filter it. The system prompt and tool
  list are built once per reply and must not change between rounds.
- **Assistant tools** (`AITools.swift`) edit the observed Space model, so their changes autosave and
  undo like typing. Bump `BlockModel.revision` after replacing a block's runs. A tool that changes
  anything sets `writes: true` so the "ask first" and "read only" modes cover it.
- **Assistant data**: conversations per Space (`ai/chats-<spaceID>.json`), shared memory per account
  (`ai/memory-<accountID>.json`), settings/skills/MCP servers in `ai/settings.json`. API keys go
  through `KeyVault` (Keychain) and must never be written to the data folder or printed. Demo runs
  (`TETHER_DATA_DIR` set) never touch the Keychain and stay off the network unless a scene asks.
- **Model names**: don't hard-code lists. Models come from each service's own list endpoint; the
  only default is `claude-opus-5-5` when that service offers it.

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
undoes/redoes them; `TETHER_SCENE=awaketest` checks the power assertion with `pmset`;
`TETHER_SCENE=filetest` imports a generated PDF, writes notes on it, deletes and restores it and
checks the clean-up; `TETHER_SCENE=spacetest` fills an account to the Space limit, deletes, reloads
from disk and signs back in (point `TETHER_DATA_DIR` at a folder written by an older build to check
that it still opens); `TETHER_SCENE=cattest` files nodes under categories, deletes one and undoes it.

The assistant has three more. They need no real key:

```bash
# One conversation through Claude → ChatGPT → Gemini against a stand-in server: streaming, a tool
# call that edits a node, Undo, shared memory, a declined edit. The server rejects a follow-up
# that doesn't replay the model's hidden state.
python3 Scripts/mock-ai.py 8765 /tmp/requests.jsonl &
D=$(mktemp -d); TETHER_DATA_DIR=$D TETHER_DEMO=1 TETHER_SCENE=aitest TETHER_SNAPSHOT=$D/s.png TETHER_SNAPSHOT_DELAY=9 \
  TETHER_AI_KEY_ANTHROPIC=test-key TETHER_AI_KEY_OPENAI=test-key TETHER_AI_KEY_GEMINI=test-key \
  TETHER_AI_BASE_ANTHROPIC=http://127.0.0.1:8765 TETHER_AI_BASE_OPENAI=http://127.0.0.1:8765 \
  TETHER_AI_BASE_GEMINI=http://127.0.0.1:8765 build/Tether.app/Contents/MacOS/Tether
```

`TETHER_SCENE=mcptest` with `TETHER_MCP_MOCK=$PWD/Scripts/mock-mcp.py` connects a stand-in MCP
server and calls its tools; `TETHER_SCENE=ollamatest` talks to a real local model if Ollama is
running (`TETHER_OLLAMA_MODEL` picks one; give it `TETHER_SNAPSHOT_DELAY=75`). The stand-in server
proves Tether's side of each wire format, not the real services — those need a real key to check.
All print to stdout:

```bash
D=$(mktemp -d); TETHER_DATA_DIR=$D TETHER_DEMO=1 TETHER_SCENE=selftest \
  TETHER_SNAPSHOT=$D/shot.png build/Tether.app/Contents/MacOS/Tether
```
