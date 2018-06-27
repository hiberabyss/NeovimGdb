if !exists('g:nvimgdb_host_cmd')
	let g:nvimgdb_host_cmd = {}
endif

if !has('nvim') | finish | endif

sign define GdbBreakpoint text=●
sign define GdbCurrentLine text=⇒

let s:breakpoints = {}
let s:max_breakpoint_sign_id = 5000

let s:GdbServer = {}

function s:GdbServer.new(gdb)
	let this = copy(self)
	let this._gdb = a:gdb
	return this
endfunction

function s:GdbServer.on_exit()
	let self._gdb._server_exited = 1
endfunction

let s:GdbPaused = vimexpect#State([
			\ ['\v[\o32]{2}([^:]+):(\d+):\d+', 'jump'],
			\ ['\v^\> \S+ ([^:]+):(\d+)', 'jump'],
			\ ['Continuing.', 'continue'],
			\ ['Starting program', 'continue'],
			\ ['\v^Breakpoint (\d+) at 0[xX]\x+: file ([^,]+), line (\d+)', 'mybreak'],
			\ ['\v^Breakpoint (\d+) at 0[xX]\x+: ([^:]+):(\d+)', 'mybreak'],
			\ ['\v^Breakpoint (\d+) set at 0[xX]\x+ for \S+ ([^:]+):(\d+)', 'mybreak'],
			\ ])

let s:GdbRunning = vimexpect#State([
			\ ['\v^Breakpoint \d+,', 'pause'],
			\ ['\vhit Breakpoint \d+, ', 'pause'],
			\ ['\v^Temporary breakpoint \d+,', 'pause'],
			\ ['\vhit Hardware ', 'pause'],
			\ ['(gdb)', 'pause'],
			\ ['gdb\$', 'pause'],
			\ ['(dlv)', 'pause'],
			\ ['\v\[Inferior\ +.{-}\ +exited\ +normally', 'disconnected'],
			\ ])

function s:GdbPaused.continue(...)
	call self._parser.switch(s:GdbRunning)
	call self.update_current_line_sign(0)
endfunction

function s:GdbPaused.jump(file, line, ...)
	let file = a:file
	if !empty(g:gdb._server_addr)
		let file = debugger_util#GetLocalFilePath(file)
	endif

	if empty(file) | return -1 | endif

	let window = winnr()
	exe self._jump_window 'wincmd w'
	let self._current_buf = bufnr('%')
	let target_buf = bufnr(file, 1)
	if bufnr('%') != target_buf
		exe 'buffer ' target_buf
		let self._current_buf = target_buf
	endif
	exe ':' a:line
	let self._current_line = a:line
	exe window 'wincmd w'
	call self.update_current_line_sign(1)
endfunction

function! <SID>ToggleBreakpoint()
	if !exists('g:gdb') | return | endif

	let file_breakpoints = get(s:breakpoints, bufname('%'), {})

	let linenr = line('.')
	if has_key(file_breakpoints, linenr)
		call debugger_term#Send("delete " . file_breakpoints[linenr]['brknum'])
		call remove(file_breakpoints, linenr)
		exe "sign unplace"
		return
	endif

	if g:gdb._parser.state() == s:GdbRunning
		call jobsend(g:gdb._client_id, "\<c-c>")
		sleep 200m
	endif

	let trimed_filename = expand('%:p:h:t') .'/'. expand('%:t')
	call debugger_term#Send(printf('break %s:%d ', trimed_filename, line('.')))
endfunction

function! s:GdbPaused.mybreak(brknum, filename, linenr, ...)
	execute("1wincmd w")
	let file_name = bufname('%')

	let file_breakpoints = get(s:breakpoints, file_name, {})
	let linenr = line('.')

	if has_key(file_breakpoints, linenr)
		return
	endif

	let file_breakpoints[linenr] = {}
	let file_breakpoints[linenr]['content'] = getline('.')
	let file_breakpoints[linenr]['brknum'] = a:brknum
	let s:breakpoints[file_name] = file_breakpoints

	exe 'sign place '. s:max_breakpoint_sign_id .' name=GdbBreakpoint line='.line('.').' buffer=' . bufnr('%')
	let s:max_breakpoint_sign_id += 1
endfunction

function s:GdbRunning.pause(...)
	call self._parser.switch(s:GdbPaused)
	if !self._initialized
		call self.send('set confirm off')
		call self.send('shell clear')
		let self._initialized = 1
	endif
endfunction

function s:GdbRunning.disconnected(...)
	if !self._server_exited && self._reconnect
		" Refresh to force a delete of all watchpoints
		call s:RefreshBreakpoints()
		sleep 1
		" call self.attach()
		call self.send('continue')
	endif
