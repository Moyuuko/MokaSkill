/*
 * Moka skill - PCB 标识放置 v1.0
 *
 * Places PCB marking glyphs generated from Mooretronics.ttf as ordinary
 * filled Allegro geometry.  Commands:
 *   moka_symbols       - open the control panel
 *   moka_symbols_place - place the symbol using the current panel settings
 */

defvar(_mts_version "1.0")
_mts_version = "1.0"
defvar(_mts_install_dir "")
defvar(_mts_form nil)
defvar(_mts_symbol "p")
defvar(_mts_layer_class "BOARD GEOMETRY")
defvar(_mts_layer_subclass "SILKSCREEN_TOP")
defvar(_mts_height 160.0)
defvar(_mts_rotation 0.0)
defvar(_mts_mirror nil)
defvar(_mts_inverse nil)
defvar(_mts_min_contour_area 0.00002)
defvar(_mts_defaults_initialized nil)
defvar(_mts_place_active nil)

/* Build GBK/CP936 UI strings without putting non-ASCII source text into a
 * SKILL file. Allegro 16.6 on Simplified Chinese Windows uses the ANSI code
 * page for form and menu labels; this also remains compatible with 17.4. */
defun( mts_text (byte_values)
    let((result)
        result = ""
        foreach(byte_value byte_values
            result = strcat(result sprintf(nil "%c" intToChar(byte_value)))
        )
        result
    )
)

defun( mts_ui_text (key)
    case(key
        ("panel_title" mts_text(list(77 111 107 97 32 115 107 105 108 108 32 45 32 80 67 66 32 177 234 202 182 183 197 214 195)))
        ("layer_class" "Layer Class:")
        ("layer_subclass" "Layer Subclass:")
        ("height" mts_text(list(184 223 182 200 163 186)))
        ("rotation" mts_text(list(208 253 215 170 163 186)))
        ("mirror" mts_text(list(190 181 207 241)))
        ("inverse" mts_text(list(183 180 207 224)))
        ("unit" mts_text(list(181 165 206 187 163 186)))
        ("hint" mts_text(list(181 227 187 247 205 188 177 234 183 197 214 195 163 187 211 210 188 252 205 234 179 201 189 225 202 248 161 163)))
        ("close" mts_text(list(185 216 177 213)))
        ("attention_plus" mts_text(list(215 162 210 226 43)))
        ("attention" mts_text(list(215 162 210 226)))
        ("earth_ground" mts_text(list(189 211 181 216)))
        ("frame_ground" mts_text(list(187 250 191 199 181 216)))
        ("high_voltage" mts_text(list(184 223 209 185)))
        ("noiseless_ground" mts_text(list(206 222 212 235 201 249 181 216)))
        ("open_hw_plus" mts_text(list(191 170 212 180 211 178 188 254 43)))
        ("open_hw" mts_text(list(191 170 212 180 211 178 188 254)))
        ("pb_free_plus" mts_text(list(206 222 199 166 43)))
        ("pb_free" mts_text(list(206 222 199 166)))
        ("protective_ground" mts_text(list(177 163 187 164 189 211 181 216)))
        ("recycling" mts_text(list(187 216 202 213)))
        (t "")
    )
)

/* Close an older panel when this file is reloaded during development. */
when(_mts_form
    errset(axlFormClose(_mts_form) nil)
    _mts_form = nil
)
let((install_dir glyph_file)
    install_dir = axlGetVariable("MTS_INSTALL_DIR")
    unless(stringp(install_dir) && strlen(install_dir) > 0
        install_dir = getWorkingDir()
    )
    _mts_install_dir = axlOSSlash(install_dir)
    glyph_file = strcat(_mts_install_dir "/mooretronics_glyphs.il")
    if(isFile(glyph_file) then
        load(glyph_file)
    else
        axlMsgPut(sprintf(nil "Mooretronics Symbols: glyph data not found: %s" glyph_file))
    )
)

