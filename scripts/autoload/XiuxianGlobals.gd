extends Node

## 全局单例（autoload）：持有 GameCore 实例、驱动时间推进、自动存档。

var game: GameCore
var running: bool = false

var _accum: float = 0.0

const MAX_STEPS_PER_FRAME := 8

signal ticked


func _ready() -> void:
	game = GameCore.new()


func _process(delta: float) -> void:
	if not running or game == null or game.s.is_empty():
		return

	var ms := float(game.speed_ms())
	_accum += delta * 1000.0

	var steps := 0
	while _accum >= ms and steps < MAX_STEPS_PER_FRAME:
		_accum -= ms
		game.tick()
		steps += 1
		ticked.emit()
	# 视野外/卡顿时丢弃积压，避免雪崩式追帧
	if steps >= MAX_STEPS_PER_FRAME:
		_accum = 0.0


func start_new(cfg: Dictionary) -> void:
	game.new_game(cfg)
	_accum = 0.0
	set_running(true)


func set_running(v: bool) -> void:
	running = v
	if v:
		_accum = 0.0


func toggle() -> void:
	set_running(not running)


func is_running() -> bool:
	return running


func set_seed(seed_value: int) -> void:
	game.rng.seed = seed_value


func save_now() -> bool:
	return game.save()


func load_saved() -> bool:
	var ok := game.load_save()
	if ok:
		set_running(false)
	return ok


func has_save() -> bool:
	return game != null and game.has_save()


func clear_save() -> void:
	game.clear_save()
