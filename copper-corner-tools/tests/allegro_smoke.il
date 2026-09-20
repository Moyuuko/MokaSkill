/*
 * Headless Allegro smoke test. The caller provides CCT_SMOKE_RESULT as an
 * absolute output path. All database changes are rolled back.
 */

let((result_file install_dir port mark rectangle_result rectangle shape_result round_result round_shape
     chamfer_check round_check poly point_data units base_x base_y width height test_size)
    result_file = axlGetVariable("CCT_SMOKE_RESULT")
    unless(stringp(result_file) && strlen(result_file) > 0
        result_file = strcat(getWorkingDir() "/cct_smoke_result.txt")
    )

    install_dir = axlGetVariable("CCT_INSTALL_DIR")
    unless(stringp(install_dir) && strlen(install_dir) > 0
        error("Set CCT_INSTALL_DIR before running allegro_smoke.il.")
    )
    load(strcat(axlOSSlash(install_dir) "/copper_corner_tools.il"))
    units = lowerCase(cct_design_units())
    if(rexMatchp("millimeter" units) then
        progn(base_x = 1000.0 base_y = 1000.0 width = 10.0 height = 6.0 test_size = 1.0)
    else
        if(rexMatchp("inch" units) then
            progn(base_x = 100.0 base_y = 100.0 width = 0.4 height = 0.24 test_size = 0.04)
        else
            progn(base_x = 100000.0 base_y = 100000.0 width = 1000.0 height = 600.0 test_size = 100.0)
        )
    )

    mark = axlDBTransactionStart()
    _cct_min_angle = 30.0
    _cct_max_angle = 150.0

    rectangle = list(
        list(base_x base_y)
        list(base_x + width base_y + height)
    )
    rectangle_result = errset(axlDBCreateRectangle(rectangle t "ETCH/TOP") nil)
    rectangle = cct_result_dbid(rectangle_result)
    _cct_mode = "CHAMFER"
    _cct_size = test_size
    shape_result = if(rectangle then cct_modify_shape(rectangle) else list(nil 0 "create failed"))
    chamfer_check = car(shape_result) && cadr(shape_result) == 4

    rectangle = list(
        list(base_x + width * 2.0 base_y)
        list(base_x + width * 3.0 base_y + height)
    )
    round_result = errset(axlDBCreateRectangle(rectangle t "ETCH/TOP") nil)
    round_shape = cct_result_dbid(round_result)
    _cct_mode = "ROUND"
    _cct_size = test_size
    shape_result = if(round_shape then cct_modify_shape(round_shape) else list(nil 0 "create failed"))
    round_check = car(shape_result) && cadr(shape_result) == 4
    when(round_check
        poly = cct_shape_polygon(round_shape)
        point_data = cct_polygon_points(poly)
        round_check = cadr(point_data)
    )

    when(mark axlDBTransactionRollback(mark))

    port = outfile(result_file)
    when(port
        fprintf(port "chamfer=%L\n" chamfer_check)
        fprintf(port "round=%L\n" round_check)
        fprintf(port "units=%s\n" units)
        close(port)
    )
)