defun( mts_put_msg (message)
    axlMsgPut(sprintf(nil "Mooretronics Symbols: %s" message))
)

defun( mts_parse_real (value default_value)
    cond(
        (numberp(value) value)
        (stringp(value) && strlen(value) > 0 atof(value))
        (t default_value)
    )
)

defun( mts_design_units ()
    let((result units)
        units = "design units"
        result = errset(axlDBGetDesignUnits() nil)
        when(result && car(result) && stringp(car(car(result)))
            units = car(car(result))
        )
        units
    )
)

defun( mts_init_defaults ()
    let((units)
        unless(_mts_defaults_initialized
            units = lowerCase(mts_design_units())
            cond(
                (rexMatchp("millimeter" units) _mts_height = 4.0)
                (rexMatchp("micron" units) _mts_height = 4000.0)
                (rexMatchp("inch" units) _mts_height = 0.160)
                (t _mts_height = 160.0)
            )
            _mts_defaults_initialized = t
        )
    )
)

defun( mts_layer_name ()
    if(stringp(_mts_layer_class) && strlen(_mts_layer_class) > 0 &&
       stringp(_mts_layer_subclass) && strlen(_mts_layer_subclass) > 0 then
        strcat(upperCase(_mts_layer_class) "/" upperCase(_mts_layer_subclass))
    else
        ""
    )
)

defun( mts_layer_exists (layer_name)
    let((result)
        result = nil
        when(stringp(layer_name) && strlen(layer_name) > 0
            result = errset(axlIsLayer(layer_name) nil)
        )
        result && car(result)
    )
)

defun( mts_class_param (class_name)
    let((result)
        result = nil
        when(stringp(class_name) && strlen(class_name) > 0
            result = errset(
                axlGetParam(sprintf(nil "paramLayerGroup:%s" class_name))
                nil)
        )
        if(result then car(result) else nil)
    )
)

defun( mts_subclass_popup (class_name)
    let((group_param popup layer_name)
        popup = nil
        group_param = mts_class_param(class_name)
        when(group_param && group_param->groupMembers
            foreach(subclass_name group_param->groupMembers
                layer_name = strcat(upperCase(class_name) "/" upperCase(subclass_name))
                when(mts_layer_exists(layer_name)
                    popup = append(
                        popup
                        list(list(upperCase(subclass_name) upperCase(subclass_name))))
                )
            )
        )
        popup
    )
)

defun( mts_class_popup ()
    let((result root popup subclasses)
        popup = nil
        result = errset(axlGetParam("paramLayerGroup") nil)
        root = if(result then car(result) else nil)
        when(root && root->groupMembers
            foreach(class_name root->groupMembers
                subclasses = mts_subclass_popup(class_name)
                when(subclasses
                    popup = append(
                        popup
                        list(list(upperCase(class_name) upperCase(class_name))))
                )
            )
        )
        popup
    )
)

defun( mts_popup_first_value (popup)
    if(popup && car(popup) && cadr(car(popup)) then
        cadr(car(popup))
    else
        ""
    )
)

defun( mts_popup_has_value (popup value)
    let((found)
        found = nil
        foreach(row popup
            when(equal(cadr(row) value) found = t)
        )
        found
    )
)

