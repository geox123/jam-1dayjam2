extends SceneTree

const GameRulesScript = preload("res://game_rules.gd")

var failures := 0


func _init() -> void:
	_assert_equal(GameRulesScript.multiplier_after_near_miss(1.0), 1.5, "Near Miss raises Risk Multiplier")
	_assert_equal(GameRulesScript.multiplier_after_near_miss(10.0), 10.0, "Risk Multiplier caps at 10x")
	_assert_equal(GameRulesScript.multiplier_after_safe_moment(4.0, 1.0), 3.92, "Safe play slowly reduces risk")
	_assert_equal(GameRulesScript.score_for_survival(10.0, 2.0), 200.0, "Survival score uses time and multiplier")
	_assert_equal(GameRulesScript.phase_for_time(0.0), 1, "Early Run uses phase one")
	_assert_equal(GameRulesScript.phase_for_time(20.0), 2, "Mid Run uses phase two")
	_assert_equal(GameRulesScript.phase_for_time(60.0), 3, "Long Run uses phase three")
	if failures > 0:
		quit(1)
	else:
		print("Airebound game rules: all checks passed")
		quit(0)


func _assert_equal(actual: Variant, expected: Variant, label: String) -> void:
	if not is_equal_approx(float(actual), float(expected)):
		failures += 1
		push_error("FAIL: %s (expected %s, got %s)" % [label, expected, actual])
