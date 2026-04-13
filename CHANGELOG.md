# Changelog

All notable changes to GuildBankRestock will be documented here.

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
