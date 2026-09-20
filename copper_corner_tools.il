/*
 * Copper Corner Tools v1.3.0
 *
 * Standalone Cadence Allegro SKILL plugin for applying a uniform chamfer or
 * fillet to automatically detected convex corners of selected copper shapes.
 *
 * Commands:
 *   copper_corner       Open the control panel.
 *   cct                 Alias for copper_corner.
 *   copper_corner_apply Start an interactive shape selection session.
 */

defvar(_cct_version "1.3.0")
defvar(_cct_form nil)
defvar(_cct_mode "CHAMFER")
defvar(_cct_corner_scope "OUTER")
defvar(_cct_size 20.0)
defvar(_cct_min_angle 30.0)
defvar(_cct_max_angle 150.0)
defvar(_cct_defaults_initialized nil)
defvar(_cct_finished nil)
defvar(_cct_commit nil)
defvar(_cct_mark nil)
defvar(_cct_session_shapes 0)
defvar(_cct_session_corners 0)
defvar(_cct_session_failed 0)

/* Reloading an older version in the same Allegro session must expose the new mode. */
_cct_version = "1.3.0"
_cct_mode = "CHAMFER"

defun( cct_put_msg (message)
    axlMsgPut(sprintf(nil "Copper Corner Tools: %s" message))
)

defun( cct_parse_real (value default_value)
    cond(
        (numberp(value) value)
        (stringp(value) && strlen(value) > 0 atof(value))
        (t default_value)
    )
)

defun( cct_design_units ()
    let((result units)
        units = "design units"
        result = errset(axlDBGetDesignUnits() nil)
        when(result && car(result) && stringp(car(car(result)))
            units = car(car(result))
        )
        units
    )
)

defun( cct_init_defaults ()
    let((units)
        unless(_cct_defaults_initialized
            units = lowerCase(cct_design_units())
            cond(
                (rexMatchp("millimeter" units) _cct_size = 0.50)
                (rexMatchp("micron" units) _cct_size = 500.0)
                (rexMatchp("inch" units) _cct_size = 0.020)
                (t _cct_size = 20.0)
            )
            _cct_defaults_initialized = t
        )
    )
)

defun( cct_point_x (point) car(point))
defun( cct_point_y (point) cadr(point))

defun( cct_point_add (point vector scale)
    list(
        cct_point_x(point) + cct_point_x(vector) * scale
        cct_point_y(point) + cct_point_y(vector) * scale
    )
)

defun( cct_point_sub (point1 point2)
    list(
        cct_point_x(point1) - cct_point_x(point2)
        cct_point_y(point1) - cct_point_y(point2)
    )
)

defun( cct_vector_length (vector)
    sqrt(
        cct_point_x(vector) * cct_point_x(vector) +
        cct_point_y(vector) * cct_point_y(vector)
    )
)

defun( cct_vector_unit (vector)
    let((length_value)
        length_value = cct_vector_length(vector)
        if(length_value > 0.0 then
            list(cct_point_x(vector) / length_value cct_point_y(vector) / length_value)
        else
            nil
        )
    )
)

defun( cct_vector_scale (vector scale)
    list(cct_point_x(vector) * scale cct_point_y(vector) * scale)
)

defun( cct_point_distance (point1 point2)
    cct_vector_length(cct_point_sub(point1 point2))
)

defun( cct_dot (vector1 vector2)
    cct_point_x(vector1) * cct_point_x(vector2) +
    cct_point_y(vector1) * cct_point_y(vector2)
)

defun( cct_cross (vector1 vector2)
    cct_point_x(vector1) * cct_point_y(vector2) -
    cct_point_y(vector1) * cct_point_x(vector2)
)

defun( cct_clamp (value minimum maximum)
    min(max(value minimum) maximum)
)

defun( cct_points_equal (point1 point2 tolerance)
    point1 && point2 &&
    abs(cct_point_x(point1) - cct_point_x(point2)) <= tolerance &&
    abs(cct_point_y(point1) - cct_point_y(point2)) <= tolerance
)

defun( cct_tolerance ()
    max(0.000001 _cct_size / 100000.0)
)

defun( cct_drop_last (items)
    if(items then reverse(cdr(reverse(items))) else nil)
)

