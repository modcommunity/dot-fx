extends "res://examples/selftest/placement_tests.gd"
## Exercises dot-fx with no renderer, which nearly all of it survives.
##
## What a headless run can genuinely check is the decision-making: which effects exist at
## a quality tier, what the budget refuses, what the distance cull skips, whether the
## decal ring actually recycles, and whether a flash is rate limited. What it cannot check
## is whether any of it looks right — that wants a screenshot, and this family has now
## found four bugs with a picture that no assertion could reach.
##
## [codeblock]
## godot --headless --path . res://examples/fx_selftest.tscn
## [/codeblock]

const SECTIONS := 16
const CHECKS := 154


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("dot-fx self-test")
	_line("")

	_test_definitions()
	_test_catalogue()
	_test_quality_gate()
	_test_budget_and_culling()
	_test_decal_ring()
	await _test_decal_surfaces()
	_test_shake()
	_test_flash_limits()
	_test_placed_before_entering()
	_test_beacon()
	_test_weather()
	_test_beam_and_thruster()
	_test_screen_goo()
	_test_muzzle_flash()
	await _test_muzzle_flash_lifetime()
	await _test_muzzle_flash_follows()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)
