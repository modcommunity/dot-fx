class_name DotFxSoftSprite
extends RefCounted
## A soft round particle sprite and the material that draws it: a particle quad with no texture is a hard square.

const SIZE := 64
static var _texture: Texture2D = null


## A white disc fading to nothing at the rim, bilinear filtered (never nearest, which is what shows as big pixels).
static func texture() -> Texture2D:
	if _texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = SIZE
		t.height = SIZE
		_texture = t
	return _texture


## A billboarded, unshaded material for a particle quad: [param colour] times the soft disc, additive for fire, alpha-blended for smoke.
static func material(colour: Color, additive: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	m.vertex_color_use_as_albedo = true
	m.albedo_color = colour
	m.albedo_texture = texture()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.no_depth_test = false
	m.disable_receive_shadows = true
	return m