endfunction

let s:Gdb = {}

function s:Gdb.kill()
	if !exists('g:gdb') | return | endif
    call debugger_util#DebuggerMapping(0)
	call self.update_current_line_sign(0)
	let s:breakpoints = {}
	call s:RefreshBreakpointSigns()
	exe 'bd! '.self._client_buf
	if self._server_buf != -1
		exe 'bd! '.self._server_buf
	endif
	exe 'tabnext '.self._tab
	unlet g:gdb
endfunction

function! s:Gdb.send(data)
	call window#GetGdbWin()
	call jobsend(self._client_id, "\<c-u>")
	call jobsend(self._client_id, a:data."\<cr>")
endfunction

function! s:Gdb.sendRaw(data)
	call window#GetGdbWin()
	call jobsend(self._client_id, "\<c-u>")
	call jobsend(self._client_id, a:data)
endfunction

function! s:Gdb.update_current_line_sign(add)
	" to avoid flicker when removing/adding the sign column(due to the change in
	" line width), we switch ids for the line sign and only remove the old line
	" sign after marking the new one
	let old_line_sign_id = get(self, '_line_sign_id', 4999)
	let self._line_sign_id = old_line_sign_id == 4999 ? 4998 : 4999
	if a:add && self._current_line != -1 && self._current_buf != -1
		exe 'sign place '.self._line_sign_id.' name=GdbCurrentLine line='
					\.self._current_line.' buffer='.self._current_buf
	endif
	exe 'sign unplace '.old_line_sign_id
endfunction

function! s:Spawn(server_host, client_cmd)
	if exists('g:gdb')
		throw 'Gdb already running'
	endif

    call debugger_util#DebuggerMapping(1)

	let gdb = vimexpect#Parser(s:GdbRunning, copy(s:Gdb))
	let gdb._server_addr = a:server_host
	let gdb._reconnect = 0

	let gdb._initialized = 0
    if &filetype == "go"
        let gdb._initialized = 1
    endif

	let gdb._jump_window = 1
	let gdb._current_buf = -1
	let gdb._current_line = -1
	let gdb._has_breakpoints = 0 
	let gdb._server_exited = 0
	let gdb._server_buf = -1
	let gdb._client_buf = -1

	let gdb._tab = tabpagenr()

	call window#CreateGdbWin()

	if empty(a:server_host)
		let gdb._client_id = termopen(a:client_cmd, gdb)
	else
		let gdb._client_id = termopen('zsh', gdb)

		let items = split(a:server_host, ':')
		let ssh_host = items[0]
		let ssh_cmd = printf('ssh %s', ssh_host)
		if len(items) > 1
			let ssh_port = items[1]
			let ssh_cmd = printf('ssh %s -p %s', ssh_host, ssh_port)
		endif

		if has_key(g:nvimgdb_host_cmd, ssh_host)
			let commands = g:nvimgdb_host_cmd[ssh_host]

			if commands[0] == 'Docker'
				call jobsend(gdb._client_id, "docker exec -it " .a:server_host. " bash\<cr>")
				let commands = commands[1:]
			else
				call jobsend(gdb._client_id, ssh_cmd ." \<cr>")
			endif

			for cmd in commands
				call jobsend(gdb._client_id, cmd . "\<cr>")
			endfor
		else
			call jobsend(gdb._client_id, ssh_cmd .' \<cr>')
		endif
	endif

	let gdb._client_buf = bufnr('%')

	exe gdb._jump_window 'wincmd w'
	let g:gdb = gdb
endfunction

function! s:ToggleBreak()
	let file_name = bufname('%')
	let file_breakpoints = get(s:breakpoints, file_name, {})
	let linenr = line('.')
	if has_key(file_breakpoints, linenr)
		call remove(file_breakpoints, linenr)
	else
		let file_breakpoints[linenr] = getline('.')
	endif
	let s:breakpoints[file_name] = file_breakpoints
	call s:RefreshBreakpointSigns()
	call s:RefreshBreakpoints()
endfunction

function! s:ClearBreak()
	let s:breakpoints = {}
	call s:RefreshBreakpointSigns()
	call s:RefreshBreakpoints()
endfunction

function! s:SetBreakpoints()
	call s:RefreshBreakpointSigns()
	call s:RefreshBreakpoints()
endfunction

function! s:RefreshBreakpointSigns()
	let buf = bufnr('%')
	let i = 5000
	while i < s:max_breakpoint_sign_id
		exe 'sign unplace '.i
		let i += 1
	endwhile
	let id = 5000
	for linenr in keys(get(s:breakpoints, bufname('%'), {}))
		exe 'sign place '.id.' name=GdbBreakpoint line='.linenr.' buffer='.buf
		let id += 1
		let s:max_breakpoint_sign_id = id
	endfor
