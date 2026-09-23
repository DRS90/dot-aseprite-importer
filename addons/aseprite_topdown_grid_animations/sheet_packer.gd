@tool
extends RefCounted
## Packs the strips of an import into one sheet, trimmed to the pixels each animation uses.
##
## Has no editor dependency, so headless tests can use it. Each strip becomes one row of the sheet,
## in the order given, with one column per frame. A row is cut to the union of the used rects of
## its frames, so every frame of an animation keeps the same size and offset; the margin returned
## for each frame gives back the space cut away, so an AtlasTexture built from it is the size of the
## cell and draws its pixels where the cell had them.

## Largest texture side the renderers accept.
const MAX_TEXTURE_SIZE := 16384

## Problems found by the last [method pack] call.
var errors := PackedStringArray()


## [param strips] holds {"key": String, "image": Image} entries, each image a strip of cells of
## [param cell_size] side by side. Returns {"sheet": Image, "cells": {key: Array of {"region":
## Rect2i, "margin": Rect2i}}}, one entry per cell of the strip, or an empty dictionary when
## [member errors] is not empty. "sheet" is null when there is nothing to pack.
func pack(strips: Array[Dictionary], cell_size: Vector2i) -> Dictionary:
	errors = PackedStringArray()
	var rows: Array[Dictionary] = []
	var sheet_size := Vector2i.ZERO
	for strip: Dictionary in strips:
		var key: String = strip["key"]
		var image: Image = strip["image"]
		var row := _measure(key, image, cell_size)
		if row.is_empty():
			continue
		var used: Rect2i = row["used"]
		var count: int = row["count"]
		row["y"] = sheet_size.y
		sheet_size = Vector2i(maxi(sheet_size.x, used.size.x * count), sheet_size.y + used.size.y)
		rows.append(row)
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
	if not errors.is_empty():
		return {}
	if rows.is_empty():
		return {"sheet": null, "cells": {}}

	var sheet := Image.create_empty(sheet_size.x, sheet_size.y, false, Image.FORMAT_RGBA8)
	var cells := {}
	for row: Dictionary in rows:
		var image: Image = row["image"]
		var used: Rect2i = row["used"]
		var y: int = row["y"]
		var count: int = row["count"]
		var margin := Rect2i(used.position, cell_size - used.size)
		var entries: Array[Dictionary] = []
		for index: int in count:
			var source := Rect2i(used.position + Vector2i(index * cell_size.x, 0), used.size)
			var target := Vector2i(index * used.size.x, y)
			sheet.blit_rect(image, source, target)
			entries.append({"region": Rect2i(target, used.size), "margin": margin})
		cells[row["key"]] = entries
	return {"sheet": sheet, "cells": cells}


## {"key", "image" (RGBA8), "count" (cells), "used" (union of the used rects, in cell space)} for
## one strip, or an empty dictionary after reporting why it cannot be packed.
func _measure(key: String, image: Image, cell_size: Vector2i) -> Dictionary:
	if (
		image == null
		or cell_size.x <= 0
		or image.get_height() != cell_size.y
		or image.get_width() % cell_size.x != 0
	):
		var size := image.get_size() if image != null else Vector2i.ZERO
		errors.append("The strip '%s' (%s) is not a row of %s cells." % [key, size, cell_size])
		return {}
	var rgba := image
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba = image.duplicate()
		rgba.convert(Image.FORMAT_RGBA8)
	var count := rgba.get_width() / cell_size.x
	var used := Rect2i()
	for index: int in count:
		var cell := rgba.get_region(Rect2i(Vector2i(index * cell_size.x, 0), cell_size))
		var frame_used := cell.get_used_rect()
		if frame_used.has_area():
			used = frame_used if not used.has_area() else used.merge(frame_used)
	# A region of size 0 means "the whole atlas" to an AtlasTexture: never hand one out.
	if not used.has_area():
		errors.append("The strip '%s' has no pixels." % key)
		return {}
	return {"key": key, "image": rgba, "count": count, "used": used}
