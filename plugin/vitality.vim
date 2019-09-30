" ============================================================================
" File:        vitality.vim
" Description: Make Vim play nicely with iTerm2 and tmux.
" Maintainer:  Steve Losh <steve@stevelosh.com>
" License:     MIT/X11
" ============================================================================

" Init {{{

if has('gui_running')
    finish
endif

if !exists('g:vitality_debug') && (exists('loaded_vitality') || &cp)
    finish
endif

let loaded_vitality = 1

if !exists('g:vitality_fix_cursor') " {{{
    let g:vitality_fix_cursor = 1
endif " }}}
if !exists('g:vitality_fix_focus') " {{{
    let g:vitality_fix_focus = 1
endif " }}}

" iTerm2 cursor types:
"
" Block = 0
" Bar = 1
" Underline = 2
if !exists('g:vitality_normal_cursor') " {{{
    let g:vitality_normal_cursor = 0
endif " }}}
if !exists('g:vitality_insert_cursor') " {{{
    let g:vitality_insert_cursor = 1
endif " }}}

if exists('g:vitality_always_assume_iterm') " {{{
    let s:inside_iterm = 1
else
    let s:inside_iterm = exists('$ITERM_PROFILE')
endif " }}}
if exists('g:vitality_always_assume_mintty') " {{{
    let s:inside_mintty = 1
else
    let s:inside_mintty = exists('$MINTTY')
endif " }}}
if exists('g:vitality_always_assume_terminalapp') " {{{
    let s:inside_terminalapp = 1
else
    let s:inside_terminalapp = $TERM_PROGRAM == 'Apple_Terminal'
endif " }}}

let s:inside_tmux = exists('$TMUX')

" }}}

function! s:SaveRestoreScreenEscapeSequences(cmd) " {{{
    if s:inside_iterm
        return a:cmd == 'save' ? "\<Esc>[?1049h" : "\<Esc>[?1049l"
    elseif s:inside_mintty
        " Not supported ? XXX
        return ""
    elseif s:inside_terminalapp
        " Not supported ? XXX
        return ""
    endif
endfunction " }}}

function! s:CursorShapeEscapeSequences(shape) "{{{
    if s:inside_iterm
        return "\<Esc>]50;CursorShape=" . a:shape . "\x7"
    elseif s:inside_mintty
        " https://github.com/mintty/mintty/wiki/CtrlSeqs#cursor-style
        let actual_shape = a:shape == 0 ? 1 : a:shape == 1 ? 5 : 3
        return "\<Esc>[" . actual_shape . " q"
    elseif s:inside_terminalapp
        " https://vt100.net/docs/vt510-rm/DECSCUSR
        let actual_shape = a:shape == 0 ? 2 : a:shape == 1 ? 5 : 3
        return "\<Esc>[" . actual_shape . " q"
    endif
endfunction " }}}

function! s:WrapForTmux(s) " {{{
    " To escape a sequence through tmux:
    "
    " * Wrap it in these sequences.
    " * Any <Esc> characters inside it must be doubled.
    let tmux_start = "\<Esc>Ptmux;"
    let tmux_end   = "\<Esc>\\"

    return tmux_start . substitute(a:s, "\<Esc>", "\<Esc>\<Esc>", 'g') . tmux_end
endfunction " }}}

