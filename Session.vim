let SessionLoad = 1
let s:so_save = &g:so | let s:siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1
let v:this_session=expand("<sfile>:p")
doautoall SessionLoadPre
silent only
silent tabonly
cd ~/work/dictionary/goldfish
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
let s:shortmess_save = &shortmess
set shortmess+=aoO
badd +0 term://~/work/dictionary/goldfish//3145:/bin/bash
badd +198 ~/work/dictionary/goldfish/src/Pages/Goldfish.elm
badd +136 ~/work/dictionary/goldfish/src/Layouts/Main.elm
badd +131 ~/work/dictionary/goldfish/src/Pages/Goldfish/Settings.elm
badd +63 ~/work/dictionary/goldfish/src/Pages/Goldfish/Learn.elm
badd +1 ~/work/dictionary/goldfish/src/Pages/Goldfish/Notebook.elm
badd +69 ~/work/dictionary/goldfish/src/Pages/Goldfish/Learn/Flashcards.elm
badd +50 ~/work/dictionary/goldfish/src/Pages/Goldfish/Learn/Typing.elm
badd +68 ~/work/dictionary/goldfish/src/Shared.elm
badd +8 ~/work/dictionary/goldfish/src/Shared/Model.elm
badd +8 ~/work/dictionary/goldfish/src/Shared/Msg.elm
badd +218 ~/work/dictionary/goldfish/src/Effect.elm
badd +5 ~/work/dictionary/goldfish/src/interop.js
argglobal
%argdel
set stal=2
tabnew +setlocal\ bufhidden=wipe
tabnew +setlocal\ bufhidden=wipe
tabrewind
argglobal
if bufexists(fnamemodify("term://~/work/dictionary/goldfish//3145:/bin/bash", ":p")) | buffer term://~/work/dictionary/goldfish//3145:/bin/bash | else | edit term://~/work/dictionary/goldfish//3145:/bin/bash | endif
if &buftype ==# 'terminal'
  silent file term://~/work/dictionary/goldfish//3145:/bin/bash
endif
balt term://~/work/dictionary/goldfish//3145:/bin/bash
setlocal foldmethod=manual
setlocal foldexpr=0
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=0
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
let s:l = 23 - ((21 * winheight(0) + 16) / 32)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 23
normal! 0
tabnext
edit ~/work/dictionary/goldfish/src/Pages/Goldfish/Settings.elm
argglobal
setlocal foldmethod=manual
setlocal foldexpr=0
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=0
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
silent! normal! zE
let &fdl = &fdl
let s:l = 77 - ((8 * winheight(0) + 16) / 32)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 77
normal! 037|
tabnext
edit ~/work/dictionary/goldfish/src/interop.js
argglobal
setlocal foldmethod=manual
setlocal foldexpr=0
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=0
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
silent! normal! zE
let &fdl = &fdl
let s:l = 5 - ((4 * winheight(0) + 16) / 32)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 5
normal! 011|
tabnext 3
set stal=1
if exists('s:wipebuf') && len(win_findbuf(s:wipebuf)) == 0 && getbufvar(s:wipebuf, '&buftype') isnot# 'terminal'
  silent exe 'bwipe ' . s:wipebuf
endif
unlet! s:wipebuf
set winheight=1 winwidth=20
let &shortmess = s:shortmess_save
let s:sx = expand("<sfile>:p:r")."x.vim"
if filereadable(s:sx)
  exe "source " . fnameescape(s:sx)
endif
let &g:so = s:so_save | let &g:siso = s:siso_save
set hlsearch
doautoall SessionLoadPost
unlet SessionLoad
" vim: set ft=vim :