defun( cct_polygon_points (polygon)
    let((points vertex point last_point tolerance has_arc)
        points = nil
        last_point = nil
        tolerance = cct_tolerance()
        has_arc = nil
        when(polygon && polygon->vertices
            foreach(vertex polygon->vertices
                point = car(vertex)
                when(cadr(vertex) && abs(cadr(vertex)) > tolerance
                    has_arc = t
                )
                unless(last_point && cct_points_equal(point last_point tolerance)
                    points = append(points list(point))
                    last_point = point
                )
            )
        )
        when(length(points) > 1 && cct_points_equal(car(points) car(reverse(points)) tolerance)
            points = cct_drop_last(points)
        )
        list(points has_arc)
    )
)

defun( cct_signed_area (points)
    let((area count index point1 point2)
        area = 0.0
        count = length(points)
        for(index 0 count - 1
            point1 = nth(index points)
            point2 = nth(mod(index + 1 count) points)
            area = area +
                cct_point_x(point1) * cct_point_y(point2) -
                cct_point_x(point2) * cct_point_y(point1)
        )
        area / 2.0
    )
)

defun( cct_turn_selected (oriented_turn tolerance)
    cond(
        (_cct_corner_scope == "INNER" oriented_turn < 0.0 - tolerance)
        (_cct_corner_scope == "BOTH" abs(oriented_turn) > tolerance)
        (t oriented_turn > tolerance)
    )
)

defun( cct_corner_sign (oriented_turn)
    if(oriented_turn >= 0.0 then 1.0 else -1.0)
)

defun( cct_line_intersection (point1 point2 point3 point4)
    let((direction1 direction2 denominator offset parameter tolerance)
        direction1 = cct_point_sub(point2 point1)
        direction2 = cct_point_sub(point4 point3)
        denominator = cct_cross(direction1 direction2)
        tolerance = cct_tolerance()
        if(abs(denominator) <= tolerance then
            nil
        else
            progn(
                offset = cct_point_sub(point3 point1)
                parameter = cct_cross(offset direction2) / denominator
                cct_point_add(point1 direction1 parameter)
            )
        )
    )
)

/*
 * Detect one existing chamfer edge P1-P2. P0-P1 and P2-P3 are treated as
 * the two main edges. Their infinite-line intersection is the original
 * virtual sharp corner. The returned endpoints use the requested uniform
 * setback from that virtual corner without adding any vertices.
 *
 * Return value:
 *   (startIndex endIndex newStart newEnd oldSetback1 oldSetback2 angle virtualCorner)
 */
defun( cct_existing_chamfer_spec (points index orientation)
    let((count index0 index1 index2 index3 point0 point1 point2 point3
         previous_vector chamfer_vector next_vector previous_length chamfer_length
         next_length previous_unit chamfer_unit next_unit turn1 turn2 change1 change2
         intersection to_corner from_corner old_setback1 old_setback2 interior_vector
         interior_angle new_point1 new_point2 tolerance result)
        result = nil
        count = length(points)
        index0 = mod(index - 1 + count count)
        index1 = index
        index2 = mod(index + 1 count)
        index3 = mod(index + 2 count)
        point0 = nth(index0 points)
        point1 = nth(index1 points)
        point2 = nth(index2 points)
        point3 = nth(index3 points)
        previous_vector = cct_point_sub(point1 point0)
        chamfer_vector = cct_point_sub(point2 point1)
        next_vector = cct_point_sub(point3 point2)
        previous_length = cct_vector_length(previous_vector)
        chamfer_length = cct_vector_length(chamfer_vector)
        next_length = cct_vector_length(next_vector)
        tolerance = cct_tolerance()

        when(previous_length > tolerance && chamfer_length > tolerance && next_length > tolerance
            previous_unit = cct_vector_unit(previous_vector)
            chamfer_unit = cct_vector_unit(chamfer_vector)
            next_unit = cct_vector_unit(next_vector)
            turn1 = cct_cross(previous_vector chamfer_vector) * orientation
            turn2 = cct_cross(chamfer_vector next_vector) * orientation
            change1 = acos(cct_clamp(cct_dot(previous_unit chamfer_unit) -1.0 1.0)) *
                180.0 / 3.141592653589793
            change2 = acos(cct_clamp(cct_dot(chamfer_unit next_unit) -1.0 1.0)) *
                180.0 / 3.141592653589793

            when(cct_turn_selected(turn1 tolerance) &&
                 cct_turn_selected(turn2 tolerance) &&
                 chamfer_length < min(previous_length next_length) * 0.98 &&
                 change1 >= 2.0 && change1 <= 88.0 &&
                 change2 >= 2.0 && change2 <= 88.0
                intersection = cct_line_intersection(point0 point1 point2 point3)
                when(intersection
                    to_corner = cct_point_sub(intersection point1)
                    from_corner = cct_point_sub(point2 intersection)
                    old_setback1 = cct_dot(to_corner previous_unit)
                    old_setback2 = cct_dot(from_corner next_unit)
                    interior_vector = cct_vector_scale(previous_unit -1.0)
                    interior_angle = acos(cct_clamp(cct_dot(interior_vector next_unit) -1.0 1.0)) *
                        180.0 / 3.141592653589793
                    when(old_setback1 > tolerance && old_setback2 > tolerance &&
                         interior_angle >= _cct_min_angle &&
                         interior_angle <= _cct_max_angle
                        new_point1 = cct_point_add(intersection previous_unit 0.0 - _cct_size)
                        new_point2 = cct_point_add(intersection next_unit _cct_size)
                        result = list(
                            index1 index2 new_point1 new_point2
                            old_setback1 old_setback2 interior_angle intersection)
                    )
                )
            )
        )
        result
    )
)

