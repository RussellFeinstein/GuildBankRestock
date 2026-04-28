# Changelog

All notable changes to GuildBankRestock will be documented here.

## [0.9.8] - 2026-04-27

### Fixed
- Guild bank scan now records actual stack counts. The third return of `GetGuildBankItemInfo` is `locked` (boolean), not `itemCount` — every stack was being recorded as 1 regardless of size, which broke restock-target math against any item with stacks larger than 1
- Target / To Buy / Qty / In Bank / bulk-set fields now accept up to 5 digits (was capped at 3, so any target above 999 was impossible to enter)
- **Est Run** total now refreshes whenever a Target, To Buy, or Qty value changes — previously target edits updated the local boxes but not the running total at the bottom of the tab, so the Est Run number could lag behind reality. To Buy and Qty also now apply on click-away (previously only on Enter), matching how Target already worked
- Re-checking an item's checkbox now adds it back into the **Est Run** total. Previously the checkbox handler only triggered a refresh on uncheck (so disabling an item correctly removed it from the running cost) but not on re-check, leaving Est Run stale until something else triggered a rebuild
- Auction House search now works against current Auctionator. The addon was passing `itemID` to `Auctionator.API.v1.ConvertToSearchString`, but that API requires `searchString` (the item NAME). Item IDs were silently dropped, validation failed, and the search aborted before any AH query was issued. Now resolves IDs to names asynchronously via `Item:CreateFromItemID():ContinueOnItemLoad(...)` and passes the name to Auctionator
- **Export** button on the Log tab no longer hides under the scrollbar. It now sits flush with the log content's right edge (20px clear of the scrollbar), matching the log text area's own offset
- Search-complete screen no longer falsely claims "All items purchased!" when items in the queue weren't actually bought. The summary now distinguishes three exit reasons separately: bought (purchase succeeded), skipped (price exceeded the per-item Max g — previously these were lumped into "Bought N"), and not-found-on-AH (no listings to map). Examples: full success shows "All items purchased!"; mixed shows "Bought 3. 1 skipped (price). 2 not found on AH."; empty AH shows "No listings found on AH. N item(s) unavailable — try later."
- Cancel-and-restart race during async name loading. Closing the window mid-search and immediately re-clicking Start Search could let stale `ContinueOnItemLoad` callbacks from the cancelled search write into the new search's name array — fired DoSearch with index-mismatched search strings. A search-generation token bumped by `Reset` and `StartSearch` invalidates any in-flight callbacks from prior runs
- Closing the addon window mid-search now stops Auctionator's underlying AH query too. Previously `Reset` only unregistered our listener — Auctionator's `SearchProvider` kept running and would eventually fire `SearchEnd` into a stale state, or get consumed by a freshly-registered listener if the user immediately restarted the search. `Reset` now calls `AuctionatorShoppingFrame:StopSearch()` when our state is `SEARCHING` or `READY`, which calls `SearchProvider:AbortSearch()` and clears Auctionator's spinner cleanly
- AH search results now map correctly. `MapResultRows` was reading from `AuctionatorShoppingFrame.ResultsListing.dataProvider`, but Auctionator's DataProvider doesn't synchronously populate `cachedResults` when the SearchEnd event fires — it queues entries via `AppendEntries` and processes them across multiple frames. So `dataProvider:GetCount()` returned 0 (or stale data) at the moment we read it, and the addon reported "0/N items found in AH" even when listings were visible in the Auctionator window. Now reads the results array directly from the SearchEnd event payload, which carries the full match set synchronously
- Every log entry was being recorded twice in saved variables. After `OnInitialize`, `ns.log` and `ns.addon.db.global.log` reference the same table, but `ns.Log` appended to both, doubling every line. Now appends once

