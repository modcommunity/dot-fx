class_name DotFxDecalSheet
extends RefCounted

## The vendored decal art, cut into textures once. Blood is six equal frames in one strip;
## graffiti is named rectangles of one sheet (see the README for the sources and licence).

const BLOOD_FRAMES := 6

## Graffiti name to pixel rectangle (x, y, w, h) in graffiti.png.
const GRAFFITI := {
	&"alien": Rect2i(25, 8, 96, 116),
	&"warning": Rect2i(133, 2, 59, 56),
	&"drip": Rect2i(128, 68, 64, 58),
	&"beast": Rect2i(193, 10, 124, 118),
	&"spider": Rect2i(3, 130, 60, 54),
	&"tentacle": Rect2i(67, 128, 125, 60),
	&"robot": Rect2i(193, 130, 124, 56),
}

## Frames in splat_pack.png (Kenney Splat Pack, white, so the blood tint applies).
const SPLAT_FRAMES := 16
## Gib cells in gibs.png: 12 px squares, 7 per row, 21 pixel-art meat chunks.
const GIB_COUNT := 21
const GIB_CELL := 12
const GIB_COLS := 7

static var _blood: Array[Texture2D] = []
static var _splats: Array[Texture2D] = []
static var _gibs: Dictionary = {}
static var _graffiti: Dictionary = {}


static func _dir() -> String:
	return (DotFxDecalSheet as Script).resource_path.get_base_dir().get_base_dir().path_join("art")


static func _image(file: String) -> Image:
	var tex := load(_dir().path_join(file)) as Texture2D
	if tex == null:
		return null
	var img := tex.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


## The blood textures, square, in the strip's order (the first is the biggest pool).
static func blood_frames() -> Array[Texture2D]:
	if _blood.is_empty():
		var img := _image("blood_splatter.png")
		if img != null:
			var w := img.get_width() / BLOOD_FRAMES
			for i in range(BLOOD_FRAMES):
				_blood.append(_texture(img.get_region(Rect2i(i * w, 0, w, img.get_height()))))
	return _blood


## Extra splat shapes; DotFxDecals.splatter draws them after the six blood frames.
static func splat_frames() -> Array[Texture2D]:
	if _splats.is_empty():
		var img := _image("splat_pack.png")
		if img != null:
			var w := img.get_width() / SPLAT_FRAMES
			for i in range(SPLAT_FRAMES):
				_splats.append(_texture(img.get_region(Rect2i(i * w, 0, w, img.get_height()))))
	return _splats


## A gib sprite by index, cropped to its pixels, or null when out of range.
static func gib(index: int) -> Texture2D:
	if index < 0 or index >= GIB_COUNT:
		return null
	if not _gibs.has(index):
		var img := _image("gibs.png")
		if img == null:
			return null
		var cell := img.get_region(Rect2i((index % GIB_COLS) * GIB_CELL, (index / GIB_COLS) * GIB_CELL, GIB_CELL, GIB_CELL))
		var used := cell.get_used_rect()
		_gibs[index] = _texture(cell.get_region(used) if used.size != Vector2i.ZERO else cell)
	return _gibs[index]


## A decal image by name: a graffiti name, or "gib_N" for a gib sprite.
static func decal_image(image: StringName) -> Texture2D:
	var s := String(image)
	if s.begins_with("gib_") and s.substr(4).is_valid_int():
		return gib(int(s.substr(4)))
	return graffiti(image)


## Names of the graffiti images.
static func graffiti_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in GRAFFITI:
		out.append(k)
	return out


## The texture for a graffiti name, or null for an unknown one.
static func graffiti(image: StringName) -> Texture2D:
	if not GRAFFITI.has(image):
		return null
	if not _graffiti.has(image):
		var img := _image("graffiti.png")
		if img == null:
			return null
		_graffiti[image] = _texture(img.get_region(GRAFFITI[image]))
	return _graffiti[image]


static func _texture(img: Image) -> Texture2D:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