defun( cct_detect_existing_chamfers (points)
    let((area orientation index spec detected used_vertices)
        area = cct_signed_area(points)
        orientation = if(area >= 0.0 then 1.0 else -1.0)
        detected = nil
        used_vertices = nil
        for(index 0 length(points) - 1
            spec = cct_existing_chamfer_spec(points index orientation)
            when(spec &&
                 !member(nth(0 spec) used_vertices) &&
                 !member(nth(1 spec) used_vertices)
                detected = append(detected list(spec))
                used_vertices = cons(nth(0 spec) used_vertices)
                used_vertices = cons(nth(1 spec) used_vertices)
            )
        )
        detected
    )
)

defun( cct_apply_point_updates (points updates)
    let((result index update)
        result = nil
        for(index 0 length(points) - 1
            update = assoc(index updates)
            result = append(result list(if(update then cadr(update) else nth(index points))))
        )
        result
    )
)

defun( cct_preserves_edge_directions (old_points new_points)
    let((valid count index old_edge new_edge tolerance)
        valid = t
        count = length(old_points)
        tolerance = cct_tolerance()
        for(index 0 count - 1
            old_edge = cct_point_sub(
                nth(mod(index + 1 count) old_points)
                nth(index old_points))
            new_edge = cct_point_sub(
                nth(mod(index + 1 count) new_points)
                nth(index new_points))
            when(cct_dot(old_edge new_edge) <= tolerance
                valid = nil
            )
        )
        valid
    )
)

/* Returns (newPoints chamferCount reason). */
defun( cct_normalize_existing_chamfers (points)
    let((spec detected updates count new_points reason)
        detected = cct_detect_existing_chamfers(points)
        updates = nil
        count = length(detected)
        reason = nil
        foreach(spec detected
            updates = cons(list(nth(0 spec) nth(2 spec)) updates)
            updates = cons(list(nth(1 spec) nth(3 spec)) updates)
        )
        if(count == 0 then
            progn(
                new_points = points
                reason = "no existing chamfer edges were detected"
            )
        else
            progn(
                new_points = cct_apply_point_updates(points updates)
                unless(cct_preserves_edge_directions(points new_points)
                    new_points = points
                    count = 0
                    reason = sprintf(nil
                        "uniform size %.4f is too large for the remaining main-edge lengths"
                        _cct_size)
                )
            )
        )
        list(new_points count reason)
    )
)

/*
 * Collapse every detected chamfer edge back to its virtual sharp corner.
 * The resulting base polygon is then suitable for either uniform chamfer or
 * uniform fillet generation. Return (basePoints detectedChamferCount).
 */
