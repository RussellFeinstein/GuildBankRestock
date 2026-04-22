# Changelog

All notable changes to GuildBankRestock will be documented here.

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
