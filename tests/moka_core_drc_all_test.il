/* Verify the independent DRC ERROR CLASS/ALL visibility switch. */
_moka_drc_test_visible = nil
_moka_drc_test_active = nil

defun( axlCmdRegister (@rest args) t)
defun( axlGetVariable (name) "D:/Moka_Skill")
defun( axlOSSlash (path) path)
defun( axlVisibleDesign (value) t)
defun( axlVisibleLayer (layer value)
    when(value _moka_drc_test_visible = cons(layer _moka_drc_test_visible))
    t
)
defun( axlIsLayer (layer) t)
defun( axlSetActiveLayer (layer) _moka_drc_test_active = layer t)
defun( axlVisibleUpdate (@rest args) t)
defun( axlMsgPut (@rest args) t)

load("src/moka_core.il")

defun( moka_drc_test_assert (condition message)
    unless(condition error("MOKA CORE DRC TEST FAILED: %s" message))
    t
)

let((cfg)
    cfg = list("TOP" t nil nil t nil nil nil nil nil nil nil nil nil nil nil nil nil nil nil)
    moka_drc_all = t
    _moka_drc_test_visible = nil
    moka_apply_view_impl(cfg)
    moka_drc_test_assert(member("DRC ERROR CLASS/TOP" _moka_drc_test_visible)
        "per-layer DRC was not enabled")
    moka_drc_test_assert(member("DRC ERROR CLASS/ALL" _moka_drc_test_visible)
        "global DRC was not enabled")
    moka_drc_all = nil
    _moka_drc_test_visible = nil
    moka_apply_view_impl(cfg)
    moka_drc_test_assert(!member("DRC ERROR CLASS/ALL" _moka_drc_test_visible)
        "global DRC ignored its independent switch")
)

printf("Moka core DRC ALL test passed.\n")
exit()