defun( cct_restore_virtual_corners (points)
    let((detected spec start_map consumed_ends base_points index start_spec)
        detected = cct_detect_existing_chamfers(points)
        start_map = nil
        consumed_ends = nil
        base_points = nil
        foreach(spec detected
            start_map = cons(list(nth(0 spec) spec) start_map)
            consumed_ends = cons(nth(1 spec) consumed_ends)
        )
        for(index 0 length(points) - 1
            start_spec = assoc(index start_map)
            cond(
                (start_spec
                    base_points = append(base_points list(nth(7 cadr(start_spec))))
                )
                (member(index consumed_ends) nil)
                (t base_points = append(base_points list(nth(index points))))
            )
        )
        list(base_points length(detected))
    )
)

defun( cct_path_from_points (points)
    if(length(points) >= 3 then
        axlPathStart(append(points list(car(points))) 0.0)
    else
        nil
    )
)

/*
 * A corner specification is:
 *   (modified incomingPoint outgoingPoint arcCenter angleDegrees trimDistance cornerSign)
 */
defun( cct_corner_spec (points index orientation)
    let((count previous current following previous_vector following_vector
         incoming_unit outgoing_unit previous_length following_length dot_value
         angle_radians angle_degrees incoming_direction outgoing_direction turn
         trim_distance half_angle bisector bisector_unit center incoming outgoing
         modified tolerance oriented_turn corner_sign)
        count = length(points)
        previous = nth(mod(index - 1 + count count) points)
        current = nth(index points)
        following = nth(mod(index + 1 count) points)
        previous_vector = cct_point_sub(previous current)
        following_vector = cct_point_sub(following current)
        previous_length = cct_vector_length(previous_vector)
        following_length = cct_vector_length(following_vector)
        tolerance = cct_tolerance()
        modified = nil
        incoming = current
        outgoing = current
        center = nil
        angle_degrees = 0.0
        trim_distance = 0.0
        corner_sign = 0.0

        when(previous_length > tolerance && following_length > tolerance
            incoming_unit = cct_vector_unit(previous_vector)
            outgoing_unit = cct_vector_unit(following_vector)
            dot_value = cct_clamp(cct_dot(incoming_unit outgoing_unit) -1.0 1.0)
            angle_radians = acos(dot_value)
            angle_degrees = angle_radians * 180.0 / 3.141592653589793
            incoming_direction = cct_point_sub(current previous)
            outgoing_direction = cct_point_sub(following current)
            turn = cct_cross(incoming_direction outgoing_direction)
            oriented_turn = turn * orientation
            corner_sign = cct_corner_sign(oriented_turn)

            when(cct_turn_selected(oriented_turn tolerance) &&
                 angle_degrees >= _cct_min_angle &&
                 angle_degrees <= _cct_max_angle
                if(_cct_mode == "ROUND" then
                    progn(
                        half_angle = angle_radians / 2.0
                        when(abs(sin(half_angle)) > tolerance && abs(cos(half_angle)) > tolerance
                            trim_distance = _cct_size * cos(half_angle) / sin(half_angle)
                            bisector = cct_point_add(incoming_unit outgoing_unit 1.0)
                            bisector_unit = cct_vector_unit(bisector)
                            when(bisector_unit
                                center = cct_point_add(
                                    current
                                    bisector_unit
                                    _cct_size / sin(half_angle)
                                )
                            )
                        )
                    )
                else
                    trim_distance = _cct_size
                )

                /* 45 percent leaves room when both ends of one edge are changed. */
                when(trim_distance > tolerance &&
                     trim_distance <= previous_length * 0.45 &&
                     trim_distance <= following_length * 0.45 &&
                     (_cct_mode != "ROUND" || center)
                    incoming = cct_point_add(current incoming_unit trim_distance)
                    outgoing = cct_point_add(current outgoing_unit trim_distance)
                    modified = t
                )
            )
        )
        list(modified incoming outgoing center angle_degrees trim_distance corner_sign)
    )
)

defun( cct_build_specs (points)
    let((specs area orientation index)
        specs = nil
        area = cct_signed_area(points)
        orientation = if(area >= 0.0 then 1.0 else -1.0)
        for(index 0 length(points) - 1
            specs = append(specs list(cct_corner_spec(points index orientation)))
        )
        list(specs orientation)
    )
)

