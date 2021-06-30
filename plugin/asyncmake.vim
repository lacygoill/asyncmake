vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

command -bar -nargs=* -complete=file AsyncMake     asyncmake#asyncMake(<q-args>)
command -bar                         AsyncMakeShow asyncmake#showMake()
command -bar                         AsyncMakeStop asyncmake#cancelMake(<args>)