function! s:Vitality() " {{{
    " Escape sequences {{{

    " iTerm2 allows you to turn "focus reporting" on and off with these
    " sequences.
    "
    " When reporting is on, iTerm2 will send <Esc>[O when the window loses focus
    " and <Esc>[I when it gains focus.
    "
    " TODO: Look into how this works with iTerm tabs.  Seems a bit wonky.
    let enable_focus_reporting  = "\<Esc>[?1004h"
    let disable_focus_reporting = "\<Esc>[?1004l"

    " These sequences save/restore the screen.
    " They should NOT be wrapped in tmux escape sequences for some reason!
    let save_screen    = s:SaveRestoreScreenEscapeSequences('save')
    let restore_screen = s:SaveRestoreScreenEscapeSequences('restore')

    " These sequences tell the terminal  to change the cursor shape.
    let cursor_to_normal = s:CursorShapeEscapeSequences(g:vitality_normal_cursor)
    let cursor_to_insert = s:CursorShapeEscapeSequences(g:vitality_insert_cursor)

    if s:inside_tmux
        " Some escape sequences (but not all, lol) need to be properly escaped
        " to get them through tmux without being eaten.

        let enable_focus_reporting = s:WrapForTmux(enable_focus_reporting) . enable_focus_reporting
        let disable_focus_reporting = disable_focus_reporting

        let cursor_to_normal = s:WrapForTmux(cursor_to_normal)
        let cursor_to_insert = s:WrapForTmux(cursor_to_insert)
    endif

    " }}}
    " Startup/shutdown escapes {{{

    " When starting Vim, enable focus reporting and save the screen.
    " When exiting Vim, disable focus reporting and save the screen.
    "
    " The "focus/save" and "nofocus/restore" each have to be in this order.
    " Trust me, you don't want to go down this rabbit hole.  Just keep them in
    " this order and no one gets hurt.
    if g:vitality_fix_focus
        let &t_ti = cursor_to_normal . enable_focus_reporting . save_screen . &t_ti
        let &t_te = disable_focus_reporting . restore_screen
    endif

    " }}}
    " Insert enter/leave escapes {{{

    if g:vitality_fix_cursor
        " When entering insert mode, change the cursor to the insert cursor.
        let &t_SI = cursor_to_insert . &t_SI

        " When exiting insert mode, change it back to normal.
        let &t_EI = cursor_to_normal . &t_EI
    endif

    " }}}
    " Focus reporting keys/mappings {{{
    if g:vitality_fix_focus
        " Map some of Vim's unused keycodes to the sequences iTerm2 is going to send
        " on focus lost/gained.
        "
        " If you're already using f24 or f25, change them to something else.  Vim
        " supports up to f37.
        "
        " Doing things this way is nicer than just mapping the raw sequences
        " directly, because Vim won't hang after a bare <Esc> waiting for the rest
        " of the mapping.
        execute "set <f24>=\<Esc>[O"
        execute "set <f25>=\<Esc>[I"

        " Handle the focus gained/lost signals in each mode separately.
        "
        " The goal is to fire the autocmd and restore the state as cleanly as
        " possible.  This is easy for some modes and hard/impossible for others.

        nnoremap <silent> <f24> :silent doautocmd FocusLost %<cr>
        nnoremap <silent> <f25> :silent doautocmd FocusGained %<cr>

        onoremap <silent> <f24> <esc>:silent doautocmd FocusLost %<cr>
        onoremap <silent> <f25> <esc>:silent doautocmd FocusGained %<cr>

        vnoremap <silent> <f24> <esc>:silent doautocmd FocusLost %<cr>gv
        vnoremap <silent> <f25> <esc>:silent doautocmd FocusGained %<cr>gv

        inoremap <silent> <f24> <c-\><c-o>:silent doautocmd FocusLost %<cr>
        inoremap <silent> <f25> <c-\><c-o>:silent doautocmd FocusGained %<cr>

        cnoremap <silent> <f24> <c-\>e<SID>DoCmdFocusLost()<cr>
        cnoremap <silent> <f25> <c-\>e<SID>DoCmdFocusGained()<cr>
    endif

    " }}}
endfunction " }}}

function s:DoCmdFocusLost()
    let cmd = getcmdline()
    let pos = getcmdpos()

    silent doautocmd FocusLost %

    call setcmdpos(pos)
    return cmd
endfunction

function s:DoCmdFocusGained()
    let cmd = getcmdline()
    let pos = getcmdpos()

    silent doautocmd FocusGained %

    call setcmdpos(pos)
    return cmd
endfunction

if s:inside_iterm || s:inside_mintty || s:inside_terminalapp
    call s:Vitality()
endif
