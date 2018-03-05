# Demo

[![screencast](https://asciinema.org/a/dT2652AAwegDo0o0gWKsGOo1W.png)](https://asciinema.org/a/dT2652AAwegDo0o0gWKsGOo1W)

# What is NeovimGdb
Integrate vim and gdb, it could help you:

* View code in vim and run gdb command in a separated vim window
* Login to remote manchine and run gdb

Now, also suppport dlv to debug go files

# Usage
## Debug in remote server
* Use `GdbConnect host` to connect to remote server, this will `ssh host` or `docker exec -it host` (if the first item in g:nvimgdb_host_cmd is `Docker`) first, then run the following command in `g:nvimgdb_host_cmd `.

```vim
let g:nvimgdb_host_cmd = {
            \ 'dr01' : ['cads', 'gdb -f ./ads'],
            \ 'ts' : ['Docker', 'gdb -q -f --pid `pgrep transcoding`'],
            \ }
```

