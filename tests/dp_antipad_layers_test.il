/* Run from the repository root with cnskill -nongraph.
 * Mock Allegro's database/form APIs to check layer routing and source reads.
 * Actual PCB creation and copper repour still require an Allegro board test.
 */

_dva_test_layers = list("TOP" "L2_GND" "BOTTOM")
_dva_test_active = "ETCH/L2_GND"
_dva_test_fields = makeTable('dva_test_fields nil)
_dva_test_popup = nil
_dva_test_read_layer = nil
_dva_test_read_type = nil
_dva_test_shape = ncons(t)
_dva_test_shape->objType = "shape"
_dva_test_count = 0

defun(axlCmdRegister (@rest args) t)
defun(axlGetActiveLayer () _dva_test_active)
defun(axlGetParam (name)
    let((param)
        param = ncons(t)
        param->groupMembers = _dva_test_layers
        param
    )
)
defun(axlFormBuildPopup (form field values)
    when(field == "layer" _dva_test_popup = values)
    t
)
defun(axlFormSetField (form field value) _dva_test_fields[field] = value t)
defun(axlFormGetField (form field) _dva_test_fields[field])
defun(axlFormSetFieldEditable (@rest args) t)
defun(axlMsgPut (message) t)
defun(axlShellPost (command) t)
defun(axlPolyFromDB (object @key layer padType holes endCapType)
    _dva_test_read_layer = layer
    _dva_test_read_type = padType
    list('test_polygon)
)
defun(axlIsDBIDType (object) eq(object _dva_test_shape))
defun(axlDBCreateShape (geometry filled layer)
    _dva_test_shape->layer = layer
    _dva_test_shape->testProps = nil
    _dva_test_shape
)
defun(axlDBCreateRectangle (box filled layer)
    axlDBCreateShape(box filled layer)
)
defun(axlDBAddProp (objects props)
    let((shape)
        shape = car(objects)
        when(stringp(car(props)) props = list(props))
        shape->testProps = append(shape->testProps props)
        t
    )
)
defun(axlDBGetProperties (object types) object->testProps)

defun(dva_test_assert (condition message)
    unless(condition error("ANTI-PAD LAYER TEST FAILED: %s" message))
    _dva_test_count = _dva_test_count + 1
    t
)

let((result)
    result = errset(
        let((object shape)
            load("src/dp_antipad.il")
            dva_ui_build_popups('test_form _dva_test_layers)
            dva_test_assert(
                equal(_dva_test_popup list(list("All" "ALL") list("TOP" "TOP")
                    list("L2_GND" "L2_GND") list("BOTTOM" "BOTTOM")))
                "popup must offer All and every board layer")

            _dva_layer = "ALL"
            dva_ui_initialize_fields('test_form _dva_test_layers)
            dva_test_assert(_dva_layer == "ALL" "reopening must preserve All")
            dva_test_assert(_dva_test_fields["layer"] == "ALL" "form must display All")
            dva_test_assert(!dva_validate_params() "All must pass parameter validation")
            dva_test_assert(dva_route_keepout_layer() == "ROUTE KEEPOUT/ALL"
                "All must target the native all-layer Keepout subclass")

            _dva_geometry_mode = "ANTIPAD"
            _dva_source_layer = "ETCH/BOTTOM"
            dva_ui_start('test_form "APPLY")
            dva_test_assert(_dva_source_layer == "ETCH/L2_GND"
                "a new All session must capture the current active ETCH layer")
            _dva_test_active = "ETCH/TOP"
            object = ncons(t)
            object->objType = "via"
            dva_object_polygons_typed(object 'ANTI)
            dva_test_assert(_dva_test_read_layer == "ETCH/L2_GND" && _dva_test_read_type == 'ANTI
                "All ANTI reads must stay on the captured layer after active-layer changes")
            _dva_geometry_mode = "CONTOUR"
            object->objType = "pin"
            dva_object_polygons_typed(object 'REGULAR)
            dva_test_assert(_dva_test_read_layer == "ETCH/L2_GND" && _dva_test_read_type == 'REGULAR
                "All CONTOUR reads must use a real ETCH layer")

            foreach(creator list('dva_create_poly_keepout 'dva_create_path_keepout 'dva_create_rectangle_keepout)
                shape = funcall(creator list(list(0.0 0.0) list(10.0 10.0)) "TEST_ID")
                dva_test_assert(shape && shape->layer == "ROUTE KEEPOUT/ALL"
                    "polygon, path and rectangle creation must target ALL")
                dva_test_assert(dva_prop_value_named(shape "ROUTES_ALLOWED") &&
                    dva_prop_value_named(shape "VIAS_ALLOWED") &&
                    dva_prop_value_named(shape "MOKA_AP_KEEP_ID") == "TEST_ID"
                    "All keepouts must retain routing, via and association properties")
            )

            _dva_run_active = nil
            _dva_geometry_mode = "ANTIPAD"
            _dva_test_active = "ROUTE KEEPOUT/ALL"
            dva_ui_start('test_form "APPLY")
            dva_test_assert(_dva_source_layer == "ETCH/TOP"
                "non-ETCH active layers must fall back to the first board ETCH layer")
            _dva_source_layer = "ETCH/ALL"
            _dva_test_active = "ETCH/ALL"
            dva_test_assert(dva_pad_source_layer() == "ETCH/TOP"
                "ETCH/ALL must never be used for Padstack geometry")

            _dva_layer = "BOTTOM"
            dva_test_assert(!dva_validate_params() "single-layer validation must still succeed")
            dva_test_assert(dva_route_keepout_layer() == "ROUTE KEEPOUT/BOTTOM"
                "single-layer destination must remain unchanged")
            dva_object_polygons_typed(object 'ANTI)
            dva_test_assert(_dva_test_read_layer == "ETCH/BOTTOM"
                "single-layer ANTI must still read the selected target layer")
            _dva_geometry_mode = "CONTOUR"
            _dva_source_layer = "ETCH/L2_GND"
            dva_object_polygons_typed(object 'REGULAR)
            dva_test_assert(_dva_test_read_layer == "ETCH/L2_GND"
                "single-layer CONTOUR must still read the session reference layer")

            _dva_layer = "MISSING"
            dva_test_assert(dva_validate_params() "unknown layers must be rejected")
            dva_ui_initialize_fields('test_form _dva_test_layers)
            dva_test_assert(_dva_layer == "TOP" "stale layer selections must reset to the first board layer")
            _dva_layer = "ALL"
            _dva_clearance = -1.0
            dva_test_assert(dva_validate_params() "All must still enforce geometry validation")
            _dva_clearance = 8.0
            _dva_test_layers = nil
            dva_test_assert(dva_validate_params() "All must not bypass a missing ETCH stack")
            printf("PASS: Anti-Pad placement layers (%d assertions).\n" _dva_test_count)
            t
        )
        t
    )
    if(result && car(result) then exit(0) else exit(1))
)
