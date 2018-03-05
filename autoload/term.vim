function! term#Send(data)
	if !exists('g:gdb')
		throw 'Gdb is not running'
	endif
	call g:gdb.send(a:data)
endfunction

function! term#SendRaw(data)
	if !exists('g:gdb')
		throw 'Gdb is not running'
	endif
	call g:gdb.sendRaw(a:data)
endfunction

