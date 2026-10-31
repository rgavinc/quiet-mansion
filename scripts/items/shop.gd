class_name Shop
extends RefCounted
## Merchant stock and buying. Static functions, so `Shop.roll_stock(...)` works as a
## class call; FESignals.get_shop_offer() finds this class by name (global class list),
## instantiates it, and calls the same functions on the instance — no FE changes.


## ItemDb.STOCK_SIZE distinct items for the shop after `stage`, weighted by rarity
## (rarer items unlock on later stages). Same (stage, seed, owned items) → same stock.
## Never offers a copy that adds nothing (ItemDb.would_add / max_copies); short of items it
## tops up from the rest of the catalogue, and with nothing left at all it offers ONE free
## gold pouch (ItemDb.fallback_gold), so the shop never runs dry.
## Offer prices are ItemDb.shop_price (row price x the PROVISIONAL ItemDb.PRICE_SCALE).
static func roll_stock(stage: int, seed: int, stats: Node = null) -> Array[Item]:
	var st := maxi(stage, 1)
	var out := ItemDb.roll(ItemDb.rng_for(st, seed, "shop"), st, ItemDb.STOCK_SIZE, PackedStringArray(), stats)
	for it in out:
		it.price = ItemDb.shop_price(it.id, st)
	if out.is_empty():
		out.append(gold_pouch(st, stats))
	return out


const GOLD_POUCH_ID := "gold_pouch"

## The "nothing left to sell" offer: free, gives ItemDb.fallback_gold(stage) gold (through
## PlayerStats.add_gold, so Gold Magnet counts; the text shows that amount). Never owned.
static func gold_pouch(stage: int, stats: Node = null) -> Item:
	var it := Item.new()
	it.id = GOLD_POUCH_ID
	it.display_name = "Pouch of Gold"
	it.price = 0
	it.rarity = "common"
	it.max_copies = 0
	it.params = {gold = ItemDb.fallback_gold(stage)}
	var ps := Item._stats(stats)
	var find: float = ps.get_stat(&"gold_find_mult") if ps and ps.has_method(&"get_stat") else 1.0
	it.description = "Nothing left that would help you. Take %d gold instead." % int(round(it.params.gold * find))
	return it


## Buys `item`: spends its price through PlayerStats.try_spend, applies it and adds it
## to PlayerStats.owned_items. False (and nothing changes) if it's already sold, not
## an Item, or you can't afford it. `stats` defaults to the PlayerStats autoload.
static func buy(item: Item, stats: Node = null) -> bool:
	if item == null or item.sold or item.is_applied():
		return false
	var ps := Item._stats(stats)
	if ps == null or not ps.try_spend(item.price):
		return false
	item.sold = true
	if item.id == GOLD_POUCH_ID:
		ps.add_gold(int(item.params.get("gold", 0)))
		return true
	ps.grant_item(item)
	return true
