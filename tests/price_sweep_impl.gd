extends RefCounted
## Price sweep implementation (see price_sweep.gd).


func run(tree: SceneTree) -> void:
	var out_path := "/tmp/gold.json"
	var seeds := 1000
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]
		if args[i] == "--seeds" and i + 1 < args.size():
			seeds = int(args[i + 1])
	var res := {}
	for st in range(1, 6):
		var rows: Array = []
		for sd in seeds:
			var L := LevelGenerator.generate(sd, st)
			var piles := 0
			for g in L.gold:
				piles += int(g.amount)
			var vases := 0
			for p in L.props:
				if str(p.type) == "vase":
					vases += 1
			seed(int(L.get("build_seed", 0)))
			var vg := 0
			for _v in vases:
				if randf() < 0.45:
					vg += randi_range(1, 3)
			var row := {piles = piles, vases = vases, vase_gold = vg, chests = L.chests.size()}
			if st <= 4:
				PlayerStats.reset()
				var ids: Array = []
				for it in Shop.roll_stock(st, sd):
					ids.append(str(it.id))
				row["stock"] = ids
			rows.append(row)
		res[str(st)] = rows
	var prices := {}
	for r in ItemDb.ITEMS:
		prices[str(r.id)] = int(r.price)
	res["row_prices"] = prices
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(res))
	f.close()
	print("wrote ", out_path)
	tree.quit(0)
