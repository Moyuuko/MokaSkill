/*
 * Run with the repository root as the working directory. This keeps the
 * integrated Moka module covered by the same corner tests as the standalone
 * copper-corner tool.
 */

let((result)
    result = errset(
        progn(
            load("moka_copper_corner.il")
            load("copper-corner-tools/tests/geometry_test.il")
            cct_test_assert(
                isCallable('cct_cmd_quick_copper)
                "quick-copper command should be defined"
            )
            cct_test_assert(
                abs(cct_quick_copper_size(
                    list(list(0.0 0.0) list(10.0 6.0))) - 0.6) < 0.000001
                "quick-copper chamfer should be ten percent of the shorter side"
            )
            _cct_size = 100000.0
            cct_test_assert(
                abs(cct_quick_copper_size(
                    list(list(10.0 6.0) list(0.0 0.0))) - 0.6) < 0.000001
                "adaptive chamfer should not depend on the panel size"
            )
            cct_test_assert(
                equal(
                    cct_quick_copper_points(
                        list(list(10.0 6.0) list(0.0 0.0)) 0.6)
                    list(
                        list(0.6 0.0) list(9.4 0.0)
                        list(10.0 0.6) list(10.0 5.4)
                        list(9.4 6.0) list(0.6 6.0)
                        list(0.0 5.4) list(0.0 0.6)
                    )
                )
                "quick-copper boundary should contain four equal chamfers"
            )
            cct_test_assert(
                equal(cct_quick_copper_boundary_layer("ETCH/TOP") "BOUNDARY/TOP")
                "quick-copper should create the matching dynamic boundary layer"
            )
            cct_run_geometry_tests()
        )
        t
    )
    if(result && car(result) then
        exit(0)
    else
        exit(1)
    )
)
