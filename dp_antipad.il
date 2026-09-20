/*
  Moka Skill Anti-Pad Module v1.0

  Commands:
    moka_dp_antipad      - open the anti-pad control panel
    dp_antipad           - compatibility command for the same panel
    moka_dp_antipad_run  - internal interactive selection command

  The module creates filled shapes on ROUTE KEEPOUT/<selected layer> and
  attaches both ROUTES_ALLOWED and VIAS_ALLOWED. The keepout therefore blocks
  conductive shapes while allowing clines and vias through the area.
*/

_dva_version = "1.0"
_dva_prop_name = "MOKA_AP_KEEP_ID"
_dva_legacy_prop_name = "MOKA_DP_AP_ID"
_dva_defaults_initialized = nil
_dva_id_counter = 0

_dva_ui_form = nil
_dva_ui_close_pending = nil
_dva_run_active = nil
_dva_panel_active = nil
_dva_panel_action = nil
_dva_ui_ministatus = nil

_dva_finished = nil
_dva_commit = nil
_dva_mark = nil
_dva_operation = "APPLY"
_dva_session_op_count = 0
_dva_last_error = nil

_dva_target_mode = "DIFF_AUTO"
_dva_geometry_mode = "CAPSULE"
_dva_layer = ""
_dva_source_layer = ""
_dva_clearance = 8.0
_dva_min_diameter = 0.0
_dva_fixed_size = nil
_dva_max_pair_distance = 120.0
_dva_replace_existing = t
_dva_confirm_before_apply = t

