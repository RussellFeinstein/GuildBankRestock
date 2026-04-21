# Guild Bank Restock

A World of Warcraft addon that automates buying items from the Auction House using [Auctionator](https://www.curseforge.com/wow/addons/auctionator). Designed for restocking a guild bank with gems, enchants, potions, flasks, and weapon oils/stones.

## Requirements

- World of Warcraft: Midnight (12.x / Retail)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator) addon

## Installation

1. Download or clone this repository
2. Copy the `GuildBankRestock` folder into your WoW AddOns directory:
   ```
   World of Warcraft\_retail_\Interface\AddOns\GuildBankRestock
   ```
3. Launch WoW and enable the addon in the AddOns menu on the character select screen

## Usage

1. Open the Auction House and switch to the **Auctionator Shopping** tab
2. Type `/restock` in chat to open the Guild Bank Restock window
3. Use the category tabs (Gems, Enchants, Potions, Flasks, Oils) to browse and select items
4. Check the items you want to buy and set the quantity for each
5. Optionally use **R1** / **R2** / **Both** to filter ranked items (enchants, etc.) across all tabs at once
6. Click **Start** — the addon will search the AH for all selected items across all categories
7. For each item found, click **Buy** to purchase it
8. Repeat until all items are purchased, then the window closes automatically

### Slash Commands

| Command | Description |
|---|---|
| `/restock` | Open the Guild Bank Restock window |
| `/restock stop` | Cancel the current run and close the window |
| `/restock version` | Print the current addon version to chat (also `/restock v`) |
| `/bankrestock` | Alias for `/restock` |
| `/rs` | Alias for `/restock` |

## Configuration

Item quantities can be set per-item directly in the UI. Use the **All** and **None** buttons to quickly enable or disable all items in the current tab, or **R1** / **R2** / **Both** to filter by rank across all tabs.

To add or remove items, edit the relevant file in the `Categories/` folder. Each category is its own file:

| File | Category |
|---|---|
| `Categories/Gems.lua` | Gems |
| `Categories/Enchants.lua` | Enchants |
| `Categories/Potions.lua` | Potions |
| `Categories/Flasks.lua` | Flasks |
| `Categories/Oils.lua` | Oils |

Items are identified by item ID for reliability across patches. Names are included as comments. Ranked items (R1/R2) carry a `rank` field used by the rank filter buttons.

Example item entry:
```lua
{ id = 240969, qty = 1, enabled = true },           -- no rank (gem)
{ id = 243976, rank = 2, qty = 1, enabled = true }, -- rank 2 enchant
```

Categories that use subcategory headers (e.g. Enchants) can include `{ header = "Label" }` entries to visually group items by slot.

## Notes

- Only commodity-type items (stackable) are supported by the underlying AH API
- Start searches all enabled items across all category tabs in one run
- The addon will stop automatically if a purchase fails (e.g. insufficient gold)
- The window is resizable, movable, and can be closed with ESC
- Item enabled states, quantities, and the active rank filter are saved automatically and restored on login