endfunction

function! s:SetLocationList()
	if !exists('g:gdb') && !g:gdb._has_breakpoints | return | endif
	let expr_list = []
	for [file, breakpoints] in items(s:breakpoints)
		for [linenr,line] in items(breakpoints)
			call add(expr_list, file . ':' . linenr . ': ' . line['content'])
		endfor
	endfor

	if !empty(expr_list)
		lgetexpr expr_list
		botright lopen
	endif
endfunction

command! GdbList call s:SetLocationList()
nmap <silent> ;gl :GdbList<cr>

function! s:RefreshBreakpoints()
	if !exists('g:gdb') | return | endif
	if g:gdb._parser.state() == s:GdbRunning
		" pause first
		call jobsend(g:gdb._client_id, "\<c-c>")
	endif
	if g:gdb._has_breakpoints
		call g:gdb.send('delete')
	endif
	let g:gdb._has_breakpoints = 0
	for [file, breakpoints] in items(s:breakpoints)
		for linenr in keys(breakpoints)
			let g:gdb._has_breakpoints = 1
			call g:gdb.send('break '.file.':'.linenr)
		endfor
	endfor
endfunction

function! s:GetExpression(...) range
	let [lnum1, col1] = getpos("'<")[1:2]
	let [lnum2, col2] = getpos("'>")[1:2]
	let lines = getline(lnum1, lnum2)
	let lines[-1] = lines[-1][:col2 - 1]
	let lines[0] = lines[0][col1 - 1:]
	return join(lines, "\n")
endfunction

function! s:Watch(expr)
	let expr = a:expr
	if expr[0] != '&'
		let expr = '&' . expr
	endif

	call debugger_util#Eval(expr)
	call debugger_term#Send('watch *$')
endfunction

function! s:Interrupt()
	if !exists('g:gdb')
		throw 'Gdb is not running'
	endif
	call jobsend(g:gdb._client_id, "\<c-c>info line\<cr>")
endfunction

function! s:Kill()
	if !exists('g:gdb') | return | endif
	call g:gdb.kill()
endfunction

function! s:CreateToggleBreak()
	if !exists('g:gdb')
		call s:Spawn(0, printf("gdb -q -f %s.bin", expand('%:r')))
		sleep 100m
	endif
	call s:ToggleBreak()
endfunction

let g:local_gdb_cmd = "gdb -q -f"

if has('mac')
    let g:local_gdb_cmd = "sudo " .g:local_gdb_cmd
endif

function! GoDlvDebug()
    if empty("<bang>")
        call s:Spawn(0, "dlv debug ")
    else
        call s:Spawn(0, "dlv debug " .expand('%'))
    endif
endfunction

command! -nargs=1 -complete=file GdbStart call s:Spawn(0, printf(g:local_gdb_cmd . " %s", <q-args>))
command! -nargs=1 GdbConnect call s:Spawn(<q-args>, 0)
command! GdbZsh call s:Spawn(0, "zsh")
command! GdbWin call window#GetGdbWin()
command! GdbSetBreaks call s:SetBreakpoints()

command! GdbStop call s:Kill()
command! GdbToggleBreakpoint call s:CreateToggleBreak()
command! GdbClearBreakpoints call s:ClearBreak()
command! GdbInterrupt call s:Interrupt()
command! GdbEvalWord call debugger_util#Eval(debugger_util#GetCppCword())
command! -range GdbEvalRange call debugger_util#Eval(s:GetExpression(<f-args>))
command! GdbWatchWord call s:Watch(expand('<cword>'))
command! -range GdbWatchRange call s:Watch(s:GetExpression(<f-args>))

let g:vim_debugger_mapping = {
            \ ';r' : "run",
            \ ';c' : "c",
            \ ';n' : "n",
            \ ';s' : "s",
            \ ';f' : "finish",
            \ }

nnoremap <silent> ;b :call <SID>ToggleBreakpoint()<cr>
nnoremap <silent> ;p :GdbEvalWord<cr>
vnoremap <silent> ;p "vy:call debugger_util#Eval(@v)<cr>
nnoremap <silent> ;gc :call debugger_util#GoCurrentLine()<cr>
nnoremap <silent> ;gk :GdbDebugStop<cr>

nnoremap <silent> ;gb :call debugger_term#SendRaw(printf("break %s:%d ", expand('%'), line('.')))<cr>
nnoremap <silent> ;tb :call debugger_term#Send(printf("tbreak %s:%d", expand('%'), line('.')))<cr>
nnoremap <silent> ;u :call debugger_term#Send(printf("until %s:%d", expand('%'), line('.')))<cr>
