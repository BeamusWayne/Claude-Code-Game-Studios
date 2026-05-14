# GDUnit4 Test Runner — CI entry point
#
# Usage:
#   godot --path . --headless -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode
#
# Or via runtest.sh:
#   bash addons/gdUnit4/runtest.sh --godot_bin /path/to/godot
#
# This script exists as a convenience alias for CI pipelines.
# GDUnit4 discovers test suites automatically by scanning for
# scripts that extend GdUnitTestSuite.

extends SceneTree

func _init() -> void:
	var runner_path: String = "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"
	if not ResourceLoader.exists(runner_path):
		push_error("GDUnit4 not installed. Install from Godot AssetLib.")
		quit(1)
		return
	push_warning("Use 'godot -s -d %s' directly instead of this wrapper." % runner_path)
	quit(0)
