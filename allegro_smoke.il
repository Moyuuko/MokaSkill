/*
 * Allegro database smoke test.  The caller must set MTS_SMOKE_RESULT to an
 * absolute text-file path.  All created geometry is rolled back.
 */

let((result_file install_dir port mark units anchor inverse_anchor layer ok normal_ok
     inverse_ok glyph contour_count shape_count inverse_shape_count)
    result_file = ""
    when(boundp('mts_smoke_result) && stringp(mts_smoke_result)
        result_file = mts_smoke_result
    )
    unless(strlen(result_file) > 0
        result_file = axlGetVariable("MTS_SMOKE_RESULT")
    )
    unless(stringp(result_file) && strlen(result_file) > 0
        result_file = strcat(getWorkingDir() "/mts_smoke_result.txt")
    )

    install_dir = ""
    when(boundp('mts_smoke_install_dir) && stringp(mts_smoke_install_dir)
        install_dir = mts_smoke_install_dir
    )
    unless(strlen(install_dir) > 0
        install_dir = axlGetVariable("MTS_INSTALL_DIR")
    )
    unless(stringp(install_dir) && strlen(install_dir) > 0
        error("Set MTS_INSTALL_DIR before running allegro_smoke.il.")
    )
    load(strcat(axlOSSlash(install_dir) "/mooretronics_symbols.il"))
    mts_init_defaults()

    units = lowerCase(mts_design_units())
    if(rexMatchp("millimeter" units) then
        anchor = list(1000.0 1000.0)
    else
        if(rexMatchp("inch" units) then
            anchor = list(100.0 100.0)
        else
            anchor = list(100000.0 100000.0)
        )
    )

    layer = "BOARD GEOMETRY/SILKSCREEN_TOP"
    _mts_symbol = "p"
    _mts_layer_class = "BOARD GEOMETRY"
    _mts_layer_subclass = "SILKSCREEN_TOP"
    glyph = mts_glyph_find(_mts_symbol)
    contour_count = if(glyph then length(nth(2 glyph)) else 0)
    shape_count = if(glyph then mts_outline_shape_count(nth(2 glyph) nil) else 0)
    inverse_shape_count = if(glyph then mts_outline_shape_count(nth(2 glyph) t) else 0)

    mark = axlDBTransactionStart()
    _mts_inverse = nil
    normal_ok = mts_layer_exists(layer) && mts_place_at(anchor)
    inverse_anchor = list(car(anchor) + _mts_height * 2.0 cadr(anchor))
    _mts_inverse = t
    inverse_ok = mts_layer_exists(layer) && mts_place_at(inverse_anchor)
    ok = normal_ok && inverse_ok
    when(mark errset(axlDBTransactionRollback(mark) nil))

    port = outfile(result_file)
    when(port
        fprintf(port "placed=%L\n" ok)
        fprintf(port "normal_placed=%L\n" normal_ok)
        fprintf(port "inverse_placed=%L\n" inverse_ok)
        fprintf(port "glyphs=%d\n" length(_mts_glyph_data))
        fprintf(port "pb_free_contours=%d\n" contour_count)
        fprintf(port "pb_free_shapes=%d\n" shape_count)
        fprintf(port "pb_free_inverse_shapes=%d\n" inverse_shape_count)
        fprintf(port "units=%s\n" units)
        close(port)
    )
)
