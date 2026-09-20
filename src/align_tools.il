/*
  Description: Alignment, Distribution and Snap-to-Grid tools
  Notes:
    - Keeps routing attached while moving symbols, vias, pins, groups and text.
    - Integrates the old snap_grid.il behavior into this file.
    - Adds a small launcher panel with buttons, including Snap To Grid.
*/

; --- Global state ---
_alg_finished = nil
_alg_commit = nil
_alg_mark = nil
_alg_find_mem = list("noall" "components" "symbols" "vias" "groups" "text" "pins")
_alg_grid_size = 0.0
_alg_version = "1.0"
_alg_debug_align = nil
_alg_bbox_cache = nil
_alg_last_op = nil
_alg_panel_form = nil
_alg_pending_cmd = nil
_alg_pending_panel_close = nil

_alg_snap_finished = nil
_alg_snap_commit = nil
_alg_snap_mark = nil
_alg_snap_last_op = nil

; --- Command registration ---
axlCmdRegister("moka_al_drag"    'alg_cmd_drag   ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_left"    'alg_cmd_left   ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_right"   'alg_cmd_right  ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_top"     'alg_cmd_top    ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_bottom"  'alg_cmd_bot    ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_hcenter" 'alg_cmd_cx     ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_vcenter" 'alg_cmd_cy     ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_hdist"   'alg_cmd_hdist  ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_vdist"   'alg_cmd_vdist  ?cmdType "interactive" ?doneCmd 'alg_cb_done      ?cancelCmd 'alg_cb_cancel)
axlCmdRegister("moka_al_grid"    'alg_cmd_snap   ?cmdType "interactive" ?doneCmd 'alg_snap_cb_done ?cancelCmd 'alg_snap_cb_cancel)
axlCmdRegister("moka_align"      'alg_cmd_panel  ?cmdType "general")

; --- Common callbacks ---
defun( alg_cb_done ()
    _alg_finished = t
    _alg_commit = t
    axlCancelEnterFun()
)

defun( alg_cb_cancel ()
    _alg_finished = t
    _alg_commit = nil
    axlCancelEnterFun()
)

defun( alg_cb_oops ()
    if(_alg_last_op then
        alg_apply_undo_moves(_alg_last_op)
        alg_last_op_reset()
    else
        if(_alg_mark then
            axlDBTransactionOops(_alg_mark)
        )
    )
    alg_bbox_cache_reset()
    axlClearSelSet()
    axlCancelEnterFun()
)

defun( alg_snap_cb_done ()
    _alg_snap_finished = t
    _alg_snap_commit = t
    axlCancelEnterFun()
)

defun( alg_snap_cb_cancel ()
    _alg_snap_finished = t
    _alg_snap_commit = nil
    axlCancelEnterFun()
)

defun( alg_snap_cb_oops ()
    if(_alg_snap_last_op then
        alg_apply_undo_moves(_alg_snap_last_op)
        alg_snap_last_op_reset()
    else
        if(_alg_snap_mark then
            axlDBTransactionOops(_alg_snap_mark)
        )
    )
    alg_bbox_cache_reset()
    axlClearSelSet()
    axlCancelEnterFun()
)

defun( alg_bbox_cache_reset ()
    _alg_bbox_cache = nil
)

defun( alg_apply_undo_moves (moves)
    let((item target delta)
        foreach(item moves
            target = car(item)
            delta = cadr(item)
            if(target && delta then
                if(car(delta) != 0.0 || cadr(delta) != 0.0 then
                    alg_move_object(target delta)
                )
            )
        )
    )
)

defun( alg_last_op_reset ()
    _alg_last_op = nil
)

defun( alg_snap_last_op_reset ()
    _alg_snap_last_op = nil
)

defun( alg_run_pending_cmd ()
    let((next_cmd)
        next_cmd = _alg_pending_cmd
        _alg_pending_cmd = nil
        when(next_cmd
            axlShellPost(next_cmd)
        )
    )
)

defun( alg_put_msg (msg)
    axlMsgPut(sprintf(nil "Moka skill: %s" msg))
)

defun( alg_run_pending_panel_close ()
    when(_alg_pending_panel_close
        _alg_pending_panel_close = nil
        when(_alg_panel_form
            errset(axlFormClose(_alg_panel_form) nil)
            _alg_panel_form = nil
        )
    )
)

defun( alg_panel_launch_cmd (next_cmd)
    if(!next_cmd then
        nil
    else
        if(_alg_snap_mark then
            _alg_pending_cmd = next_cmd
            _alg_snap_finished = t
            _alg_snap_commit = t
            axlCancelEnterFun()
        else
            if(_alg_mark then
                _alg_pending_cmd = next_cmd
                _alg_finished = t
                _alg_commit = t
                axlCancelEnterFun()
            else
                axlShellPost(next_cmd)
            )
        )
    )
)

defun( alg_panel_request_close (form)
    _alg_pending_cmd = nil
    if(_alg_snap_mark then
        _alg_pending_panel_close = t
        _alg_snap_finished = t
        _alg_snap_commit = t
        axlCancelEnterFun()
    else
        if(_alg_mark then
            _alg_pending_panel_close = t
            _alg_finished = t
            _alg_commit = t
            axlCancelEnterFun()
        else
            _alg_panel_form = nil
            errset(axlFormClose(form) nil)
        )
    )
)

; --- Utility helpers ---
defun( alg_parse_real (value default_value)
    let((result)
        result = default_value
        if(numberp(value) then
            result = value
        else
            if(stringp(value) && strlen(value) > 0 then
                result = atof(value)
            )
        )
        result
    )
)

defun( alg_round_to_grid (value grid)
    round(value / grid) * grid
)

defun( alg_tol ()
    let((tol)
        tol = 0.001
        if(_alg_grid_size && _alg_grid_size > 0.0 then
            tol = _alg_grid_size / 1000.0
            if(tol < 0.001 then
                tol = 0.001
            )
        )
        tol
    )
)

defun( alg_zero_small (value)
    if(abs(value) < alg_tol() then
        0.0
    else
        value
    )
)

defun( alg_debug_log (msg)
    when(_alg_debug_align
        axlMsgPut(msg)
    )
)

when(_alg_debug_align
    axlMsgPut("Moka skill: Align debug enabled.")
)

defun( alg_target_label (target)
    let((x y)
        x = 0.0
        y = 0.0
        if(target->xy then
            x = car(target->xy)
            y = cadr(target->xy)
        )
        sprintf(nil "%s@%.3f,%.3f" target->objType x y)
    )
)

defun( alg_mode_name (mode)
    let((name)
        name = "align"
        if(mode == 'left then name = "left")
        if(mode == 'right then name = "right")
        if(mode == 'top then name = "top")
        if(mode == 'bottom then name = "bottom")
        if(mode == 'center_x then name = "center_x")
        if(mode == 'center_y then name = "center_y")
        name
    )
)

defun( alg_snap_origin_delta_to_grid (obj dx dy)
    let((new_x new_y)
        if(_alg_grid_size && _alg_grid_size > 0.0 then
            if(obj->xy then
                new_x = alg_round_to_grid(car(obj->xy) + dx _alg_grid_size)
                new_y = alg_round_to_grid(cadr(obj->xy) + dy _alg_grid_size)
                dx = new_x - car(obj->xy)
                dy = new_y - cadr(obj->xy)
            else
                dx = alg_round_to_grid(dx _alg_grid_size)
                dy = alg_round_to_grid(dy _alg_grid_size)
            )
        )
        list(dx dy)
    )
)

defun( alg_grid_tol ()
    let((tol)
        tol = 0.000000001
        if(_alg_grid_size && _alg_grid_size > 0.0 then
            tol = _alg_grid_size / 1000000.0
            if(tol < 0.000000001 then
                tol = 0.000000001
            )
        )
        tol
    )
)

defun( alg_value_is_on_grid (value)
    if(!_alg_grid_size || _alg_grid_size <= 0.0 then
        t
    else
        abs(value - alg_round_to_grid(value _alg_grid_size)) <= alg_grid_tol()
    )
)

defun( alg_target_origin_is_on_grid (target)
    if(!_alg_grid_size || _alg_grid_size <= 0.0 || !target->xy then
        t
    else
        alg_value_is_on_grid(car(target->xy)) && alg_value_is_on_grid(cadr(target->xy))
    )
)

defun( alg_last_item (items)
    let((last_one)
        last_one = nil
        foreach(item items
            last_one = item
        )
        last_one
    )
)

defun( alg_bbox_metric (box mode)
    let((minX maxX minY maxY)
        minX = car(car(box))
        maxX = car(cadr(box))
        minY = cadr(car(box))
        maxY = cadr(cadr(box))
        if(mode == 'left then
            minX
        else
            if(mode == 'right then
                maxX
            else
                if(mode == 'bottom then
                    minY
                else
                    if(mode == 'top then
                        maxY
                    else
                        if(mode == 'center_x then
                            (minX + maxX) / 2.0
                        else
                            (minY + maxY) / 2.0
                        )
                    )
                )
            )
        )
    )
)

defun( alg_is_aligned (objs mode)
    let((first_val box value aligned)
        aligned = t
        first_val = nil
        foreach(obj objs
            box = alg_get_bbox(obj)
            if(box then
                value = alg_bbox_metric(box mode)
                if(first_val == nil then
                    first_val = value
                else
                    if(abs(value - first_val) > alg_tol() then
                        aligned = nil
                    )
                )
            )
        )
        aligned
    )
)

defun( alg_bbox_union (boxes)
    let((minX maxX minY maxY box)
        minX = 1000000.0
        maxX = -1000000.0
        minY = 1000000.0
        maxY = -1000000.0
        foreach(box boxes
            if(box then
                if(car(car(box)) < minX then minX = car(car(box)))
                if(car(cadr(box)) > maxX then maxX = car(cadr(box)))
                if(cadr(car(box)) < minY then minY = cadr(car(box)))
                if(cadr(cadr(box)) > maxY then maxY = cadr(cadr(box)))
            )
        )
        if(minX != 1000000.0 then
            list(minX:minY maxX:maxY)
        else
            nil
        )
    )
)

defun( alg_translate_box (box dx dy)
    if(box then
        list(
            (car(car(box)) + dx):(cadr(car(box)) + dy)
            (car(cadr(box)) + dx):(cadr(cadr(box)) + dy)
        )
    else
        nil
    )
)

defun( alg_copy_point (pt)
    if(pt then
        car(pt):cadr(pt)
    else
        nil
    )
)

defun( alg_copy_box (box)
    if(box then
        list(
            alg_copy_point(car(box))
            alg_copy_point(cadr(box))
        )
    else
        nil
    )
)

defun( alg_same_box (box1 box2)
    if(!box1 || !box2 then
        nil
    else
        if(!alg_same_point(car(box1) car(box2)) then
            nil
        else
            alg_same_point(cadr(box1) cadr(box2))
        )
    )
)

defun( alg_same_point (p1 p2)
    if(!p1 || !p2 then
        nil
    else
        if(abs(car(p1) - car(p2)) > alg_tol() then
            nil
        else
            abs(cadr(p1) - cadr(p2)) <= alg_tol()
        )
    )
)

defun( alg_bbox_cache_find (target)
    let((entry found xy target_type)
        found = nil
        xy = if(target && target->xy then target->xy else nil)
        target_type = if(target && target->objType then target->objType else "")
        foreach(entry _alg_bbox_cache
            if(car(entry) == target then
                found = entry
            )
        )
        if(!found && target && xy then
            foreach(entry _alg_bbox_cache
                if(
                    cadr(entry) == target_type &&
                    alg_same_point(caddr(entry) xy)
                then
                    found = entry
                )
            )
            when(found && _alg_debug_align
                alg_debug_log(sprintf(nil "[ALG-DEBUG]   bbox-cache-xy-hit %s" alg_target_label(target)))
            )
        )
        found
    )
)

defun( alg_bbox_cache_put (target xy box raw_box)
    let((entry kept target_type)
        kept = nil
        target_type = if(target && target->objType then target->objType else "")
        foreach(entry _alg_bbox_cache
            if(
                car(entry) != target &&
                !(cadr(entry) == target_type && alg_same_point(caddr(entry) xy))
            then
                kept = cons(entry kept)
            )
        )
        _alg_bbox_cache = cons(
            list(
                target
                target_type
                alg_copy_point(xy)
                alg_copy_box(box)
                alg_copy_box(raw_box)
            )
            reverse(kept)
        )
        box
    )
)

defun( alg_bbox_origin_delta (prev_xy curr_xy)
    let((dx dy)
        dx = 0.0
        dy = 0.0
        if(prev_xy && curr_xy then
            dx = car(curr_xy) - car(prev_xy)
            dy = cadr(curr_xy) - cadr(prev_xy)
        )
        list(dx dy)
    )
)

defun( alg_bbox_shift_matches_origin (prev_raw raw_box origin_delta)
    let((dx dy raw_dx1 raw_dy1 raw_dx2 raw_dy2)
        if(!prev_raw || !raw_box then
            t
        else
            dx = car(origin_delta)
            dy = cadr(origin_delta)
            raw_dx1 = car(car(raw_box)) - car(car(prev_raw))
            raw_dy1 = cadr(car(raw_box)) - cadr(car(prev_raw))
            raw_dx2 = car(cadr(raw_box)) - car(cadr(prev_raw))
            raw_dy2 = cadr(cadr(raw_box)) - cadr(cadr(prev_raw))
            if(abs(raw_dx1 - dx) > alg_tol() then
                nil
            else
                if(abs(raw_dy1 - dy) > alg_tol() then
                    nil
                else
                    if(abs(raw_dx2 - dx) > alg_tol() then
                        nil
                    else
                        abs(raw_dy2 - dy) <= alg_tol()
                    )
                )
            )
        )
    )
)

defun( alg_bbox_from_cache_or_raw (target raw_box)
    let((xy entry prev_xy prev_box prev_raw origin_delta fixed_box expected_box expected_raw)
        xy = if(target && target->xy then target->xy else nil)
        if(!target || !xy || !raw_box then
            raw_box
        else
            entry = alg_bbox_cache_find(target)
            fixed_box = raw_box
            if(entry then
                prev_xy = nth(2 entry)
                prev_box = nth(3 entry)
                prev_raw = nth(4 entry)
                origin_delta = alg_bbox_origin_delta(prev_xy xy)
                expected_box = alg_translate_box(prev_box car(origin_delta) cadr(origin_delta))
                expected_raw = alg_translate_box(prev_raw car(origin_delta) cadr(origin_delta))
                if(alg_same_box(raw_box expected_box) then
                    fixed_box = raw_box
                else
                    if(alg_same_box(raw_box expected_raw) then
                        if(alg_same_box(prev_box prev_raw) then
                            fixed_box = raw_box
                        else
                            fixed_box = expected_box
                        )
                    else
                        fixed_box = expected_box
                    )
                )
                if(!alg_same_box(fixed_box raw_box) then
                    when(_alg_debug_align
                        alg_debug_log(
                            sprintf(
                                nil
                                "[ALG-DEBUG]   bbox-corrected %s dx=%.6f dy=%.6f"
                                alg_target_label(target)
                                car(origin_delta)
                                cadr(origin_delta)
                            )
                        )
                    )
                )
            )
            alg_bbox_cache_put(target xy fixed_box raw_box)
        )
    )
)

defun( alg_symbol_layer_bbox (children layer_name)
    let((boxes)
        boxes = nil
        foreach(child children
            if(child->objType == "shape" && child->layer == layer_name && child->bBox then
                boxes = cons(child->bBox boxes)
            )
        )
        alg_bbox_union(boxes)
    )
)

defun( alg_highlight_all (objs)
    let((targets)
        targets = nil
        foreach(obj objs
            if(obj->objType == "pin" && obj->parent then
                targets = cons(obj->parent targets)
            else
                targets = cons(obj targets)
            )
        )
        axlAddSelectObject(targets)
        errset(axlVisibleUpdate(t) t)
    )
)

defun( alg_pause_briefly ()
    errset(axlShell("powershell -NoProfile -Command \"Start-Sleep -Milliseconds 250\"") t)
)

defun( alg_highlight_briefly (objs)
    axlClearSelSet()
    alg_highlight_all(objs)
    alg_pause_briefly()
)

; --- Selection extraction ---
defun( alg_align_filter_buttons ()
    list("noall" "components" "symbols" "vias" "groups" "text" "pins" "clines")
)

defun( alg_is_pathlike_obj (obj)
    obj && (obj->segments || obj->objType == "line" || obj->objType == "path")
)

defun( alg_normalize_pathlike_target (obj)
    let((parent target)
        parent = if(obj then obj->parent else nil)
        target = nil
        if(alg_is_pathlike_obj(obj) then
            target = obj
        else
            if(parent && alg_is_pathlike_obj(parent) then
                target = parent
            else
                if(obj && obj->startEnd then
                    target = obj
                )
            )
        )
        target
    )
)

defun( alg_normalize_align_target (obj)
    let((target)
        target = nil
        case(obj->objType
            ("component"
                if(obj->symbol && obj->symbol->xy then
                    target = obj->symbol
                )
            )
            ("symbol"
                if(obj->xy then
                    target = obj
                )
            )
            ("pin"
                if(obj->parent then
                    target = obj->parent
                else
                    if(obj->xy then
                        target = obj
                    )
                )
            )
            ("via"
                if(obj->xy then
                    target = obj
                )
            )
            ("group"
                if(obj->groupMembers then
                    target = obj
                )
            )
            ("text"
                if(obj->xy then
                    target = obj
                )
            )
        )
        if(!target then
            target = alg_normalize_pathlike_target(obj)
        )
        target
    )
)

defun( alg_target_is_movable (target)
    let((fixed)
        fixed = nil
        if(target then
            fixed = axlDBIsFixed(target nil)
        )
        target && !fixed
    )
)

defun( alg_extract_real (all_sel)
    let((targets target)
        targets = nil
        foreach(obj all_sel
            target = alg_normalize_align_target(obj)
            if(alg_target_is_movable(target) && !memq(target targets) then
                targets = cons(target targets)
            )
        )
        reverse(targets)
    )
)

defun( alg_extract_snap_objects (all_sel)
    let((real_objs unique_objs)
        real_objs = nil
        unique_objs = nil

        foreach(obj all_sel
            if(!axlDBIsFixed(obj nil) then
                case(obj->objType
                    ("group" if(obj->groupMembers then real_objs = cons(obj real_objs)))
                    ("via"   if(obj->xy then real_objs = cons(obj real_objs)))
                    ("symbol" if(obj->xy then real_objs = cons(obj real_objs)))
                    ("component"
                        if(obj->symbol && obj->symbol->xy then
                            real_objs = cons(obj->symbol real_objs)
                        )
                    )
                    ("text" if(obj->xy then real_objs = cons(obj real_objs)))
                )
            )
        )

        foreach(obj real_objs
            if(!memq(obj unique_objs) then
                unique_objs = cons(obj unique_objs)
            )
        )
        unique_objs
    )
)

defun( alg_get_selected ()
    let((all_sel current_checked)
        all_sel = axlGetSelSet()
        if(!all_sel then
            axlClearSelSet()
            axlSetFindFilter(?enabled alg_align_filter_buttons() ?onButtons _alg_find_mem)
            axlSelect()
            all_sel = axlGetSelSet()

            current_checked = axlGetFindFilter(t)
            if(current_checked then
                _alg_find_mem = current_checked
            )
        )
        alg_extract_real(all_sel)
    )
)

; --- Geometry helpers ---
defun( alg_get_bbox (object)
    let((objectChildren child dfaLayer placeLayer result minX maxX minY maxY box pin_box)
        case(object->objType
            ("group"
                minX = 1000000.0
                maxX = -1000000.0
                minY = 1000000.0
                maxY = -1000000.0
                foreach(member object->groupMembers
                    box = alg_get_bbox(member)
                    if(box then
                        if(car(car(box)) < minX then minX = car(car(box)))
                        if(car(cadr(box)) > maxX then maxX = car(cadr(box)))
                        if(cadr(car(box)) < minY then minY = cadr(car(box)))
                        if(cadr(cadr(box)) > maxY then maxY = cadr(cadr(box)))
                    )
                )
                if(minX != 1000000.0 then
                    result = list(minX:minY maxX:maxY)
                else
                    result = nil
                )
            )
            ("via" result = if(object->bBox then object->bBox else list(object->xy object->xy)))
            ("pin" result = if(object->bBox then object->bBox else list(object->xy object->xy)))
            ("text" result = if(object->bBox then object->bBox else list(object->xy object->xy)))
            ("symbol"
                if(object->isMirrored then
                    dfaLayer = "PACKAGE GEOMETRY/DFA_BOUND_BOTTOM"
                    placeLayer = "PACKAGE GEOMETRY/PLACE_BOUND_BOTTOM"
                else
                    dfaLayer = "PACKAGE GEOMETRY/DFA_BOUND_TOP"
                    placeLayer = "PACKAGE GEOMETRY/PLACE_BOUND_TOP"
                )
                objectChildren = object->children
                if(objectChildren then
                    result = alg_symbol_layer_bbox(objectChildren dfaLayer)

                    if(!result then
                        result = alg_symbol_layer_bbox(objectChildren placeLayer)
                    )
                )
                if(!result && object->pins then
                    minX = 1000000.0
                    maxX = -1000000.0
                    minY = 1000000.0
                    maxY = -1000000.0
                    foreach(pin object->pins
                        pin_box = if(pin->bBox then
                            pin->bBox
                        else
                            if(pin->xy then
                                list(pin->xy pin->xy)
                            else
                                nil
                            )
                        )
                        if(pin_box then
                            if(car(car(pin_box)) < minX then minX = car(car(pin_box)))
                            if(car(cadr(pin_box)) > maxX then maxX = car(cadr(pin_box)))
                            if(cadr(car(pin_box)) < minY then minY = cadr(car(pin_box)))
                            if(cadr(cadr(pin_box)) > maxY then maxY = cadr(cadr(pin_box)))
                        )
                    )
                    if(minX != 1000000.0 then
                        result = list(minX:minY maxX:maxY)
                    )
                )
                if(!result then result = object->bBox)
            )
        )
        result
    )
)

defun( alg_get_all_pins (obj)
    let((pins)
        pins = nil
        case(obj->objType
            ("pin" pins = list(obj))
            ("via" pins = list(obj))
            ("symbol" pins = obj->pins)
            ("component" if(obj->symbol then pins = obj->symbol->pins))
            ("group"
                foreach(mem obj->groupMembers
                    foreach(p alg_get_all_pins(mem)
                        pins = cons(p pins)
                    )
                )
            )
        )
        pins
    )
)

; --- Movement core ---
defun( alg_move_object (object deltaPoint)
    let((pinList pinXY paths isVia segments startEnd newStartEnd segmentsToCreate segmentsToRemove segmentToCreate x1 y1 x2 y2 net target_move)
        if(car(deltaPoint) != 0.0 || cadr(deltaPoint) != 0.0 then
            if(object->objType == "pin" && object->parent then
                target_move = object->parent
            else
                if(object->objType == "component" && object->symbol then
                    target_move = object->symbol
                else
                    target_move = object
                )
            )

            pinList = alg_get_all_pins(target_move)
            if(target_move->objType == "via" then isVia = t)

            foreach(pin pinList
                pinXY = pin->xy
                paths = axlDBGetConnect(pin nil)
                if(paths then
                    foreach(path paths
                        segments = path->segments
                        foreach(segment segments
                            startEnd = segment->startEnd
                            newStartEnd = nil
                            if(equal(car(startEnd) pinXY) then
                                x1 = car(car(startEnd)) + car(deltaPoint)
                                y1 = cadr(car(startEnd)) + cadr(deltaPoint)
                                x2 = car(cadr(startEnd))
                                y2 = cadr(cadr(startEnd))
                                newStartEnd = list(x1:y1 x2:y2)
                            else
                                if(equal(cadr(startEnd) pinXY) then
                                    x1 = car(car(startEnd))
                                    y1 = cadr(car(startEnd))
                                    x2 = car(cadr(startEnd)) + car(deltaPoint)
                                    y2 = cadr(cadr(startEnd)) + cadr(deltaPoint)
                                    newStartEnd = list(x1:y1 x2:y2)
                                )
                            )
                            if(newStartEnd then
                                segmentsToRemove = cons(segment segmentsToRemove)
                                segmentToCreate = ncons(t)
                                segmentToCreate->startEnd = newStartEnd
                                segmentToCreate->width = segment->width
                                segmentToCreate->layer = segment->layer
                                if(segment->net then
                                    segmentToCreate->netname = segment->net->name
                                else
                                    segmentToCreate->netname = ""
                                )
                                segmentsToCreate = cons(segmentToCreate segmentsToCreate)
                            )
                        )
                    )
                )
            )

            if(segmentsToRemove then
                foreach(segment segmentsToRemove
                    axlDeleteObject(segment)
                )
            )

            axlTransformObject(target_move ?move deltaPoint)

            when(isVia
                if(segmentsToCreate then net = car(segmentsToCreate)->netname else net = nil)
                when(net axlDBAssignNet(target_move net))
            )

            if(segmentsToCreate then
                foreach(segment segmentsToCreate
                    axlDBCreateLine(segment->startEnd segment->width segment->layer segment->netname nil)
                )
            )
        )
        t
    )
)

; --- Align core ---
defun( alg_align_core (objs mode)
    let((target_val box dx dy obj obj_box_alist minX maxX minY maxY cx cy reference_edge)
        if(mode == 'left || mode == 'center_x then reference_edge = 1000000.0)
        if(mode == 'right then reference_edge = -1000000.0)
        if(mode == 'bottom || mode == 'center_y then reference_edge = 1000000.0)
        if(mode == 'top then reference_edge = -1000000.0)

        foreach(obj objs
            box = alg_get_bbox(obj)
            if(box then
                obj_box_alist = cons(list(obj box) obj_box_alist)

                minX = car(car(box))
                maxX = car(cadr(box))
                minY = cadr(car(box))
                maxY = cadr(cadr(box))
                cx = (minX + maxX) / 2.0
                cy = (minY + maxY) / 2.0

                if(mode == 'left && minX < reference_edge then reference_edge = minX target_val = minX)
                if(mode == 'right && maxX > reference_edge then reference_edge = maxX target_val = maxX)
                if(mode == 'bottom && minY < reference_edge then reference_edge = minY target_val = minY)
                if(mode == 'top && maxY > reference_edge then reference_edge = maxY target_val = maxY)
                if(mode == 'center_x && minX < reference_edge then reference_edge = minX target_val = cx)
                if(mode == 'center_y && minY < reference_edge then reference_edge = minY target_val = cy)
            )
        )

        if(_alg_grid_size && _alg_grid_size > 0.0 then
            target_val = alg_round_to_grid(target_val _alg_grid_size)
        )

        foreach(item obj_box_alist
            obj = car(item)
            box = cadr(item)
            minX = car(car(box))
            maxX = car(cadr(box))
            minY = cadr(car(box))
            maxY = cadr(cadr(box))
            cx = (minX + maxX) / 2.0
            cy = (minY + maxY) / 2.0

            dx = 0.0
            dy = 0.0
            if(mode == 'left then dx = target_val - minX)
            if(mode == 'right then dx = target_val - maxX)
            if(mode == 'bottom then dy = target_val - minY)
            if(mode == 'top then dy = target_val - maxY)
            if(mode == 'center_x then dx = target_val - cx)
            if(mode == 'center_y then dy = target_val - cy)
            dx = alg_zero_small(dx)
            dy = alg_zero_small(dy)

            if(dx != 0.0 || dy != 0.0 then
                alg_move_object(obj list(dx dy))
            )
        )
    )
)

; --- Distribution core ---
defun( alg_entry_center (entry axis)
    if(axis == 'horiz then
        caddr(entry)
    else
        car(cdddr(entry))
    )
)

defun( alg_insert_entry_sorted (entry sorted axis)
    if(!sorted then
        list(entry)
    else
        if(alg_entry_center(entry axis) <= alg_entry_center(car(sorted) axis) then
            cons(entry sorted)
        else
            cons(car(sorted) alg_insert_entry_sorted(entry cdr(sorted) axis))
        )
    )
)

defun( alg_sort_entries (entries axis)
    let((sorted)
        sorted = nil
        foreach(entry entries
            sorted = alg_insert_entry_sorted(entry sorted axis)
        )
        sorted
    )
)

defun( alg_distribute_core (objs axis)
    let((entries sorted entry first_entry last_entry count first_center last_center step idx obj box dx dy target_center center_x center_y)
        entries = nil
        foreach(obj objs
            box = alg_get_bbox(obj)
            if(box then
                center_x = (car(car(box)) + car(cadr(box))) / 2.0
                center_y = (cadr(car(box)) + cadr(cadr(box))) / 2.0
                entries = cons(list(obj box center_x center_y) entries)
            )
        )

        count = length(entries)
        if(count < 3 then
            nil
        else
            sorted = alg_sort_entries(entries axis)
            first_entry = car(sorted)
            last_entry = alg_last_item(sorted)
            first_center = alg_entry_center(first_entry axis)
            last_center = alg_entry_center(last_entry axis)
            step = (last_center - first_center) / (count - 1)
            idx = 0
            foreach(entry sorted
                obj = car(entry)
                dx = 0.0
                dy = 0.0
                target_center = first_center + step * idx
                if(_alg_grid_size && _alg_grid_size > 0.0 then
                    target_center = alg_round_to_grid(target_center _alg_grid_size)
                )
                if(axis == 'horiz then
                    dx = target_center - caddr(entry)
                else
                    dy = target_center - car(cdddr(entry))
                )
                dx = alg_zero_small(dx)
                dy = alg_zero_small(dy)
                if(dx != 0.0 || dy != 0.0 then
                    alg_move_object(obj list(dx dy))
                )
                idx = idx + 1
            )
            t
        )
    )
)

; --- V2 core: clean-room target normalization and deterministic geometry ---
defun( alg_v2_normalize_target (obj)
    let((target parent)
        target = nil
        parent = nil
        case(obj->objType
            ("component"
                if(obj->symbol && obj->symbol->xy then
                    target = obj->symbol
                )
            )
            ("symbol"
                if(obj->xy then
                    target = obj
                )
            )
            ("pin"
                parent = obj->parent
                if(parent then
                    if(parent->objType == "component" && parent->symbol && parent->symbol->xy then
                        target = parent->symbol
                    else
                        if(parent->xy then
                            target = parent
                        )
                    )
                else
                    if(obj->xy then
                        target = obj
                    )
                )
            )
            ("via"
                if(obj->xy then
                    target = obj
                )
            )
            ("group"
                if(obj->groupMembers then
                    target = obj
                )
            )
            ("text"
                if(obj->xy then
                    target = obj
                )
            )
        )
        if(!target then
            target = alg_normalize_pathlike_target(obj)
        )
        target
    )
)

defun( alg_v2_target_movable (target)
    target && !axlDBIsFixed(target nil)
)

defun( alg_v2_targets_from_selection (all_sel)
    let((targets target)
        targets = nil
        foreach(obj all_sel
            target = alg_v2_normalize_target(obj)
            if(alg_v2_target_movable(target) && !memq(target targets) then
                targets = cons(target targets)
            )
        )
        reverse(targets)
    )
)

defun( alg_v2_symbol_pin_bbox (symbol)
    let((boxes pin pin_box)
        boxes = nil
        if(symbol->pins then
            foreach(pin symbol->pins
                pin_box = if(pin->bBox then
                    pin->bBox
                else
                    if(pin->xy then
                        list(pin->xy pin->xy)
                    else
                        nil
                    )
                )
                if(pin_box then
                    boxes = cons(pin_box boxes)
                )
            )
        )
        alg_bbox_union(boxes)
    )
)

defun( alg_v2_symbol_shape_bbox (symbol)
    let((top_bbox bot_bbox dfa_top dfa_bot place_top place_bot)
        dfa_top = alg_symbol_layer_bbox(symbol->children "PACKAGE GEOMETRY/DFA_BOUND_TOP")
        dfa_bot = alg_symbol_layer_bbox(symbol->children "PACKAGE GEOMETRY/DFA_BOUND_BOTTOM")
        place_top = alg_symbol_layer_bbox(symbol->children "PACKAGE GEOMETRY/PLACE_BOUND_TOP")
        place_bot = alg_symbol_layer_bbox(symbol->children "PACKAGE GEOMETRY/PLACE_BOUND_BOTTOM")
        top_bbox = if(dfa_top then dfa_top else place_top)
        bot_bbox = if(dfa_bot then dfa_bot else place_bot)
        if(symbol->isMirrored then
            bot_bbox
        else
            top_bbox
        )
    )
)

defun( alg_v2_group_bbox (group)
    let((boxes member box)
        boxes = nil
        foreach(member group->groupMembers
            box = alg_v2_target_bbox(member)
            if(box then
                boxes = cons(box boxes)
            )
        )
        alg_bbox_union(boxes)
    )
)

defun( alg_v2_target_bbox (target)
    let((box)
        box = nil
        case(target->objType
            ("group" box = alg_v2_group_bbox(target))
            ("symbol"
                box = alg_v2_symbol_pin_bbox(target)
                if(!box then
                    box = alg_v2_symbol_shape_bbox(target)
                )
                if(!box then
                    box = target->bBox
                )
            )
            ("via" box = if(target->bBox then target->bBox else list(target->xy target->xy)))
            ("pin" box = if(target->bBox then target->bBox else list(target->xy target->xy)))
            ("text" box = if(target->bBox then target->bBox else list(target->xy target->xy)))
            ("line" box = target->bBox)
            ("path" box = target->bBox)
        )
        alg_bbox_from_cache_or_raw(target box)
    )
)

defun( alg_v2_collect_records (targets)
    let((records target box idx)
        records = nil
        idx = 0
        foreach(target targets
            box = alg_v2_target_bbox(target)
            if(box then
                records = cons(list(target box idx) records)
                idx = idx + 1
            )
        )
        reverse(records)
    )
)

defun( alg_v2_record_metric (record mode)
    alg_bbox_metric(cadr(record) mode)
)

defun( alg_v2_record_seq (record)
    caddr(record)
)

defun( alg_v2_record_before (left right mode)
    let((lv rv)
        lv = alg_v2_record_metric(left mode)
        rv = alg_v2_record_metric(right mode)
        if(lv < rv then
            t
        else
            if(lv > rv then
                nil
            else
                alg_v2_record_seq(left) < alg_v2_record_seq(right)
            )
        )
    )
)

defun( alg_v2_insert_record_sorted (record sorted mode)
    if(!sorted then
        list(record)
    else
        if(alg_v2_record_before(record car(sorted) mode) then
            cons(record sorted)
        else
            cons(car(sorted) alg_v2_insert_record_sorted(record cdr(sorted) mode))
        )
    )
)

defun( alg_v2_sort_records (records mode)
    let((sorted)
        sorted = nil
        foreach(record records
            sorted = alg_v2_insert_record_sorted(record sorted mode)
        )
        sorted
    )
)

defun( alg_v2_target_metric (records mode)
    let((sorted ref_record target_val)
        sorted = alg_v2_sort_records(records mode)
        if(!sorted then
            nil
        else
            if(mode == 'left || mode == 'bottom || mode == 'center_x || mode == 'center_y then
                ref_record = car(sorted)
            else
                ref_record = alg_last_item(sorted)
            )
            target_val = alg_v2_record_metric(ref_record mode)
            if(_alg_grid_size && _alg_grid_size > 0.0 then
                target_val = alg_round_to_grid(target_val _alg_grid_size)
            )
            target_val
        )
    )
)

defun( alg_v2_debug_dump (stage records mode)
    let((target_val record target box metric)
        when(_alg_debug_align
            target_val = alg_v2_target_metric(records mode)
            alg_debug_log(sprintf(nil "[ALG-DEBUG] %s mode=%s target=%.6f count=%d" stage alg_mode_name(mode) target_val length(records)))
            foreach(record records
                target = car(record)
                box = cadr(record)
                metric = alg_v2_record_metric(record mode)
                alg_debug_log(
                    sprintf(
                        nil
                        "[ALG-DEBUG]   %s metric=%.6f box=(%.6f,%.6f)-(%.6f,%.6f)"
                        alg_target_label(target)
                        metric
                        car(car(box))
                        cadr(car(box))
                        car(cadr(box))
                        cadr(cadr(box))
                    )
                )
            )
        )
    )
)

defun( alg_v2_is_aligned_records (records mode)
    let((target_val aligned)
        aligned = t
        target_val = alg_v2_target_metric(records mode)
        alg_v2_debug_dump("is-aligned" records mode)
        foreach(record records
            if(abs(alg_v2_record_metric(record mode) - target_val) > alg_tol() || !alg_target_origin_is_on_grid(car(record)) then
                aligned = nil
            )
        )
        aligned
    )
)

defun( alg_v2_is_aligned (targets mode)
    alg_v2_is_aligned_records(alg_v2_collect_records(targets) mode)
)

defun( alg_v2_is_aligned_to_value (targets mode target_val)
    let((records aligned)
        records = alg_v2_collect_records(targets)
        aligned = t
        when(_alg_debug_align
            alg_debug_log(sprintf(nil "[ALG-DEBUG] is-aligned mode=%s target=%.6f count=%d" alg_mode_name(mode) target_val length(records)))
        )
        foreach(record records
            when(_alg_debug_align
                alg_debug_log(
                    sprintf(
                        nil
                        "[ALG-DEBUG]   %s metric=%.6f box=(%.6f,%.6f)-(%.6f,%.6f)"
                        alg_target_label(car(record))
                        alg_v2_record_metric(record mode)
                        car(car(cadr(record)))
                        cadr(car(cadr(record)))
                        car(cadr(cadr(record)))
                        cadr(cadr(cadr(record)))
                    )
                )
            )
            if(abs(alg_v2_record_metric(record mode) - target_val) > alg_tol() || !alg_target_origin_is_on_grid(car(record)) then
                aligned = nil
            )
        )
        aligned
    )
)

defun( alg_v2_align_targets_to_value (targets mode target_val)
    let((records record target box dx dy snapped_delta undo_moves)
        records = alg_v2_collect_records(targets)
        undo_moves = nil
        when(_alg_debug_align
            alg_debug_log(sprintf(nil "[ALG-DEBUG] before-align mode=%s target=%.6f count=%d" alg_mode_name(mode) target_val length(records)))
            foreach(record records
                alg_debug_log(
                    sprintf(
                        nil
                        "[ALG-DEBUG]   %s metric=%.6f box=(%.6f,%.6f)-(%.6f,%.6f)"
                        alg_target_label(car(record))
                        alg_v2_record_metric(record mode)
                        car(car(cadr(record)))
                        cadr(car(cadr(record)))
                        car(cadr(cadr(record)))
                        cadr(cadr(cadr(record)))
                    )
                )
            )
        )
        foreach(record records
            target = car(record)
            box = cadr(record)
            dx = 0.0
            dy = 0.0
            if(mode == 'left then dx = target_val - car(car(box)))
            if(mode == 'right then dx = target_val - car(cadr(box)))
            if(mode == 'bottom then dy = target_val - cadr(car(box)))
            if(mode == 'top then dy = target_val - cadr(cadr(box)))
            if(mode == 'center_x then dx = target_val - ((car(car(box)) + car(cadr(box))) / 2.0))
            if(mode == 'center_y then dy = target_val - ((cadr(car(box)) + cadr(cadr(box))) / 2.0))
            if(_alg_grid_size && _alg_grid_size > 0.0 then
                snapped_delta = alg_snap_origin_delta_to_grid(target dx dy)
                dx = car(snapped_delta)
                dy = cadr(snapped_delta)
            else
                dx = alg_zero_small(dx)
                dy = alg_zero_small(dy)
            )
            when(_alg_debug_align
                alg_debug_log(sprintf(nil "[ALG-DEBUG]   move %s dx=%.6f dy=%.6f" alg_target_label(target) dx dy))
            )
            if(dx != 0.0 || dy != 0.0 then
                alg_move_object(target list(dx dy))
                undo_moves = cons(list(target list(-dx -dy)) undo_moves)
            )
        )
        _alg_last_op = reverse(undo_moves)
        when(_alg_debug_align
            records = alg_v2_collect_records(targets)
            alg_debug_log(sprintf(nil "[ALG-DEBUG] after-align mode=%s target=%.6f count=%d" alg_mode_name(mode) target_val length(records)))
            foreach(record records
                alg_debug_log(
                    sprintf(
                        nil
                        "[ALG-DEBUG]   %s metric=%.6f box=(%.6f,%.6f)-(%.6f,%.6f)"
                        alg_target_label(car(record))
                        alg_v2_record_metric(record mode)
                        car(car(cadr(record)))
                        cadr(car(cadr(record)))
                        car(cadr(cadr(record)))
                        cadr(cadr(cadr(record)))
                    )
                )
            )
        )
        t
    )
)

defun( alg_v2_align_targets (targets mode)
    let((records target_val)
        records = alg_v2_collect_records(targets)
        target_val = alg_v2_target_metric(records mode)
        alg_v2_align_targets_to_value(targets mode target_val)
    )
)

defun( alg_v2_distribute_targets (targets axis)
    let((mode records sorted count first_center last_center step idx record target box center_x center_y target_center dx dy snapped_delta undo_moves)
        mode = if(axis == 'horiz then 'center_x else 'center_y)
        records = alg_v2_collect_records(targets)
        undo_moves = nil
        sorted = alg_v2_sort_records(records mode)
        count = length(sorted)
        if(count < 3 then
            nil
        else
            first_center = alg_v2_record_metric(car(sorted) mode)
            last_center = alg_v2_record_metric(alg_last_item(sorted) mode)
            step = (last_center - first_center) / (count - 1)
            idx = 0
            foreach(record sorted
                target = car(record)
                box = cadr(record)
                center_x = (car(car(box)) + car(cadr(box))) / 2.0
                center_y = (cadr(car(box)) + cadr(cadr(box))) / 2.0
                target_center = first_center + step * idx
                if(_alg_grid_size && _alg_grid_size > 0.0 then
                    target_center = alg_round_to_grid(target_center _alg_grid_size)
                )
                dx = 0.0
                dy = 0.0
                if(axis == 'horiz then
                    dx = target_center - center_x
                else
                    dy = target_center - center_y
                )
                if(_alg_grid_size && _alg_grid_size > 0.0 then
                    snapped_delta = alg_snap_origin_delta_to_grid(target dx dy)
                    dx = car(snapped_delta)
                    dy = cadr(snapped_delta)
                else
                    dx = alg_zero_small(dx)
                    dy = alg_zero_small(dy)
                )
                if(dx != 0.0 || dy != 0.0 then
                    alg_move_object(target list(dx dy))
                    undo_moves = cons(list(target list(-dx -dy)) undo_moves)
                )
                idx = idx + 1
            )
            _alg_last_op = reverse(undo_moves)
            t
        )
    )
)

; Override legacy entry points with V2 implementations.
defun( alg_extract_real (all_sel)
    alg_v2_targets_from_selection(all_sel)
)

defun( alg_is_aligned (objs mode)
    alg_v2_is_aligned(objs mode)
)

defun( alg_align_core (objs mode)
    alg_v2_align_targets(objs mode)
)

defun( alg_distribute_core (objs axis)
    alg_v2_distribute_targets(objs axis)
)

defun( alg_axis_name (axis)
    if(axis == 'horiz then
        "horizontal"
    else
        "vertical"
    )
)

defun( alg_select_align_batch (prompt_text)
    let((objs current_checked)
        objs = nil
        axlClearSelSet()
        axlSetFindFilter(?enabled alg_align_filter_buttons() ?onButtons _alg_find_mem)
        alg_put_msg(prompt_text)
        if(axlSelect() && !_alg_finished then
            objs = alg_extract_real(axlGetSelSet())
            current_checked = axlGetFindFilter(t)
            if(current_checked then
                _alg_find_mem = current_checked
            )
        )
        objs
    )
)

defun( alg_extract_reference_target (all_sel)
    let((target)
        target = nil
        foreach(obj all_sel
            if(!target then
                target = alg_v2_normalize_target(obj)
            )
        )
        target
    )
)

defun( alg_select_reference_target (prompt_text)
    let((target current_checked)
        target = nil
        axlClearSelSet()
        axlSetFindFilter(?enabled alg_align_filter_buttons() ?onButtons _alg_find_mem)
        alg_put_msg(prompt_text)
        if(axlSelect() && !_alg_finished then
            target = alg_extract_reference_target(axlGetSelSet())
            current_checked = axlGetFindFilter(t)
            if(current_checked then
                _alg_find_mem = current_checked
            )
        )
        if(target then
            axlClearSelSet()
            alg_highlight_all(list(target))
        )
        target
    )
)

defun( alg_mode_requires_reference (mode)
    if(mode == 'center_x then
        t
    else
        mode == 'center_y
    )
)

defun( alg_reference_target_value (target mode)
    let((box value)
        value = nil
        box = alg_v2_target_bbox(target)
        if(box then
            value = alg_bbox_metric(box mode)
            if(_alg_grid_size && _alg_grid_size > 0.0 then
                value = alg_round_to_grid(value _alg_grid_size)
            )
        )
        value
    )
)

defun( alg_run_align_session (mode)
    let((popup objs result ref_target ref_value)
        if(!alg_ensure_grid_size() then
            alg_put_msg("Align cancelled.")
            axlFinishEnterFun()
        else
            _alg_finished = nil
            _alg_commit = nil
            alg_bbox_cache_reset()
            alg_last_op_reset()
            axlClearSelSet()
            _alg_mark = axlDBTransactionStart()
            popup = axlUIPopupDefine(nil list(list("Done" 'alg_cb_done) list("Oops" 'alg_cb_oops) list("Cancel" 'alg_cb_cancel)))
            axlUIPopupSet(popup)

            unwindProtect(
                progn(
                    while(!_alg_finished
                        objs = alg_select_align_batch(sprintf(nil "Select objects to align %s on %.3f grid. Right-click -> Done/Oops/Cancel." alg_mode_name(mode) _alg_grid_size))
                        if(objs && !_alg_finished then
                            if(length(objs) > 1 then
                                if(alg_mode_requires_reference(mode) then
                                    ref_target = alg_select_reference_target(sprintf(nil "Select reference object for %s alignment." alg_mode_name(mode)))
                                    if(ref_target && !_alg_finished then
                                        ref_value = alg_reference_target_value(ref_target mode)
                                        if(ref_value != nil then
                                            if(alg_v2_is_aligned_to_value(objs mode ref_value) then
                                                alg_highlight_briefly(objs)
                                                alg_put_msg(sprintf(nil "Objects are already aligned %s." alg_mode_name(mode)))
                                            else
                                                axlDBTransactionMark(_alg_mark)
                                                result = errset(alg_v2_align_targets_to_value(objs mode ref_value) nil)
                                                if(result then
                                                    alg_highlight_briefly(objs)
                                                    alg_put_msg(sprintf(nil "Aligned %d object(s) to %s on %.3f grid." length(objs) alg_mode_name(mode) _alg_grid_size))
                                                else
                                                    alg_put_msg("Align failed.")
                                                )
                                            )
                                        else
                                            alg_put_msg("Reference object is invalid for center alignment.")
                                        )
                                    )
                                else
                                    if(alg_is_aligned(objs mode) then
                                        alg_highlight_briefly(objs)
                                        alg_put_msg(sprintf(nil "Objects are already aligned %s." alg_mode_name(mode)))
                                    else
                                        axlDBTransactionMark(_alg_mark)
                                        result = errset(alg_align_core(objs mode) nil)
                                        if(result then
                                            alg_highlight_briefly(objs)
                                            alg_put_msg(sprintf(nil "Aligned %d object(s) to %s on %.3f grid." length(objs) alg_mode_name(mode) _alg_grid_size))
                                        else
                                            alg_put_msg("Align failed.")
                                        )
                                    )
                                )
                            else
                                alg_put_msg("Align requires at least two valid objects.")
                            )
                        )
                    )
                )
                progn(
                    if(_alg_commit then
                        if(_alg_mark then axlDBTransactionCommit(_alg_mark))
                        alg_put_msg("Align session applied.")
                    else
                        if(_alg_mark then axlDBTransactionRollback(_alg_mark))
                        alg_put_msg("Align session cancelled and rolled back.")
                    )
                    axlUIPopupSet(nil)
                    axlClearSelSet()
                    alg_bbox_cache_reset()
                    alg_last_op_reset()
                    _alg_mark = nil
                    axlFinishEnterFun()
                    alg_run_pending_cmd()
                    alg_run_pending_panel_close()
                )
            )
        )
    )
)

defun( alg_run_distribute_session (axis)
    let((popup objs result)
        if(!alg_ensure_grid_size() then
            alg_put_msg("Distribute cancelled.")
            axlFinishEnterFun()
        else
            _alg_finished = nil
            _alg_commit = nil
            alg_bbox_cache_reset()
            alg_last_op_reset()
            axlClearSelSet()
            _alg_mark = axlDBTransactionStart()
            popup = axlUIPopupDefine(nil list(list("Done" 'alg_cb_done) list("Oops" 'alg_cb_oops) list("Cancel" 'alg_cb_cancel)))
            axlUIPopupSet(popup)

            unwindProtect(
                progn(
                    while(!_alg_finished
                        objs = alg_select_align_batch(sprintf(nil "Select objects to %s distribute on %.3f grid. Right-click -> Done/Oops/Cancel." alg_axis_name(axis) _alg_grid_size))
                        if(objs && !_alg_finished then
                            if(length(objs) > 2 then
                                axlDBTransactionMark(_alg_mark)
                                result = errset(alg_distribute_core(objs axis) nil)
                                if(result then
                                    alg_highlight_briefly(objs)
                                    alg_put_msg(sprintf(nil "Distributed %d object(s) %s on %.3f grid." length(objs) alg_axis_name(axis) _alg_grid_size))
                                else
                                    alg_put_msg("Distribute failed.")
                                )
                            else
                                alg_put_msg("Distribute requires at least three valid objects.")
                            )
                        )
                    )
                )
                progn(
                    if(_alg_commit then
                        if(_alg_mark then axlDBTransactionCommit(_alg_mark))
                        alg_put_msg("Distribute session applied.")
                    else
                        if(_alg_mark then axlDBTransactionRollback(_alg_mark))
                        alg_put_msg("Distribute session cancelled and rolled back.")
                    )
                    axlUIPopupSet(nil)
                    axlClearSelSet()
                    alg_bbox_cache_reset()
                    alg_last_op_reset()
                    _alg_mark = nil
                    axlFinishEnterFun()
                    alg_run_pending_cmd()
                    alg_run_pending_panel_close()
                )
            )
        )
    )
)

; --- Standard interactive commands ---
defun( alg_cmd_left ()  alg_run_align_session('left) )
defun( alg_cmd_right () alg_run_align_session('right) )
defun( alg_cmd_top ()   alg_run_align_session('top) )
defun( alg_cmd_bot ()   alg_run_align_session('bottom) )
defun( alg_cmd_cx ()    alg_run_align_session('center_x) )
defun( alg_cmd_cy ()    alg_run_align_session('center_y) )
defun( alg_cmd_hdist () alg_run_distribute_session('horiz) )
defun( alg_cmd_vdist () alg_run_distribute_session('vert) )

; --- Gesture align ---
defun( alg_cmd_drag ()
    let((popup box p1 p2 dx dy abs_dx abs_dy mode objs current_checked result)
        if(!alg_ensure_grid_size() then
            alg_put_msg("Gesture align cancelled.")
            axlFinishEnterFun()
        else
            _alg_finished = nil
            _alg_commit = nil
            alg_bbox_cache_reset()
            alg_last_op_reset()
            axlClearSelSet()

            axlSetFindFilter(?enabled list("noall" "symbols" "vias" "pins") ?onButtons _alg_find_mem)

            _alg_mark = axlDBTransactionStart()
            popup = axlUIPopupDefine(nil list(list("Done" 'alg_cb_done) list("Oops" 'alg_cb_oops) list("Cancel" 'alg_cb_cancel)))
            axlUIPopupSet(popup)

            unwindProtect(
                progn(
                    while(!_alg_finished
                        box = axlEnterBox(?prompts list(sprintf(nil "Gesture Align on %.3f grid: drag box to preview." _alg_grid_size) "Wide=top/bottom, tall=left/right. Right-click -> Done/Oops/Cancel"))
                        if(box && !_alg_finished then
                            p1 = car(box)
                            p2 = cadr(box)
                            dx = car(p2) - car(p1)
                            dy = cadr(p2) - cadr(p1)
                            abs_dx = abs(dx)
                            abs_dy = abs(dy)

                            if(abs_dx > abs_dy then
                                if(dy > 0 then mode = 'top else mode = 'bottom)
                            else
                                if(dx > 0 then mode = 'right else mode = 'left)
                            )

                            axlClearSelSet()
                            axlSingleSelectBox(box)
                            objs = alg_extract_real(axlGetSelSet())

                            if(objs && length(objs) > 1 then
                                axlDBTransactionMark(_alg_mark)
                                result = errset(alg_align_core(objs mode) nil)
                                if(result then
                                    alg_highlight_briefly(objs)
                                    alg_put_msg(sprintf(nil "Preview: aligned %s on %.3f grid. Right-click -> Done to save." alg_mode_name(mode) _alg_grid_size))
                                else
                                    alg_put_msg("Preview failed.")
                                )
                            else
                                alg_put_msg("Not enough valid objects in selection box.")
                            )
                        )
                    )
                )
                progn(
                    if(_alg_commit then
                        if(_alg_mark then axlDBTransactionCommit(_alg_mark))
                        alg_put_msg("Gesture Align: changes applied.")
                    else
                        if(_alg_mark then axlDBTransactionRollback(_alg_mark))
                        alg_put_msg("Gesture Align: cancelled and rolled back.")
                    )
                    current_checked = axlGetFindFilter(t)
                    if(current_checked then _alg_find_mem = current_checked)
                    axlUIPopupSet(nil)
                    axlClearSelSet()
                    alg_bbox_cache_reset()
                    alg_last_op_reset()
                    _alg_mark = nil
                    axlFinishEnterFun()
                    alg_run_pending_cmd()
                    alg_run_pending_panel_close()
                )
            )
        )
    )
)

; --- Snap-to-grid ---
defun( alg_ensure_grid_size ()
    let((ans value)
        if(numberp(_alg_grid_size) && _alg_grid_size >= 0.0 then
            t
        else
            ans = axlEnterString(?prompts list("Enter alignment grid size (0 disables align snap):"))
            if(stringp(ans) && strlen(ans) > 0 then
                value = atof(ans)
                if(value >= 0.0 then
                    _alg_grid_size = value
                    t
                else
                    nil
                )
            else
                nil
            )
        )
    )
)

defun( alg_ensure_snap_grid_size ()
    let((ans value)
        if(numberp(_alg_grid_size) && _alg_grid_size > 0.0 then
            t
        else
            ans = axlEnterString(?prompts list("Enter snap grid size (> 0):"))
            if(stringp(ans) && strlen(ans) > 0 then
                value = atof(ans)
                if(value > 0.0 then
                    _alg_grid_size = value
                    t
                else
                    nil
                )
            else
                nil
            )
        )
    )
)

defun( alg_snap_run_loop ()
    let((sel_objs popup objs snap_count obj dx dy delta undo_moves)
        if(!_alg_grid_size || _alg_grid_size <= 0.0 then
            alg_put_msg("Snap To Grid requires a grid size greater than 0.")
        else
            _alg_snap_finished = nil
            _alg_snap_commit = nil
            alg_bbox_cache_reset()
            alg_snap_last_op_reset()
            axlClearSelSet()
            axlSetFindFilter(
                ?enabled list("noall" "components" "symbols" "vias" "text" "groups")
                ?onButtons list("noall" "components" "symbols" "vias" "text" "groups")
            )

            _alg_snap_mark = axlDBTransactionStart()
            popup = axlUIPopupDefine(nil list(list("Done" 'alg_snap_cb_done) list("Oops" 'alg_snap_cb_oops) list("Cancel" 'alg_snap_cb_cancel)))
            axlUIPopupSet(popup)

            unwindProtect(
                progn(
                    while(!_alg_snap_finished
                        alg_put_msg(sprintf(nil "Select objects to snap to %.3f grid. Right-click -> Done." _alg_grid_size))
                        if(axlSelect() && !_alg_snap_finished then
                            sel_objs = axlGetSelSet()
                            if(sel_objs then
                                objs = alg_extract_snap_objects(sel_objs)
                                if(objs then
                                    axlDBTransactionMark(_alg_snap_mark)
                                    snap_count = 0
                                    undo_moves = nil
                                    foreach(obj objs
                                        if(obj->xy then
                                            delta = alg_snap_origin_delta_to_grid(obj 0.0 0.0)
                                            dx = car(delta)
                                            dy = cadr(delta)
                                            if(dx != 0.0 || dy != 0.0 then
                                                alg_move_object(obj list(dx dy))
                                                undo_moves = cons(list(obj list(-dx -dy)) undo_moves)
                                                snap_count = snap_count + 1
                                            )
                                        )
                                    )
                                    _alg_snap_last_op = reverse(undo_moves)
                                    alg_put_msg(sprintf(nil "Snapped %d object(s). Continue selecting or right-click -> Done." snap_count))
                                else
                                    alg_put_msg("No valid movable objects were selected.")
                                )
                                axlClearSelSet()
                            )
                        )
                    )
                )
                progn(
                    if(_alg_snap_commit then
                        if(_alg_snap_mark then axlDBTransactionCommit(_alg_snap_mark))
                        alg_put_msg("Snap To Grid: changes applied.")
                    else
                        if(_alg_snap_mark then axlDBTransactionRollback(_alg_snap_mark))
                        alg_put_msg("Snap To Grid: cancelled and rolled back.")
                    )
                    axlUIPopupSet(nil)
                    axlClearSelSet()
                    alg_bbox_cache_reset()
                    alg_snap_last_op_reset()
                    _alg_snap_mark = nil
                    alg_run_pending_cmd()
                    alg_run_pending_panel_close()
                )
            )
        )
    )
)

defun( alg_cmd_snap ()
    if(alg_ensure_snap_grid_size() then
        alg_snap_run_loop()
    else
        alg_put_msg("Snap To Grid cancelled.")
        axlFinishEnterFun()
    )
)

; --- Launcher panel ---
defun( alg_panel_store_grid (form)
    let((grid_val)
        grid_val = alg_parse_real(axlFormGetField(form "grid_input") _alg_grid_size)
        if(numberp(grid_val) then
            _alg_grid_size = grid_val
        )
    )
)

defun( alg_panel_action_cmd (field_name)
    let((cmd)
        cmd = nil
        case(field_name
            ("BTN_DRAG"  cmd = "moka_al_drag")
            ("BTN_LEFT"  cmd = "moka_al_left")
            ("BTN_RIGHT" cmd = "moka_al_right")
            ("BTN_TOP"   cmd = "moka_al_top")
            ("BTN_BOT"   cmd = "moka_al_bottom")
            ("BTN_CX"    cmd = "moka_al_hcenter")
            ("BTN_CY"    cmd = "moka_al_vcenter")
            ("BTN_HDIST" cmd = "moka_al_hdist")
            ("BTN_VDIST" cmd = "moka_al_vdist")
            ("BTN_SNAP"  cmd = "moka_al_grid")
        )
        cmd
    )
)

defun( alg_panel_form_cb (form)
    let((next_cmd)
        when(form->doneState > 0
            alg_panel_request_close(form)
        )
        case(form->curField
            ("BTN_CLOSE"
                alg_panel_request_close(form)
            )
            (t
                next_cmd = alg_panel_action_cmd(form->curField)
                if(next_cmd then
                    alg_panel_store_grid(form)
                    alg_panel_launch_cmd(next_cmd)
                )
            )
        )
        t
    )
)

defun( alg_write_panel_form (form_file)
    let((p)
        p = outfile(form_file)
        if(p then
            fprintf(p "FILE_TYPE=FORM_DEFN VERSION=2\n")
            fprintf(p "FORM\nFIXED\nPORT 62 18\nHEADER \"Moka skill v%s - \266\324\306\353\271\244\276\337\"\n" _alg_version)
            fprintf(p "TILE\n")
            fprintf(p "TEXT \"\325\244\270\361\040\050\060\040\261\355\312\276\262\273\316\374\270\275\266\324\306\353\051\072\"\nTLOC 2 2\nENDTEXT\n")
            fprintf(p "FIELD grid_input\nFLOC 37 2\nREALFILLIN 10 10\nDECIMAL 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_LEFT\nFLOC 2 5\nMENUBUTTON \"\327\363\266\324\306\353\" 12 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_RIGHT\nFLOC 16 5\nMENUBUTTON \"\323\322\266\324\306\353\" 12 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_TOP\nFLOC 30 5\nMENUBUTTON \"\311\317\266\324\306\353\" 12 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_BOT\nFLOC 44 5\nMENUBUTTON \"\317\302\266\324\306\353\" 12 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_CX\nFLOC 2 9\nMENUBUTTON \"\313\256\306\275\276\323\326\320\" 12 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_CY\nFLOC 16 9\nMENUBUTTON \"\264\271\326\261\276\323\326\320\" 12 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_HDIST\nFLOC 30 9\nMENUBUTTON \"\313\256\306\275\267\326\262\274\" 12 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_VDIST\nFLOC 44 9\nMENUBUTTON \"\264\271\326\261\267\326\262\274\" 12 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_DRAG\nFLOC 2 13\nMENUBUTTON \"\326\307\304\334\266\324\306\353\" 16 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_SNAP\nFLOC 20 13\nMENUBUTTON \"\266\324\306\353\325\244\270\361\" 16 3\nENDFIELD\n")
            fprintf(p "FIELD BTN_CLOSE\nFLOC 44 13\nMENUBUTTON \"\271\330\261\325\" 12 3\nENDFIELD\n")
            fprintf(p "ENDTILE\nENDFORM\n")
            close(p)
            t
        else
            nil
        )
    )
)

defun( alg_cmd_panel ()
    let((form_file form)
        if(_alg_panel_form then
            axlFormSetField(_alg_panel_form "grid_input" _alg_grid_size)
            axlFormDisplay(_alg_panel_form)
        else
            form_file = strcat(getWorkingDir() "/align_tools_panel.form")
            if(alg_write_panel_form(form_file) then
                form = axlFormCreate((gensym) form_file '("E" "OUT" "center") 'alg_panel_form_cb t)
                if(form then
                    _alg_panel_form = form
                    axlFormSetField(form "grid_input" _alg_grid_size)
                    axlFormDisplay(form)
                else
                    alg_put_msg("Failed to create Align Tools panel.")
                )
                if(isFile(form_file) then deleteFile(form_file))
            else
                alg_put_msg("Failed to write Align Tools panel form file.")
            )
        )
    )
)