defun( cct_target_corner_count (points)
    let((count area orientation index point_count previous current following
         incoming outgoing incoming_length outgoing_length incoming_unit outgoing_unit
         angle turn tolerance)
        count = 0
        point_count = length(points)
        area = cct_signed_area(points)
        orientation = if(area >= 0.0 then 1.0 else -1.0)
        tolerance = cct_tolerance()
        for(index 0 point_count - 1
            previous = nth(mod(index - 1 + point_count point_count) points)
            current = nth(index points)
            following = nth(mod(index + 1 point_count) points)
            incoming = cct_point_sub(current previous)
            outgoing = cct_point_sub(following current)
            incoming_length = cct_vector_length(incoming)
            outgoing_length = cct_vector_length(outgoing)
            when(incoming_length > tolerance && outgoing_length > tolerance
                incoming_unit = cct_vector_unit(cct_vector_scale(incoming -1.0))
                outgoing_unit = cct_vector_unit(outgoing)
                angle = acos(cct_clamp(cct_dot(incoming_unit outgoing_unit) -1.0 1.0)) *
                    180.0 / 3.141592653589793
                turn = cct_cross(incoming outgoing) * orientation
                when(cct_turn_selected(turn tolerance) &&
                     angle >= _cct_min_angle && angle <= _cct_max_angle
                    count = count + 1
                )
            )
        )
        count
    )
)

defun( cct_modified_count (specs)
    let((count spec)
        count = 0
        foreach(spec specs
            when(car(spec) count = count + 1)
        )
        count
    )
)

defun( cct_corner_clockwise (spec polygon_clockwise)
    if(nth(6 spec) < 0.0 then !polygon_clockwise else polygon_clockwise)
)

defun( cct_add_corner_to_path (path spec clockwise)
    when(car(spec)
        if(_cct_mode == "ROUND" then
            axlPathArcCenter(
                path
                0.0
                nth(2 spec)
                cct_corner_clockwise(spec clockwise)
                nth(3 spec))
        else
            axlPathLine(path 0.0 nth(2 spec))
        )
    )
    path
)

defun( cct_build_path (specs orientation)
    let((path count index spec first_spec clockwise)
        path = nil
        count = length(specs)
        when(count >= 3 && cct_modified_count(specs) > 0
            first_spec = car(specs)
            path = axlPathStart(list(nth(2 first_spec)) 0.0)
            clockwise = if(orientation > 0.0 then nil else t)
            for(index 1 count - 1
                spec = nth(index specs)
                axlPathLine(path 0.0 nth(1 spec))
                cct_add_corner_to_path(path spec clockwise)
            )
            axlPathLine(path 0.0 nth(1 first_spec))
            cct_add_corner_to_path(path first_spec clockwise)
        )
        path
    )
)

defun( cct_shape_polygon (shape)
    let((result polygons polygon candidate)
        polygon = nil
        result = errset(axlPolyFromDB(shape ?holes nil) nil)
        when(result && car(result)
            polygons = car(result)
            if(listp(polygons) then
                foreach(candidate polygons
                    when(!polygon && candidate && !candidate->isHole
                        polygon = candidate
                    )
                )
            else
                polygon = polygons
            )
        )
        polygon
    )
)

/*
 * Dynamic copper shown on an ETCH layer is an auto-generated child shape.
 * Allegro does not allow that child to be edited. Resolve it to the owning
 * BOUNDARY shape before reading or replacing the outline.
 */
defun( cct_editable_shape (shape)
    let((target next_target guard)
        target = shape
        guard = 0
        while(target && target->objType == "shape" && target->shapeBoundary && guard < 8
            next_target = target->shapeBoundary
            if(next_target == target then
                guard = 8
            else
                target = next_target
                guard = guard + 1
            )
        )
        target
    )
)

defun( cct_result_dbid (result)
    let((value)
        value = nil
        when(result && car(result)
            cond(
                (axlIsDBIDType(car(result)) value = car(result))
                (listp(car(result)) && car(car(result)) && axlIsDBIDType(car(car(result)))
                    value = car(car(result))
                )
            )
        )
        value
    )
)