### Added
- **Scan Guild Bank** button in the sidebar (Guild context). Mirrors the existing **Scan Inventory** button in the Personal context. The bank-attached "Scan for Restock" button below the guild bank frame still works as before, but the sidebar button is always visible when the addon window is open. Clicking it without the guild bank open prints a friendly reminder. On a successful scan, the sidebar button briefly shows **Scanned!** before reverting, matching the bank-attached button's feedback
- **Bulk-set field** in the button bar of every category and the All Items tab. Type a number, press **Set Target** (Restock mode) or **Set Qty** (Bulk mode) — or hit Enter — and the value is applied to every row that is both visible under the active rank filter AND currently checked. Uncheck any rows you want to skip (e.g. uncheck the epic gems to set just the rare ones). Restock mode also recalculates To Buy. Avoids retyping the same number across many rows
- **Sortable columns**. Click any column header (Item, Target, In Bank, To Buy, Qty, Mkt Price, Est g, Max g) to sort by that column ascending; click again for descending; click a third time to return to default order. The active column shows a `^` (asc) / `v` (desc) glyph next to its label. Items with no TSM price always sort to the bottom so an unpriced row never tops a "highest first" view. While sorted, section dividers (Gems / Potions / …) collapse into one flat list — switch back to default order to bring them back. Sort state is session-only and resets on `/reload`
- In-flight diagnostic logging for the AH search path. Log-only (no chat noise): traces async name resolution, search-string build, DoSearch firing, EventBus reception, ignored events with reasons, and search-generation invalidations. Visible in the Log tab and exportable, so the next bug in the search code is debuggable from the user's log instead of needing fresh instrumentation

## [0.9.7] - 2026-04-27

### Fixed
- Gems R1/R2 filter buttons now work correctly — all gem entries now carry `rank = 1` or `rank = 2` so the Rank 1 / Rank 2 / All Ranks filter applies to the Gems tab the same way it does for Potions and Flasks

## [0.9.6] - 2026-04-27

### Added
- **Gems R1 entries**: all 20 gem cuts now have R1 counterparts (ID = R2 − 1) listed above their R2 entry — covers Eversong Diamonds, Lapis, Amethyst, Peridot, and Garnet cuts

## [0.9.5] - 2026-04-27

### Added
- **First-run hint**: on the very first load, a chat message directs new users to open the minimap button and check the About tab
- **Guild bank scan timestamp**: after scanning the guild bank, the sidebar shows "Scanned HH:MM" (matching the existing Personal scan time display); scan status now shows for both Guild and Personal contexts
- **Restock scan prompt**: in Restock mode, when no scan has been done yet, a dimmed hint appears below the scan status — "Open the guild bank to scan." or "Open your bank to scan."
- **Tooltips on edit box fields**: hovering any input field now shows a tooltip — Max g ("Max price per unit. Leave blank for no limit."), Budget ("Per-run gold limit…"), Target ("Target quantity to keep in stock."), To Buy ("Amount to buy. Auto-calculated from Target minus current stock. Can be overridden manually.")
- **Rank button tooltips**: hovering Rank 1, Rank 2, or All Ranks in the button bar shows a brief description of each tier
- **Empty categories hidden**: sidebar buttons are no longer created for categories with no items (hides the empty Food stub)

### Changed
- "Add Items" / "Hide Extra" toggle in the Selected tab (Restock mode) renamed to **"Show All Items"** / **"Profile Only"** for clarity

### Fixed
- Typing numbers into any edit field no longer triggers action bar abilities — key events were propagating to the game's keybinding system for unhandled keys

## [0.9.4] - 2026-04-26

### Changed
- "Est Run" and "Budget" labels in the search bar now use `GameFontHighlightLarge` for better readability
- Status bar idle text corrected from "…click Start." to "…click Start Search."
- Sidebar scan-status color codes extracted to `C_GREEN` / `C_ORANGE` file-level locals (code cleanup)
- Budget logic: magic numbers `10000` and `100` replaced with `COPPER_PER_GOLD` / `COPPER_PER_SILVER` constants
- `## OptionalDeps: Ace3` removed from .toc — Ace3 is bundled locally in `Libs/` and is not a game-level optional dependency

### Fixed
- `ns.DeleteProfile`: prints "No profiles remain — create one with New." when the last profile is deleted, instead of silently leaving the UI in a "(no profile)" state with no guidance

## [0.9.3] - 2026-04-25

