/* Parse/load smoke test for a generic SKILL interpreter. */

defun( axlGetVariable (name)
    if(equal(name "MTS_INSTALL_DIR") then getWorkingDir() else nil)
)

defun( axlOSSlash (path) path)
defun( axlMsgPut (message) printf("%s\n" message))
defvar(_mts_test_bitmap_path list("existing/bitmaps"))
defun( axlGetVariableList (name)
    if(equal(lowerCase(name) "bmppath") then _mts_test_bitmap_path else nil)
)
defun( axlSetVariable (name value)
    when(equal(lowerCase(name) "bmppath")
        _mts_test_bitmap_path = value
    )
    t
)
defun( axlDBGetDesignUnits () list("MILS"))
defun( axlPathStart (points width_value) points)
defun( axlDBCreateOpenShape (path dynamic_value layer_name) 'mts_test_shape)
defun( axlDBCreateVoid (shape path) t)
defun( axlDBCreateCloseShape (shape) t)
defvar(_mts_test_finish_count 0)
defvar(_mts_test_cancel_count 0)
defun( axlFinishEnterFun ()
    _mts_test_finish_count = _mts_test_finish_count + 1
    t
)
defun( axlCancelEnterFun ()
    _mts_test_cancel_count = _mts_test_cancel_count + 1
    t
)

load("mooretronics_symbols.il")

unless(boundp('_mts_glyph_data) && length(_mts_glyph_data) == 26
    error("Mooretronics glyph data did not load correctly.")
)

unless(strlen(mts_ui_text("panel_title")) == 25
    error("CP936 Chinese UI text was not constructed correctly.")
)

unless(length(mts_icon_labels()) == 26
    error("Localized icon label list is incomplete.")
)

let((point transformed contours contour closed_points bounds normal_count inverse_count
     form_file form_port form_line bitmap_line_count outer_polygon inner_polygon
     crossing_polygon csa_contours)
    contours = nth(2 mts_glyph_find("F"))
    contour = car(contours)
    point = car(nth(2 contour))
    transformed = mts_transform_point(point list(100.0 200.0) 40.0 1.0 0.0 nil)
    unless(numberp(car(transformed)) && numberp(cadr(transformed))
        error("Glyph coordinate transform did not return numeric X/Y values.")
    )
    closed_points = mts_transform_contour(
        nth(2 contour) list(100.0 200.0) 40.0 1.0 0.0 nil)
    unless(length(closed_points) > 3 && equal(car(closed_points) car(reverse(closed_points)))
        error("Font outline contour is not closed.")
    )
    bounds = mts_outline_bounds(list(contour))
    unless(bounds && nth(2 bounds) > car(bounds) && nth(3 bounds) > cadr(bounds)
        error("Outline bounds are invalid.")
    )
    normal_count = mts_outline_shape_count(contours nil)
    inverse_count = mts_outline_shape_count(contours t)
    unless(normal_count > 0 && inverse_count > 0
        error("Normal/inverse outline counts are invalid.")
    )
    unless(mts_create_inverse_background(
        contours list(0.0 0.0) 40.0 1.0 0.0 nil "TEST/LAYER")
        error("Inverse background/void construction failed.")
    )
    unless(equal(mts_symbol_for_field("sym_08") "F")
        error("Icon button did not map to the FCC glyph.")
    )
    outer_polygon = list(list(0.0 0.0) list(10.0 0.0)
        list(10.0 10.0) list(0.0 10.0))
    inner_polygon = list(list(2.0 2.0) list(8.0 2.0)
        list(8.0 8.0) list(2.0 8.0))
    crossing_polygon = list(list(9.0 2.0) list(11.0 2.0)
        list(11.0 8.0) list(9.0 8.0))
    unless(mts_contour_strictly_inside(inner_polygon outer_polygon)
        error("Valid inner contour was rejected.")
    )
    when(mts_contour_strictly_inside(crossing_polygon outer_polygon)
        error("Crossing contour was accepted as a void.")
    )
    csa_contours = nth(2 mts_glyph_find("c"))
    when(mts_contour_strictly_inside(
            nth(2 nth(3 csa_contours)) nth(2 nth(1 csa_contours)))
        error("CSA crossing fragment was accepted as a void.")
    )
    unless(mts_contour_strictly_inside(
            nth(2 nth(29 csa_contours)) nth(2 nth(1 csa_contours)))
        error("CSA valid counter was rejected as a void.")
    )
    unless(mts_polygon_area(nth(2 nth(25 csa_contours))) <
            _mts_min_contour_area
        error("CSA microscopic fragment guard is no longer effective.")
    )
    _mts_place_active = t
    mts_place_done()
    unless(!_mts_place_active && _mts_test_finish_count == 1
        error("Done did not terminate the active enter function.")
    )
    _mts_place_active = t
    mts_place_cancel()
    unless(!_mts_place_active && _mts_test_cancel_count == 1
        error("Cancel did not terminate the active enter function.")
    )
    form_file = "mts_form_smoke.form"
    unless(mts_register_bitmap_path() &&
           member(strcat(getWorkingDir() "/icons") _mts_test_bitmap_path)
        error("Mooretronics icon directory was not registered in BMPPATH.")
    )
    unless(mts_write_form(form_file)
        error("Icon form definition could not be generated.")
    )
    form_port = infile(form_file)
    bitmap_line_count = 0
    while(gets(form_line form_port)
        when(rexMatchp("^BITMAP mts_symbol_[0-9][0-9]\\.bmp" form_line)
            bitmap_line_count = bitmap_line_count + 1
        )
    )
    close(form_port)
    unless(bitmap_line_count == 26
        error("Form BITMAP entries must use 26 BMPPATH-resolved file names.")
    )
    deleteFile(form_file)
)

printf("MTS_SKILL_SYNTAX_OK glyphs=%d\n" length(_mts_glyph_data))
exit()
