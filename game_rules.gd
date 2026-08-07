class_name GameRules
extends RefCounted

const MAX_RISK_MULTIPLIER := 10.0

static func multiplier_after_near_miss(current: float) -> float:
	return min(MAX_RISK_MULTIPLIER, current + 0.5)

static func multiplier_after_safe_moment(current: float, delta: float) -> float:
	return move_toward(current, 1.0, delta * 0.08)

static func score_for_survival(seconds: float, multiplier: float) -> float:
	return max(0.0, seconds) * 10.0 * max(1.0, multiplier)

static func phase_for_time(seconds: float) -> int:
	if seconds < 20.0:
		return 1
	if seconds < 60.0:
		return 2
	return 3
