# OptionsWindowShade — spec

Adds two subtle title-bar buttons to Blizzard's unified Options window (`SettingsPanel`):
**Shade** collapses the window to just its title bar so you can see what you are tweaking; **Lock/Unlock**
lets you drag the window by its title bar. Nothing is remembered: every time the window is dismissed it
comes back full-size, centered, locked — exactly as Blizzard ships it.

Repo: `OptionsWindowShade\` (own git repo, origin WoWAddons-Kuro/OptionsWindowShade). Single addon, no libs,
no SavedVariables. Targets WoW Forever first; Classic Era shares the same `Blizzard_Settings_Shared` panel.

## Ground truth (Blizzard source, `live` branch, saved under `_ref\blizzard\forever\`)

| File | What we rely on |
|---|---|
| `Blizzard_SettingsPanel.xml` | `SettingsPanel`: `movable="true"`, `enableMouse`, strata HIGH, 920x724, anchored `CENTER`. Parent is `UIParent` (`GetAppropriateTopLevelParent()` in `OnLoad`). |
| `Blizzard_SettingsPanelTemplates.xml` | `SettingsFrameTemplate`: title text is `SettingsPanel.NineSlice.Text` (anchored `TOP y=-5`, `LEFT x=60`, `RIGHT x=-60`); the title-bar X is `SettingsPanel.ClosePanelButton` (`UIPanelCloseButtonDefaultAnchors`, top-right). `SettingsPanel.CloseButton` is the *bottom-right* "Close" text button, not the X. |
| `Blizzard_SettingsPanel.lua` | `OnHide` → `Flush()` (clears search box, wipes pending Apply table, saves bindings). `Close()` → `ExitWithCommit` → `HideUIPanel` + `ToggleGameMenu()`. `SettingsPanel_EscapePressed` is the ESC path. No code re-anchors the frame after `ShowUIPanel`. |

Consequences:

- **Never `Hide()` the panel to shade it** — that is `Flush()`; search text, unapplied game settings and addon canvas state are lost. Shade = keep the frame *shown* but move it entirely off-screen, and show our own title-bar strip in its place. Off-screen (not `SetAlpha(0)`) so it cannot eat clicks.
- `StartMoving()/StopMovingOrSizing()` on `SettingsPanel` works (it is `movable`), but `StopMovingOrSizing()` flips `IsUserPlaced()` to true and the client would then restore the dragged position next login. **Always `SetUserPlaced(false)` right after `StopMovingOrSizing()`.**
- `HookScript(SettingsPanel, "OnHide")` is the single reset point: covers the X, bottom Close, ESC, `/reload`, and any addon calling `HideUIPanel(SettingsPanel)`.
- Only `C_SettingsUtil.OpenSettingsPanel` is protected; we never call it. Everything here is plain frame API → works in combat, no taint of Blizzard tables (we only parent our own frames under `SettingsPanel` and call its frame methods).

## Behaviour

### Title-bar buttons (always, while the panel is shown)

Two 18x18 buttons, children of `SettingsPanel`, anchored `RIGHT` → `SettingsPanel.ClosePanelButton` `LEFT` (x = -4), then chained leftwards:

```
[ Options title ............................ ][shade][lock][X]
```

- Style: **subtle / desaturated**. Icon textures `SetDesaturated(true)`, alpha 0.55 at rest, 1.0 on hover (`OnEnter`/`OnLeave`), highlight texture `Interface\Buttons\UI-Common-MouseHilight` (ADD blend). No red, no gold.
- Icons: shade = `Interface\Buttons\UI-Panel-CollapseButton-Up` ("−") when open, `UI-Panel-ExpandButton-Up` ("+") when shaded; lock = `Interface\Buttons\LockButton-Locked-Up` / `LockButton-Unlocked-Up`. Each path is checked with `SetTexture()` returning false → fall back to a `FontString` glyph ("−"/"+", "L"/"U") so a missing art file on one flavour never leaves an invisible button.
- Tooltips (`GameTooltip`, `ANCHOR_RIGHT`):
  - shade: `Shade window` / `Unshade window`, second line grey: `Keybind: <key>` or `Keybind: none` (see Keybinding).
  - lock: `Unlock window (drag the title bar to move)` / `Lock window`.

### Shade

State is a local table in `Core.lua` — `OWS_State = { shaded=false, unlocked=false, savedPoints=nil, strip=<frame> }`. Nothing is written onto `SettingsPanel`.

Shade (`OWS.Shade()`):

1. Guard: panel shown and not already shaded.
2. Record the strip position **before** moving: `left, top = SettingsPanel:GetLeft(), SettingsPanel:GetTop()`, `width = SettingsPanel:GetWidth()`, `scale = SettingsPanel:GetEffectiveScale()`.
3. Save every anchor: `savedPoints[i] = { SettingsPanel:GetPoint(i) }` for `i = 1..GetNumPoints()`.
4. `SettingsPanel:ClearAllPoints(); SettingsPanel:SetPoint("TOP", UIParent, "BOTTOM", 0, -200)` — fully below the screen. The frame stays `IsShown()==true`, so Blizzard state is untouched.
5. Show the strip (below) at `left/top/width`.

Unshade (`OWS.Unshade()`): hide strip, `ClearAllPoints()`, re-apply `savedPoints` in order, `savedPoints=nil`, `shaded=false`, update the shade icon.

**Strip** (`OWS_StripFrame`, parent `UIParent`, strata HIGH, frame level above the panel's, `SetScale` to match the panel, size `width x 26`):

- Looks like the panel's own title bar: inherits `NineSlicePanelTemplate` with `layoutType="ButtonFrameTemplateNoPortrait"` when that template exists (Mainline/Forever and Era 1.15 both have it), else `BackdropTemplate` dark fill + thin border.
- Title `FontString` copies `SettingsPanel.NineSlice.Text:GetText()` at shade time.
- Buttons on the strip mirror the panel's: `[unshade][lock][X]`. **X on the strip calls `SettingsPanel:Close()`** (same discard-confirm/commit path as Blizzard's X) — the resulting `OnHide` resets us.
- Positioned `TOPLEFT` → `UIParent BOTTOMLEFT` at (`left`, `top`) — exactly where the panel's title bar was. Not draggable in v1.
- Not movable, no SavedVariables, not an Edit Mode frame.

External re-anchoring while shaded: `UIParent`'s panel manager may `SetPoint` the panel again when another UI panel opens. `hooksecurefunc(SettingsPanel, "SetPoint", ...)` with a re-entrancy guard: if `shaded` and the call did not come from us, re-apply the off-screen anchor on the next frame (`C_Timer.After(0, …)`). Keeps the strip truthful.

### Lock / Unlock (move)

- `OWS_DragHandle`: invisible frame, child of `SettingsPanel`, covering the title-bar band (`TOPLEFT` x=0 y=0 → `TOPRIGHT`, height 26) but stopping short of the three buttons (anchor `RIGHT` to the shade button's `LEFT`). `EnableMouse(true)` only while unlocked so a locked window behaves 100% like stock. `RegisterForDrag("LeftButton")`.
- `OnDragStart` → `SettingsPanel:StartMoving()`; `OnDragStop` → `SettingsPanel:StopMovingOrSizing(); SettingsPanel:SetUserPlaced(false)`.
- Toggle lock updates the icon, tooltip and `EnableMouse`. Moving does **not** touch `savedPoints`; if the user moves then shades, the strip appears where the title bar currently is, and unshade restores to the moved spot (it saved the moved anchors).
- While shaded the drag handle is irrelevant (panel is off-screen). Dragging the strip: out of scope v1 (see Open Questions).

### Reset on dismiss

`SettingsPanel:HookScript("OnHide", OWS.ResetAll)`:

1. if shaded → `Unshade()` (restores anchors, hides strip);
2. `unlocked=false`, drag handle `EnableMouse(false)`, lock icon back to locked;
3. `SettingsPanel:SetUserPlaced(false)` (belt and braces).

Because Blizzard anchors the panel on `ShowUIPanel` and we restored its original anchors, the next open is centered and full-size with no SavedVariables involved.

### Keybinding

`Bindings.xml`:

```xml
<Bindings>
  <Binding name="OPTIONSWINDOWSHADE_TOGGLE_SHADE" category="BINDING_HEADER_OPTIONSWINDOWSHADE">
    OptionsWindowShade_ToggleShade();
  </Binding>
  <Binding name="OPTIONSWINDOWSHADE_TOGGLE_LOCK" category="BINDING_HEADER_OPTIONSWINDOWSHADE">
    OptionsWindowShade_ToggleLock();
  </Binding>
