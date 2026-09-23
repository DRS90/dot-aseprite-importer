@tool
extends RefCounted
## Packs the strips of an import into one sheet, each frame trimmed to its own pixels and repeated
## frames stored once.
##
## Has no editor dependency, so headless tests can use it. Every cell of every strip is cut to its
## used rect; cells with the same pixels (same size, same bytes) share one region of the sheet,
## wherever they sat in their cells, and the regions are packed in shelves. The margin returned for
## each cell gives back the space cut away, so an AtlasTexture built from it is the size of the cell
## and draws its pixels where the cell had them: frames keep their size and their pivot. A cell with
## no visible pixel gets a shared transparent pixel, since a region of size 0 means "the whole
## atlas" to an AtlasTexture. A strip with no visible pixel at all is left out, as Aseprite leaves
## out an empty cell: Aseprite calls a cell empty only when its raw pixels are zero, so a cell of
## fully transparent pixels with color under them still reaches the packer.

## Largest texture side the renderers accept.
const MAX_TEXTURE_SIZE := 16384
## Shelf widths tried, as tenths of the side of a square holding every region.
const WIDTH_STEPS: Array[int] = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]

## Problems found by the last [method pack] call.
var errors := PackedStringArray()


## [param strips] holds {"key": String, "image": Image} entries, each image a strip of cells of
## [param cell_size] side by side. Returns {"sheet": Image, "cells": {key: Array of {"region":
## Rect2i, "margin": Rect2i}}}, one entry per cell of each strip that has a visible pixel, or an
## empty dictionary when [member errors] is not empty. "sheet" is null when nothing is visible. The
## same strips always give the same sheet.
func pack(strips: Array[Dictionary], cell_size: Vector2i) -> Dictionary:
	errors = PackedStringArray()
	# Distinct trimmed images, and for each strip [item index, margin] per cell.
	var items: Array[Image] = []
	var item_index := {}
	var placements := {}
	var order := PackedStringArray()
	for strip: Dictionary in strips:
		var key: String = strip["key"]
		var cells := _cut(key, strip["image"], cell_size)
		if cells.is_empty():
			continue
		var placed: Array[Array] = []
		for cell: Dictionary in cells:
			var trimmed: Image = cell["image"]
			var identity := [trimmed.get_size(), trimmed.get_data()]
			if not item_index.has(identity):
				item_index[identity] = items.size()
				items.append(trimmed)
			placed.append([item_index[identity], cell["margin"]])
		placements[key] = placed
		order.append(key)
	if not errors.is_empty():
		return {}
	if items.is_empty():
		return {"sheet": null, "cells": {}}

	var sizes: Array[Vector2i] = []
	for item: Image in items:
		sizes.append(item.get_size())
	var layout := best_layout(sizes)
	var sheet_size: Vector2i = layout["size"]
	if sheet_size.x > MAX_TEXTURE_SIZE or sheet_size.y > MAX_TEXTURE_SIZE:
		errors.append(
			(
				(
					"The packed sheet would be %dx%d px, larger than the %d px a texture can be. "
					% [sheet_size.x, sheet_size.y, MAX_TEXTURE_SIZE]
				)
				+ "Split the file or its tags."
			)
		)
		return {}

	var sheet := Image.create_empty(sheet_size.x, sheet_size.y, false, Image.FORMAT_RGBA8)
	var positions: Array[Vector2i] = layout["positions"]
	for index: int in items.size():
		sheet.blit_rect(items[index], Rect2i(Vector2i.ZERO, sizes[index]), positions[index])
	var cells := {}
	for key: String in order:
		var entries: Array[Dictionary] = []
		for placed: Array in placements[key]:
			var index: int = placed[0]
			var region := Rect2i(positions[index], sizes[index])
			entries.append({"region": region, "margin": placed[1]})
		cells[key] = entries
	return {"sheet": sheet, "cells": cells}


