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

static var _blood: Array[Texture2D] = []
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