</Bindings>
```

- `BINDING_HEADER_OPTIONSWINDOWSHADE = "Options Window Shade"`, `BINDING_NAME_OPTIONSWINDOWSHADE_TOGGLE_SHADE = "Shade / unshade the Options window"`, `BINDING_NAME_OPTIONSWINDOWSHADE_TOGGLE_LOCK = "Lock / unlock the Options window"` set in `Locales.lua` (same pattern as `MoveMyBags.Kuro\Bindings.xml`).
- **No default keys.** Addon bindings never ship a default; we simply never call `SetBinding`.
- `OptionsWindowShade_ToggleShade()` / `OptionsWindowShade_ToggleLock()` are no-ops unless `SettingsPanel and SettingsPanel:IsShown()`.
- Tooltip line on each button: `GetBindingKey(<its binding>)` → `GetBindingText(key)`; nil → `Keybind: none`. Refresh on `UPDATE_BINDINGS` so the tooltip is live after the user binds it in the Keybindings category.
- `## IconTexture: Interface\AddOns\OptionsWindowShade\Media\OptionsWindowShade.tga` in the TOC (icon supplied by the owner).

### Slash command

`/optionswindowshade` and `/ows`:

| Command | Effect |
|---|---|
| (none) / `help` | prints version, current keybind, and the sub-commands |
| `shade` | toggle shade — only if the Options window is open, otherwise prints `Open the Options window first.` |
| `lock` | toggle lock — same guard |

