if exists('loaded_asyncmake')
    finish
endif
let loaded_asyncmake = 1

com -bar -nargs=* -complete=file AsyncMake     call asyncmake#async_make(<q-args>)
com -bar                         AsyncMakeShow call asyncmake#show_make()
com -bar                         AsyncMakeStop call asyncmake#cancel_make(<args>)
