extends GdUnitTestSuite

# Smoke test: verifies GDUnit4 framework is correctly installed and operational.


func test_gdunit4_framework_loaded() -> void:
	assert_bool(true).is_true()


func test_project_name_configured() -> void:
	assert_that(ProjectSettings.get_setting("application/config/name")).is_equal("七夜 (Seven Nights)")
