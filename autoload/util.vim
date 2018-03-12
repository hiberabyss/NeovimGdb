function! util#Eval(expr)
	call term#Send(printf('print %s', a:expr))
endfunction

function! util#GetLocalFilePath(file)
	let paths = split(split(a:file, ':')[0], '/')

	let file_path = ""
	for i in range(-1, -len(paths), -1)
		let search_pattern = "**/" . join(paths[i:], '/')
		let res = split(globpath(getcwd(), search_pattern))
		if len(res) == 0
			return file_path
		endif

		if len(res) == 1
			let file_path = res[0]
			break
		endif
	endfor

	if !empty(file_path)
		let file_path = fnamemodify(file_path, ":~:.")
	endif

	return file_path
endfunction

function! util#GetCppCword()
	let save_keyword = &iskeyword
	set iskeyword+=.,-,>,:
	let cword = expand('<cword>')
	let &iskeyword = save_keyword
	return cword
endfunction

function! util#GoCurrentLine()
	if !exists('g:gdb')
		return
	endif
	execute(":buffer " . g:gdb._current_buf)
	execute(":" . g:gdb._current_line)
endfunction

function! util#DebuggerMapping(load)
    if ! exists('g:vim_debugger_mapping')
        return
    endif

    for k in keys(g:vim_debugger_mapping)
        if a:load
            execute(printf(':nnoremap <silent> %s :call term#Send("%s")<cr>', k, g:vim_debugger_mapping[k]))
        else
            execute(printf(':unmap %s', k))
        endif
    endfor
endfunction
