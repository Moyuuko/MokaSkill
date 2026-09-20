/*
  Description: Voidless cline spreading for Cadence Allegro PCB Editor.
  Behavior:
    - Select at least three parallel straight cline segments on one layer.
    - The two outermost segments remain fixed.
    - Intermediate segments are distributed at equal centerline spacing.
    - Adjacent straight segments are trimmed or extended along their original
      directions so connectivity and corner angles are preserved.
    - DRCs and other physical conflicts are intentionally ignored.
*/

_msv_eps = 0.000001
_msv_parallel_tol = 0.00001
_msv_cancelled = nil
_msv_done = nil

defun( msv_put_msg (message)
    if(isCallable('axlMsgPut) then
        axlMsgPut(sprintf(nil "Moka skill - Spread Clines: %s" message))
    else
        printf("Moka skill - Spread Clines: %s\n" message)
    )
)

defun( msv_point (x y)
    list(x y)
)

defun( msv_point_add (a b)
    msv_point(car(a) + car(b) cadr(a) + cadr(b))
)

defun( msv_point_sub (a b)
    msv_point(car(a) - car(b) cadr(a) - cadr(b))
)

defun( msv_point_scale (point scale)
    msv_point(car(point) * scale cadr(point) * scale)
)

defun( msv_dot (a b)
    car(a) * car(b) + cadr(a) * cadr(b)
)

defun( msv_cross (a b)
    car(a) * cadr(b) - cadr(a) * car(b)
)

defun( msv_length (vector)
    sqrt(msv_dot(vector vector))
)

defun( msv_midpoint (a b)
    msv_point((car(a) + car(b)) / 2.0 (cadr(a) + cadr(b)) / 2.0)
)

defun( msv_same_point (a b)
    a && b && msv_length(msv_point_sub(a b)) <= _msv_eps
)

defun( msv_unit_direction_points (start_point end_point)
    let((vector vector_length)
        vector = msv_point_sub(end_point start_point)
        vector_length = msv_length(vector)
        if(vector_length > _msv_eps then
            msv_point_scale(vector 1.0 / vector_length)
        else
            nil
        )
    )
)

defun( msv_parallel_p (direction reference_direction)
    direction && reference_direction &&
    abs(abs(msv_dot(direction reference_direction)) - 1.0) <= _msv_parallel_tol
)

defun( msv_line_intersection (p direction q other_direction)
    let((denominator distance)
        denominator = msv_cross(direction other_direction)
        if(abs(denominator) <= _msv_eps then
            nil
        else
            distance = msv_cross(msv_point_sub(q p) other_direction) / denominator
            msv_point_add(p msv_point_scale(direction distance))
        )
    )
)

defun( msv_even_target (first_offset last_offset index count)
    first_offset + (last_offset - first_offset) * index / (count - 1.0)
)

defun( msv_shift_geometry (main_start main_end start_fixed end_fixed delta normal)
    let((main_direction shifted_start start_direction end_direction new_start new_end
         main_vector result)
        result = nil
        main_direction = msv_unit_direction_points(main_start main_end)
        shifted_start = msv_point_add(main_start msv_point_scale(normal delta))
        start_direction = msv_unit_direction_points(start_fixed main_start)
        end_direction = msv_unit_direction_points(end_fixed main_end)

        if(main_direction && start_direction && end_direction then
            new_start = msv_line_intersection(shifted_start main_direction start_fixed start_direction)
            new_end = msv_line_intersection(shifted_start main_direction end_fixed end_direction)
            when(new_start && new_end
                main_vector = msv_point_sub(new_end new_start)
                when(msv_length(main_vector) > _msv_eps
                    result = list(new_start new_end)
                )
            )
        )
        result
    )
)

defun( msv_segment_direction (segment)
    if(segment && segment->startEnd then
        msv_unit_direction_points(car(segment->startEnd) cadr(segment->startEnd))
    else
        nil
    )
)

defun( msv_segment_net_name (segment)
    let((net_name parent)
        net_name = ""
        when(segment
            if(segment->net && stringp(segment->net->name) then
                net_name = segment->net->name
            else
                parent = segment->parent
                when(parent && parent->net && stringp(parent->net->name)
                    net_name = parent->net->name
                )
            )
        )
        net_name
    )
)

defun( msv_valid_selected_segment (segment)
    segment &&
    segment->objType == "line" &&
    segment->isEtch &&
    stringp(segment->layer) &&
    numberp(segment->width) &&
    segment->startEnd &&
    length(segment->startEnd) == 2 &&
    segment->parent &&
    segment->parent->segments
)

defun( msv_normalize_selected_segment (object)
    let((segment)
        segment = nil
        when(msv_valid_selected_segment(object)
            segment = object
        )
        segment
    )
)

defun( msv_collect_selected_segments (selected)
    let((segments segment)
        segments = nil
        foreach(object selected
            segment = msv_normalize_selected_segment(object)
            when(segment && !memq(segment segments)
                segments = cons(segment segments)
            )
        )
        reverse(segments)
    )
)

defun( msv_segments_at_point (path point excluded_segment)
    let((matches)
        matches = nil
        foreach(segment path->segments
            when(
                segment != excluded_segment &&
                segment->startEnd &&
                (msv_same_point(car(segment->startEnd) point) ||
                 msv_same_point(cadr(segment->startEnd) point))
                matches = cons(segment matches)
            )
        )
        reverse(matches)
    )
)

defun( msv_other_endpoint (segment shared_point)
    let((other)
        other = nil
        when(segment && segment->startEnd
            if(msv_same_point(car(segment->startEnd) shared_point) then
                other = cadr(segment->startEnd)
            else
                when(msv_same_point(cadr(segment->startEnd) shared_point)
                    other = car(segment->startEnd)
                )
            )
        )
        other
    )
)

defun( msv_replace_endpoint (start_end old_point new_point)
    if(msv_same_point(car(start_end) old_point) then
        list(new_point cadr(start_end))
    else
        if(msv_same_point(cadr(start_end) old_point) then
            list(car(start_end) new_point)
        else
            nil
        )
    )
)

defun( msv_make_segment_change (segment new_start_end)
    let((change)
        change = ncons(t)
        change->segment = segment
        change->startEnd = new_start_end
        change->width = segment->width
        change->layer = segment->layer
        change->netName = msv_segment_net_name(segment)
        change->removeOnly = msv_same_point(car(new_start_end) cadr(new_start_end))
        change
    )
)

defun( msv_make_new_segment_change (template_segment new_start_end)
    let((change)
        change = ncons(t)
        change->segment = nil
        change->startEnd = new_start_end
        change->width = template_segment->width
        change->layer = template_segment->layer
        change->netName = msv_segment_net_name(template_segment)
        change->removeOnly = msv_same_point(car(new_start_end) cadr(new_start_end))
        change->createOnly = t
        change
    )
)

defun( msv_record_lessp (left right)
    left->offset < right->offset
)

defun( msv_make_selection_records (segments)
    let((records reference_direction normal layer_name path_list common_min common_max valid reason
         segment direction start_point end_point midpoint offset tangent_a tangent_b low high record)
        records = nil
        reference_direction = nil
        normal = nil
        layer_name = nil
        path_list = nil
        common_min = -1000000000.0
        common_max = 1000000000.0
        valid = t
        reason = nil

        foreach(segment segments
            when(valid
                direction = msv_segment_direction(segment)
                unless(direction
                    valid = nil
                    reason = "zero-length segment selected"
                )
            )
            when(valid && !reference_direction
                reference_direction = direction
                normal = msv_point(-cadr(reference_direction) car(reference_direction))
                layer_name = segment->layer
            )
            when(valid && !msv_parallel_p(direction reference_direction)
                valid = nil
                reason = "selected segments are not parallel"
            )
            when(valid && upperCase(segment->layer) != upperCase(layer_name)
                valid = nil
                reason = "selected segments are not on one layer"
            )
            when(valid && memq(segment->parent path_list)
                valid = nil
                reason = "select only one main segment from each cline"
            )
            when(valid && isCallable('axlDBIsFixed) && axlDBIsFixed(segment nil)
                valid = nil
                reason = "a selected segment is fixed"
            )
            when(valid
                path_list = cons(segment->parent path_list)
                start_point = car(segment->startEnd)
                end_point = cadr(segment->startEnd)
                midpoint = msv_midpoint(start_point end_point)
                offset = msv_dot(midpoint normal)
                tangent_a = msv_dot(start_point reference_direction)
                tangent_b = msv_dot(end_point reference_direction)
                low = min(tangent_a tangent_b)
                high = max(tangent_a tangent_b)
                common_min = max(common_min low)
                common_max = min(common_max high)

                record = ncons(t)
                record->segment = segment
                record->offset = offset
                records = cons(record records)
            )
        )

        when(valid && common_max - common_min <= _msv_eps
            valid = nil
            reason = "selected segments do not share a longitudinal overlap"
        )

        if(valid then
            list(sort(records 'msv_record_lessp) reference_direction normal nil)
        else
            list(nil nil nil reason)
        )
    )
)

defun( msv_trace_to_corner (path initial_segment initial_point main_direction initial_visited)
    let((current_segment current_point visited chain boundary boundary_point fixed_point
         matches neighbor neighbor_direction next_point reason done anchored)
        current_segment = initial_segment
        current_point = initial_point
        visited = initial_visited
        chain = nil
        boundary = nil
        boundary_point = nil
        fixed_point = nil
        reason = nil
        done = nil
        anchored = nil

        while(!done && !reason
            matches = msv_segments_at_point(path current_point current_segment)
            if(length(matches) != 1 then
                boundary_point = current_point
                fixed_point = current_point
                anchored = t
                done = t
            else
                neighbor = car(matches)
                if(memq(neighbor visited) then
                    boundary_point = current_point
                    fixed_point = current_point
                    anchored = t
                    done = t
                else
                    if(
                        neighbor->objType != "line" ||
                        !neighbor->startEnd ||
                        (isCallable('axlDBIsFixed) && axlDBIsFixed(neighbor nil))
                    then
                        boundary_point = current_point
                        fixed_point = current_point
                        anchored = t
                        done = t
                    else
                        neighbor_direction = msv_segment_direction(neighbor)
                        next_point = msv_other_endpoint(neighbor current_point)
                        if(!neighbor_direction || !next_point then
                            reason = "a connected segment has invalid geometry"
                        else
                            if(msv_parallel_p(neighbor_direction main_direction) then
                                chain = cons(neighbor chain)
                                visited = cons(neighbor visited)
                                current_segment = neighbor
                                current_point = next_point
                            else
                                boundary = neighbor
                                boundary_point = current_point
                                fixed_point = next_point
                                visited = cons(neighbor visited)
                                done = t
                            )
                        )
                    )
                )
            )
        )

        list(chain boundary boundary_point fixed_point reason visited anchored)
    )
)

defun( msv_chain_segment_at_point (chain_segments point)
    let((found)
        found = nil
        foreach(segment chain_segments
            when(
                !found &&
                (msv_same_point(car(segment->startEnd) point) ||
                 msv_same_point(cadr(segment->startEnd) point))
                found = segment
            )
        )
        found
    )
)

defun( msv_shifted_endpoint (outer_point fixed_point main_direction shift_vector anchored)
    let((arm_direction shifted_point)
        shifted_point = msv_point_add(outer_point shift_vector)
        if(anchored then
            shifted_point
        else
            arm_direction = msv_unit_direction_points(fixed_point outer_point)
            if(arm_direction then
                msv_line_intersection(shifted_point main_direction fixed_point arm_direction)
            else
                nil
            )
        )
    )
)

defun( msv_build_shift_changes (segment delta normal)
    let((start_point end_point path main_direction start_trace end_trace start_chain end_chain
         start_neighbor end_neighbor outer_start outer_end start_fixed end_fixed geometry
         new_start new_end changes reason visited chain_segments shift_vector shifted_outer_start
         shifted_outer_end chain_segment new_start_end start_change end_change start_anchored
         end_anchored start_template end_template)
        changes = nil
        reason = nil
        start_point = car(segment->startEnd)
        end_point = cadr(segment->startEnd)
        path = segment->parent
        main_direction = msv_segment_direction(segment)
        visited = list(segment)

        start_trace = msv_trace_to_corner(path segment start_point main_direction visited)
        start_chain = car(start_trace)
        start_neighbor = cadr(start_trace)
        outer_start = nth(2 start_trace)
        start_fixed = nth(3 start_trace)
        reason = nth(4 start_trace)
        visited = nth(5 start_trace)
        start_anchored = nth(6 start_trace)

        when(!reason
            end_trace = msv_trace_to_corner(path segment end_point main_direction visited)
            end_chain = car(end_trace)
            end_neighbor = cadr(end_trace)
            outer_end = nth(2 end_trace)
            end_fixed = nth(3 end_trace)
            reason = nth(4 end_trace)
            end_anchored = nth(6 end_trace)
        )

        when(!reason && start_neighbor && start_neighbor == end_neighbor
            reason = "both ends resolve to the same corner arm"
        )

        when(!reason
            shift_vector = msv_point_scale(normal delta)
            new_start = msv_shifted_endpoint(
                outer_start start_fixed main_direction shift_vector start_anchored
            )
            new_end = msv_shifted_endpoint(
                outer_end end_fixed main_direction shift_vector end_anchored
            )
            if(!new_start || !new_end || msv_same_point(new_start new_end) then
                reason = "the expanded main run would collapse, or a corner arm is parallel"
            else
                shifted_outer_start = msv_point_add(outer_start shift_vector)
                shifted_outer_end = msv_point_add(outer_end shift_vector)
                chain_segments = append(append(start_chain list(segment)) end_chain)
                start_template = msv_chain_segment_at_point(chain_segments outer_start)
                end_template = msv_chain_segment_at_point(chain_segments outer_end)

                if(start_anchored then
                    start_change = msv_make_new_segment_change(
                        start_template list(outer_start new_start)
                    )
                else
                    start_change = msv_make_segment_change(
                        start_neighbor
                        msv_replace_endpoint(start_neighbor->startEnd outer_start new_start)
                    )
                )
                changes = list(start_change)

                foreach(chain_segment chain_segments
                    new_start_end = list(
                        msv_point_add(car(chain_segment->startEnd) shift_vector)
                        msv_point_add(cadr(chain_segment->startEnd) shift_vector)
                    )
                    when(
                        msv_same_point(car(new_start_end) shifted_outer_start) ||
                        msv_same_point(cadr(new_start_end) shifted_outer_start)
                        new_start_end = msv_replace_endpoint(
                            new_start_end shifted_outer_start new_start
                        )
                    )
                    when(
                        msv_same_point(car(new_start_end) shifted_outer_end) ||
                        msv_same_point(cadr(new_start_end) shifted_outer_end)
                        new_start_end = msv_replace_endpoint(
                            new_start_end shifted_outer_end new_end
                        )
                    )
                    changes = append(
                        changes
                        list(msv_make_segment_change(chain_segment new_start_end))
                    )
                )

                if(end_anchored then
                    end_change = msv_make_new_segment_change(
                        end_template list(outer_end new_end)
                    )
                else
                    end_change = msv_make_segment_change(
                        end_neighbor
                        msv_replace_endpoint(end_neighbor->startEnd outer_end new_end)
                    )
                )
                changes = append(changes list(end_change))
            )
        )
        list(changes reason)
    )
)

defun( msv_prepare_changes (segments)
    let((selection_data records normal reason count first_offset last_offset index record target delta
         shift_data changes all_changes changed_count)
        all_changes = nil
        changed_count = 0
        selection_data = msv_make_selection_records(segments)
        records = car(selection_data)
        normal = nth(2 selection_data)
        reason = nth(3 selection_data)

        when(records
            count = length(records)
            first_offset = car(records)->offset
            last_offset = car(last(records))->offset
            if(abs(last_offset - first_offset) <= _msv_eps then
                reason = "the outermost segments have no usable spacing"
                records = nil
            else
                index = 0
                foreach(record records
                    when(index > 0 && index < count - 1 && !reason
                        target = msv_even_target(first_offset last_offset index count)
                        delta = target - record->offset
                        when(abs(delta) > _msv_eps
                            shift_data = msv_build_shift_changes(record->segment delta normal)
                            changes = car(shift_data)
                            reason = cadr(shift_data)
                            if(changes then
                                all_changes = append(all_changes changes)
                                changed_count = changed_count + 1
                            )
                        )
                    )
                    index = index + 1
                )
            )
        )

        if(reason then
            list(nil 0 reason)
        else
            list(all_changes changed_count nil)
        )
    )
)

defun( msv_create_change (change)
    let((result)
        result = errset(
            axlDBCreateLine(
                change->startEnd
                change->width
                change->layer
                change->netName
                nil
            )
            nil
        )
        result && car(result)
    )
)

defun( msv_apply_changes (changes)
    let((change success delete_result)
        success = t
        foreach(change changes
            when(success
                unless(change->createOnly
                    delete_result = errset(axlDeleteObject(change->segment) nil)
                    success = delete_result && car(delete_result)
                )
            )
        )
        foreach(change changes
            when(success
                unless(change->removeOnly
                    success = msv_create_change(change)
                )
            )
        )
        success
    )
)

defun( msv_cancel_cmd ()
    _msv_cancelled = t
    _msv_done = nil
    when(isCallable('axlCancelEnterFun)
        axlCancelEnterFun()
    )
)

defun( msv_done_cmd ()
    _msv_cancelled = nil
    _msv_done = t
    when(isCallable('axlCancelEnterFun)
        axlCancelEnterFun()
    )
)

defun( msv_cmd ()
    let((saved_enabled saved_on selected segments prepared changes changed_count reason mark applied popup)
        _msv_cancelled = nil
        _msv_done = nil
        saved_enabled = axlGetFindFilter()
        saved_on = axlGetFindFilter(t)
        mark = nil
        applied = nil

        unwindProtect(
            progn(
                selected = axlGetSelSet()
                segments = msv_collect_selected_segments(selected)
                when(length(segments) < 3
                    axlClearSelSet()
                    axlSetFindFilter(
                        ?enabled list("noall" "clinesegs")
                        ?onButtons list("noall" "clinesegs")
                    )
                    msv_put_msg("Select at least three parallel straight cline segments, then right-click Done.")
                    popup = axlUIPopupDefine(
                        nil
                        list(
                            list("Done" 'msv_done_cmd)
                            list("Cancel" 'msv_cancel_cmd)
                        )
                    )
                    axlUIPopupSet(popup)
                    axlSelect(
                        ?groupMode t
                        ?prompt "Spread Clines: select one parallel straight segment from each cline, then right-click Done."
                    )
                    when(_msv_done && !_msv_cancelled
                        segments = msv_collect_selected_segments(axlGetSelSet())
                    )
                )

                if(_msv_cancelled then
                    msv_put_msg("Cancelled.")
                else
                    if(length(segments) < 3 then
                        msv_put_msg("At least three valid cline segments are required.")
                    else
                        prepared = msv_prepare_changes(segments)
                        changes = car(prepared)
                        changed_count = cadr(prepared)
                        reason = nth(2 prepared)
                        if(reason then
                            msv_put_msg(sprintf(nil "No changes: %s." reason))
                        else
                            if(changed_count == 0 then
                                msv_put_msg("The selected clines are already evenly distributed.")
                            else
                                mark = axlDBTransactionStart()
                                if(!mark then
                                    msv_put_msg("Unable to start an Allegro database transaction.")
                                else
                                    applied = msv_apply_changes(changes)
                                    if(applied && axlDBTransactionCommit(mark) then
                                        progn(
                                            mark = nil
                                            msv_put_msg(sprintf(nil "%d intermediate cline(s) distributed; outer clines remained fixed." changed_count))
                                        )
                                    else
                                        progn(
                                            when(mark axlDBTransactionRollback(mark))
                                            mark = nil
                                            msv_put_msg("Database update failed; the operation was rolled back.")
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
            progn(
                when(mark axlDBTransactionRollback(mark))
                axlUIPopupSet(nil)
                axlClearSelSet()
                errset(axlSetFindFilter(?enabled saved_enabled ?onButtons saved_on) nil)
                axlFinishEnterFun()
            )
        )
    )
)

when(isCallable('axlCmdRegister)
    axlCmdRegister(
        "moka_spread_between_clines"
        'msv_cmd
        ?cmdType "interactive"
        ?doneCmd 'msv_done_cmd
        ?cancelCmd 'msv_cancel_cmd
    )
    axlCmdRegister(
        "msbc"
        'msv_cmd
        ?cmdType "interactive"
        ?doneCmd 'msv_done_cmd
        ?cancelCmd 'msv_cancel_cmd
    )
)