That is the whole surface. No `/ows config`: there is nothing to configure.

## Files

```
OptionsWindowShade\
├── OptionsWindowShade.toc        ## Interface: 16001 (+ Era/Anniversary numbers copied from MinimapButtonTray's TOCs)
├── Bindings.xml                   one binding, no default
├── Locales.lua                    L[] table + BINDING_HEADER_*/BINDING_NAME_* globals
├── Core.lua                       state, Shade/Unshade/Lock, strip, hooks, slash, PLAYER_LOGIN init
├── .pkgmeta                       package-as: OptionsWindowShade; ignore README.md, SPEC.md, .github, .gitignore, .pkgmeta
├── .gitignore
├── LICENSE                        MIT
├── README.md
└── SPEC.md                        this file
```

Init: `PLAYER_LOGIN` → `if not SettingsPanel then return end` (`Blizzard_Settings_Shared` loads at startup on every supported flavour) → build buttons/strip/handle once, `HookScript("OnHide")`, `hooksecurefunc("SetPoint")`. Globals exported: `OptionsWindowShade_ToggleShade` only (plus slash handlers).

## Milestones

- [ ] **M1 — Scaffold**: repo, TOC, LICENSE, .pkgmeta, Locales.lua, README. `/ows` prints version. Add row to `AddonManagement\PROJECT_STRUCTURE.md` tree and `webhooks.cs` table (owner creates GitHub repo + CurseForge project).
- [ ] **M2 — Buttons + Lock**: two title-bar buttons with desaturated art, tooltips, drag handle, `SetUserPlaced(false)`, `OnHide` reset of lock. Manual test: drag, close, reopen → centered.
- [ ] **M3 — Shade**: off-screen anchor + strip with title/unshade/lock/X, anchor save/restore, `OnHide` reset, `SetPoint` guard. Manual test: shade → open bags → strip stays, panel stays off-screen; ESC while shaded → next open full-size; search text survives shade/unshade; AceConfig (DragonToast_Options) canvas survives shade/unshade.
- [ ] **M4 — Keybind + slash**: Bindings.xml, live tooltip text, `/ows shade|lock|help`.
- [ ] **M5 — Era check**: load on `_classic_era_`, confirm template/texture fallbacks are not hit (or that they look right if they are).

## Decisions (2026-11-22)

1. The shaded strip is **not draggable** — it sits exactly where the title bar was.
2. **Two keybinds**, both with no default: `OPTIONSWINDOWSHADE_TOGGLE_SHADE` and `OPTIONSWINDOWSHADE_TOGGLE_LOCK`. Both no-op unless the panel is shown; the lock button's tooltip shows its keybind the same way the shade button's does.
3. Slash: `/optionswindowshade` and `/ows`.
4. Addon icon (`## IconTexture`) is supplied by the owner as `Media\OptionsWindowShade.tga`; TOC references it from M1.
5. Button icon art: `UI-Panel-Collapse/ExpandButton` and `LockButton-*` textures; if they look wrong desaturated on Forever, switch to `common-icon-*` atlases. Decide on sight in M2.