/* Returns (changed cornerCount reason). */
defun( cct_modify_shape (shape)
    let((polygon point_data points has_arc specs_data specs orientation corner_count
         expected_count normalize_data normalized_points base_data base_points path open_result
         updated_shape reason)
        reason = nil
        corner_count = 0
        updated_shape = nil
        shape = cct_editable_shape(shape)
        cond(
            (!shape reason = "invalid selection")
            (shape->objType != "shape" reason = "not a shape")
            (t
                polygon = cct_shape_polygon(shape)
                if(!polygon then
                    reason = "cannot read boundary polygon"
                else
                    point_data = cct_polygon_points(polygon)
                    points = car(point_data)
                    has_arc = cadr(point_data)
                    cond(
                        (has_arc reason = "contains existing arc segments")
                        (length(points) < 3 reason = "boundary has fewer than three vertices")
                        (abs(cct_signed_area(points)) <= cct_tolerance() reason = "boundary area is zero")
                        (t
                            if(_cct_mode == "NORMALIZE" then
                                progn(
                                    normalize_data = cct_normalize_existing_chamfers(points)
                                    normalized_points = car(normalize_data)
                                    corner_count = cadr(normalize_data)
                                    reason = caddr(normalize_data)
                                    when(corner_count > 0
                                        path = cct_path_from_points(normalized_points)
                                    )
                                )
                            else
                                progn(
                                    base_data = cct_restore_virtual_corners(points)
                                    base_points = car(base_data)
                                    expected_count = cct_target_corner_count(base_points)
                                    specs_data = cct_build_specs(base_points)
                                    specs = car(specs_data)
                                    orientation = cadr(specs_data)
                                    corner_count = cct_modified_count(specs)
                                    if(expected_count > 0 && corner_count < expected_count then
                                        progn(
                                            corner_count = 0
                                            reason = sprintf(nil
                                                "uniform size %.4f does not fit all %d target corners"
                                                _cct_size expected_count)
                                        )
                                    else
                                        if(corner_count == 0 then
                                        reason = sprintf(nil
                                            "no eligible convex corners; size %.4f may be too large or angles may be outside %.1f..%.1f degrees"
                                            _cct_size _cct_min_angle _cct_max_angle)
                                        else
                                            path = cct_build_path(specs orientation)
                                        )
                                    )
                                )
                            )
                            if(corner_count > 0 then
                                if(!path then
                                    progn(
                                        corner_count = 0
                                        reason = "cannot build replacement boundary"
                                    )
                                else
                                    open_result = errset(axlDBOpenShape(shape path t) nil)
                                    updated_shape = cct_result_dbid(open_result)
                                    if(updated_shape then
                                        when(updated_shape->shapeIsBoundary
                                            errset(axlShapeDynamicUpdate(updated_shape t) nil)
                                        )
                                    else
                                        corner_count = 0
                                        reason = "Allegro rejected the new boundary; check void clearance"
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
        list(if(updated_shape then t else nil) corner_count reason)
    )
)

defun( cct_validate_settings ()
    cond(
        (_cct_size <= 0.0 "Size must be greater than zero.")
        (_cct_min_angle <= 0.0 "Minimum angle must be greater than zero.")
        (_cct_max_angle >= 180.0 "Maximum angle must be less than 180 degrees.")
        (_cct_min_angle > _cct_max_angle "Minimum angle cannot exceed maximum angle.")
        (t nil)
    )
)

defun( cct_operation_name ()
    cond(
        (_cct_mode == "NORMALIZE" "normalizing existing chamfers")
        (_cct_mode == "ROUND" "applying uniform fillets")
        (t "applying uniform chamfers")
    )
)

defun( cct_corner_scope_name ()
    cond(
        (_cct_corner_scope == "INNER" "inner corners")
        (_cct_corner_scope == "BOTH" "outer and inner corners")
        (t "outer corners")
    )
)

defun( cct_apply_selection (selected)
    let((shape target targets result changed corner_count reason selection_changed selection_corners)
        selection_changed = 0
        selection_corners = 0
        targets = nil
        foreach(shape selected
            target = cct_editable_shape(shape)
            when(target && !member(target targets)
                targets = append(targets list(target))
            )
        )
        foreach(target targets
            result = cct_modify_shape(target)
            changed = car(result)
            corner_count = cadr(result)
            reason = caddr(result)
            if(changed then
                selection_changed = selection_changed + 1
                selection_corners = selection_corners + corner_count
            else
                _cct_session_failed = _cct_session_failed + 1
                cct_put_msg(sprintf(nil "Skipped %L: %s." target reason))
            )
        )
        _cct_session_shapes = _cct_session_shapes + selection_changed
        _cct_session_corners = _cct_session_corners + selection_corners
        when(selection_changed > 0
            cct_put_msg(sprintf(nil "Updated %d shape(s), %d corner(s) in this selection."
                selection_changed selection_corners))
        )
    )
)

defun( cct_apply_done ()
    _cct_finished = t
    _cct_commit = t
    axlCancelEnterFun()
)

defun( cct_apply_cancel ()
    _cct_finished = t
    _cct_commit = nil
    axlCancelEnterFun()
)

defun( cct_cmd_apply ()
    let((popup selected error_message saved_enabled saved_on)
        if(_cct_mark then
            cct_put_msg("Finish or cancel the current selection session first.")
        else
            error_message = cct_validate_settings()
            if(error_message then
                cct_put_msg(error_message)
            else
                _cct_finished = nil
                _cct_commit = nil
                _cct_session_shapes = 0
                _cct_session_corners = 0
                _cct_session_failed = 0
                saved_enabled = axlGetFindFilter()
                saved_on = axlGetFindFilter(t)
                axlClearSelSet()
                axlSetFindFilter(
                    ?enabled list("noall" "shapes" "boundary_shapes")
                    ?onButtons list("noall" "shapes")
                )
                _cct_mark = axlDBTransactionStart()
                popup = axlUIPopupDefine(
                    nil
                    list(
                        list("Done" 'cct_apply_done)
                        list("Cancel session" 'cct_apply_cancel)
                    )
                )
                axlUIPopupSet(popup)
                unwindProtect(
                    progn(
                        while(!_cct_finished
                            cct_put_msg(sprintf(nil
                                "Select copper shapes for %s on %s, size %.4f. Right-click Done to commit."
                                cct_operation_name()
                                cct_corner_scope_name()
                                _cct_size))
                            if(axlSelect() && !_cct_finished then
                                selected = axlGetSelSet()
                                when(selected cct_apply_selection(selected))
                                axlClearSelSet()
                            )
                        )
                    )
                    progn(
                        if(_cct_commit then
                            progn(
                                when(_cct_mark axlDBTransactionCommit(_cct_mark))
                                cct_put_msg(sprintf(nil
                                    "Committed %d shape(s), %d corner(s); skipped %d selection(s)."
                                    _cct_session_shapes _cct_session_corners _cct_session_failed))
                            )
                        else
                            progn(
                                when(_cct_mark axlDBTransactionRollback(_cct_mark))
                                cct_put_msg("Session cancelled; all changes from this session were rolled back.")
                            )
                        )
                        _cct_mark = nil
                        axlUIPopupSet(nil)
                        axlClearSelSet()
                        errset(axlSetFindFilter(?enabled saved_enabled ?onButtons saved_on) nil)
                    )
                )
            )
        )
    )
)

defun( cct_form_store (form)
    _cct_size = cct_parse_real(axlFormGetField(form "size") _cct_size)
    _cct_min_angle = cct_parse_real(axlFormGetField(form "min_angle") _cct_min_angle)
    _cct_max_angle = cct_parse_real(axlFormGetField(form "max_angle") _cct_max_angle)
)

defun( cct_form_close (form)
    _cct_form = nil
    errset(axlFormClose(form) nil)
)

defun( cct_form_callback (form)
    let((value error_message)
        if(form->doneState > 0 then
            cct_form_close(form)
        else
            case(form->curField
                ("mode"
                    value = form->curValue
                    when(value _cct_mode = value)
                    axlFormSetField(form "mode" _cct_mode)
                )
                ("corner_scope"
                    value = form->curValue
                    when(value _cct_corner_scope = value)
                    axlFormSetField(form "corner_scope" _cct_corner_scope)
                )
                ("btn_apply"
                    cct_form_store(form)
                    if(_cct_mark then
                        cct_put_msg("Finish or cancel the current selection session first.")
                    else
                        error_message = cct_validate_settings()
                        if(error_message then
                            cct_put_msg(error_message)
                        else
                            axlShellPost("copper_corner_apply")
                        )
                    )
                )
                ("btn_close" cct_form_close(form))
                (t cct_form_store(form))
            )
        )
        t
    )
)

defun( cct_write_form (form_file)
    let((port)
        port = outfile(form_file)
        if(port then
            progn(
                fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\n")
                fprintf(port "FORM\nFIXED\nPORT 64 30\n")
                fprintf(port "HEADER \"Copper Corner Tools v%s\"\n" _cct_version)
                fprintf(port "POPUP <MODEPOP> \"Uniform chamfer\" \"CHAMFER\".\n")
                fprintf(port "POPUP <SCOPEPOP> \"Outer corners\" \"OUTER\".\n")
                fprintf(port "TILE\n")
                fprintf(port "TEXT \"Operation:\"\nTLOC 2 2\nENDTEXT\n")
                fprintf(port "FIELD mode\nFLOC 18 2\nENUMSET 34\nPOP \"MODEPOP\"\nENDFIELD\n")
                fprintf(port "TEXT \"Corner selection:\"\nTLOC 2 6\nENDTEXT\n")
                fprintf(port "FIELD corner_scope\nFLOC 18 6\nENUMSET 34\nPOP \"SCOPEPOP\"\nENDFIELD\n")
                fprintf(port "TEXT \"Uniform setback / radius:\"\nTLOC 2 10\nENDTEXT\n")
                fprintf(port "FIELD size\nFLOC 31 10\nREALFILLIN 12 12\nDECIMAL 4\nENDFIELD\n")
                fprintf(port "TEXT \"Minimum corner angle:\"\nTLOC 2 14\nENDTEXT\n")
                fprintf(port "FIELD min_angle\nFLOC 31 14\nREALFILLIN 12 12\nDECIMAL 2\nENDFIELD\n")
                fprintf(port "TEXT \"Maximum corner angle:\"\nTLOC 2 17\nENDTEXT\n")
                fprintf(port "FIELD max_angle\nFLOC 31 17\nREALFILLIN 12 12\nDECIMAL 2\nENDFIELD\n")
                fprintf(port "TEXT \"Units: %s\"\nTLOC 2 20\nENDTEXT\n" cct_design_units())
                fprintf(port "FIELD btn_apply\nFLOC 2 23\nMENUBUTTON \"Select and apply\" 18 3\nENDFIELD\n")
                fprintf(port "FIELD btn_close\nFLOC 49 23\nMENUBUTTON \"Close\" 10 3\nENDFIELD\n")
                fprintf(port "ENDTILE\nENDFORM\n")
                close(port)
                t
            )
        else
            nil
        )
    )
)

defun( cct_form_initialize (form)
    axlFormBuildPopup(
        form
        "mode"
        list(
            list("Uniform chamfer (modify / add)" "CHAMFER")
            list("Uniform round (modify / add)" "ROUND")
            list("Normalize existing only" "NORMALIZE")
        )
    )
    axlFormBuildPopup(
        form
        "corner_scope"
        list(
            list("Outer corners" "OUTER")
            list("Inner corners" "INNER")
            list("Outer + inner corners" "BOTH")
        )
    )
    axlFormSetField(form "mode" _cct_mode)
    axlFormSetField(form "corner_scope" _cct_corner_scope)
    axlFormSetField(form "size" _cct_size)
    axlFormSetField(form "min_angle" _cct_min_angle)
    axlFormSetField(form "max_angle" _cct_max_angle)
)

defun( cct_open_panel ()
    let((form_file form)
        cct_init_defaults()
        if(_cct_form then
            progn(
                cct_form_initialize(_cct_form)
                axlFormDisplay(_cct_form)
            )
        else
            form_file = axlTempFile(t)
            if(cct_write_form(form_file) then
                progn(
                    form = axlFormCreate(
                        (gensym)
                        form_file
                        list("E" "OUT" "center")
                        'cct_form_callback
                        t
                    )
                    when(isFile(form_file) errset(axlTempFileRemove(form_file) nil))
                    if(form then
                        progn(
                            _cct_form = form
                            cct_form_initialize(form)
                            axlFormDisplay(form)
                        )
                    else
                        cct_put_msg("Unable to create the control panel.")
                    )
                )
            else
                cct_put_msg("Unable to write the temporary form definition.")
            )
        )
    )
)

when(isCallable('axlCmdRegister)
    axlCmdRegister("copper_corner" 'cct_open_panel ?cmdType "general")
    axlCmdRegister("cct" 'cct_open_panel ?cmdType "general")
    axlCmdRegister(
        "copper_corner_apply"
        'cct_cmd_apply
        ?cmdType "interactive"
        ?doneCmd 'cct_apply_done
        ?cancelCmd 'cct_apply_cancel
    )
)