### Changed
- **UI split into Sidebar.lua and Tabs.lua**: sidebar panel code extracted to `Sidebar.lua`; all tab content builders (`BuildCategoryContent`, `BuildAllItemsContent`, `BuildLogContent`, `BuildAboutContent`) and `SelectTab` extracted to `Tabs.lua`; `UI.lua` now only owns the main frame shell, static popups, `ShowTabView`, `ShowStatusView`, and `UpdateUI`
- Shared UI state moved into `ns.ui` table (`LOG_TAB`, `ABOUT_TAB`, `ALL_TAB`, `version`, `currentCatIdx`, `currentRankFilter`, `showAllProfileItems`, `sidebarButtons`, `mainFrame`, `sidebarPanel`, `contentGroup`) — eliminates upvalue coupling between files
- `StartSearch` moved from `UI.lua` to `GuildBankRestock.lua` as `ns.StartSearch` so it is accessible before the UI loads
- Log timestamps now include date: `[MM/DD HH:MM:SS]` instead of `[HH:MM:SS]`
- `ns.RefreshProfileUI` merged into `ns.RefreshToBuyUI` (both did the same refresh; callers updated)
- Category tabs now show all items regardless of profile — profile inclusion filtering moved exclusively to the Selected tab; "Add Items" / "Hide Extra" toggle removed from per-category view
- **Select All / Select None** in category tabs now respect the active rank filter (only affect visible ranked items)
- Log export popup reworked: uses `AceGUI:Release` on close to avoid frame leaks; export button repositioned to bottom-right of log content area

### Fixed
- Personal inventory scanning now uses `stackCount` (total items in stack) instead of `itemCount` (which may be per-slot metadata) — fixes undercounting stacked items in bags, personal bank, and warband bank

## [0.9.2] - 2026-04-25

### Changed
- **Sidebar controls moved**: Mode (Bulk / Restock), Profile nav (<< Name >>), Profile actions (New / Delete / Save), and Scan Inventory are now persistent sidebar controls instead of being rebuilt inside each tab — they stay visible and update in place when switching tabs
- Sidebar widened from 120 px to 150 px to fit the new controls; content area shifted right to match
- `RefreshSidebar()` centralises all highlight and reposition logic for Guild/Personal, Bulk/Restock, profile section, and scan section; `ns.ApplySettingsToUI` and `ns.RefreshToBuyUI` / `ns.RefreshProfileUI` now call it directly
- **Runes category**: merged `AugmentRunes.lua` and `VantusRunes.lua` into a single `Runes.lua`; populated with Void-Touched Augment Rune (ID 259085)
- **Oils populated**: Thalassian Phoenix Oil R1 (ID 243733) and R2 (ID 243734)

## [0.9.1] - 2026-04-25

### Added
- **Personal mode**: new context (toggled via Guild / Personal buttons at the top of the sidebar) for restocking your own consumables instead of the guild bank — scans bags, personal bank, and warband bank; settings and profiles are stored separately from Guild Bank context
- **Personal inventory scanning** (`Personal.lua`): "Scan Inventory" button appears in the UI; scans all bag slots, personal bank slots, and warband bank tabs; scan time is displayed in the UI after scanning
- **Selected tab**: new sidebar entry that shows all checked / profile-included items across every category in a single flat list, so you can review and start a run without switching tabs
- **Profile inclusion snapshots** (`_inc`): profiles now record which items are included, so switching profiles correctly enables/disables items across all categories
- **"Add Items" / "Hide Extra" toggle**: in Restock mode with a profile active, a new button lets you temporarily reveal non-profile items so you can check them in and add them to the profile
- **New category files** (empty, ready to populate): Augment Runes, Food, Vantus Runes
- **Potions** populated — 16 items (R1/R2 pairs): Light's Potential, Potion of Recklessness, Draught of Rampant Abandon, Potion of Zealotry, Silvermoon Health Potion, Lightfused Mana Potion, Potion of Devoured Dreams, Void-Shrouded Tincture
- **Flasks** populated — 8 items (R1/R2 pairs): Flask of the Blood Knights, Flask of the Magisters, Flask of the Shattered Sun, Flask of Thalassian Resistance

