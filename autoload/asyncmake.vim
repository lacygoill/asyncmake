if exists('g:autoloaded_asyncmake')
    finish
endif
let g:autoloaded_asyncmake = 1

let s:make_cmd = ''
" vim -es +'set nonu nornu | vimgrep /$*/ ** | cw | %p | qa'
" let &mp = "vim -Nu NONE -es +'set nonu nornu | vimgrep /$*/ ~/.vim/** | cw | 1,$p | qa'"

fu! asyncmake#async_make(args) abort "{{{1
" Run a make command and process the output asynchronously.
" Only one make command can be run in the background.
    if !empty(s:make_cmd)
        try
            throw '[asyncmake] A make command is already running'
        catch
            call lg#catch_error()
        endtry
    endif

    let s:make_cmd = &makeprg

    " Replace $* (if present) in 'makeprg' with the supplied arguments
    if match(s:make_cmd, '\$\*') !=# -1
        let s:make_cmd = substitute(s:make_cmd, '\$\*', a:args, 'g')
    else
        if !empty(a:args)
            let s:make_cmd = s:make_cmd.' '.a:args
        endif
    endif

    " Replace cmdline-special characters
    let s:make_cmd = s:expand_cmd_special(s:make_cmd)

    " Save all the modified buffers if 'autowrite' or 'autowriteall' is set
    if &autowrite || &autowriteall
         sil! wall
    endif

    " Create a new quickfix list at the end of the stack
    call setqflist([], ' ', {'nr': '$',
    \        'title': s:make_cmd,
    \        'lines': ['Make command (' . s:make_cmd . ') output']})
    let qfid = getqflist({'nr':'$', 'id':0}).id

    let s:make_job = job_start(s:make_cmd, {
    \       'callback': function('s:make_process_output', [qfid]),
    \       'close_cb': function('s:make_close_cb', [qfid]),
    \       'exit_cb':  function('s:make_completed'),
    \       'in_io':    'null'})
    if job_status(s:make_job) is# 'fail'
        try
            throw '[asyncmake] Failed to run ('.s:make_cmd.')'
        catch
            return lg#catch_error()
        endtry
        let s:make_cmd = ''
        return
    endif
    let s:make_dir = getcwd()
    let s:make_efm = &efm
endfu

fu! asyncmake#cancel_make() abort "{{{1
" Stop a make command if it is running
    if empty(s:make_cmd)
        echo '[asyncmake] Make is not running'
        return
    endif

    call job_stop(s:make_job)
    echom 'Make command ('.s:make_cmd.') is stopped'
endfu

fu! s:expand(string) abort "{{{1
    " Backslashes in 'makeprg' are escaped twice. Refer to :help 'makeprg'
    " for details. Reduce the number of backslashes by two.
    let slashes = len(matchstr(a:string, '^\%(\\\\\)*'))
    sandbox let v = repeat('\', slashes/2) . expand(a:string[slashes : -1])
    return v
endfu

fu! s:expand_cmd_special(string) abort "{{{1
    return substitute(a:string, s:EXPANDABLE, '\=s:expand(submatch(0))', 'g')
endfu
" Expand special characters in the command-line (:help cmdline-special)
" Leveraged from the dispatch.vim plugin
let s:flags      = '<\=\%(:[p8~.htre]\|:g\=s\(.\).\{-\}\1.\{-\}\1\)*'
let s:EXPANDABLE = '\\*\%(<\w\+>\|%\|#\d*\)'.s:flags

fu! s:make_close_cb(qf_id, channel) abort "{{{1
" s:make_close_cb
" Close callback for the make command channel. No more output is available.
    let job = ch_getjob(a:channel)
    if job_status(job) is# 'fail'
        try
            throw '[asyncmake] Job not found in make channel close callback'
        catch
            return lg#catch_error()
        endtry
        return
    endif
    let exitval = job_info(job).exitval
    let emsg = '[Make command exited with status ' . exitval . ']'

    " Add the exit status message if the quickfix list is still present
    let l = getqflist({'id': a:qf_id})
    if has_key(l, 'id') && l.id ==# a:qf_id
        call setqflist([], 'a', {'id': a:qf_id, 'lines': [emsg]})

        " Open the quickfix list if make exited with a non-zero value
        if exitval !=# 0
            let save_wid = win_getid()
            copen
            " Jump to the correct quickfix list
            let cur_qfnr = getqflist({'nr': 0}).nr
            let tgt_qfnr = getqflist({'id': a:qf_id, 'nr': 0}).nr
            if cur_qfnr !=# tgt_qfnr
                if tgt_qfnr > cur_qfnr
                    exe 'cnewer '.(tgt_qfnr - cur_qfnr)
                else
                    exe 'colder'. (cur_qfnr - tgt_qfnr)
                endif
            endif
            call win_gotoid(save_wid)
        endif
    endif
endfu

fu! s:make_completed(job, exitStatus) abort "{{{1
" s:make_completed
" Make command completion handler
    echom 'Make ('.s:make_cmd.') completed'
    let s:make_cmd = ''
endfu

fu! s:make_process_output(qfid, channel, msg) abort "{{{1
" s:make_process_output
" Make command output handler.  Process part of the make command output and
" add the output to a quickfix list.

    " Make sure the quickfix list is still present
    let l = getqflist({'id': a:qfid})
    if l.id !=# a:qfid
        echom 'Quickfix list not found, stopping the make'
        call job_stop(ch_getjob(a:channel))
        return
    endif

    " The user or some other plugin might have changed the directory,
    " change to the original direcotry of the make command.
    exe 'lcd ' . s:make_dir
    call setqflist([], 'a', {'id':a:qfid,
    \        'lines': [a:msg],
    \        'efm': s:make_efm})
    lcd -
endfu

fu! asyncmake#show_make() abort "{{{1
    if empty(s:make_cmd)
        echo '[asyncmake] Make is not running'
        return
    endif
    echo '[asyncmake] Make command('. s:make_cmd.') is running'
endfu

