if exists('loaded_asyncmake')
    finish
endif
let loaded_asyncmake = 1

com -nargs=* -complete=file AsyncMake     call asyncmake#async_make(<q-args>)
com                         AsyncMakeShow call asyncmake#show_make()
com                         AsyncMakeStop call asyncmake#cancel_make(<args>)
