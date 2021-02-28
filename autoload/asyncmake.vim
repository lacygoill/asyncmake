vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

var make_cmd: string = ''

# Interface {{{1
def asyncmake#asyncMake(args: string) #{{{2
# Run a make command and process the output asynchronously.
# Only one make command can be run in the background.
    if !empty(make_cmd)
        Warn('[asyncmake] A make command is already running')
        return
    endif

    make_cmd = &makeprg

    # Replace $* (if present) in 'makeprg' with the supplied arguments
    if match(make_cmd, '\$\*') >= 0
        make_cmd = substitute(make_cmd, '\$\*', args, 'g')
    else
        if !empty(args)
            make_cmd ..= ' ' .. args
        endif
    endif

    # Replace cmdline-special characters
    make_cmd = ExpandCmdSpecial(make_cmd)

    # Save all the modified buffers if 'autowrite' or 'autowriteall' is set
    if &autowrite || &autowriteall
         sil! wall
    endif

    # Create a new quickfix list at the end of the stack
    setqflist([], ' ', {
        nr: '$',
        title: make_cmd,
        lines: ['Make command (' .. make_cmd .. ') output']
        })
    var qfid: number = getqflist({nr: '$', id: 0}).id

    # Why starting a shell to run the command?{{{
    #
    # The command may be passed filenames as arguments.
    # Those could be quoted to be protected from the shell, in case they contain
    # special characters.
    #
    # If you don't  start a shell, the quotes won't  be removed, and `pandoc(1)`
    # will try to find files whose literal names contain quotes.
    #
    # It won't find them, and the compilation will fail.
    #}}}
    make_job = job_start(['/bin/sh', '-c', make_cmd], {
        callback: function(MakeProcessOutput, [qfid]),
        close_cb: function(MakeCloseCb, [qfid]),
        exit_cb: MakeCompleted,
        in_io: 'null'
        })
    if job_status(make_job) == 'fail'
        Warn('[asyncmake] Failed to run (' .. make_cmd .. ')')
        make_cmd = ''
        return
    endif
    make_dir = getcwd()
    make_efm = &efm
enddef

var make_dir: string = getcwd()
var make_efm: string
var make_job: job

def asyncmake#cancelMake() #{{{2
# Stop a make command if it is running
    if empty(make_cmd)
        echo '[asyncmake] Make is not running'
        return
    endif

    job_stop(make_job)
    echom 'Make command (' .. make_cmd .. ') is stopped'
enddef

def asyncmake#showMake() #{{{2
    if empty(make_cmd)
        echo '[asyncmake] Make is not running'
        return
    endif
    echo '[asyncmake] Make command(' .. make_cmd .. ') is running'
enddef
#}}}1
# Core {{{1
def Expand(string: string): string #{{{2
    # Backslashes in `'makeprg'` are escaped  twice.  See `:h 'mp'` for details.
    # Reduce the number of backslashes by two.
    var slashes: number = matchstr(string, '^\%(\\\\\)*')->strlen()
    sandbox var v: string = repeat('\', slashes / 2) .. expand(string[slashes : -1])
    return v
enddef

def ExpandCmdSpecial(string: string): string #{{{2
    return substitute(
        string,
        EXPANDABLE,
        (m: list<string>): string => m[0]->Expand(),
        'g'
    )
enddef
# Expand special characters in the command-line (:help cmdline-special)
# Leveraged from the dispatch.vim plugin
var flags: string = '<\=\%(:[p8~.htre]\|:g\=s\(.\).\{-\}\1.\{-\}\1\)*\%(:S\)\='
var EXPANDABLE: string = '\\*\%(<\w\+>\|%\|#\d*\)' .. flags

def MakeCloseCb(qf_id: number, channel: channel) #{{{2
# Close callback for the make command channel.  No more output is available.
    var job: job = ch_getjob(channel)
    if job_status(job) == 'fail'
        Warn('[asyncmake] Job not found in make channel close callback')
        return
    endif
    var exitval: number = job_info(job).exitval
    var emsg: string = '[Make command exited with status ' .. exitval .. ']'

    # Add the exit status message if the quickfix list is still present
    var l: dict<any> = getqflist({id: qf_id})
    if has_key(l, 'id') && l.id == qf_id
        setqflist([], 'a', {id: qf_id, lines: [emsg]})

        # Open the quickfix list if make exited with a non-zero value
        if exitval != 0
            var save_wid: number = win_getid()
            copen
            # Jump to the correct quickfix list
            var cur_qfnr: number = getqflist({nr: 0}).nr
            var tgt_qfnr: number = getqflist({id: qf_id, nr: 0}).nr
            if cur_qfnr != tgt_qfnr
                if tgt_qfnr > cur_qfnr
                    exe 'cnewer ' .. (tgt_qfnr - cur_qfnr)
                else
                    exe 'colder' .. (cur_qfnr - tgt_qfnr)
                endif
            endif
            win_gotoid(save_wid)
        endif
    endif
enddef

def MakeCompleted(...l: any) #{{{2
# Make command completion handler
    echom 'Make (' .. make_cmd .. ') completed'
    make_cmd = ''
enddef

def MakeProcessOutput(qfid: number, channel: channel, msg: string) #{{{2
# Make command output handler.  Process part of the make command output and
# add the output to a quickfix list.

    # Make sure the quickfix list is still present
    var l: dict<any> = getqflist({id: qfid})
    if l.id != qfid
        echom 'Quickfix list not found, stopping the make'
        ch_getjob(channel)->job_stop()
        return
    endif

    # The user or some other plugin might have changed the directory,
    # change to the original direcotry of the make command.
    exe 'lcd ' .. make_dir
    setqflist([], 'a', {
        id: qfid,
        lines: [msg],
        efm: make_efm})
    lcd -
enddef

def Warn(msg: string) #{{{2
    echohl WarningMsg
    echom msg
    echohl NONE
enddef