### Changed
- Est Run cost, Budget, and Start Search bar moved to the bottom of the frame
- "In Bank" column header renamed to "In Bags" when in Personal context
- Select All / Select None now only affect items visible in the current filter (respects profile inclusion and the Add Items toggle)
- Unchecking an item in Restock mode with an active profile now removes it from the profile's inclusion snapshot and immediately rebuilds the tab
- `ns.ContextDB()` helper added — all settings reads/writes are now routed through the active context (guild or personal) automatically
- `ns.GetStock(itemID)` replaces direct `guildBankStock` lookups — returns from the correct stock table based on context
- Switching profiles now syncs `item.enabled` across all categories to match the profile's inclusion snapshot

### Fixed
- Pressing Enter to confirm a number field no longer opens the game chat box — the key event was propagating to WoW's global keybinding system

## [0.9.0] - 2026-04-24

### Changed
- Replaced AceGUI Frame + TabGroup with a raw WoW frame and a left-side sidebar for navigation
- Category buttons (Gems, Enchants, Potions, Flasks, Oils) stack at the top of the sidebar; Log and About are pinned to the bottom
- Active sidebar tab is visually highlighted
- Window chrome is now fully custom: draggable title bar, close button, and status text at the bottom — AceGUI Frame widget removed
- Frame has a visible border and inner padding on all sides so no content touches the frame edge
- AceGUI is still used for all per-tab widget content (checkboxes, edit boxes, scroll frames, labels, buttons)

## [0.8.12] - 2026-04-24

### Changed
- About tab moved to the right of Log, both right-aligned in the tab bar
- About tab uses larger font sizes (`GameFontNormalHuge` for headings, `GameFontNormalLarge` for body) for easier reading

## [0.8.11] - 2026-04-24

### Fixed
- Minimap icon was black — switched from path-based lookup to file data ID (413587) which is required for retail

## [0.8.10] - 2026-04-24

### Added
- **About tab**: new tab with addon description, feature list, getting started guide, slash commands, requirements, and author credit
- Minimap button position (drag angle) now persists across sessions via SavedVariables

## [0.8.9] - 2026-04-24

### Changed
- Minimap button now uses the in-game `GUILDPERK_MOBILEBANKING` icon instead of a custom PNG

## [0.8.8] - 2026-04-24

### Added
- TSM integration: each item row now shows a **Mkt Price** column (TSM DBMarket) and an **Est g** column (market price × quantity to buy); a right-aligned **Est Run** total in the search bar sums estimated cost across all enabled items — both are display-only and fall back gracefully when TSM is not loaded
- **Save As** button on the profile bar: copies the active profile to a new name and switches to it, replacing the delete-and-recreate workflow
- Keyboard navigation for edit-box fields: Tab / Shift-Tab move linearly, Left / Right move within a row, Up / Down move by column across rows

### Changed
- Column widths tightened to fit the two new price columns without horizontal overflow
- Editing a quantity, Target, or To Buy value now rebuilds the tab immediately so Mkt Price and Est g reflect the new quantity in place

## [0.8.7] - 2026-04-24

### Added
- To Buy column now autofills after a guild bank scan: calculates `max(0, Target − In Bank)` for every item and refreshes the UI automatically

### Fixed
- Target Qty field now saves when clicking away (focus-loss), not only on Enter — previously, typing a target without pressing Enter meant the scan would recalculate using the old (unsaved) value and reset To Buy to 0
- `RefreshToBuyUI` no longer errors when the addon frame was never opened before a scan (`tabGroup` nil guard)
- To Buy values are now populated on addon load so the column shows the correct baseline immediately instead of showing 0 for every item until a profile change or scan

## [0.8.6] - 2026-04-23

### Added
- Timestamps (`[HH:MM:SS]`) prepended to every log entry

### Changed
- Log now persists across sessions — stored in SavedVariables (capped at 500 entries) and replayed on login; it no longer resets on reload or relog

### Fixed
- Log scrollbar thumb direction was inverted — thumb now sits at the bottom when viewing the most recent entries and at the top when scrolled to oldest

## [0.8.5] - 2026-04-23