## Where to put regions of [param sizes] in shelves: {"size": Vector2i, "positions":
## Array[Vector2i]} (one per size, in the same order), trying several shelf widths and keeping the
## smallest sheet, then the squarest.
static func best_layout(sizes: Array[Vector2i]) -> Dictionary:
	var order: Array[int] = []
	var widest := 0
	var area := 0
	for index: int in sizes.size():
		order.append(index)
		widest = maxi(widest, sizes[index].x)
		area += sizes[index].x * sizes[index].y
	# Tallest first, then widest, then in order: the same sizes always give the same layout.
	order.sort_custom(
		func(a: int, b: int) -> bool:
			if sizes[a].y != sizes[b].y:
				return sizes[a].y > sizes[b].y
			if sizes[a].x != sizes[b].x:
				return sizes[a].x > sizes[b].x
			return a < b
	)
	var best := {}
	var tried := {}
	var side := sqrt(float(area))
	for step: int in WIDTH_STEPS:
		# Never narrower than the widest region, which could not be placed at all.
		var width := maxi(widest, ceili(side * step / 10.0))
		if tried.has(width):
			continue
		tried[width] = true
		var layout := _shelves(sizes, order, width)
		if best.is_empty() or _is_better(layout["size"], best["size"]):
			best = layout
	return best


## Cells of one strip, each {"image": Image (the trimmed pixels), "margin": Rect2i}, or nothing when
## no cell has a visible pixel or the strip is not a row of cells (reported in [member errors]).
func _cut(key: String, image: Image, cell_size: Vector2i) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	if (
		image == null
		or cell_size.x <= 0
		or image.get_height() != cell_size.y
		or image.get_width() % cell_size.x != 0
	):
		var size := image.get_size() if image != null else Vector2i.ZERO
		errors.append("The strip '%s' (%s) is not a row of %s cells." % [key, size, cell_size])
		return cells
	var rgba := image
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba = image.duplicate()
		rgba.convert(Image.FORMAT_RGBA8)
	var visible := false
	for index: int in rgba.get_width() / cell_size.x:
		var origin := Vector2i(index * cell_size.x, 0)
		var used := rgba.get_region(Rect2i(origin, cell_size)).get_used_rect()
		if not used.has_area():
			# One transparent pixel, shared by every empty cell of the file.
			var blank := Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
			cells.append(
				{"image": blank, "margin": Rect2i(Vector2i.ZERO, cell_size - Vector2i.ONE)}
			)
			continue
		visible = true
		var trimmed := rgba.get_region(Rect2i(origin + used.position, used.size))
		cells.append({"image": trimmed, "margin": Rect2i(used.position, cell_size - used.size)})
	if not visible:
		cells.clear()
	return cells


## Places [param sizes] in [param order] on shelves [param width] wide: each region goes on the
## first shelf with room for it, or opens a new one below. Taller regions come first, so a shelf is
## always at least as tall as what lands on it later.
static func _shelves(sizes: Array[Vector2i], order: Array[int], width: int) -> Dictionary:
	var positions: Array[Vector2i] = []
	positions.resize(sizes.size())
	# Top, height and filled width of each shelf.
	var tops := PackedInt32Array()
	var heights := PackedInt32Array()
	var filled := PackedInt32Array()
	var height := 0
	var used_width := 0
	for index: int in order:
		var size := sizes[index]
		var shelf := 0
		while shelf < tops.size() and (filled[shelf] + size.x > width or size.y > heights[shelf]):
			shelf += 1
		if shelf == tops.size():
			tops.append(height)
			heights.append(size.y)
			filled.append(0)
			height += size.y
		positions[index] = Vector2i(filled[shelf], tops[shelf])
		filled[shelf] += size.x
		used_width = maxi(used_width, filled[shelf])
	return {"size": Vector2i(used_width, height), "positions": positions}


static func _is_better(size: Vector2i, than: Vector2i) -> bool:
	var area := size.x * size.y
	var other := than.x * than.y
	if area != other:
		return area < other
	return absi(size.x - size.y) < absi(than.x - than.y)
