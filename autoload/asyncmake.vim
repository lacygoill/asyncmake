vim9script noclear

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
        make_cmd = make_cmd->substitute('\$\*', args, 'g')
    else
        if !empty(args)
            make_cmd ..= ' ' .. args
        endif
    endif

    # Replace cmdline-special characters
    make_cmd = expandcmd(make_cmd)

    # Save all the modified buffers if 'autowrite' or 'autowriteall' is set
    if &autowrite || &autowriteall
         silent! wall
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
    make_errorformat = &errorformat
enddef

var make_dir: string = getcwd()
var make_errorformat: string
var make_job: job

def asyncmake#cancelMake() #{{{2
# Stop a make command if it is running
    if empty(make_cmd)
        echo '[asyncmake] Make is not running'
        return
    endif

    job_stop(make_job)
    echomsg 'Make command (' .. make_cmd .. ') is stopped'
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
    if l->has_key('id') && l.id == qf_id
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
                    execute 'cnewer ' .. (tgt_qfnr - cur_qfnr)
                else
                    execute 'colder' .. (cur_qfnr - tgt_qfnr)
                endif
            endif
            win_gotoid(save_wid)
        endif
    endif
enddef

def MakeCompleted(_, _) #{{{2
# Make command completion handler
    echomsg 'Make (' .. make_cmd .. ') completed'
    make_cmd = ''
enddef

def MakeProcessOutput( #{{{2
    qfid: number,
    channel: channel,
    msg: string
)
# Make command output handler.  Process part of the make command output and
# add the output to a quickfix list.

    # Make sure the quickfix list is still present
    var l: dict<any> = getqflist({id: qfid})
    if l.id != qfid
        echomsg 'Quickfix list not found, stopping the make'
        ch_getjob(channel)->job_stop()
        return
    endif

    # The user or some other plugin might have changed the directory,
    # change to the original direcotry of the make command.
    execute 'lcd ' .. make_dir
    setqflist([], 'a', {
        id: qfid,
        lines: [msg],
        efm: make_errorformat
    })
    lcd -
enddef

def Warn(msg: string) #{{{2
    echohl WarningMsg
    echomsg msg
    echohl NONE
enddef