### Fixed
- "Scan for Restock" button was not appearing on the guild bank UI — `GUILDBANKFRAME_OPENED` was replaced by `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` in WoW 10.0.2+; switched to the new event with a fallback for older clients

## [0.8.4] - 2026-04-23

### Fixed
- ESC now closes the window again — the Ace3 migration left the frame anonymous, so it was never registered with `UISpecialFrames`; fixed by giving the inner frame a global name and inserting it
- Ring enchant rank data corrected: all 5 ring enchants were mislabeled `rank = 2`; added the missing R2 entries and corrected R1/R2 assignment — lower ID = R1, higher ID = R2, consistent with every other enchant slot

### Changed
- Default window width increased from 440 to 1000

## [0.8.3] - 2026-04-23

### Changed
- Button bar split into two rows to eliminate cramped layout and truncated labels
- "All" / "None" renamed to **Select All** / **Select None** with wider buttons
- "R1" / "R2" / "Both" renamed to **Rank 1** / **Rank 2** / **All Ranks** with wider buttons
- "Start" renamed to **Start Search** and given more width; budget editbox widened

## [0.8.2] - 2026-04-23

### Fixed
- `GetAddOnMetadata` nil error on load — replaced with `C_AddOns.GetAddOnMetadata` (the old global was removed in The War Within 11.0), with a fallback for compatibility

## [0.8.1] - 2026-04-21

### Added
- Per-item maximum price: each item row in the checklist now has a **Max g** field. If the AH price per unit exceeds this limit the item is automatically skipped and a message is printed to chat and the Log tab explaining why (e.g. "Skipped Vibrant Shard: 45.00g/ea exceeds max 30g."). Leave blank or set to 0 for no limit. Value is saved between sessions.

## [0.8.0] - 2026-04-21

### Changed
- Migrated to Ace3 framework: AceAddon (lifecycle), AceDB (SavedVariables), AceConsole (slash commands), AceEvent (WoW events), AceGUI (UI widgets)
- Rebuilt UI with AceGUI: tabs, item checklist, and buttons are now standard Ace3 widgets
- `Commands.lua` removed — slash commands absorbed into the core addon lifecycle
- Raw event frame replaced by AceEvent; raw SavedVariables access replaced by AceDB
- Tab content is rebuilt dynamically on selection; rank filter rebuilds the tab instead of repositioning rows
- Budget field moved inline into the button bar (beside the rank filter buttons and Start)
- Existing settings (items, quantities, rank filter, mode, profiles, budget) migrate automatically to the AceDB format

### Added
- `fetch-libs.sh` — downloads Ace3 libraries into `Libs/` for local development (idempotent, skips libraries already present)
- `.gitignore` — excludes the fetched `Libs/` directory from version control
- Item link tooltips on checkbox hover in the checklist

## [0.7.1] - 2026-04-21

### Added
- Per-run gold budget: set a limit in the `Budget (g):` field above the Start button
- When the budget is hit mid-run the addon pauses, prints how much was spent (gold/silver/copper), and lists every item that was not purchased in chat and in the Log tab
- Budget persists between sessions; set to 0 for no limit

## [0.7.0] - 2026-04-21

### Added
- Guild bank scanning: a "Scan for Restock" button appears on the guild bank UI and scans all tabs on demand; scanning is never automatic
- Bulk mode: buy a set quantity of each selected item regardless of guild bank contents — useful for fresh expansion starts
- Restock mode: load a named profile with per-item target quantities; the addon compares current bank stock against targets and queues only what is needed
- Multiple named profiles supported — switch between them with the `<` / `>` buttons, create with `+`, delete with `-`
- Target and To Buy columns in Restock mode — Target saves to the active profile, To Buy is calculated from the bank scan but can be overridden before starting a run
- Guild bank scanning logic moved to its own file (`GuildBank.lua`) and profile logic to `Profiles.lua`

## [0.6.2] - 2026-04-21

### Added
- Version number is now visible in the title bar of the main window
- `/restock version` (or `/restock v`, `/rs v`, etc.) prints the current version to chat

## [0.6.1] - 2026-04-21

### Added
- toc bump for 12.0.5

## [0.6.0] - 2026-04-13

