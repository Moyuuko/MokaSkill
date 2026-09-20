/* Pure geometry tests for spread_between_clines.il. */

unless(isCallable('msv_line_intersection)
    load("spread_between_clines.il")
)

defun( msv_test_assert (condition message)
    unless(condition
        error(sprintf(nil "MSV TEST FAILED: %s" message))
    )
)

defun( msv_test_close (actual expected)
    abs(actual - expected) <= 0.000001
)

defun( msv_test_point_close (actual expected)
    msv_same_point(actual expected)
)

defun( msv_test_make_segment (start_point end_point)
    let((segment)
        segment = ncons(t)
        segment->objType = "line"
        segment->isEtch = t
        segment->startEnd = list(start_point end_point)
        segment->width = 0.2
        segment->layer = "ETCH/TOP"
        segment->net = nil
        segment
    )
)

defun( msv_test_make_path (offset)
    let((path left main right)
        path = ncons(t)
        left = msv_test_make_segment(msv_point(-5.0 offset - 5.0) msv_point(0.0 offset))
        main = msv_test_make_segment(msv_point(0.0 offset) msv_point(10.0 offset))
        right = msv_test_make_segment(msv_point(10.0 offset) msv_point(15.0 offset - 5.0))
        path->segments = list(left main right)
        path->net = nil
        left->parent = path
        main->parent = path
        right->parent = path
        list(path main)
    )
)

defun( msv_test_make_45_chain_path ()
    let((path start_arm first_45 selected_45 last_45 end_arm)
        path = ncons(t)
        start_arm = msv_test_make_segment(msv_point(-5.0 0.0) msv_point(0.0 0.0))
        first_45 = msv_test_make_segment(msv_point(0.0 0.0) msv_point(5.0 5.0))
        selected_45 = msv_test_make_segment(msv_point(5.0 5.0) msv_point(10.0 10.0))
        last_45 = msv_test_make_segment(msv_point(10.0 10.0) msv_point(15.0 15.0))
        end_arm = msv_test_make_segment(msv_point(15.0 15.0) msv_point(20.0 15.0))
        path->segments = list(start_arm first_45 selected_45 last_45 end_arm)
        path->net = nil
        foreach(segment path->segments
            segment->parent = path
        )
        list(path selected_45)
    )
)

defun( msv_test_make_anchored_path ()
    let((path main)
        path = ncons(t)
        main = msv_test_make_segment(msv_point(0.0 0.0) msv_point(10.0 0.0))
        path->segments = list(main)
        path->net = nil
        main->parent = path
        list(path main)
    )
)

defun( msv_run_geometry_tests ()
    let((intersection geometry path0 path3 path10 main0 main3 main10 prepared changes main_change
         collapse_plan chain45 selected45 chain45_plan selected45_change anchored_path
         anchored_main anchored_plan anchored_start anchored_main_change anchored_end)
        intersection = msv_line_intersection(
            msv_point(0.0 2.0)
            msv_point(1.0 0.0)
            msv_point(-2.0 -2.0)
            msv_point(1.0 1.0)
        )
        msv_test_assert(
            msv_test_point_close(intersection msv_point(2.0 2.0))
            "line intersection should retain the adjacent 45 degree direction"
        )

        msv_test_assert(
            msv_line_intersection(
                msv_point(0.0 0.0)
                msv_point(1.0 0.0)
                msv_point(0.0 1.0)
                msv_point(1.0 0.0)
            ) == nil
            "parallel lines should not produce an intersection"
        )

        geometry = msv_shift_geometry(
            msv_point(0.0 0.0)
            msv_point(10.0 0.0)
            msv_point(-2.0 -2.0)
            msv_point(12.0 -2.0)
            2.0
            msv_point(0.0 1.0)
        )
        msv_test_assert(geometry "valid connected shift should return geometry")
        msv_test_assert(
            msv_test_point_close(car(geometry) msv_point(2.0 2.0))
            "shifted start corner should remain on the original 45 degree arm"
        )
        msv_test_assert(
            msv_test_point_close(cadr(geometry) msv_point(8.0 2.0))
            "shifted end corner should remain on the original 45 degree arm"
        )

        geometry = msv_shift_geometry(
            msv_point(0.0 0.0)
            msv_point(10.0 0.0)
            msv_point(-2.0 2.0)
            msv_point(12.0 2.0)
            3.0
            msv_point(0.0 1.0)
        )
        msv_test_assert(geometry "adjacent arms may extend through their old outer endpoints")
        msv_test_assert(
            msv_test_point_close(car(geometry) msv_point(-3.0 3.0))
            "reversed start arm should remain on the same infinite 45 degree line"
        )
        msv_test_assert(
            msv_test_point_close(cadr(geometry) msv_point(13.0 3.0))
            "reversed end arm should remain on the same infinite 45 degree line"
        )

        geometry = msv_shift_geometry(
            msv_point(0.0 0.0)
            msv_point(10.0 0.0)
            msv_point(-2.0 0.0)
            msv_point(12.0 0.0)
            2.0
            msv_point(0.0 1.0)
        )
        msv_test_assert(
            geometry == nil
            "parallel adjacent arms cannot preserve connectivity during a lateral shift"
        )

        msv_test_assert(msv_test_close(msv_even_target(0.0 12.0 1 4) 4.0) "first inner target should be evenly spaced")
        msv_test_assert(msv_test_close(msv_even_target(0.0 12.0 2 4) 8.0) "second inner target should be evenly spaced")

        path0 = msv_test_make_path(0.0)
        path3 = msv_test_make_path(3.0)
        path10 = msv_test_make_path(10.0)
        main0 = cadr(path0)
        main3 = cadr(path3)
        main10 = cadr(path10)
        collapse_plan = car(msv_build_shift_changes(main0 -5.0 msv_point(0.0 1.0)))
        msv_test_assert(car(collapse_plan)->removeOnly "collapsed start arm should be removed instead of recreated")
        msv_test_assert(nth(2 collapse_plan)->removeOnly "collapsed end arm should be removed instead of recreated")
        prepared = msv_prepare_changes(list(main10 main0 main3))
        changes = car(prepared)
        msv_test_assert(cadr(prepared) == 1 "one intermediate cline should require movement")
        msv_test_assert(length(changes) == 3 "one moved cline should rebuild its three local segments")
        main_change = cadr(changes)
        msv_test_assert(
            msv_test_point_close(car(main_change->startEnd) msv_point(2.0 5.0))
            "automatic outer-line sorting should move the middle cline start to the 5.0 target"
        )
        msv_test_assert(
            msv_test_point_close(cadr(main_change->startEnd) msv_point(8.0 5.0))
            "automatic outer-line sorting should move the middle cline end to the 5.0 target"
        )

        chain45 = msv_test_make_45_chain_path()
        selected45 = cadr(chain45)
        chain45_plan = car(
            msv_build_shift_changes(
                selected45
                sqrt(2.0)
                msv_point(-sqrt(0.5) sqrt(0.5))
            )
        )
        msv_test_assert(length(chain45_plan) == 5 "45 degree collinear chain should rebuild two arms and three main segments")
        selected45_change = nth(2 chain45_plan)
        msv_test_assert(
            msv_test_point_close(car(selected45_change->startEnd) msv_point(4.0 6.0))
            "selected 45 degree segment start should translate with its collinear chain"
        )
        msv_test_assert(
            msv_test_point_close(cadr(selected45_change->startEnd) msv_point(9.0 11.0))
            "selected 45 degree segment end should translate with its collinear chain"
        )

        anchored_path = msv_test_make_anchored_path()
        anchored_main = cadr(anchored_path)
        anchored_plan = car(
            msv_build_shift_changes(
                anchored_main
                2.0
                msv_point(0.0 1.0)
            )
        )
        msv_test_assert(length(anchored_plan) == 3 "an endpoint-anchored main run should create two connectors")
        anchored_start = car(anchored_plan)
        anchored_main_change = cadr(anchored_plan)
        anchored_end = nth(2 anchored_plan)
        msv_test_assert(anchored_start->createOnly "the start anchor connector should be newly created")
        msv_test_assert(anchored_end->createOnly "the end anchor connector should be newly created")
        msv_test_assert(
            msv_test_point_close(car(anchored_start->startEnd) msv_point(0.0 0.0)) &&
            msv_test_point_close(cadr(anchored_start->startEnd) msv_point(0.0 2.0))
            "the start connector should join the fixed endpoint to the shifted run"
        )
        msv_test_assert(
            msv_test_point_close(car(anchored_main_change->startEnd) msv_point(0.0 2.0)) &&
            msv_test_point_close(cadr(anchored_main_change->startEnd) msv_point(10.0 2.0))
            "the endpoint-anchored main segment should translate without breaking connectivity"
        )
        msv_test_assert(
            msv_test_point_close(car(anchored_end->startEnd) msv_point(10.0 0.0)) &&
            msv_test_point_close(cadr(anchored_end->startEnd) msv_point(10.0 2.0))
            "the end connector should join the fixed endpoint to the shifted run"
        )

        printf("Spread Between Clines geometry tests passed.\n")
        t
    )
)

msv_run_geometry_tests()
exit()
