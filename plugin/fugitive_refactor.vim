" fugitive_refactor.vim - Plugin file for refactored code detection
" Requires vim-fugitive

if exists('g:loaded_fugitive_refactor') || &cp
  finish
endif
let g:loaded_fugitive_refactor = 1

" Highlight groups for refactored code (cycling colors)
" 1. Magenta (Original)
highlight default DiffRefactor1 guibg=#FF00FF guifg=#000000 ctermbg=201 ctermfg=black gui=bold cterm=bold
" 2. Cyan
highlight default DiffRefactor2 guibg=#00FFFF guifg=#000000 ctermbg=51 ctermfg=black gui=bold cterm=bold
" 3. Yellow
highlight default DiffRefactor3 guibg=#FFFF00 guifg=#000000 ctermbg=226 ctermfg=black gui=bold cterm=bold
" 4. Orange / Gold
highlight default DiffRefactor4 guibg=#FFD700 guifg=#000000 ctermbg=220 ctermfg=black gui=bold cterm=bold
" 5. Spring Green
highlight default DiffRefactor5 guibg=#00FF7F guifg=#000000 ctermbg=48 ctermfg=black gui=bold cterm=bold

" Backwards compatibility alias
highlight link DiffRefactor DiffRefactor1

" Commands
" :GdiffRefactor - Like :Gdiffsplit but with refactor detection
" :RefactorAnalyze - Manually trigger analysis on current diff
" :RefactorClear - Clear refactor highlights

command! -bar -bang -nargs=* -complete=customlist,fugitive#EditComplete GdiffRefactor call fugitive#refactor#Diffsplit('<mods>', <q-args>)
command! -bar RefactorAnalyze call fugitive#refactor#Analyze()
command! -bar RefactorClear call fugitive#refactor#Clear()
