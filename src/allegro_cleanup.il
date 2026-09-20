; ============================================================================
; Allegro project log cleanup module for Moka Skill.
; Deletes only files ending in .log or ,<number> under the active project directory.
; ============================================================================

defvar(allegro_cleanup_version "0.2.0")
defvar(allegro_cleanup_excluded_dirs list(".git" ".svn" ".hg" "node_modules" "gerber" "output_files"))

defun( allegro_cleanup_project_root ()
    let((value root)
        root = ""
        value = errset(axlGetVariable("designPath") nil)
        when(value && stringp(car(value))
            root = car(value)
        )
        when(strlen(root) == 0 || isFile(root)
            root = getWorkingDir()
        )
        if(stringp(root) then axlOSSlash(root) else "")
    )
)

defun( allegro_cleanup_candidate_p (name)
    let((lower_name)
        lower_name = lowerCase(name)
        rexMatchp("\\.log$" lower_name) || rexMatchp(",[0-9]+$" name)
    )
)

defun( allegro_cleanup_collect (directory)
    let((entries result full_name entry)
        result = nil
        entries = errset(getDirFiles(directory) nil)
        when(entries
            foreach(entry car(entries)
                when(stringp(entry) && entry != "." && entry != ".."
                    full_name = strcat(directory "/" entry)
                    if(isDir(full_name) then
                        unless(member(lowerCase(entry) allegro_cleanup_excluded_dirs)
                            result = append(result allegro_cleanup_collect(full_name))
                        )
                    else when(isFile(full_name) && allegro_cleanup_candidate_p(entry)
                        result = cons(full_name result)
                    )
                    )
                )
            )
        )
        result
    )
)

defun( allegro_cleanup_cmd ()
    let((root candidates answer removed failed path delete_result)
        root = allegro_cleanup_project_root()
        if(strlen(root) == 0 then
            axlMsgPut("Moka skill - Clean Project Logs: project directory is unavailable.")
        else
            candidates = allegro_cleanup_collect(root)
            if(length(candidates) == 0 then
                axlMsgPut(sprintf(nil "Moka skill - Clean Project Logs: no .log or ,number files under %s" root))
            else
                axlMsgPut(sprintf(nil "Moka skill - Clean Project Logs: found %d file(s) under %s" length(candidates) root))
                foreach(path reverse(candidates)
                    axlMsgPut(sprintf(nil "  %s" path))
                )
                answer = axlUIYesNo(
                    sprintf(nil "Delete %d .log / ,number file(s) under:\n%s" length(candidates) root)
                    "Moka skill - Clean Project Logs"
                    'no)
                if(answer then
                    removed = 0
                    failed = 0
                    foreach(path candidates
                        delete_result = errset(deleteFile(path) nil)
                        if(delete_result && car(delete_result) then
                            removed = removed + 1
                        else
                            failed = failed + 1
                            axlMsgPut(sprintf(nil "Moka skill - Clean Project Logs: could not delete %s" path))
                        )
                    )
                    axlMsgPut(sprintf(nil "Moka skill - Clean Project Logs: deleted %d, failed %d" removed failed))
                else
                    axlMsgPut("Moka skill - Clean Project Logs: cancelled.")
                )
            )
        )
    )
)

axlCmdRegister("moka_clean_logs" 'allegro_cleanup_cmd ?cmdType "general")
