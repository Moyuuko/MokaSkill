; Exercise the collector payload assembly without a board database.
defun(axlCmdRegister (@rest args) t)
unless(errset(load("src/interactive-bom/exportJson.il") t) exit(1))
defun(axlCurrentDesign () "fixture")
defun(addIndent (value @optional tabs) value)
defun(addMetadata (@rest args) "\"metadata\": {}")
defun(addBoardGeometry (@rest args) "\"edges\": []")
defun(addSymbols (@rest args) "\"footprints\": []")
defun(addComponentTable (@rest args) "\"components\": []")
defun(addCopper (@rest args)
    copper_calls = copper_calls + 1
    "\"tracks\": {\"F\": [], \"B\": []}, \"zones\": {\"F\": [], \"B\": []}"
)
defun(addNets (@rest args)
    net_calls = net_calls + 1
    "\"nets\": []"
)

unless(errset(let((payload)
    moka_ibom_inline_export = t
    foreach(tracks list(nil t)
        foreach(nets list(nil t)
            moka_ibom_include_tracks = tracks
            moka_ibom_include_nets = nets
            moka_ibom_payloads = nil
            copper_calls = 0
            net_calls = 0
            writeJsonFile()
            unless(moka_ibom_payloads error("Collector did not produce a payload"))
            payload = cadr(car(moka_ibom_payloads))
            unless((copper_calls == if(tracks then 1 else 0)) error("Track option did not control collection"))
            unless((net_calls == if(nets then 1 else 0)) error("Net option did not control collection"))
            unless((if(index(payload "\"tracks\"") then t else nil) == tracks) error("Track payload did not match option"))
            unless((if(index(payload "\"nets\"") then t else nil) == nets) error("Net payload did not match option"))
        )
    )
) t) exit(1))
printf("Interactive BOM collector option test passed.\n")
exit()
