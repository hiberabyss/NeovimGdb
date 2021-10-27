if exists('b:loaded_onekeycompile') || exists('g:loaded_onekeycompile')
  finish
endif

let b:loaded_onekeycompile = 1

let b:binary_filename = expand('%:p:r') . '.bin'
let b:makeprg = {}
let b:makeprg.c   = "clang -std=c99 -Wall % -o " . b:binary_filename
let b:makeprg.cpp = "g++ -Wall -std=c++17 % -o " . b:binary_filename
let b:makeprg.gdb = "g++ -Wall -g -O0 -std=c++17 % -o " . b:binary_filename
let b:makeprg.gtest = "g++ -Wall -lgmock_main -lgmock -g -O0 -std=c++17 % -o " . b:binary_filename

function! s:ErrReturn(msg)
	echohl ErrorMsg | echom a:msg | echohl None
	return -1
endfunction

function! s:NormalReturn(msg)
	echohl WarningMsg | echo a:msg | echohl None
	return 0
endfunction

function! CompileCCpp(gdb_flag, msg) "{{{
	if &modified | w | endif
	let b:syntastic_mode = 'active'

    if filereadable(b:binary_filename) && delete(b:binary_filename)
		set makeprg=make
		return s:ErrReturn("Delete " . b:binary_filename . " failed")
    endif

	if a:gdb_flag == 1
		let &makeprg = b:makeprg['gdb']
	elseif a:gdb_flag == 2
		let &makeprg = b:makeprg['gtest']
	else
		let &makeprg = b:makeprg[&filetype]
	endif
    execute "silent make!"
    
    if !filereadable(b:binary_filename)
        execute "copen"
        return -3
    endif

	if !empty(a:msg)
		return s:NormalReturn(a:msg)
	else
		return 0
	endif
endfunction "}}}

function! NormalRun(flag) "{{{
    if CompileCCpp(a:flag, "") < 0 | return | endif
	let binary = b:binary_filename
	botright new | res 12
	" let cmd = binary ." ; if [[ $? == 139 ]]; then echo 'Segmentation Fault'; fi"
	let cmd = binary ." ; errcode=$?; if [[ $errcode -gt 128 ]]; then echo \"System Error! Errno: $errcode\"; fi"
	call termopen(cmd)
	startinsert
endfunction "}}}

function! DebugRun() "{{{
    if CompileCCpp(1, "") < 0 | return | endif

	if has('nvim')
		silent execute "GdbStart " . b:binary_filename
	endif
endfunction "}}}

" nmap <buffer> <A-]> :<C-U>call JumpToClassMemberByDecl('tj')<cr>

nmap <buffer> <silent> ,rr :call NormalRun(1)<CR>
map <buffer> <silent> ,rd :call DebugRun()<cr>
command! -nargs=0 -buffer GdbLocal call DebugRun()
map <buffer> <silent> ,rt :call NormalRun(2)<cr>

command! -buffer M call CompileCCpp(0, "Build succesfully!")
command! -buffer MD call CompileCCpp(1, "Build in Debug mode succesfully!")
nmap <buffer> <silent> ,mk :M<cr>

" For TopCoder plugin VimCoder
nmap <buffer> <silent> ,op ,cd:!xdg-open Problem.html<cr><cr>:redraw!<cr>

" vim:fdm=marker:
