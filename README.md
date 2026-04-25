# Guild Bank Restock

A World of Warcraft addon that automates buying items from the Auction House using [Auctionator](https://www.curseforge.com/wow/addons/auctionator). Designed for restocking a guild bank or your own bags with gems, enchants, potions, flasks, and weapon oils/stones.

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

## Contexts

Use the **Guild** / **Personal** buttons at the top of the sidebar to switch contexts. Each context has its own settings, profiles, and scan data.

- **Guild** — restock the guild bank; scans all guild bank tabs
- **Personal** — restock your own consumables; scans bags, personal bank, and warband bank

## Modes

Each context has two operating modes, toggled with the **Bulk** and **Restock** buttons.

### Bulk mode
Buys a fixed quantity of each selected item regardless of what is already in stock. Good for restocking at the start of a new expansion.

1. Type `/restock` to open the window, choose **Guild** or **Personal**, and select **Bulk**
2. Check the items you want and set the **Qty** for each
3. Open the AH and switch to the **Auctionator Shopping** tab
4. Click **Start Search** at the bottom of the frame — the addon searches and queues purchases for every enabled item

### Restock mode
Scans your stock source (guild bank or personal inventory) to determine what is actually needed before buying anything.

**Guild Bank:**
1. Open the guild bank and click the **Scan for Restock** button that appears on the bank UI
2. Type `/restock`, choose **Guild**, and select **Restock**
3. Create or select a profile using the `+` / `-` / `<` / `>` controls
4. Set a **Target** quantity per item — the stock level you want to maintain
5. The **To Buy** column is calculated automatically (`Target − in bank`) but can be edited
6. Open the AH and click **Start Search**

**Personal:**
1. Open your bank and click **Scan Inventory** in the addon window (or click the button that appears on the bank UI)
2. Choose **Personal** and select **Restock**
3. Create or select a profile, set **Target** quantities, and click **Start Search**

### Profiles
Profiles store per-item target quantities and inclusion state. You can have multiple profiles — for example, one per role or content type. Use `+` to create, `<` / `>` to cycle, `-` to delete, and **Save As** to copy the active profile to a new name.

In Restock mode, use **Add Items** to temporarily reveal non-profile items so you can check them in and add them to the profile.

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
| `Categories/Food.lua` | Food |
| `Categories/Runes.lua` | Runes (Augment + Vantus) |

Items are identified by item ID for reliability across patches. Names are included as comments. Ranked items (R1/R2) carry a `rank` field used by the rank filter buttons.

Example item entry:
```lua
{ id = 240969, qty = 1, enabled = true },           -- no rank (gem)
{ id = 243976, rank = 2, qty = 1, enabled = true }, -- rank 2 enchant
```

Categories that use subcategory headers (e.g. Enchants) can include `{ header = "Label" }` entries to visually group items by slot.

## Budget

A per-run gold limit can be set in the `Budget (g):` field at the bottom of the frame. Set it to `0` (the default) for no limit.

When the budget is reached mid-run, the addon pauses and returns to the main window. It prints:
- Total gold spent for the run (broken down to gold/silver/copper)
- Every item that was not purchased due to the budget being hit

The budget is saved between sessions so you don't need to re-enter it each time.

## Max price per item

Each item row has a **Max g** column. Enter a gold ceiling for that item; if the current AH unit price exceeds it, the item is automatically skipped and a message is printed to chat and the Log tab:

```
Guild Bank Restock: Skipped Vibrant Shard: 45.00g/ea exceeds max 30g.
```

Leave the field blank (or set it to `0`) for no limit. This is useful for avoiding market-reset prices where someone has listed an item far above its normal value. The value is saved between sessions.

## Development

The `Libs/` directory is gitignored. To populate it for local development, run:

```bash
bash fetch-libs.sh
```

This downloads the required Ace3 libraries (LibStub, CallbackHandler-1.0, AceAddon-3.0, AceDB-3.0, AceConsole-3.0, AceEvent-3.0, AceGUI-3.0) from GitHub. The script is idempotent — it skips any library already present. Packaged releases bundle the libraries automatically.

## Notes

- Uses [Ace3](https://www.wowace.com/projects/ace3) (AceAddon, AceDB, AceConsole, AceEvent, AceGUI) — libraries are bundled with the addon; run `fetch-libs.sh` for development
- Only commodity-type items (stackable) are supported by the underlying AH API
- The Auctionator Shopping tab must be open before clicking Start — the addon builds and runs the search itself, no manual shopping list setup required
- In Restock mode, click **Scan for Restock** on the guild bank UI before heading to the AH — scanning is always manual and never happens automatically
- The addon will stop automatically if a purchase fails (e.g. insufficient gold)
- The window is movable and can be closed with ESC
- Navigation uses a left-side sidebar: Guild/Personal context switcher at the top, category buttons below, Selected/About/Log pinned to the bottom
- Guild Bank and Personal contexts each have independent item settings and profiles
- The **Selected** tab shows all currently checked / profile-included items across every category in one flat list
- Item states, quantities, rank filter, active mode, active profile, active context, and the activity log are all saved automatically and restored on login
