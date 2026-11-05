/* cnskill -nongraph ./tests/dp_antipad_batch_test.il (repository root).
 * Mock board constraints, geometry and transactions; exercise production code.
 */
_dvb_count = 0
_dvb_design = nil
_dvb_layers = list("TOP" "BOTTOM")
_dvb_fields = makeTable('dvb_fields nil)
_dvb_groups = makeTable('dvb_groups nil)
_dvb_shapes = nil
_dvb_marks = nil
_dvb_next_id = 0
_dvb_fail_x = nil
_dvb_throw_x = nil
_dvb_answer = t
_dvb_finish = "DONE"
_dvb_transaction_count = 0
_dvb_commits = 0
_dvb_rollbacks = 0
_dvb_popup = nil
_dvb_last_status = ""

defun(dvb_object (kind)
    let((object)
        _dvb_next_id = _dvb_next_id + 1
        object = ncons(_dvb_next_id)
        object->objType = kind
        object
    )
)
defun(dvb_assert (condition message)
    unless(condition error("BATCH TEST FAILED: %s" message))
    _dvb_count = _dvb_count + 1
    t
)
defun(axlCmdRegister (@rest args) t)
defun(axlDBGetDesign () _dvb_design)
defun(axlGetParam (name)
    let((param) param = dvb_object("param") param->groupMembers = _dvb_layers param)
)
defun(axlGetActiveLayer () "ETCH/BOTTOM")
defun(axlDBGetDesignUnits () list("MILS"))
defun(axlDBGetGroupFromItem (net kind recursive) _dvb_groups[net->name])
defun(axlFormGetField (form field) _dvb_fields[field])
defun(axlFormSetField (form field value) _dvb_fields[field] = value t)
defun(axlFormSetFieldEditable (@rest args) t)
defun(axlShellPost (command) command)
defun(axlMsgPut (message) _dvb_last_status = message t)
defun(axlUIYesNo (@rest args) _dvb_answer)
defun(axlPolyFromDB (@rest args) nil)
defun(axlDBCreatePropDictEntry (@rest args) t)
defun(axlDBGetProperties (object types) object->testProps)
defun(axlDBAddProp (objects props)
    when(stringp(car(props)) props = list(props))
    foreach(object objects object->testProps = append(props object->testProps))
    t
)
defun(axlDBDeleteProp (objects names)
    foreach(object objects
        object->testProps = setof(entry object->testProps !member(car(entry) names))
    )
    t
)
defun(axlIsDBIDType (object) object && object->objType == "shape")
defun(axlDBGetShapes (layer)
    if(layer == "ROUTE KEEPOUT" then _dvb_shapes else nil)
)
defun(axlDBCreateRectangle (box filled layer)
    let((shape x)
        x = caar(box)
        when(_dvb_throw_x && x >= _dvb_throw_x error("Simulated geometry exception"))
        if(_dvb_fail_x && x >= _dvb_fail_x then
            nil
        else
            shape = dvb_object("shape")
            shape->layer = layer
            shape->bBox = box
            _dvb_shapes = append(_dvb_shapes list(shape))
            list(shape)
        )
    )
)
defun(axlDeleteObject (objects)
    unless(listp(objects) objects = list(objects))
    _dvb_shapes = setof(shape _dvb_shapes !member(shape objects))
    t
)
defun(dvb_snapshot ()
    let((props object)
        props = nil
        foreach(object append(dva_all_anchors() _dvb_shapes)
            props = cons(list(object copy(object->testProps)) props)
        )
        list(copy(_dvb_shapes) props)
    )
)
defun(dvb_restore (snapshot)
    _dvb_shapes = car(snapshot)
    foreach(entry cadr(snapshot) car(entry)->testProps = cadr(entry))
    t
)
defun(axlDBTransactionStart ()
    _dvb_transaction_count = _dvb_transaction_count + 1
    _dvb_marks = nil
    _dvb_start = dvb_snapshot()
    'test_transaction
)
defun(axlDBTransactionMark (transaction)
    _dvb_marks = cons(dvb_snapshot() _dvb_marks)
    t
)
defun(axlDBTransactionOops (transaction)
    when(_dvb_marks dvb_restore(car(_dvb_marks)) _dvb_marks = cdr(_dvb_marks) t)
)
defun(axlDBTransactionCommit (transaction) _dvb_commits = _dvb_commits + 1 t)
defun(axlDBTransactionRollback (transaction)
    _dvb_rollbacks = _dvb_rollbacks + 1
    dvb_restore(_dvb_start)
)
defun(axlUIPopupDefine (unused items) items)
defun(axlUIPopupSet (popup) _dvb_popup = popup t)
defun(axlCancelEnterFun () t)
defun(axlClearSelSet () t)
defun(axlEnterPoint (@key prompts)
    case(_dvb_finish
        ("DONE" dva_cb_done())
        ("CANCEL" dva_cb_cancel())
        ("OOPS" dva_cb_oops() _dvb_finish = "DONE")
    )
    nil
)

defun(dvb_add_via (net x y)
    let((via branch)
        via = dvb_object("via")
        via->net = net
        via->xy = list(x y)
        via->bBox = list(list(x-0.5 y-0.5) list(x+0.5 y+0.5))
        branch = dvb_object("branch")
        branch->children = list(via via) ; duplicate traversal must be harmless
        net->branches = append(net->branches list(branch))
        via
    )
)
defun(dvb_fixture ()
    let((positive negative unrelated group pin branch)
        _dvb_shapes = nil
        _dvb_groups = makeTable('dvb_groups nil)
        _dvb_fail_x = nil
        _dvb_throw_x = nil
        _dvb_answer = t
        _dvb_finish = "DONE"
        positive = dvb_object("net") positive->name = "USB_P"
        negative = dvb_object("net") negative->name = "USB_N"
        unrelated = dvb_object("net") unrelated->name = "GUESS_P"
        _dvb_design = dvb_object("design")
        _dvb_design->nets = list(positive negative unrelated)
        _dvb_p1 = dvb_add_via(positive 0.0 0.0)
        _dvb_p2 = dvb_add_via(positive 3.0 0.0)
        _dvb_p3 = dvb_add_via(positive 100.0 0.0)
        _dvb_n1 = dvb_add_via(negative 1.0 0.0)
        _dvb_n2 = dvb_add_via(negative 4.0 0.0)
        _dvb_other = dvb_add_via(unrelated 0.0 0.0)
        pin = dvb_object("pin") pin->net = positive pin->xy = list(4.0 0.0)
        branch = dvb_object("branch") branch->children = list(pin)
        positive->branches = append(positive->branches list(branch))
        group = dvb_object("group") group->groupMembers = list(positive negative)
        _dvb_groups[positive->name] = list(group)
        _dvb_groups[negative->name] = list(group)
        _dva_layer = "ALL"
        _dva_operation = "BATCH"
        _dva_target_mode = "GROUP" ; batch must ignore manual target mode
        _dva_geometry_mode = "RECTANGLE"
        _dva_clearance = 0.0
        _dva_min_diameter = 0.0
        _dva_fixed_size = nil
        _dva_max_pair_distance = 5.0
        _dva_replace_existing = t
        _dva_confirm_before_apply = nil
        _dva_source_layer = nil
        _dva_session_op_count = 0
        t
    )
)

let((result)
    result = errset(
        let((plan pairs stats before_count before_commits before_rollbacks old_id old_shapes form_file port line found)
            load("src/dp_antipad.il")
            dvb_fixture()
            plan = dva_plan_all_diff_vias()
            pairs = car(plan)
            dvb_assert(length(pairs) == 2 "scan must match two pairs without reusing a via")
            dvb_assert(nth(1 plan) == 6 && nth(2 plan) == 5 && nth(3 plan) == 1
                "statistics must exclude pins and count duplicates only once")
            dvb_assert(dva_pair_exists(pairs _dvb_p1 _dvb_n1) && dva_pair_exists(pairs _dvb_p2 _dvb_n2)
                "closest opposite-net vias must pair one-to-one")
            dva_set_source_id(list(_dvb_p3 _dvb_other) "STALE_ID")
            dvb_assert(length(car(dva_plan_all_diff_vias())) == 2
                "old tags and suggestive net names must not override constraints")
            _dva_max_pair_distance = 0.5
            dvb_assert(!car(dva_plan_all_diff_vias()) "distance limit must reject distant mates")
            _dva_max_pair_distance = 0.0
            dvb_assert(dva_validate_batch_params() "batch must validate distance even in manual GROUP mode")
            _dva_max_pair_distance = 5.0
            dvb_assert(!dva_validate_batch_params() && _dva_target_mode == "GROUP"
                "batch validation must not change the manual target mode")

            dvb_fixture()
            pairs = car(dva_plan_all_diff_vias())
            _dva_mark = axlDBTransactionStart()
            stats = dva_batch_apply_pairs(pairs)
            dvb_assert(equal(stats list(2 0 0)) && length(_dvb_shapes) == 2
                "batch must create one paired rectangle per detected via pair")
            dvb_assert(_dva_target_mode == "GROUP" && _dva_session_op_count == 2
                "batch must preserve target mode and count undo operations")
            dvb_assert(car(_dvb_shapes)->layer == "ROUTE KEEPOUT/ALL"
                "batch must honor All placement")
            old_id = dva_object_keepout_id(_dvb_p1)
            dvb_assert(old_id && equal(old_id dva_object_keepout_id(_dvb_n1)) &&
                !equal(old_id dva_object_keepout_id(_dvb_p2))
                "each pair must get its own shared source ID")
            dva_cb_oops()
            dvb_assert(length(_dvb_shapes) == 1 && _dva_session_op_count == 1 &&
                !dva_object_keepout_id(car(nth(1 pairs))) "Oops must restore the previous pair and tags")
            axlDBTransactionRollback(_dva_mark)
            dvb_assert(!_dvb_shapes && !dva_object_keepout_id(_dvb_p1)
                "whole batch rollback must restore all geometry and tags")

            dvb_fixture()
            dva_cmd_run_batch()
            old_shapes = copy(_dvb_shapes)
            _dva_replace_existing = nil
            _dva_mark = axlDBTransactionStart()
            stats = dva_batch_apply_pairs(car(dva_plan_all_diff_vias()))
            dvb_assert(equal(stats list(0 2 0)) && equal(old_shapes _dvb_shapes)
                "repeat runs with replace disabled must skip existing pairs")
            _dva_replace_existing = t
            stats = dva_batch_apply_pairs(car(dva_plan_all_diff_vias()))
            dvb_assert(equal(stats list(2 0 0)) && length(_dvb_shapes) == 2
                "repeat runs with replace enabled must rebuild without duplicates")
            axlDBTransactionRollback(_dva_mark)
            dvb_assert(equal(old_shapes _dvb_shapes) "rollback after replacement must restore previous shapes")

            dvb_fixture()
            _dvb_fail_x = 2.0
            _dva_mark = axlDBTransactionStart()
            stats = dva_batch_apply_pairs(car(dva_plan_all_diff_vias()))
            dvb_assert(equal(stats list(1 0 1)) && length(_dvb_shapes) == 1 &&
                !dva_object_keepout_id(_dvb_p2) "a failed pair must rollback without removing successful pairs")
            axlDBTransactionRollback(_dva_mark)
            dvb_fixture()
            _dvb_throw_x = 2.0
            _dva_mark = axlDBTransactionStart()
            stats = dva_batch_apply_pairs(car(dva_plan_all_diff_vias()))
            dvb_assert(equal(stats list(1 0 1)) "geometry exceptions must rollback the affected pair")
            axlDBTransactionRollback(_dva_mark)

            dvb_fixture()
            _dva_geometry_mode = "ANTIPAD"
            _dvb_fail_x = 0.0 ; first via succeeds, second fails in the first pair
            _dva_mark = axlDBTransactionStart()
            stats = dva_batch_apply_pairs(list(list(_dvb_p1 _dvb_n1)))
            dvb_assert(equal(stats list(0 0 1)) && !_dvb_shapes &&
                !dva_object_keepout_id(_dvb_p1) "partial two-via contour creation must rollback the entire pair")
            axlDBTransactionRollback(_dva_mark)

            dvb_fixture()
            before_commits = _dvb_commits
            dva_cmd_run_batch()
            dvb_assert(length(_dvb_shapes) == 2 && _dvb_commits == before_commits + 1 &&
                !_dva_run_active && !_dva_mark && !_dvb_popup "Done must commit and clean up batch state")
            dvb_fixture()
            _dvb_finish = "CANCEL"
            before_rollbacks = _dvb_rollbacks
            dva_cmd_run_batch()
            dvb_assert(!_dvb_shapes && _dvb_rollbacks == before_rollbacks + 1 &&
                !dva_object_keepout_id(_dvb_p1) "Cancel must rollback the entire generated batch")
            dvb_fixture()
            _dvb_finish = "OOPS"
            dva_cmd_run_batch()
            dvb_assert(length(_dvb_shapes) == 1 "Oops followed by Done must commit only the remaining pair")
            dvb_fixture()
            _dva_confirm_before_apply = t
            _dvb_answer = nil
            before_count = _dvb_transaction_count
            dva_cmd_run_batch()
            dvb_assert(!_dvb_shapes && _dvb_transaction_count == before_count && !_dva_run_active
                "declining confirmation must not start a transaction")
            dvb_fixture()
            _dvb_groups = makeTable('no_diff_groups nil)
            before_count = _dvb_transaction_count
            dva_cmd_run_batch()
            dvb_assert(!_dvb_shapes && _dvb_transaction_count == before_count
                "no constrained pairs must produce no writes")

            form_file = "tests/dp_antipad_batch_smoke_result.txt"
            dvb_assert(dva_write_form(form_file) "updated form must be writable")
            port = infile(form_file)
            found = nil
            while(gets(line port)
                when(rexMatchp("FIELD btn_all_vias" line) found = t)
            )
            close(port)
            deleteFile(form_file)
            dvb_assert(found "form must contain the one-click full-board button")
            printf("PASS: Anti-Pad batch (%d assertions).\n" _dvb_count)
            t
        )
        t
    )
    if(result && car(result) then exit(0) else exit(1))
)
