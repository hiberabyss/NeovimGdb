
function! window#CreateGdbWin()
	botright new | res 12 | setl winfixheight
endfunction

function! window#GetGdbWin()
	if !exists('g:gdb') | return | endif
	if g:gdb._client_buf >= 0
		let buflist = tabpagebuflist()
		if index(buflist, g:gdb._client_buf) >= 0 | return | endif
		call window#CreateGdbWin()
		execute('silent buffer +set\ nornu ' . g:gdb._client_buf)
		execute('wincmd w | stopinsert')
	endif
endfunction

