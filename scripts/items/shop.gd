class_name Shop
extends RefCounted
## Merchant stock and buying. Static functions, so `Shop.roll_stock(...)` works as a
## class call; FESignals.get_shop_offer() finds this class by name (global class list),
## instantiates it, and calls the same functions on the instance — no FE changes.


## ItemDb.STOCK_SIZE distinct items for the shop after `stage`, weighted by rarity
## (rarer items unlock on later stages). Same (stage, seed) → same stock.
## Offer prices are ItemDb.shop_price (row price x the PROVISIONAL ItemDb.PRICE_SCALE).
static func roll_stock(stage: int, seed: int) -> Array[Item]:
	var st := maxi(stage, 1)
	var out := ItemDb.roll(ItemDb.rng_for(st, seed, "shop"), st, ItemDb.STOCK_SIZE)
	for it in out:
		it.price = ItemDb.shop_price(it.id, st)
	return out


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
	ps.grant_item(item)
	return true
