extends Node
## DotFxSoftSprite: the particle sprite is a smooth disc, filtered linearly.


func _ready() -> void:
	var failed := 0
	var tex := DotFxSoftSprite.texture()
	var img := tex.get_image()
	var centre := img.get_pixel(DotFxSoftSprite.SIZE / 2, DotFxSoftSprite.SIZE / 2).a
	var edge := img.get_pixel(0, DotFxSoftSprite.SIZE / 2).a
	var quarter := img.get_pixel(DotFxSoftSprite.SIZE / 4, DotFxSoftSprite.SIZE / 2).a
	var checks := [
		[centre > 0.95, "the sprite is opaque at its centre (%.2f)" % centre],
		[edge < 0.05, "and clear at its rim (%.2f)" % edge],
		[quarter > 0.2 and quarter < 0.8, "and soft between, not a hard-edged square (%.2f)" % quarter],
		[DotFxSoftSprite.texture() == tex, "one shared texture"],
		[DotFxSoftSprite.material(Color.ORANGE).texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR, "the material filters linearly"],
		[DotFxSoftSprite.material(Color.ORANGE).albedo_texture == tex, "and samples the soft sprite"],
		[DotFxSoftSprite.material(Color.ORANGE).blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "fire blends additively"],
		[DotFxSoftSprite.material(Color.GRAY, false).blend_mode == BaseMaterial3D.BLEND_MODE_MIX, "smoke blends by alpha"],
	]
	for c in checks:
		if not c[0]:
			failed += 1
		print("%s %s" % ["ok  " if c[0] else "FAIL", c[1]])
	print("%d checks, %d failed" % [checks.size(), failed])
	get_tree().quit(1 if failed > 0 else 0)
