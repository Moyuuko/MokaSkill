/* Pure geometry tests. Run after loading copper_corner_tools.il in SKILL. */

defun( cct_test_assert (condition message)
    unless(condition
        error(sprintf(nil "CCT TEST FAILED: %s" message))
    )
)

defun( cct_run_geometry_tests ()
    let((rectangle reversed_rectangle l_shape specs_data specs reversed_specs concave l_specs
         trapezoid t_specs round_specs uneven_chamfers normalized expected_normalized
         single_chamfer single_normalized restored restored_specs inner_chamfer inner_restored
         inner_specs both_specs)
        _cct_size = 1.0
        _cct_min_angle = 30.0
        _cct_max_angle = 150.0
        _cct_mode = "CHAMFER"
        _cct_corner_scope = "OUTER"

        rectangle = list(list(0.0 0.0) list(10.0 0.0) list(10.0 6.0) list(0.0 6.0))
        specs_data = cct_build_specs(rectangle)
        specs = car(specs_data)
        cct_test_assert(cct_modified_count(specs) == 4 "rectangle should have four convex corners")

        reversed_rectangle = reverse(rectangle)
        reversed_specs = car(cct_build_specs(reversed_rectangle))
        cct_test_assert(cct_modified_count(reversed_specs) == 4 "clockwise rectangle should have four convex corners")

        concave = list(
            list(0.0 0.0) list(10.0 0.0) list(10.0 10.0)
            list(6.0 10.0) list(6.0 4.0) list(0.0 4.0)
        )
        l_specs = car(cct_build_specs(concave))
        cct_test_assert(cct_modified_count(l_specs) == 5 "L shape should skip its one concave corner")

        _cct_corner_scope = "INNER"
        inner_specs = car(cct_build_specs(concave))
        cct_test_assert(cct_modified_count(inner_specs) == 1 "inner mode should process the one concave L-shape corner")
        cct_test_assert(cct_target_corner_count(concave) == 1 "inner target count should contain one concave corner")
        cct_test_assert(nth(6 nth(4 inner_specs)) < 0.0 "inner corner specification should reverse fillet direction")
        cct_test_assert(cct_corner_clockwise(nth(4 inner_specs) nil) "CCW polygon inner fillet should use a clockwise arc")

        _cct_corner_scope = "BOTH"
        both_specs = car(cct_build_specs(concave))
        cct_test_assert(cct_modified_count(both_specs) == 6 "both mode should process five outer and one inner corner")

        _cct_corner_scope = "OUTER"

        trapezoid = list(list(0.0 0.0) list(12.0 0.0) list(9.0 6.0) list(2.0 6.0))
        t_specs = car(cct_build_specs(trapezoid))
        cct_test_assert(cct_modified_count(t_specs) == 4 "trapezoid corners should be detected")

        _cct_mode = "ROUND"
        round_specs = car(cct_build_specs(rectangle))
        cct_test_assert(cct_modified_count(round_specs) == 4 "round mode should retain four corners")
        cct_test_assert(abs(nth(5 car(round_specs)) - 1.0) < 0.000001 "90 degree fillet trim should equal radius")

        _cct_size = 4.0
        _cct_mode = "CHAMFER"
        specs = car(cct_build_specs(rectangle))
        cct_test_assert(cct_modified_count(specs) == 0 "short edges should safely reject oversized corners")

        uneven_chamfers = list(
            list(2.0 0.0) list(17.0 0.0) list(20.0 3.0) list(20.0 8.0)
            list(18.0 10.0) list(3.0 10.0) list(0.0 7.0) list(0.0 1.0)
        )
        expected_normalized = list(
            list(2.0 0.0) list(18.0 0.0) list(20.0 2.0) list(20.0 8.0)
            list(18.0 10.0) list(2.0 10.0) list(0.0 8.0) list(0.0 2.0)
        )
        _cct_mode = "NORMALIZE"
        _cct_size = 2.0
        normalized = cct_normalize_existing_chamfers(uneven_chamfers)
        cct_test_assert(cadr(normalized) == 4 "four existing chamfer edges should be detected")
        cct_test_assert(equal(car(normalized) expected_normalized) "existing chamfers should be rebuilt to one setback")

        normalized = cct_normalize_existing_chamfers(rectangle)
        cct_test_assert(cadr(normalized) == 0 "plain rectangle has no existing chamfer edges")

        single_chamfer = list(
            list(0.0 0.0) list(10.0 0.0) list(12.0 2.0)
            list(12.0 8.0) list(0.0 8.0)
        )
        _cct_size = 1.0
        single_normalized = cct_normalize_existing_chamfers(single_chamfer)
        cct_test_assert(cadr(single_normalized) == 1 "single existing trapezoid chamfer should be detected")
        cct_test_assert(
            equal(nth(1 car(single_normalized)) list(11.0 0.0)) &&
            equal(nth(2 car(single_normalized)) list(12.0 1.0))
            "single chamfer endpoints should use the requested setback")

        restored = cct_restore_virtual_corners(uneven_chamfers)
        cct_test_assert(cadr(restored) == 4 "hybrid mode should detect four existing chamfers")
        cct_test_assert(length(car(restored)) == 4 "existing chamfers should collapse to four virtual corners")
        _cct_mode = "CHAMFER"
        _cct_size = 2.0
        restored_specs = car(cct_build_specs(car(restored)))
        cct_test_assert(cct_modified_count(restored_specs) == 4 "uniform chamfer should rebuild four corners, not eight endpoint corners")

        restored = cct_restore_virtual_corners(single_chamfer)
        cct_test_assert(cadr(restored) == 1 "hybrid mode should detect the one existing chamfer")
        cct_test_assert(length(car(restored)) == 4 "one existing chamfer should restore the base rectangle")
        restored_specs = car(cct_build_specs(car(restored)))
        cct_test_assert(cct_modified_count(restored_specs) == 4 "hybrid chamfer should modify one existing and add three missing chamfers")
        cct_test_assert(cct_target_corner_count(car(restored)) == 4 "hybrid base shape should require four uniformly treated corners")

        _cct_mode = "ROUND"
        restored_specs = car(cct_build_specs(car(restored)))
        cct_test_assert(cct_modified_count(restored_specs) == 4 "hybrid round should replace one chamfer and add three fillets")

        _cct_size = 100.0
        restored = cct_restore_virtual_corners(uneven_chamfers)
        cct_test_assert(cadr(restored) == 4 "existing chamfer detection must not depend on requested size")
        cct_test_assert(length(car(restored)) == 4 "oversized requests must not fall back to secondary endpoint chamfers")
        restored_specs = car(cct_build_specs(car(restored)))
        cct_test_assert(
            cct_modified_count(restored_specs) < cct_target_corner_count(car(restored))
            "oversized uniform requests should be rejected instead of partially applied")

        inner_chamfer = list(
            list(0.0 0.0) list(10.0 0.0) list(10.0 10.0)
            list(6.0 10.0) list(6.0 5.0) list(5.0 4.0) list(0.0 4.0)
        )
        _cct_corner_scope = "INNER"
        _cct_size = 1.0
        inner_restored = cct_restore_virtual_corners(inner_chamfer)
        cct_test_assert(cadr(inner_restored) == 1 "existing inner chamfer should be detected")
        cct_test_assert(length(car(inner_restored)) == 6 "existing inner chamfer should restore one virtual concave corner")
        inner_specs = car(cct_build_specs(car(inner_restored)))
        cct_test_assert(cct_modified_count(inner_specs) == 1 "restored concave corner should receive one uniform inner treatment")

        printf("CCT geometry tests passed.\n")
        t
    )
)