defun( mts_glyph_find (key)
    let((found)
        found = nil
        when(boundp('_mts_glyph_data)
            foreach(entry _mts_glyph_data
                when(equal(car(entry) key) found = entry)
            )
        )
        found
    )
)

defun( mts_icon_labels ()
    list(
        "Attention+" "Attention" "Recycle O" "Recycle"
        "CE" "CSA" "ESD+" "ESD" "FCC"
        "Earth GND" "Frame GND" "High Volt" "Quiet GND"
        "Open HW+" "Open HW" "Pb Free+" "Pb Free"
        "RoHS" "RCM" "PE Ground" "C-Tick" "UL" "WEEE"
        "Attn solid" "Hot Surf+" "Hot Surf")
)

defun( mts_missing_icon ()
    let((missing index icon_file)
        missing = nil
        index = 0
        when(boundp('_mts_glyph_data)
            foreach(entry _mts_glyph_data
                icon_file = strcat(
                    _mts_install_dir sprintf(nil "/icons/mts_symbol_%02d.bmp" index))
                when(!missing && !isFile(icon_file) missing = icon_file)
                index = index + 1
            )
        )
        missing
    )
)

/* Allegro's FORM BITMAP token expects a file name resolved through BMPPATH.
   Register the icon folder at runtime so an installation path
   containing spaces (for example "Moka Skill") cannot break form parsing. */
defun( mts_register_bitmap_path ()
    let((icon_dir get_result bitmap_paths set_result)
        icon_dir = strcat(_mts_install_dir "/icons")
        get_result = errset(axlGetVariableList("bmppath") nil)
        bitmap_paths = if(get_result && listp(car(get_result)) then
            car(get_result)
        else
            nil
        )
        if(member(icon_dir bitmap_paths) then
            t
        else
            set_result = errset(
                axlSetVariable("bmppath" cons(icon_dir bitmap_paths))
                nil)
            set_result && car(set_result)
        )
    )
)

defun( mts_transform_point (point anchor height_value angle_cos angle_sin mirror_value)
    let((x_value y_value rotated_x rotated_y)
        x_value = car(point) * height_value
        y_value = cadr(point) * height_value
        when(mirror_value x_value = -x_value)
        rotated_x = x_value * angle_cos - y_value * angle_sin
        rotated_y = x_value * angle_sin + y_value * angle_cos
        list(car(anchor) + rotated_x cadr(anchor) + rotated_y)
    )
)

defun( mts_transform_contour (points anchor height_value angle_cos angle_sin mirror_value)
    let((transformed)
        transformed = nil
        foreach(point points
            transformed = append(
                transformed
                list(mts_transform_point(
                    point anchor height_value angle_cos angle_sin mirror_value)))
        )
        when(transformed
            transformed = append(transformed list(car(transformed)))
        )
        transformed
    )
)

defun( mts_outline_bounds (contours)
    let((initialized min_x min_y max_x max_y)
        initialized = nil
        foreach(contour contours
            foreach(point nth(2 contour)
                if(initialized then
                    progn(
                        when(car(point) < min_x min_x = car(point))
                        when(car(point) > max_x max_x = car(point))
                        when(cadr(point) < min_y min_y = cadr(point))
                        when(cadr(point) > max_y max_y = cadr(point))
                    )
                else
                    progn(
                        min_x = car(point)
                        max_x = car(point)
                        min_y = cadr(point)
                        max_y = cadr(point)
                        initialized = t
                    )
                )
            )
        )
        if(initialized then list(min_x min_y max_x max_y) else nil)
    )
)

defun( mts_contour_is_solid (contour)
    mod(cadr(contour) 2) == 0
)

defun( mts_contour_children (contours parent_index)
    let((children index contour)
        children = nil
        for(index 0 length(contours) - 1
            contour = nth(index contours)
            when(car(contour) == parent_index
                children = append(children list(contour))
            )
        )
        children
    )
)

defun( mts_polygon_area (points)
    let((area_value previous current)
        area_value = 0.0
        when(points
            previous = nth(length(points) - 1 points)
            foreach(current points
                area_value = area_value +
                    car(previous) * cadr(current) - car(current) * cadr(previous)
                previous = current
            )
        )
        abs(area_value / 2.0)
    )
)

defun( mts_inset_contour (points factor_value)
    let((center_x center_y count_value inset_points)
        center_x = 0.0
        center_y = 0.0
        count_value = length(points)
        foreach(point points
            center_x = center_x + car(point)
            center_y = center_y + cadr(point)
        )
        center_x = center_x / count_value
        center_y = center_y / count_value
        inset_points = nil
        foreach(point points
            inset_points = append(
                inset_points
                list(list(
                    center_x + (car(point) - center_x) * factor_value
                    center_y + (cadr(point) - center_y) * factor_value)))
        )
        inset_points
    )
)

/* Return t only when the complete candidate void is strictly inside its
 * owner. Checking vertices and segment midpoints rejects the thin crossing
 * contours present in the CSA font glyph that a single-point hierarchy test
 * can incorrectly classify as holes. */
defun( mts_point_in_polygon (point polygon)
    let((x_value y_value inside previous current x1 y1 x2 y2 crossing_x)
        x_value = car(point)
        y_value = cadr(point)
        inside = nil
        when(polygon
            previous = nth(length(polygon) - 1 polygon)
            foreach(current polygon
                x1 = car(previous)
                y1 = cadr(previous)
                x2 = car(current)
                y2 = cadr(current)
                when(
                    ((y1 > y_value) && (y2 <= y_value)) ||
                    ((y1 <= y_value) && (y2 > y_value))
                    crossing_x =
                        (x2 - x1) * (y_value - y1) / (y2 - y1) + x1
                    when(x_value < crossing_x inside = !inside)
                )
                previous = current
            )
        )
        inside
    )
)

defun( mts_contour_strictly_inside (inner_points outer_points)
    let((inside previous current midpoint)
        inside = inner_points && outer_points
        when(inside
            previous = nth(length(inner_points) - 1 inner_points)
            foreach(current inner_points
                when(inside
                    midpoint = list(
                        (car(previous) + car(current)) / 2.0
                        (cadr(previous) + cadr(current)) / 2.0)
                    unless(
                        mts_point_in_polygon(current outer_points) &&
                        mts_point_in_polygon(midpoint outer_points)
                        inside = nil
                    )
                )
                previous = current
            )
        )
        inside
    )
)

/*
 * Create one solid TrueType outline island. Quadratic Bezier curves have
 * already been adaptively flattened by the generator. Direct child contours
 * are created as real voids, so letters and certification marks stay hollow
 * without being decomposed into scanline cells.
 */
defun( mts_create_outline_island
        (contours contour_index anchor height_value angle_cos angle_sin mirror_value
         layer_name inset_holes)
    let((contour boundary_points boundary_path holes result open_shape ok
         hole hole_source hole_points hole_path void_result close_result)
        contour = nth(contour_index contours)
        boundary_points = mts_transform_contour(
            nth(2 contour) anchor height_value angle_cos angle_sin mirror_value)
        boundary_path = axlPathStart(boundary_points 0.0)
        holes = mts_contour_children(contours contour_index)

        if(holes then
            progn(
                result = errset(axlDBCreateOpenShape(boundary_path t layer_name) nil)
                open_shape = if(result then car(result) else nil)
                ok = open_shape
                foreach(hole holes
                    when(ok
                        hole_source = nth(2 hole)
                        /* Allegro rejects voids that touch or cross the owner.
                         * Ignore malformed font fragments, and inset every
                         * valid hole slightly to survive 16.6 coordinate
                         * rounding. Inverse nesting retains the larger 0.2%
                         * inset used by previous releases. */
                        if(!mts_contour_strictly_inside(
                                hole_source nth(2 contour)) then
                            nil
                        else if(mts_polygon_area(hole_source) <
                                _mts_min_contour_area then
                            nil
                        else
                            progn(
                                hole_source = mts_inset_contour(
                                    hole_source
                                    if(inset_holes then 0.998 else 0.9995))
                                hole_points = mts_transform_contour(
                                    hole_source anchor height_value angle_cos
                                    angle_sin mirror_value)
                                hole_path = axlPathStart(hole_points 0.0)
                                void_result = errset(
                                    axlDBCreateVoid(open_shape hole_path) nil)
                                unless(void_result && car(void_result) ok = nil)
                            )
                        )
                        )
                    )
                )
                when(ok
                    close_result = errset(axlDBCreateCloseShape(open_shape) nil)
                    ok = close_result && car(close_result)
                )
                ok
            )
        else
            progn(
                result = errset(axlDBCreateShape(boundary_path t layer_name) nil)
                result && car(result)
            )
        )
    )
)

/*
 * In inverse mode the glyph is cut out of a rectangular field.  Root
 * contours become voids in the field; original holes are restored as
 * separate islands, with their own nested contours handled recursively by
 * the same shape/void rule.
 */
defun( mts_create_inverse_background
        (contours anchor height_value angle_cos angle_sin mirror_value layer_name)
    let((bounds margin rectangle boundary_points boundary_path result open_shape
         ok contour hole_points hole_path void_result close_result)
        bounds = mts_outline_bounds(contours)
        margin = 0.08
        rectangle = list(
            list(car(bounds) - margin cadr(bounds) - margin)
            list(nth(2 bounds) + margin cadr(bounds) - margin)
            list(nth(2 bounds) + margin nth(3 bounds) + margin)
            list(car(bounds) - margin nth(3 bounds) + margin))
        boundary_points = mts_transform_contour(
            rectangle anchor height_value angle_cos angle_sin mirror_value)
        boundary_path = axlPathStart(boundary_points 0.0)
        result = errset(axlDBCreateOpenShape(boundary_path t layer_name) nil)
        open_shape = if(result then car(result) else nil)
        ok = open_shape

        foreach(contour contours
            when(ok && cadr(contour) == 0 &&
                    mts_polygon_area(nth(2 contour)) >= _mts_min_contour_area
                hole_points = mts_transform_contour(
                    nth(2 contour) anchor height_value angle_cos angle_sin mirror_value)
                hole_path = axlPathStart(hole_points 0.0)
                void_result = errset(axlDBCreateVoid(open_shape hole_path) nil)
                unless(void_result && car(void_result) ok = nil)
            )
        )
        when(ok
            close_result = errset(axlDBCreateCloseShape(open_shape) nil)
            ok = close_result && car(close_result)
        )
        ok
    )
)

defun( mts_contour_should_place (contour inverse_value)
    mts_polygon_area(nth(2 contour)) >= _mts_min_contour_area &&
        if(inverse_value then
            !mts_contour_is_solid(contour)
        else
            mts_contour_is_solid(contour)
        )
)

defun( mts_outline_shape_count (contours inverse_value)
    let((count_value)
        count_value = if(inverse_value then 1 else 0)
        foreach(contour contours
            when(mts_contour_should_place(contour inverse_value)
                count_value = count_value + 1
            )
        )
        count_value
    )
)

defun( mts_validate_settings ()
    let((layer_name)
        layer_name = mts_layer_name()
        cond(
            (!boundp('_mts_glyph_data) || !_mts_glyph_data
                "Glyph data is not loaded. Reload the plugin from its loader.")
            (!boundp('_mts_glyph_format) || !equal(_mts_glyph_format "OUTLINE_V1")
                "Outline glyph data is not loaded. Reload mooretronics_symbols.il.")
            (!mts_glyph_find(_mts_symbol)
                "The selected symbol is not present in the glyph data.")
            (_mts_height <= 0.0
                "Symbol height must be greater than zero.")
            (!mts_layer_exists(layer_name)
                sprintf(nil "Layer does not exist: %s" layer_name))
            (t nil)
        )
    )
)

defun( mts_place_at (anchor)
    let((glyph contours layer_name radians angle_cos angle_sin mark ok created
         expected contour index create_result commit_result mode_text)
        glyph = mts_glyph_find(_mts_symbol)
        contours = if(glyph then nth(2 glyph) else nil)
        layer_name = mts_layer_name()
        radians = _mts_rotation * 0.0174532925199433
        angle_cos = cos(radians)
        angle_sin = sin(radians)
        mark = axlDBTransactionStart()
        ok = mark && contours
        created = 0
        expected = mts_outline_shape_count(contours _mts_inverse)

        when(ok && _mts_inverse
            create_result = mts_create_inverse_background(
                contours anchor _mts_height angle_cos angle_sin
                _mts_mirror layer_name)
            if(create_result then created = 1 else ok = nil)
        )

        for(index 0 length(contours) - 1
            contour = nth(index contours)
            when(ok && mts_contour_should_place(contour _mts_inverse)
                create_result = mts_create_outline_island(
                    contours index anchor _mts_height angle_cos angle_sin
                    _mts_mirror layer_name _mts_inverse)
                if(create_result then created = created + 1 else ok = nil)
            )
        )

        if(ok && created == expected then
            progn(
                commit_result = axlDBTransactionCommit(mark)
                if(commit_result then
                    progn(
                        axlFlushDisplay()
                        mode_text = if(_mts_inverse then "inverse " else "")
                        mts_put_msg(sprintf(nil
                            "Placed %s%s on %s at %.4f:%.4f (%d outline shapes)."
                            mode_text cadr(glyph) layer_name
                            car(anchor) cadr(anchor) created))
                        t
                    )
                else
                    progn(
                        errset(axlDBTransactionRollback(mark) nil)
                        mts_put_msg("Commit failed; the symbol was rolled back.")
                        nil
                    )
                )
            )
        else
            progn(
                when(mark errset(axlDBTransactionRollback(mark) nil))
                mts_put_msg(sprintf(nil
                    "Outline placement failed on %s after %d shape(s). The layer may not support filled shapes or voids; no geometry was kept."
                    layer_name created))
                nil
            )
        )
    )
)

defun( mts_place_done ()
    _mts_place_active = nil
    when(isCallable('axlFinishEnterFun)
        errset(axlFinishEnterFun() nil)
    )
    t
)

defun( mts_place_cancel ()
    _mts_place_active = nil
    when(isCallable('axlCancelEnterFun)
        errset(axlCancelEnterFun() nil)
    )
    mts_put_msg("Placement command cancelled.")
    t
)

defun( mts_place_cmd ()
    let((error_message point glyph)
        if(_mts_place_active then
            mts_put_msg("A placement command is already active.")
        else
            error_message = mts_validate_settings()
            if(error_message then
                mts_put_msg(error_message)
            else
                progn(
                    glyph = mts_glyph_find(_mts_symbol)
                    _mts_place_active = t
                    mts_put_msg(sprintf(nil
                        "Click to place %s; right-click Done to finish."
                        cadr(glyph)))
                    unwindProtect(
                        while(_mts_place_active
                            point = axlEnterPoint(
                                ?prompts list(sprintf(nil
                                    "Place %s on %s; right-click Done to finish."
                                    cadr(glyph) mts_layer_name())))
                            if(point then
                                mts_place_at(point)
                            else
                                _mts_place_active = nil
                            )
                        )
                        _mts_place_active = nil
                    )
                )
            )
        )
        t
    )
)

defun( mts_form_store (form)
    let((value)
        value = axlFormGetField(form "layer_class")
        when(stringp(value) _mts_layer_class = upperCase(value))
        value = axlFormGetField(form "layer_subclass")
        when(stringp(value) _mts_layer_subclass = upperCase(value))
        _mts_height = mts_parse_real(axlFormGetField(form "height") _mts_height)
        _mts_rotation = mts_parse_real(axlFormGetField(form "rotation") _mts_rotation)
        _mts_mirror = if(axlFormGetField(form "mirror") then t else nil)
        _mts_inverse = if(axlFormGetField(form "inverse") then t else nil)
    )
)

defun( mts_symbol_for_field (field_name)
    let((found index)
        found = nil
        index = 0
        when(stringp(field_name) && boundp('_mts_glyph_data)
            foreach(entry _mts_glyph_data
                when(equal(field_name sprintf(nil "sym_%02d" index))
                    found = car(entry)
                )
                index = index + 1
            )
        )
        found
    )
)

defun( mts_form_close (form)
    _mts_form = nil
    errset(axlFormClose(form) nil)
)

defun( mts_form_callback (form)
    let((value popup error_message symbol_key)
        if(form->doneState > 0 then
            mts_form_close(form)
        else
            symbol_key = mts_symbol_for_field(form->curField)
            if(symbol_key then
                progn(
                    mts_form_store(form)
                    _mts_symbol = symbol_key
                    error_message = mts_validate_settings()
                    if(error_message then
                        mts_put_msg(error_message)
                    else
                        axlShellPost("mts_place")
                    )
                )
            else
                case(form->curField
                    ("layer_class"
                        value = form->curValue
                        when(stringp(value) _mts_layer_class = upperCase(value))
                        popup = mts_subclass_popup(_mts_layer_class)
                        if(mts_popup_has_value(popup _mts_layer_subclass) then
                            nil
                        else
                            _mts_layer_subclass = mts_popup_first_value(popup)
                        )
                        axlFormBuildPopup(form "layer_subclass" popup)
                        axlFormSetField(form "layer_subclass" _mts_layer_subclass)
                    )
                    ("btn_close" mts_form_close(form))
                    (t mts_form_store(form))
                )
            )
        )
        t
    )
)

defun( mts_write_form (form_file)
    let((port index column row x_pos y_pos icon_file short_labels)
        port = outfile(form_file)
        if(port then
            progn(
                fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\n")
                fprintf(port "FORM\nFIXED\nPORT 85 51\n")
                fprintf(port "HEADER \"%s v%s\"\n" mts_ui_text("panel_title") _mts_version)
                fprintf(port "POPUP <CLASSPOP> \"BOARD GEOMETRY\" \"BOARD GEOMETRY\".\n")
                fprintf(port "POPUP <SUBPOP> \"SILKSCREEN_TOP\" \"SILKSCREEN_TOP\".\n")
                fprintf(port "TILE\n")
                index = 0
                column = 0
                row = 0
                short_labels = mts_icon_labels()
                foreach(entry _mts_glyph_data
                    x_pos = 1 + column * 12
                    y_pos = 1 + row * 8
                    icon_file = sprintf(nil "mts_symbol_%02d.bmp" index)
                    fprintf(port "FIELD sym_%02d\nFLOC %d %d\n" index x_pos y_pos)
                    fprintf(port "MENUBUTTON \"\" 10 5\nBITMAP %s\nENDFIELD\n" icon_file)
                    fprintf(port "TEXT \"%s\"\nTLOC %d %d\nFSIZE 10 2\nOPTIONS center\nENDTEXT\n"
                        nth(index short_labels) x_pos y_pos + 5)
                    index = index + 1
                    column = column + 1
                    when(column == 7
                        column = 0
                        row = row + 1
                    )
                )
                fprintf(port "TEXT \"%s\"\nTLOC 1 33\nENDTEXT\n" mts_ui_text("layer_class"))
                fprintf(port "FIELD layer_class\nFLOC 1 35\nENUMSET 24\nPOP \"CLASSPOP\"\nENDFIELD\n")
                fprintf(port "TEXT \"%s\"\nTLOC 29 33\nENDTEXT\n" mts_ui_text("layer_subclass"))
                fprintf(port "FIELD layer_subclass\nFLOC 29 35\nENUMSET 24\nPOP \"SUBPOP\"\nENDFIELD\n")
                fprintf(port "TEXT \"%s\"\nTLOC 57 33\nENDTEXT\n" mts_ui_text("height"))
                fprintf(port "FIELD height\nFLOC 57 35\nREALFILLIN 10 12\nDECIMAL 4\nENDFIELD\n")
                fprintf(port "TEXT \"%s\"\nTLOC 1 40\nENDTEXT\n" mts_ui_text("rotation"))
                fprintf(port "FIELD rotation\nFLOC 1 42\nREALFILLIN 10 12\nDECIMAL 2\nENDFIELD\n")
                fprintf(port "FIELD mirror\nFLOC 18 42\nCHECKLIST \"%s\"\nENDFIELD\n" mts_ui_text("mirror"))
                fprintf(port "FIELD inverse\nFLOC 33 42\nCHECKLIST \"%s\"\nENDFIELD\n" mts_ui_text("inverse"))
                fprintf(port "TEXT \"%s %s\"\nTLOC 51 42\nENDTEXT\n" mts_ui_text("unit") mts_design_units())
                fprintf(port "TEXT \"%s\"\nTLOC 1 48\nENDTEXT\n" mts_ui_text("hint"))
                fprintf(port "FIELD btn_close\nFLOC 72 47\nMENUBUTTON \"%s\" 10 3\nENDFIELD\n" mts_ui_text("close"))
                fprintf(port "ENDTILE\nENDFORM\n")
                close(port)
                t
            )
        else
            nil
        )
    )
)

defun( mts_form_initialize (form)
    let((class_popup subclass_popup)
        class_popup = mts_class_popup()
        unless(mts_glyph_find(_mts_symbol)
            when(boundp('_mts_glyph_data) && _mts_glyph_data
                _mts_symbol = car(car(_mts_glyph_data))
            )
        )
        unless(mts_class_param(_mts_layer_class)
            _mts_layer_class = mts_popup_first_value(class_popup)
            _mts_layer_subclass = ""
        )
        subclass_popup = mts_subclass_popup(_mts_layer_class)
        unless(mts_layer_exists(mts_layer_name())
            _mts_layer_subclass = mts_popup_first_value(subclass_popup)
        )
        axlFormBuildPopup(form "layer_class" class_popup)
        axlFormBuildPopup(form "layer_subclass" subclass_popup)
        axlFormSetField(form "layer_class" _mts_layer_class)
        axlFormSetField(form "layer_subclass" _mts_layer_subclass)
        axlFormSetField(form "height" _mts_height)
        axlFormSetField(form "rotation" _mts_rotation)
        axlFormSetField(form "mirror" _mts_mirror)
        axlFormSetField(form "inverse" _mts_inverse)
    )
)

defun( mts_open_panel ()
    let((form_file form missing_icon)
        mts_init_defaults()
        missing_icon = mts_missing_icon()
        mts_register_bitmap_path()
        if(!boundp('_mts_glyph_data) || !_mts_glyph_data then
            mts_put_msg("Glyph data is unavailable; check the loader and install directory.")
        else
            if(missing_icon then
                mts_put_msg(sprintf(nil "Icon file not found: %s" missing_icon))
            else
              if(_mts_form then
                progn(
                    mts_form_initialize(_mts_form)
                    axlFormDisplay(_mts_form)
                )
            else
                progn(
                    form_file = axlTempFile(t)
                    if(mts_write_form(form_file) then
                        progn(
                            form = axlFormCreate(
                                (gensym)
                                form_file
                                list("E" "OUT" "center")
                                'mts_form_callback
                                t)
                            when(isFile(form_file)
                                errset(axlTempFileRemove(form_file) nil))
                            if(form then
                                progn(
                                    _mts_form = form
                                    mts_form_initialize(form)
                                    axlFormDisplay(form)
                                )
                            else
                                mts_put_msg("Unable to create the control panel.")
                            )
                        )
                    else
                        mts_put_msg("Unable to write the temporary form definition.")
                    )
                )
              )
        )
        )
        t
    )
)

when(isCallable('axlCmdRegister)
    axlCmdRegister("moka_symbols" 'mts_open_panel ?cmdType "general")
    axlCmdRegister(
        "moka_symbols_place"
        'mts_place_cmd
        ?cmdType "interactive"
        ?doneCmd 'mts_place_done
        ?cancelCmd 'mts_place_cancel)
    /* Backward-compatible standalone command names. */
    axlCmdRegister("mts_symbols" 'mts_open_panel ?cmdType "general")
    axlCmdRegister("mooretronics_symbols" 'mts_open_panel ?cmdType "general")
    axlCmdRegister(
        "mts_place"
        'mts_place_cmd
        ?cmdType "interactive"
        ?doneCmd 'mts_place_done
        ?cancelCmd 'mts_place_cancel)
)