axlCmdRegister(
    "moka_dp_antipad" 'dva_ui_open
    ?cmdType "interactive"
    ?doneCmd 'dva_panel_done
    ?cancelCmd 'dva_panel_cancel)
axlCmdRegister(
    "dp_antipad" 'dva_ui_open
    ?cmdType "interactive"
    ?doneCmd 'dva_panel_done
    ?cancelCmd 'dva_panel_cancel)
axlCmdRegister(
    "moka_dp_antipad_run"
    'dva_cmd_run
    ?cmdType "interactive"
    ?doneCmd 'dva_cb_done
    ?cancelCmd 'dva_cb_cancel
)

defun( dva_put_msg (message)
    axlMsgPut(sprintf(nil "Moka skill - Anti-Pad: %s" message))
)

defun( dva_parse_real (value default_value)
    let((result)
        result = default_value
        if(numberp(value) then
            result = value
        else
            when(stringp(value) && strlen(value) > 0
                result = atof(value)
            )
        )
        result
    )
)

defun( dva_design_units ()
    let((info units)
        units = "design units"
        info = errset(axlDBGetDesignUnits() nil)
        when(info && car(info) && stringp(car(car(info)))
            units = car(car(info))
        )
        units
    )
)

defun( dva_init_defaults ()
    let((units)
        unless(_dva_defaults_initialized
            units = lowerCase(dva_design_units())
            cond(
                (rexMatchp("millimeter" units)
                    _dva_clearance = 0.20
                    _dva_min_diameter = 0.0
                    _dva_max_pair_distance = 3.00
                )
                (rexMatchp("micron" units)
                    _dva_clearance = 200.0
                    _dva_min_diameter = 0.0
                    _dva_max_pair_distance = 3000.0
                )
                (rexMatchp("inch" units)
                    _dva_clearance = 0.008
                    _dva_min_diameter = 0.0
                    _dva_max_pair_distance = 0.120
                )
                (t
                    _dva_clearance = 8.0
                    _dva_min_diameter = 0.0
                    _dva_max_pair_distance = 120.0
                )
            )
            _dva_defaults_initialized = t
        )
    )
)

defun( dva_board_layers ()
    let((param layers)
        layers = nil
        param = errset(axlGetParam("paramLayerGroup:ETCH") nil)
        when(param && car(param) && car(param)->groupMembers
            layers = car(param)->groupMembers
        )
        layers
    )
)

defun( dva_normalize_etch_layer (layer)
    let((normalized)
        normalized = nil
        when(stringp(layer) && strlen(layer) > 0
            if(rexMatchp("^ETCH/" upperCase(layer)) then
                normalized = layer
            else
                when(member(layer dva_board_layers())
                    normalized = strcat("ETCH/" layer)
                )
            )
        )
        normalized
    )
)

defun( dva_active_etch_layer ()
    let((result layer)
        layer = nil
        result = errset(axlGetActiveLayer() nil)
        when(result && car(result)
            layer = dva_normalize_etch_layer(car(result))
        )
        layer
    )
)

defun( dva_contour_source_layer ()
    let((layer)
        layer = dva_normalize_etch_layer(_dva_source_layer)
        unless(layer layer = dva_active_etch_layer())
        unless(layer layer = strcat("ETCH/" _dva_layer))
        layer
    )
)

defun( dva_route_keepout_layer ()
    strcat("ROUTE KEEPOUT/" _dva_layer)
)

defun( dva_bbox_valid (box)
    box && length(box) >= 2 && car(box) && cadr(box)
)

defun( dva_bbox_union (box1 box2)
    let((min_x min_y max_x max_y)
        cond(
            (!dva_bbox_valid(box1) box2)
            (!dva_bbox_valid(box2) box1)
            (t
                min_x = min(car(car(box1)) car(car(box2)))
                min_y = min(cadr(car(box1)) cadr(car(box2)))
                max_x = max(car(cadr(box1)) car(cadr(box2)))
                max_y = max(cadr(cadr(box1)) cadr(cadr(box2)))
                list(list(min_x min_y) list(max_x max_y))
            )
        )
    )
)

defun( dva_bbox_expand (box amount)
    if(dva_bbox_valid(box) then
        list(
            list(car(car(box))-amount cadr(car(box))-amount)
            list(car(cadr(box))+amount cadr(cadr(box))+amount)
        )
    else
        nil
    )
)

defun( dva_bbox_width (box)
    if(dva_bbox_valid(box) then car(cadr(box))-car(car(box)) else 0.0)
)

defun( dva_bbox_height (box)
    if(dva_bbox_valid(box) then cadr(cadr(box))-cadr(car(box)) else 0.0)
)

defun( dva_bbox_center (box)
    if(dva_bbox_valid(box) then
        list(
            (car(car(box))+car(cadr(box)))/2.0
            (cadr(car(box))+cadr(cadr(box)))/2.0
        )
    else
        nil
    )
)

defun( dva_bbox_force_minimum (box minimum_size)
    let((center width height half_width half_height)
        if(!dva_bbox_valid(box) || minimum_size <= 0.0 then
            box
        else
            center = dva_bbox_center(box)
            width = max(dva_bbox_width(box) minimum_size)
            height = max(dva_bbox_height(box) minimum_size)
            half_width = width / 2.0
            half_height = height / 2.0
            list(
                list(car(center)-half_width cadr(center)-half_height)
                list(car(center)+half_width cadr(center)+half_height)
            )
        )
    )
)

defun( dva_point_distance (point1 point2)
    let((dx dy)
        dx = car(point2) - car(point1)
        dy = cadr(point2) - cadr(point1)
        sqrt(dx * dx + dy * dy)
    )
)

defun( dva_unique_dbids (items)
    let((result item)
        result = nil
        foreach(item items
            when(item && !member(item result)
                result = append(result list(item))
            )
        )
        result
    )
)

defun( dva_unique_strings (items)
    let((result item)
        result = nil
        foreach(item items
            when(stringp(item) && strlen(item) > 0 && !member(item result)
                result = append(result list(item))
            )
        )
        result
    )
)

defun( dva_net_name (net)
    if(net && stringp(net->name) then net->name else "<NO_NET>")
)

defun( dva_object_label (object)
    let((center)
        if(!object then
            "<nil>"
        else
            center = dva_object_center(object)
            case(object->objType
                ("via" sprintf(nil "Via %s@%.4f,%.4f" dva_net_name(object->net) car(center) cadr(center)))
                ("pin" sprintf(nil "Pin %s@%.4f,%.4f" dva_net_name(object->net) car(center) cadr(center)))
                ("symbol" sprintf(nil "Symbol %s" if(object->refdes then object->refdes else "<unnamed>")))
                ("component" sprintf(nil "Component %s" if(object->name then object->name else "<unnamed>")))
                (t sprintf(nil "%s@%.4f,%.4f" object->objType car(center) cadr(center)))
            )
        )
    )
)

defun( dva_prop_value_named (object prop_name)
    let((props entry entry_name value)
        value = nil
        when(object
            props = errset(axlDBGetProperties(object list("user" "allegro")) nil)
            when(props && car(props)
                foreach(entry car(props)
                    when(entry
                        entry_name = car(entry)
                        when(symbolp(entry_name)
                            entry_name = symbolToString(entry_name)
                        )
                        when(stringp(entry_name) && equal(lowerCase(entry_name) lowerCase(prop_name))
                            value = cadr(entry)
                        )
                    )
                )
            )
        )
        value
    )
)

defun( dva_object_keepout_id (object)
    let((value)
        value = dva_prop_value_named(object _dva_prop_name)
        unless(value
            value = dva_prop_value_named(object _dva_legacy_prop_name)
        )
        value
    )
)

defun( dva_ensure_property ()
    errset(axlDBCreatePropDictEntry(_dva_prop_name "STRING" t) nil)
    t
)

defun( dva_dbid_list (objects)
    if(axlIsDBIDType(objects) then list(objects) else objects)
)

defun( dva_set_source_id (objects pair_id)
    let((targets result)
        targets = dva_dbid_list(objects)
        result = errset(axlDBAddProp(targets list(_dva_prop_name pair_id)) nil)
        errset(axlDBDeleteProp(targets list(_dva_legacy_prop_name)) nil)
        if(result && car(result) then t else nil)
    )
)

defun( dva_clear_source_ids (objects)
    let((targets)
        targets = dva_dbid_list(objects)
        errset(axlDBDeleteProp(targets list(_dva_prop_name _dva_legacy_prop_name)) nil)
        t
    )
)

defun( dva_new_keepout_id ()
    let((stamp)
        _dva_id_counter = _dva_id_counter + 1
        stamp = buildString(parseString(getCurrentTime() " :/") "")
        sprintf(nil "MOKA_AP_%s_%d" stamp _dva_id_counter)
    )
)

defun( dva_add_keepout_properties (shape pair_id)
    let((standard_result id_result routes_allowed vias_allowed keepout_id)
        standard_result = errset(
            axlDBAddProp(
                list(shape)
                list(
                    list("ROUTES_ALLOWED" t)
                    list("VIAS_ALLOWED" t)
                )
            )
            nil
        )
        id_result = errset(axlDBAddProp(list(shape) list(_dva_prop_name pair_id)) nil)
        routes_allowed = dva_prop_value_named(shape "ROUTES_ALLOWED")
        vias_allowed = dva_prop_value_named(shape "VIAS_ALLOWED")
        keepout_id = dva_prop_value_named(shape _dva_prop_name)
        if(routes_allowed && vias_allowed && equal(keepout_id pair_id) then
            t
        else
            _dva_last_error = "Route Keepout was created, but ROUTES_ALLOWED / VIAS_ALLOWED / MOKA_AP_KEEP_ID could not all be attached."
            nil
        )
    )
)

defun( dva_result_dbid (result)
    let((value)
        value = nil
        when(result && car(result)
            if(axlIsDBIDType(car(result)) then
                value = car(result)
            else
                when(listp(car(result)) && car(car(result)) && axlIsDBIDType(car(car(result)))
                    value = car(car(result))
                )
            )
        )
        value
    )
)

defun( dva_create_poly_keepout (polygon pair_id)
    let((result shape)
        shape = nil
        when(polygon
            result = errset(axlDBCreateShape(polygon t dva_route_keepout_layer()) nil)
            shape = dva_result_dbid(result)
            if(shape then
                unless(dva_add_keepout_properties(shape pair_id)
                    errset(axlDeleteObject(shape) nil)
                    shape = nil
                )
            else
                _dva_last_error = sprintf(nil "axlDBCreateShape failed on %s. Confirm the selected ROUTE KEEPOUT subclass exists and is writable." dva_route_keepout_layer())
            )
        )
        shape
    )
)

defun( dva_create_path_keepout (path pair_id)
    let((result shape)
        shape = nil
        when(path
            result = errset(axlDBCreateShape(path t dva_route_keepout_layer()) nil)
            shape = dva_result_dbid(result)
            if(shape then
                unless(dva_add_keepout_properties(shape pair_id)
                    errset(axlDeleteObject(shape) nil)
                    shape = nil
                )
            else
                _dva_last_error = sprintf(nil "axlDBCreateShape failed on %s. Confirm the selected ROUTE KEEPOUT subclass exists and is writable." dva_route_keepout_layer())
            )
        )
        shape
    )
)

defun( dva_create_rectangle_keepout (box pair_id)
    let((result shape)
        shape = nil
        when(dva_bbox_valid(box)
            result = errset(axlDBCreateRectangle(box t dva_route_keepout_layer()) nil)
            shape = dva_result_dbid(result)
            if(shape then
                unless(dva_add_keepout_properties(shape pair_id)
                    errset(axlDeleteObject(shape) nil)
                    shape = nil
                )
            else
                _dva_last_error = sprintf(nil "axlDBCreateRectangle failed on %s. Confirm the selected ROUTE KEEPOUT subclass exists and is writable." dva_route_keepout_layer())
            )
        )
        shape
    )
)

defun( dva_create_circle_keepout (center radius pair_id)
    let((path)
        if(center && radius > 0.0 then
            path = axlPathStartCircle(list(center radius) 0.0)
            dva_create_path_keepout(path pair_id)
        else
            nil
        )
    )
)

defun( dva_capsule_path (point1 point2 radius)
    let((dx dy distance ux uy nx ny p1 p2 p3 p4 path)
        path = nil
        dx = car(point2) - car(point1)
        dy = cadr(point2) - cadr(point1)
        distance = sqrt(dx * dx + dy * dy)
        if(distance <= 0.0 then
            path = axlPathStartCircle(list(point1 radius) 0.0)
        else
            ux = dx / distance
            uy = dy / distance
            nx = -uy
            ny = ux
            p1 = list(car(point1) + nx * radius cadr(point1) + ny * radius)
            p2 = list(car(point2) + nx * radius cadr(point2) + ny * radius)
            p3 = list(car(point2) - nx * radius cadr(point2) - ny * radius)
            p4 = list(car(point1) - nx * radius cadr(point1) - ny * radius)
            path = axlPathStart(list(p1 p2) 0.0)
            when(path
                axlPathArcCenter(path 0.0 p3 t point2)
                axlPathLine(path 0.0 p4)
                axlPathArcCenter(path 0.0 p1 t point1)
            )
        )
        path
    )
)

defun( dva_create_capsule_keepout (point1 point2 radius pair_id)
    dva_create_path_keepout(dva_capsule_path(point1 point2 radius) pair_id)
)

defun( dva_normalize_polygons (value)
    cond(
        (!value nil)
        (listp(value) value)
        (t list(value))
    )
)

defun( dva_object_polygons_typed (object pad_type)
    let((result pad_layer)
        result = nil
        when(object
            if(object->objType == "via" || object->objType == "pin" then
                pad_layer = strcat("ETCH/" _dva_layer)
                when(pad_type == 'REGULAR && _dva_geometry_mode == "CONTOUR"
                    pad_layer = dva_contour_source_layer()
                )
                result = errset(
                    axlPolyFromDB(
                        object
                        ?layer pad_layer
                        ?padType pad_type
                        ?holes nil
                    )
                    nil
                )
            else
                unless(pad_type == 'ANTI
                    result = errset(
                        axlPolyFromDB(object ?endCapType 'ROUND ?holes nil) nil)
                )
            )
        )
        if(result && car(result) then dva_normalize_polygons(car(result)) else nil)
    )
)

defun( dva_object_polygons (object)
    dva_object_polygons_typed(object 'REGULAR)
)

defun( dva_polygons_bbox (polygons)
    let((box polygon)
        box = nil
        foreach(polygon polygons
            when(polygon && polygon->bBox
                box = dva_bbox_union(box polygon->bBox)
            )
        )
        box
    )
)

defun( dva_point_lessp (point1 point2)
    car(point1) < car(point2) ||
        (car(point1) == car(point2) && cadr(point1) < cadr(point2))
)

defun( dva_points_equal (point1 point2)
    point1 && point2 &&
        abs(car(point1)-car(point2)) <= 0.0000001 &&
        abs(cadr(point1)-cadr(point2)) <= 0.0000001
)

defun( dva_unique_points (points)
    let((result point existing found)
        result = nil
        foreach(point points
            found = nil
            foreach(existing result
                when(dva_points_equal(point existing) found = t)
            )
            unless(found result = append(result list(point)))
        )
        result
    )
)

defun( dva_drop_last (items)
    if(items then reverse(cdr(reverse(items))) else nil)
)

defun( dva_hull_turn (point1 point2 point3)
    (car(point2)-car(point1)) * (cadr(point3)-cadr(point1)) -
        (cadr(point2)-cadr(point1)) * (car(point3)-car(point1))
)

defun( dva_build_half_hull (points)
    let((hull point count)
        hull = nil
        foreach(point points
            count = length(hull)
            while(count >= 2 && dva_hull_turn(nth(count-2 hull) nth(count-1 hull) point) <= 0.0
                hull = dva_drop_last(hull)
                count = length(hull)
            )
            hull = append(hull list(point))
        )
        hull
    )
)

defun( dva_convex_hull (points)
    let((sorted lower upper)
        sorted = sort(dva_unique_points(points) 'dva_point_lessp)
        if(length(sorted) < 3 then
            sorted
        else
            lower = dva_build_half_hull(sorted)
            upper = dva_build_half_hull(reverse(sorted))
            append(dva_drop_last(lower) dva_drop_last(upper))
        )
    )
)

defun( dva_polygon_points (polygon)
    let((points vertex)
        points = nil
        when(polygon && polygon->vertices
            foreach(vertex polygon->vertices
                when(car(vertex) points = append(points list(car(vertex))))
            )
        )
        points
    )
)

defun( dva_bbox_points (box)
    if(dva_bbox_valid(box) then
        list(
            car(box)
            list(car(cadr(box)) cadr(car(box)))
            cadr(box)
            list(car(car(box)) cadr(cadr(box)))
        )
    else
        nil
    )
)

defun( dva_polygons_points (polygons)
    let((points polygon)
        points = nil
        foreach(polygon polygons
            points = append(points dva_polygon_points(polygon))
        )
        dva_unique_points(points)
    )
)

defun( dva_points_to_polygons (points)
    let((path result)
        result = nil
        when(length(points) >= 3
            path = axlPathStart(append(points list(car(points))) 0.0)
            when(path result = errset(axlPolyFromDB(path ?holes nil) nil))
        )
        if(result && car(result) then dva_normalize_polygons(car(result)) else nil)
    )
)

defun( dva_group_contour_polygons (sources)
    let((result source polygons)
        result = nil
        foreach(source sources
            polygons = dva_object_polygons_typed(source 'REGULAR)
            unless(polygons
                polygons = dva_points_to_polygons(dva_bbox_points(dva_object_bbox(source)))
            )
            when(polygons result = append(result polygons))
        )
        result
    )
)

defun( dva_object_bbox (object)
    let((box polygons pin member)
        box = nil
        when(object
            case(object->objType
                ("component"
                    when(object->symbol
                        box = dva_object_bbox(object->symbol)
                    )
                )
                ("symbol"
                    foreach(pin object->pins
                        box = dva_bbox_union(box dva_object_bbox(pin))
                    )
                    unless(box box = object->bBox)
                )
                ("group"
                    foreach(member object->groupMembers
                        box = dva_bbox_union(box dva_object_bbox(member))
                    )
                    unless(box box = object->bBox)
                )
                (t
                    polygons = dva_object_polygons(object)
                    when(polygons box = dva_polygons_bbox(polygons))
                    unless(box box = object->bBox)
                    unless(box
                        when(object->xy box = list(object->xy object->xy))
                    )
                )
            )
        )
        box
    )
)

defun( dva_object_center (object)
    let((box)
        box = dva_object_bbox(object)
        if(box then dva_bbox_center(box) else if(object && object->xy then object->xy else 0:0))
    )
)

defun( dva_objects_bbox (objects)
    let((box object)
        box = nil
        foreach(object objects
            box = dva_bbox_union(box dva_object_bbox(object))
        )
        box
    )
)

defun( dva_object_cover_radius (object)
    let((box width height radius)
        box = dva_object_bbox(object)
        width = dva_bbox_width(box)
        height = dva_bbox_height(box)
        radius = sqrt(width * width + height * height) / 2.0
        radius = radius + _dva_clearance
        if(_dva_fixed_size && _dva_min_diameter > 0.0 then
            radius = _dva_min_diameter / 2.0
        else
            when(_dva_min_diameter > 0.0
                radius = max(radius _dva_min_diameter / 2.0)
            )
        )
        radius
    )
)

defun( dva_anchor_objects (object)
    let((result pin member)
        result = nil
        when(object
            case(object->objType
                ("via" result = list(object))
                ("pin" result = list(object))
                ("symbol" result = object->pins)
                ("component" when(object->symbol result = object->symbol->pins))
                ("group"
                    foreach(member object->groupMembers
                        result = append(result dva_anchor_objects(member))
                    )
                )
            )
        )
        dva_unique_dbids(result)
    )
)

defun( dva_each_objects (object)
    let((anchors)
        anchors = dva_anchor_objects(object)
        if(anchors then anchors else if(object then list(object) else nil))
    )
)

defun( dva_selected_sources (selected)
    let((result object)
        result = nil
        foreach(object selected
            if(_dva_target_mode == "DIFF_AUTO" || _dva_target_mode == "PAIR_MANUAL" then
                result = append(result dva_anchor_objects(object))
            else
                if(_dva_target_mode == "EACH" then
                    result = append(result dva_each_objects(object))
                else
                    when(object result = append(result list(object)))
                )
            )
        )
        dva_unique_dbids(result)
    )
)

defun( dva_net_anchors (net)
    let((result branch child)
        result = nil
        when(net && net->branches
            foreach(branch net->branches
                foreach(child branch->children
                    when(child && (child->objType == "via" || child->objType == "pin")
                        result = append(result list(child))
                    )
                )
            )
        )
        dva_unique_dbids(result)
    )
)

defun( dva_all_anchors ()
    let((result design net symbol)
        result = nil
        design = axlDBGetDesign()
        when(design
            foreach(net design->nets
                result = append(result dva_net_anchors(net))
            )
            foreach(symbol design->symbols
                result = append(result symbol->pins)
            )
        )
        dva_unique_dbids(result)
    )
)

defun( dva_member_nets (member_dbid)
    let((result child)
        result = nil
        when(member_dbid
            cond(
                (member_dbid->objType == "net" result = list(member_dbid))
                (member_dbid->objType == "group"
                    foreach(child member_dbid->groupMembers
                        result = append(result dva_member_nets(child))
                    )
                )
            )
        )
        dva_unique_dbids(result)
    )
)

defun( dva_member_contains_net (member_dbid net)
    let((found candidate)
        found = nil
        foreach(candidate dva_member_nets(member_dbid)
            when(candidate == net || equal(upperCase(dva_net_name(candidate)) upperCase(dva_net_name(net)))
                found = t
            )
        )
        found
    )
)

defun( dva_diffpair_for_anchor (anchor)
    let((groups result)
        result = nil
        when(anchor && anchor->net
            groups = errset(axlDBGetGroupFromItem(anchor->net "DIFF_PAIR" t) nil)
            when(groups && car(groups)
                result = car(car(groups))
            )
        )
        result
    )
)

defun( dva_find_anchor_by_id (source pair_id)
    let((result candidate)
        result = nil
        foreach(candidate dva_all_anchors()
            when(!result && candidate != source && candidate->objType == source->objType && equal(dva_object_keepout_id(candidate) pair_id)
                result = candidate
            )
        )
        result
    )
)

defun( dva_auto_mate (anchor)
    let((pair_id result diffpair own_member other_member member net candidate distance best_distance)
        result = nil
        best_distance = nil
        pair_id = dva_object_keepout_id(anchor)
        when(pair_id
            result = dva_find_anchor_by_id(anchor pair_id)
        )
        unless(result
            diffpair = dva_diffpair_for_anchor(anchor)
            when(diffpair && length(diffpair->groupMembers) >= 2
                own_member = nil
                other_member = nil
                foreach(member diffpair->groupMembers
                    if(dva_member_contains_net(member anchor->net) then
                        own_member = member
                    else
                        unless(other_member other_member = member)
                    )
                )
                when(own_member && other_member
                    foreach(net dva_member_nets(other_member)
                        foreach(candidate dva_net_anchors(net)
                            when(candidate != anchor && candidate->objType == anchor->objType
                                distance = dva_point_distance(dva_object_center(anchor) dva_object_center(candidate))
                                when(distance <= _dva_max_pair_distance && (!best_distance || distance < best_distance)
                                    result = candidate
                                    best_distance = distance
                                )
                            )
                        )
                    )
                )
            )
        )
        result
    )
)

defun( dva_pair_exists (pairs object1 object2)
    let((found pair)
        found = nil
        foreach(pair pairs
            when((car(pair) == object1 && cadr(pair) == object2) || (car(pair) == object2 && cadr(pair) == object1)
                found = t
            )
        )
        found
    )
)

defun( dva_build_auto_pairs (anchors)
    let((pairs anchor mate)
        pairs = nil
        foreach(anchor anchors
            mate = dva_auto_mate(anchor)
            when(mate && !dva_pair_exists(pairs anchor mate)
                pairs = append(pairs list(list(anchor mate)))
            )
        )
        pairs
    )
)

defun( dva_poly_expansion (polygon)
    let((box width height min_dimension expansion)
        expansion = _dva_clearance
        when(_dva_min_diameter > 0.0 && polygon && polygon->bBox
            box = polygon->bBox
            width = dva_bbox_width(box)
            height = dva_bbox_height(box)
            min_dimension = min(width height)
            when(min_dimension < _dva_min_diameter
                expansion = max(expansion (_dva_min_diameter-min_dimension)/2.0)
            )
        )
        expansion
    )
)

defun( dva_expand_polygon (polygon)
    let((expansion expand_type result)
        result = nil
        expansion = dva_poly_expansion(polygon)
        expand_type = if(_dva_geometry_mode == "CONTOUR" then 'NONE else 'ALL_ARC)
        if(expansion > 0.0 then
            result = errset(axlPolyExpand(polygon expansion expand_type) nil)
        else
            result = list(polygon)
        )
        if(result && car(result) then dva_normalize_polygons(car(result)) else nil)
    )
)

defun( dva_create_contour_geometry (sources pair_id)
    let((count source polygons polygon expanded output fallback_box pad_type)
        count = 0
        pad_type = if(_dva_geometry_mode == "ANTIPAD" then 'ANTI else 'REGULAR)
        foreach(source sources
            polygons = dva_object_polygons_typed(source pad_type)
            if(polygons then
                foreach(polygon polygons
                    expanded = dva_expand_polygon(polygon)
                    foreach(output expanded
                        when(dva_create_poly_keepout(output pair_id)
                            count = count + 1
                        )
                    )
                )
            else
                fallback_box = dva_bbox_force_minimum(dva_bbox_expand(dva_object_bbox(source) _dva_clearance) _dva_min_diameter)
                when(dva_create_rectangle_keepout(fallback_box pair_id)
                    count = count + 1
                )
            )
        )
        count
    )
)

defun( dva_create_group_contour_geometry (sources pair_id)
    let((source_polygons points hull hull_polygons merge_result merged_polygons
         base_polygon expanded output fallback_box count)
        count = 0
        source_polygons = dva_group_contour_polygons(sources)
        points = dva_polygons_points(source_polygons)
        hull = dva_convex_hull(points)
        if(length(hull) >= 3 then
            hull_polygons = dva_points_to_polygons(hull)
            when(hull_polygons
                merge_result = errset(
                    axlPolyOperation(source_polygons hull_polygons 'OR) nil)
                when(merge_result && car(merge_result)
                    merged_polygons = dva_normalize_polygons(car(merge_result))
                )
                unless(merged_polygons merged_polygons = hull_polygons)
                base_polygon = car(merged_polygons)
                when(base_polygon
                    expanded = dva_expand_polygon(base_polygon)
                    output = car(expanded)
                    when(output && dva_create_poly_keepout(output pair_id)
                        count = 1
                    )
                )
            )
        )
        when(count == 0
            fallback_box = dva_bbox_force_minimum(
                dva_bbox_expand(dva_objects_bbox(sources) _dva_clearance)
                _dva_min_diameter)
            when(dva_create_rectangle_keepout(fallback_box pair_id)
                count = 1
            )
        )
        count
    )
)

defun( dva_create_circle_for_bbox (box pair_id)
    let((center width height radius)
        if(dva_bbox_valid(box) then
            progn(
                center = dva_bbox_center(box)
                width = dva_bbox_width(box)
                height = dva_bbox_height(box)
                radius = sqrt(width * width + height * height) / 2.0 + _dva_clearance
                if(_dva_fixed_size && _dva_min_diameter > 0.0 then
                    radius = _dva_min_diameter / 2.0
                else
                    when(_dva_min_diameter > 0.0
                        radius = max(radius _dva_min_diameter / 2.0)
                    )
                )
                dva_create_circle_keepout(center radius pair_id)
            )
        else
            nil
        )
    )
)

defun( dva_create_capsule_for_bbox (box pair_id)
    let((center width height radius base_radius point1 point2)
        if(dva_bbox_valid(box) then
            progn(
                center = dva_bbox_center(box)
                width = dva_bbox_width(box)
                height = dva_bbox_height(box)
                if(width >= height then
                    progn(
                        base_radius = height / 2.0
                        radius = base_radius + _dva_clearance
                        point1 = list(car(car(box)) + base_radius cadr(center))
                        point2 = list(car(cadr(box)) - base_radius cadr(center))
                    )
                else
                    progn(
                        base_radius = width / 2.0
                        radius = base_radius + _dva_clearance
                        point1 = list(car(center) cadr(car(box)) + base_radius)
                        point2 = list(car(center) cadr(cadr(box)) - base_radius)
                    )
                )
                if(_dva_fixed_size && _dva_min_diameter > 0.0 then
                    radius = _dva_min_diameter / 2.0
                else
                    when(_dva_min_diameter > 0.0
                        radius = max(radius _dva_min_diameter / 2.0)
                    )
                )
                dva_create_capsule_keepout(point1 point2 radius pair_id)
            )
        else
            nil
        )
    )
)

defun( dva_create_pair_capsule (sources pair_id)
    let((point1 point2 radius)
        if(sources && length(sources) == 2 then
            progn(
                point1 = dva_object_center(nth(0 sources))
                point2 = dva_object_center(nth(1 sources))
                if(point1 && point2 then
                    progn(
                        radius = max(dva_object_cover_radius(nth(0 sources)) dva_object_cover_radius(nth(1 sources)))
                        dva_create_capsule_keepout(point1 point2 radius pair_id)
                    )
                else
                    nil
                )
            )
        else
            nil
        )
    )
)

defun( dva_create_geometry (sources grouped pair_id)
    let((count source box)
        count = 0
        case(_dva_geometry_mode
            (("ANTIPAD" "CONTOUR")
                if(grouped && _dva_target_mode == "GROUP" && _dva_geometry_mode == "CONTOUR" then
                    count = dva_create_group_contour_geometry(sources pair_id)
                else
                    count = dva_create_contour_geometry(sources pair_id)
                )
            )
            ("CIRCLE"
                if(grouped then
                    when(dva_create_circle_for_bbox(dva_objects_bbox(sources) pair_id)
                        count = 1
                    )
                else
                    foreach(source sources
                        when(dva_create_circle_for_bbox(dva_object_bbox(source) pair_id)
                            count = count + 1
                        )
                    )
                )
            )
            ("CAPSULE"
                if(grouped && length(sources) == 2 && (_dva_target_mode == "DIFF_AUTO" || _dva_target_mode == "PAIR_MANUAL") then
                    when(dva_create_pair_capsule(sources pair_id)
                        count = 1
                    )
                else
                    if(grouped then
                        when(dva_create_capsule_for_bbox(dva_objects_bbox(sources) pair_id)
                            count = 1
                        )
                    else
                        foreach(source sources
                            when(dva_create_capsule_for_bbox(dva_object_bbox(source) pair_id)
                                count = count + 1
                            )
                        )
                    )
                )
            )
            ("RECTANGLE"
                if(grouped then
                    if(_dva_fixed_size && _dva_min_diameter > 0.0 then
                        box = dva_bbox_force_minimum(list(dva_bbox_center(dva_objects_bbox(sources)) dva_bbox_center(dva_objects_bbox(sources))) _dva_min_diameter)
                    else
                        box = dva_bbox_force_minimum(dva_bbox_expand(dva_objects_bbox(sources) _dva_clearance) _dva_min_diameter)
                    )
                    when(dva_create_rectangle_keepout(box pair_id)
                        count = 1
                    )
                else
                    foreach(source sources
                        if(_dva_fixed_size && _dva_min_diameter > 0.0 then
                            box = dva_bbox_force_minimum(list(dva_object_center(source) dva_object_center(source)) _dva_min_diameter)
                        else
                            box = dva_bbox_force_minimum(dva_bbox_expand(dva_object_bbox(source) _dva_clearance) _dva_min_diameter)
                        )
                        when(dva_create_rectangle_keepout(box pair_id)
                            count = count + 1
                        )
                    )
                )
            )
        )
        count
    )
)

defun( dva_tagged_legacy_voids (shape pair_id)
    let((result void_id)
        result = nil
        when(shape && shape->voids
            foreach(void_id shape->voids
                when(equal(dva_prop_value_named(void_id _dva_legacy_prop_name) pair_id)
                    result = append(result list(void_id))
                )
            )
        )
        result
    )
)

defun( dva_delete_legacy_from_shape (shape pair_id)
    let((voids opened delete_result close_result closed_shape count)
        count = 0
        voids = dva_tagged_legacy_voids(shape pair_id)
        when(voids && !shape->shapeBoundary
            opened = errset(axlDBOpenShape(shape) nil)
            when(opened && car(opened)
                delete_result = errset(axlShapeDeleteVoids(voids) nil)
                close_result = errset(axlDBCreateCloseShape(shape) nil)
                when(delete_result && car(delete_result) && close_result && car(close_result)
                    count = length(voids)
                    closed_shape = car(car(close_result))
                    when(closed_shape && closed_shape->shapeIsBoundary
                        errset(axlShapeDynamicUpdate(closed_shape t) nil)
                    )
                )
            )
        )
        count
    )
)

defun( dva_delete_legacy_voids (pair_id)
    let((count result shape)
        count = 0
        result = errset(axlDBGetShapes("BOUNDARY") nil)
        when(result && car(result)
            foreach(shape car(result)
                count = count + dva_delete_legacy_from_shape(shape pair_id)
            )
        )
        result = errset(axlDBGetShapes("ETCH") nil)
        when(result && car(result)
            foreach(shape car(result)
                when(!shape->shapeBoundary
                    count = count + dva_delete_legacy_from_shape(shape pair_id)
                )
            )
        )
        count
    )
)

defun( dva_delete_route_keepouts (pair_id)
    let((result shapes shape targets count delete_result)
        count = 0
        targets = nil
        result = errset(axlDBGetShapes("ROUTE KEEPOUT") nil)
        when(result && car(result)
            foreach(shape car(result)
                when(equal(dva_prop_value_named(shape _dva_prop_name) pair_id)
                    targets = append(targets list(shape))
                )
            )
        )
        when(targets
            delete_result = errset(axlDeleteObject(targets) nil)
            when(delete_result && car(delete_result)
                count = length(targets)
            )
        )
        count
    )
)

defun( dva_delete_id_everywhere (pair_id)
    dva_delete_route_keepouts(pair_id) + dva_delete_legacy_voids(pair_id)
)

defun( dva_matching_ids (sources)
    let((ids source value)
        ids = nil
        foreach(source sources
            value = dva_object_keepout_id(source)
            when(value ids = append(ids list(value)))
        )
        dva_unique_strings(ids)
    )
)

defun( dva_clear_matching_id (objects pair_id)
    let((targets object)
        targets = nil
        foreach(object objects
            when(equal(dva_object_keepout_id(object) pair_id)
                targets = append(targets list(object))
            )
        )
        when(targets dva_clear_source_ids(targets))
        length(targets)
    )
)

defun( dva_clear_id_from_all_anchors (pair_id)
    dva_clear_matching_id(dva_all_anchors() pair_id)
)

defun( dva_apply_group (sources grouped)
    let((old_ids pair_id deleted_count keepout_count message old_id)
        old_ids = dva_matching_ids(sources)
        deleted_count = 0
        keepout_count = 0
        message = nil
        pair_id = nil
        _dva_last_error = nil

        if(old_ids && !_dva_replace_existing then
            message = "Selected source already has a Moka anti-pad. Enable Replace existing to rebuild it."
        else
            if(length(old_ids) == 1 then
                pair_id = car(old_ids)
            else
                pair_id = dva_new_keepout_id()
            )
            foreach(old_id old_ids
                deleted_count = deleted_count + dva_delete_id_everywhere(old_id)
                dva_clear_id_from_all_anchors(old_id)
                dva_clear_matching_id(sources old_id)
            )
            keepout_count = dva_create_geometry(sources grouped pair_id)
            when(keepout_count > 0
                unless(dva_set_source_id(sources pair_id)
                    keepout_count = 0
                    message = "Route Keepout was created, but the source objects could not be tagged. The group was rolled back."
                )
            )
            when(keepout_count == 0 && !message && _dva_last_error
                message = _dva_last_error
            )
        )
        list(pair_id keepout_count deleted_count message)
    )
)

defun( dva_highlight_objects (objects mode)
    let((object)
        foreach(object objects
            if(mode then
                errset(axlHighlightObject(object t) nil)
            else
                errset(axlDehighlightObject(object t) nil)
            )
        )
        errset(axlFlushDisplay() nil)
    )
)

defun( dva_confirm_objects (objects action)
    let((answer message)
        answer = t
        when(_dva_confirm_before_apply
            dva_highlight_objects(objects t)
            message = sprintf(
                nil
                "%s %d source object(s) on ROUTE KEEPOUT/%s?"
                action
                length(objects)
                _dva_layer
            )
            answer = axlUIYesNo(message "Moka skill - Anti-Pad" 'yes)
            dva_highlight_objects(objects nil)
        )
        answer
    )
)

defun( dva_group_label (sources)
    if(length(sources) == 1 then
        dva_object_label(car(sources))
    else
        sprintf(nil "%d objects" length(sources))
    )
)

defun( dva_apply_marked_group (sources grouped)
    let((result ok message)
        ok = nil
        axlDBTransactionMark(_dva_mark)
        result = dva_apply_group(sources grouped)
        if(nth(1 result) > 0 then
            progn(
                _dva_session_op_count = _dva_session_op_count + 1
                ok = t
            )
        else
            progn(
                axlDBTransactionOops(_dva_mark)
                message = nth(3 result)
                unless(message message = "No route keepout geometry could be created from the selected source.")
                dva_put_msg(sprintf(nil "%s: %s" dva_group_label(sources) message))
            )
        )
        ok
    )
)

defun( dva_run_apply_selection (selected)
    let((sources pairs pair confirm_objects success_count)
        sources = dva_selected_sources(selected)
        success_count = 0
        if(!sources then
            dva_ui_set_status("No supported source objects were selected.")
        else
            case(_dva_target_mode
                ("EACH"
                    when(dva_confirm_objects(sources "Create one anti-pad for each of")
                        foreach(source sources
                            when(dva_apply_marked_group(list(source) nil)
                                success_count = success_count + 1
                            )
                        )
                    )
                )
                ("DIFF_AUTO"
                    pairs = dva_build_auto_pairs(sources)
                    if(!pairs then
                        dva_ui_set_status("No constrained differential mate was found within the maximum distance.")
                    else
                        confirm_objects = nil
                        foreach(pair pairs confirm_objects = append(confirm_objects pair))
                        confirm_objects = dva_unique_dbids(confirm_objects)
                        when(dva_confirm_objects(confirm_objects "Create differential anti-pads for")
                            foreach(pair pairs
                                when(dva_apply_marked_group(pair t)
                                    success_count = success_count + 1
                                )
                            )
                        )
                    )
                )
                ("PAIR_MANUAL"
                    if(length(sources) != 2 then
                        dva_ui_set_status("Manual pair mode requires exactly two Via/Pin source objects.")
                    else
                        when(dva_confirm_objects(sources "Create one paired anti-pad for")
                            when(dva_apply_marked_group(sources t)
                                success_count = 1
                            )
                        )
                    )
                )
                ("GROUP"
                    when(dva_confirm_objects(sources "Create one anti-pad around the selected objects")
                        when(dva_apply_marked_group(sources t)
                            success_count = 1
                        )
                    )
                )
            )
            when(success_count > 0
                dva_ui_set_status(sprintf(nil "Created %d anti-pad group(s). Continue selecting or right-click Done." success_count))
            )
        )
    )
)

defun( dva_remove_id (pair_id selected)
    let((deleted_count cleared_count)
        deleted_count = dva_delete_id_everywhere(pair_id)
        cleared_count = dva_clear_id_from_all_anchors(pair_id)
        cleared_count = cleared_count + dva_clear_matching_id(selected pair_id)
        list(deleted_count cleared_count)
    )
)

defun( dva_run_remove_selection (selected)
    let((sources ids pair_id result success_count)
        sources = dva_unique_dbids(append(selected dva_selected_sources(selected)))
        ids = dva_matching_ids(sources)
        success_count = 0
        if(!ids then
            dva_ui_set_status("The selection has no Moka anti-pad ID.")
        else
            when(dva_confirm_objects(sources "Remove tagged anti-pads referenced by")
                foreach(pair_id ids
                    axlDBTransactionMark(_dva_mark)
                    result = dva_remove_id(pair_id sources)
                    if(nth(0 result) > 0 || nth(1 result) > 0 then
                        progn(
                            success_count = success_count + 1
                            _dva_session_op_count = _dva_session_op_count + 1
                        )
                    else
                        axlDBTransactionOops(_dva_mark)
                    )
                )
            )
            dva_ui_set_status(sprintf(nil "Removed %d tagged anti-pad group(s). Continue selecting or right-click Done." success_count))
        )
    )
)

defun( dva_cb_done ()
    _dva_finished = t
    _dva_commit = t
    axlCancelEnterFun()
)

defun( dva_cb_cancel ()
    _dva_finished = t
    _dva_commit = nil
    axlCancelEnterFun()
)

defun( dva_cb_oops ()
    if(_dva_mark && _dva_session_op_count > 0 then
        if(axlDBTransactionOops(_dva_mark) then
            _dva_session_op_count = _dva_session_op_count - 1
            dva_ui_set_status("Previous anti-pad operation was undone.")
        else
            dva_ui_set_status("Unable to undo the previous anti-pad operation.")
        )
    else
        dva_ui_set_status("No anti-pad operation is available to undo.")
    )
    axlClearSelSet()
    axlCancelEnterFun()
)

defun( dva_cmd_run ()
    let((popup selected)
        _dva_run_active = t
        _dva_finished = nil
        _dva_commit = nil
        _dva_session_op_count = 0
        axlClearSelSet()
        axlUIPopupSet(nil)
        dva_ensure_property()
        axlSetFindFilter(
            ?enabled list("noall" "vias" "pins" "symbols" "components" "groups" "clines" "clinesegs" "shapes" "noboundary_shapes")
            ?onButtons list("noall" "vias" "pins" "symbols" "components" "groups" "clines" "clinesegs" "shapes")
        )
        _dva_mark = axlDBTransactionStart()
        popup = axlUIPopupDefine(
            nil
            list(
                list("Done" 'dva_cb_done)
                list("Oops" 'dva_cb_oops)
                list("Cancel" 'dva_cb_cancel)
            )
        )
        axlUIPopupSet(popup)

        unwindProtect(
            progn(
                while(!_dva_finished
                    if(_dva_operation == "REMOVE" then
                        dva_put_msg("Select a tagged source object or Moka Route Keepout to remove. Right-click Done when finished.")
                    else
                        dva_put_msg("Select Via, Pin, component, Cline, Cline Seg, or Shape sources for the configured anti-pad mode.")
                    )
                    if(axlSelect() && !_dva_finished then
                        selected = axlGetSelSet()
                        when(selected
                            if(_dva_operation == "REMOVE" then
                                dva_run_remove_selection(selected)
                            else
                                dva_run_apply_selection(selected)
                            )
                        )
                        axlClearSelSet()
                    )
                )
            )
            progn(
                if(_dva_commit then
                    progn(
                        when(_dva_mark axlDBTransactionCommit(_dva_mark))
                        dva_ui_set_status("Session committed. Use Oops or Cancel before Done; committed SKILL changes are not added to Allegro global Undo.")
                    )
                else
                    progn(
                        when(_dva_mark axlDBTransactionRollback(_dva_mark))
                        dva_ui_set_status("Session cancelled; all keepout changes from this session were rolled back.")
                    )
                )
                _dva_mark = nil
                _dva_session_op_count = 0
                _dva_run_active = nil
                axlUIPopupSet(nil)
                axlClearSelSet()
                dva_ui_close_if_pending()
            )
        )
    )
)

defun( dva_validate_params ()
    let((error_message layers)
        error_message = nil
        layers = dva_board_layers()
        cond(
            (!layers error_message = "The drawing has no ETCH layer stack.")
            (!member(_dva_layer layers) error_message = "The selected placement layer is invalid.")
            (_dva_clearance < 0.0 error_message = "Clearance cannot be negative.")
            (_dva_min_diameter < 0.0 error_message = "Minimum diameter cannot be negative.")
            (_dva_target_mode == "DIFF_AUTO" && _dva_max_pair_distance <= 0.0 error_message = "Maximum pair distance must be greater than zero.")
            (_dva_fixed_size && member(_dva_geometry_mode list("CIRCLE" "CAPSULE" "RECTANGLE")) && _dva_min_diameter <= 0.0
                error_message = "Fixed size must be greater than zero."
            )
            (_dva_target_mode == "GROUP" && _dva_geometry_mode == "ANTIPAD"
                error_message = "Overall selection does not support existing Padstack ANTI geometry."
            )
        )
        error_message
    )
)

defun( dva_ui_set_status (status_text)
    when(status_text dva_put_msg(status_text))
    t
)

defun( dva_panel_release_enter ()
    let((result)
        result = errset(axlCancelEnterFun() nil)
        unless(result && car(result)
            errset(axlFinishEnterFun() nil)
        )
        t
    )
)

defun( dva_panel_schedule (action)
    _dva_panel_action = action
    dva_panel_release_enter()
)

defun( dva_panel_stop ()
    _dva_panel_active = nil
    dva_panel_release_enter()
)

defun( dva_panel_done ()
    if(_dva_run_active then
        _dva_ui_close_pending = t
        dva_cb_done()
    else
        _dva_panel_active = nil
        errset(axlFinishEnterFun() nil)
    )
    t
)

defun( dva_panel_cancel ()
    if(_dva_run_active then
        _dva_ui_close_pending = t
        dva_cb_cancel()
    else
        dva_panel_stop()
    )
    t
)

defun( dva_ui_store_params (form)
    _dva_clearance = dva_parse_real(axlFormGetField(form "clearance") _dva_clearance)
    _dva_min_diameter = dva_parse_real(axlFormGetField(form "min_diameter") _dva_min_diameter)
    _dva_fixed_size = if(axlFormGetField(form "fixed_size") then t else nil)
    _dva_max_pair_distance = dva_parse_real(axlFormGetField(form "pair_distance") _dva_max_pair_distance)
    _dva_replace_existing = if(axlFormGetField(form "replace_existing") then t else nil)
    _dva_confirm_before_apply = if(axlFormGetField(form "confirm_apply") then t else nil)
    t
)

defun( dva_ui_update_editability (form)
    errset(axlFormSetFieldEditable(form "pair_distance" _dva_target_mode == "DIFF_AUTO") nil)
    errset(axlFormSetFieldEditable(form "fixed_size" member(_dva_geometry_mode list("CIRCLE" "CAPSULE" "RECTANGLE"))) nil)
)

defun( dva_ui_request_close (form)
    if(_dva_run_active then
        _dva_ui_close_pending = t
        dva_cb_cancel()
    else
        if(_dva_panel_active then
            dva_panel_stop()
        else
            _dva_ui_form = nil
            errset(axlFormClose(form) nil)
        )
    )
)

defun( dva_ui_close_if_pending ()
    when(_dva_ui_close_pending && _dva_ui_form && !_dva_run_active
        _dva_ui_close_pending = nil
        if(_dva_panel_active then
            dva_panel_stop()
        else
            dva_ui_request_close(_dva_ui_form)
        )
    )
)

defun( dva_ui_start (form operation)
    let((error_message)
        if(_dva_run_active then
            dva_ui_set_status("Finish or cancel the current selection session first.")
        else
            dva_ui_store_params(form)
            error_message = dva_validate_params()
            if(error_message then
                dva_ui_set_status(error_message)
            else
                _dva_operation = operation
                when(operation == "APPLY" && _dva_geometry_mode == "CONTOUR"
                    _dva_source_layer = dva_active_etch_layer()
                )
                dva_ui_set_status(if(operation == "REMOVE" then "Select tagged sources or Moka Route Keepouts." else "Select source objects for the configured anti-pad mode."))
                if(_dva_panel_active then
                    dva_panel_schedule(operation)
                else
                    _dva_run_active = t
                    axlShellPost("moka_dp_antipad_run")
                )
            )
        )
    )
)

defun( dva_ui_form_cb (form)
    let((field value)
        if(form->doneState > 0 then
            dva_ui_request_close(form)
        else
            field = form->curField
            value = form->curValue
            case(field
                ("target_mode"
                    when(value _dva_target_mode = value)
                    errset(axlFormSetField(form "target_mode" _dva_target_mode) nil)
                    dva_ui_update_editability(form)
                )
                ("geometry_mode"
                    when(value _dva_geometry_mode = value)
                    errset(axlFormSetField(form "geometry_mode" _dva_geometry_mode) nil)
                    dva_ui_update_editability(form)
                )
                ("layer"
                    when(value _dva_layer = value)
                    errset(axlFormSetField(form "layer" _dva_layer) nil)
                )
                ("btn_apply" dva_ui_start(form "APPLY"))
                ("btn_remove" dva_ui_start(form "REMOVE"))
                ("btn_finish"
                    if(_dva_run_active then dva_cb_done() else dva_ui_set_status("No selection session is active."))
                )
                ("btn_cancel"
                    if(_dva_run_active then dva_cb_cancel() else dva_ui_set_status("No selection session is active."))
                )
                ("btn_close" dva_ui_request_close(form))
                (t dva_ui_store_params(form))
            )
        )
        t
    )
)

defun( dva_write_form (form_file)
    let((port ok)
        ok = nil
        port = outfile(form_file)
        when(port
            fprintf(port "FILE_TYPE=FORM_DEFN VERSION=2\n")
            fprintf(port "FORM\nFIXED\nPORT 32 42\n")
            fprintf(port "HEADER \"Moka skill v%s - Anti-Pad\"\n" _dva_version)
            fprintf(port "POPUP <TARGETMODE> \"Auto DP\" \"DIFF_AUTO\".\n")
            fprintf(port "POPUP <GEOMETRYMODE> \"Ellipse\" \"CAPSULE\".\n")
            fprintf(port "POPUP <LAYERPOP> \"TOP\" \"TOP\".\n")
            fprintf(port "TILE\n")
            fprintf(port "TEXT \"\304\277\261\352\300\340\320\315\072\"\nTLOC 1 1\nENDTEXT\n")
            fprintf(port "FIELD target_mode\nFLOC 11 1\nENUMSET 16\nPOP \"TARGETMODE\"\nENDFIELD\n")
            fprintf(port "TEXT \"\274\270\272\316\267\275\312\275\072\"\nTLOC 1 4\nENDTEXT\n")
            fprintf(port "FIELD geometry_mode\nFLOC 11 4\nENUMSET 16\nPOP \"GEOMETRYMODE\"\nENDFIELD\n")
            fprintf(port "TEXT \"\267\305\326\303\262\343\072\"\nTLOC 1 7\nENDTEXT\n")
            fprintf(port "FIELD layer\nFLOC 11 7\nENUMSET 16\nPOP \"LAYERPOP\"\nENDFIELD\n")
            fprintf(port "FIELD replace_existing\nFLOC 1 11\nCHECKLIST \"\314\346\273\273\322\321\323\320\311\350\326\303\"\nENDFIELD\n")
            fprintf(port "FIELD confirm_apply\nFLOC 1 14\nCHECKLIST \"\262\331\327\367\307\260\310\267\310\317\"\nENDFIELD\n")
            fprintf(port "FIELD fixed_size\nFLOC 1 17\nCHECKLIST \"\271\314\266\250\264\363\320\241\"\nENDFIELD\n")
            fprintf(port "TEXT \"Units: %s\"\nTLOC 1 20\nENDTEXT\n" dva_design_units())
            fprintf(port "TEXT \"\315\342\300\251\301\277\072\"\nTLOC 1 23\nENDTEXT\n")
            fprintf(port "FIELD clearance\nFLOC 17 23\nREALFILLIN 10 12\nDECIMAL 4\nENDFIELD\n")
            fprintf(port "TEXT \"\263\337\264\347\057\327\356\320\241\326\261\276\266\072\"\nTLOC 1 26\nENDTEXT\n")
            fprintf(port "FIELD min_diameter\nFLOC 17 26\nREALFILLIN 10 12\nDECIMAL 4\nENDFIELD\n")
            fprintf(port "TEXT \"\327\356\264\363\305\344\266\324\276\340\300\353\072\"\nTLOC 1 29\nENDTEXT\n")
            fprintf(port "FIELD pair_distance\nFLOC 17 29\nREALFILLIN 10 12\nDECIMAL 4\nENDFIELD\n")
            fprintf(port "FIELD btn_apply\nFLOC 1 32\nMENUBUTTON \"\321\241\324\361\262\242\323\246\323\303\" 13 3\nENDFIELD\n")
            fprintf(port "FIELD btn_remove\nFLOC 15 32\nMENUBUTTON \"\321\241\324\361\262\242\311\276\263\375\" 13 3\nENDFIELD\n")
            fprintf(port "FIELD btn_finish\nFLOC 1 35\nMENUBUTTON \"\315\352\263\311\" 8 3\nENDFIELD\n")
            fprintf(port "FIELD btn_cancel\nFLOC 11 35\nMENUBUTTON \"\310\241\317\373\262\331\327\367\" 17 3\nENDFIELD\n")
            fprintf(port "FIELD btn_close\nFLOC 20 38\nMENUBUTTON \"\271\330\261\325\" 9 3\nENDFIELD\n")
            fprintf(port "ENDTILE\nENDFORM\n")
            close(port)
            ok = t
        )
        ok
    )
)

defun( dva_ui_build_popups (form layers)
    let((target_popup geometry_popup layer_popup layer)
        target_popup = list(
            list("\265\245\270\366\266\324\317\363" "EACH")
            list("\327\324\266\257\262\356\267\326\266\324" "DIFF_AUTO")
            list("\312\326\266\257\313\253\266\324\317\363" "PAIR_MANUAL")
            list("\325\373\314\345\260\374\316\247" "GROUP")
        )
        geometry_popup = list(
            list("\317\326\323\320\267\264\272\270\305\314" "ANTIPAD")
            list("\324\255\312\274\302\326\300\252" "CONTOUR")
            list("\324\262\320\316" "CIRCLE")
            list("\315\326\324\262\320\316" "CAPSULE")
            list("\276\330\320\316" "RECTANGLE")
        )
        layer_popup = nil
        foreach(layer layers
            layer_popup = append(layer_popup list(list(layer layer)))
        )
        axlFormBuildPopup(form "target_mode" target_popup)
        axlFormBuildPopup(form "geometry_mode" geometry_popup)
        axlFormBuildPopup(form "layer" layer_popup)
    )
)

defun( dva_ui_initialize_fields (form layers)
    unless(stringp(_dva_layer) && member(_dva_layer layers)
        _dva_layer = car(layers)
    )
    axlFormSetField(form "target_mode" _dva_target_mode)
    axlFormSetField(form "geometry_mode" _dva_geometry_mode)
    axlFormSetField(form "layer" _dva_layer)
    axlFormSetField(form "clearance" _dva_clearance)
    axlFormSetField(form "min_diameter" _dva_min_diameter)
    axlFormSetField(form "fixed_size" _dva_fixed_size)
    axlFormSetField(form "pair_distance" _dva_max_pair_distance)
    axlFormSetField(form "replace_existing" _dva_replace_existing)
    axlFormSetField(form "confirm_apply" _dva_confirm_before_apply)
    dva_ui_update_editability(form)
)

defun( dva_ui_open ()
    let((layers form_file form load_result point action saved_enabled saved_on)
        dva_init_defaults()
        layers = dva_board_layers()
        if(!layers then
            dva_put_msg("The active drawing has no ETCH layer stack.")
        else
            _dva_panel_active = t
            _dva_panel_action = nil
            _dva_ui_ministatus = nil
            _dva_source_layer = ""
            saved_enabled = axlGetFindFilter()
            saved_on = axlGetFindFilter(t)
            form_file = axlTempFile(t)
            if(dva_write_form(form_file) then
                when(isCallable('axlMiniStatusLoad)
                    load_result = errset(
                        axlMiniStatusLoad((gensym) form_file 'dva_ui_form_cb) nil)
                    when(load_result && car(load_result)
                        form = car(load_result)
                        _dva_ui_ministatus = t
                    )
                )
                unless(form
                    form = axlFormCreate(
                        (gensym)
                        form_file
                        list("E" "INNER" "WINDOW" "NOBORDER" "MSGLINES 0")
                        'dva_ui_form_cb
                        t)
                )
                when(isFile(form_file) errset(axlTempFileRemove(form_file) nil))
                if(form then
                    _dva_ui_form = form
                    dva_ui_build_popups(form layers)
                    dva_ui_initialize_fields(form layers)
                    unless(_dva_ui_ministatus axlFormDisplay(form))
                    when(_dva_ui_ministatus errset(axlControlRaise('options) nil))
                    unwindProtect(
                        while(_dva_panel_active
                            _dva_panel_action = nil
                            point = axlEnterPoint(
                                ?prompts list("Moka skill - Anti-Pad: Use the Options panel; right-click Done to exit."))
                            when(point axlClearSelSet())
                            action = _dva_panel_action
                            _dva_panel_action = nil
                            when(action dva_cmd_run())
                        )
                        progn(
                            when(!_dva_ui_ministatus && form
                                errset(axlFormClose(form) nil)
                            )
                            _dva_ui_form = nil
                            _dva_ui_ministatus = nil
                            _dva_panel_action = nil
                            _dva_panel_active = nil
                            _dva_ui_close_pending = nil
                            axlClearSelSet()
                            errset(axlSetFindFilter(
                                ?enabled saved_enabled ?onButtons saved_on) nil)
                        )
                    )
                else
                    _dva_panel_active = nil
                    dva_put_msg("Unable to create the Anti-Pad panel.")
                )
            else
                _dva_panel_active = nil
                dva_put_msg("Unable to write the anti-pad form definition.")
            )
        )
        t
    )
)
