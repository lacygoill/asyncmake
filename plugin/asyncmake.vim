vim9 noclear

if exists('loaded') | finish | endif
var loaded = true

com -bar -nargs=* -complete=file AsyncMake     asyncmake#asyncMake(<q-args>)
com -bar                         AsyncMakeShow asyncmake#showMake()
com -bar                         AsyncMakeStop asyncmake#cancelMake(<args>)