### Added
- Log tab in the main window showing session activity: search started, search complete, items not found, purchases, purchase failures, and stops
- Log is in-memory only and resets each WoW session
- Log entries are color-coded by event type; scroll with the mouse wheel

## [0.5.2] - 2026-04-13

### Fixed
- ESC now prints "Stopped." in all cases, not just when a run is in progress
- Reset and stop message are now handled in a single OnHide script instead of being duplicated across the stop button and slash command

## [0.5.1] - 2026-04-13

### Fixed
- Pressing ESC during a run now stops the addon and prints "Stopped." instead of just hiding the window

## [0.5.0] - 2026-04-13

### Added
- Settings now persist across sessions via SavedVariables (`GuildBankRestockDB`)
- Item enabled states, quantities, and the active rank filter (R1/R2/Both) are all saved automatically on change and restored on login

## [0.4.1] - 2026-04-13

### Added
- R1, R2, and Both buttons highlight in gold to show the active rank filter; defaults to Both on load

## [0.4.0] - 2026-04-13

### Changed
- Split main lua into `GuildBankRestock.lua` (core logic), `UI.lua` (frames and handlers), and `Commands.lua` (slash commands)
- Updated README to reflect current features: rank filter buttons, `/rs` alias, category files, item ID format, and header entries

## [0.3.1] - 2026-04-13

### Fixed
- Hidden rows no longer leave empty space when filtering by rank; visible rows are repacked and the scroll area resizes to match

## [0.3.0] - 2026-04-13

### Added
- Subcategory headers within the Enchants tab (Rings, Chest, Leg, Head, Shoulder, Boots)

### Changed
- R1 / R2 buttons now fully hide items of the other rank instead of just unchecking them
- Subcategory headers are hidden automatically when all their items are filtered out

## [0.2.5] - 2026-04-13

### Changed
- Column headers (Item, Qty) now render in larger text

## [0.2.4] - 2026-04-13

### Fixed
- Lua error on load caused by column header referencing layout constants before they were defined

## [0.2.3] - 2026-04-13

### Added
- Column headers (Item, Qty) above the checklist
- ESC now closes the window

## [0.2.2] - 2026-04-13

### Fixed
- Item name column now stretches to fill available space when the window is resized
- Quantity box is anchored to the right edge of the window and moves with it on resize

## [0.2.1] - 2026-04-13

### Fixed
- Item names no longer wrap onto a second line in the checklist

## [0.2.0] - 2026-04-13

### Added
- R1 / R2 / Both buttons to filter ranked items across all tabs at once
- Items in category files now support an optional `rank` field; items without one are unaffected by the rank filter
- Enchants category fully populated (41 items across Rings, Chest, Leg, Head, Shoulder, Boots)

## [0.1.2] - 2026-04-13

### Changed
- Items are now identified by item ID instead of name, making matching more reliable across patches
- AH search, result mapping, and UI display all use item ID; names are shown as comments in category files

## [0.1.1] - 2026-04-13

### Changed
- Each item category is now defined in its own file under `Categories/` (Gems, Enchants, Potions, Flasks, Oils) instead of inline in the main file

## [0.1.0] - 2026-04-10

### Changed
- Renamed addon from GemBuyer to Guild Bank Restock
- Slash commands changed from `/gemshop` / `/gemshop stop` to `/restock`, `/bankrestock`, and `/rs`.
- Items are now organized into category tabs (Gems, Enchants, Potions, Flasks, Oils)
- Frame collapses to compact mode during search and purchase flow

### Added
- Category tab UI with per-tab All / None selection
- State machine (IDLE → SEARCHING → READY → CONFIRMING) for structured purchase flow

## [0.0.1] - 2026-04-10 - GemBuyer

### Added
- Initial release
- Automated gem purchasing via Auctionator Shopping tab
- Checklist UI with per-gem enable/disable toggles and quantity fields
- All / None quick-select buttons
- Item link tooltips on hover
- Resizable and movable window
- `/gemshop` and `/gemshop stop` slash commands
- Support for 20 gem types (Eversong Diamonds, Lapis, Amethyst, Peridot, Garnet)
