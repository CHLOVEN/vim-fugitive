" fugitive_refactor.vim - Refactored code detection for vim-fugitive
" Maintainer: vim-fugitive contributors

" Highlight group for refactored code - BRIGHT MAGENTA to be very visible
highlight default DiffRefactor guibg=#FF00FF guifg=#000000 ctermbg=201 ctermfg=black gui=bold cterm=bold

" Store match IDs for cleanup
let s:match_ids = {'old': [], 'new': []}

" Get the path to the Python analyzer script
function! s:GetAnalyzerPath() abort
  " Search for the Python script in runtimepath
  for path in split(&runtimepath, ',')
    let candidate = path . '/python/fugitive_refactor_analyzer.py'
    if filereadable(candidate)
      return candidate
    endif
  endfor
  " Fallback: try to find it relative to fugitive.vim location
  let fugitive_path = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
  return fugitive_path . '/python/fugitive_refactor_analyzer.py'
endfunction

" Clear all refactor highlights
function! fugitive#refactor#Clear() abort
  for winid in keys(s:match_ids)
    for id in get(s:match_ids, winid, [])
      try
        call matchdelete(id)
      catch
      endtry
    endfor
  endfor
  let s:match_ids = {'old': [], 'new': []}
endfunction

" Apply highlights for matched BLOCKS (line ranges)
function! fugitive#refactor#ApplyHighlights(blocks, old_winnr, new_winnr) abort
  call fugitive#refactor#Clear()
  
  let i = 0
  for block in a:blocks
    let old_start = get(block, 'old_start', 0)
    let old_end = get(block, 'old_end', 0)
    let new_start = get(block, 'new_start', 0)
    let new_end = get(block, 'new_end', 0)
    
    " Cycle colors: 1 -> 2 -> 3 -> 4 -> 5 -> 1...
    let color_idx = (i % 5) + 1
    let group_name = 'DiffRefactor' . color_idx
    
    if old_start > 0 && old_end > 0
      " Highlight block in old window (LHS)
      let current_win = winnr()
      execute a:old_winnr . 'wincmd w'
      " Match range of lines: \%>Xl\%<Yl matches lines X+1 to Y-1
      let pattern = '\%>' . (old_start - 1) . 'l\%<' . (old_end + 1) . 'l'
      let match_id = matchadd(group_name, pattern, 20)
      call add(s:match_ids['old'], match_id)
      execute current_win . 'wincmd w'
    endif
    
    if new_start > 0 && new_end > 0
      " Highlight block in new window (RHS)
      let current_win = winnr()
      execute a:new_winnr . 'wincmd w'
      let pattern = '\%>' . (new_start - 1) . 'l\%<' . (new_end + 1) . 'l'
      let match_id = matchadd(group_name, pattern, 20)
      call add(s:match_ids['new'], match_id)
      execute current_win . 'wincmd w'
    endif
    
    let i += 1
  endfor
endfunction

" Get file content from a fugitive buffer (handles fugitive:// URLs)
function! s:GetTempFileForBuffer(bufnr) abort
  let bufname = bufname(a:bufnr)
  
  " If it's a fugitive URL, we need to get the content
  if bufname =~# '^fugitive://'
    let temp = tempname()
    let lines = getbufline(a:bufnr, 1, '$')
    call writefile(lines, temp)
    return temp
  endif
  
  " Regular file
  return fnamemodify(bufname, ':p')
endfunction

" Main analysis function - called after diffsplit
function! fugitive#refactor#Analyze() abort
  " Check if refactor detection is enabled
  if !get(g:, 'fugitive_refactor_detection', 1)
    return
  endif
  
  " We need exactly 2 diff windows
  let diff_wins = []
  for winnr in range(1, winnr('$'))
    if getwinvar(winnr, '&diff')
      call add(diff_wins, winnr)
    endif
  endfor
  
  if len(diff_wins) != 2
    return
  endif
  
  let old_winnr = diff_wins[0]
  let new_winnr = diff_wins[1]
  let old_bufnr = winbufnr(old_winnr)
  let new_bufnr = winbufnr(new_winnr)
  
  " Get file paths
  let old_file = s:GetTempFileForBuffer(old_bufnr)
  let new_file = s:GetTempFileForBuffer(new_bufnr)
  
  if empty(old_file) || empty(new_file)
    return
  endif
  
  " Get threshold
  let threshold = get(g:, 'fugitive_refactor_threshold', 0.75)
  
  " Get analyzer script path
  let analyzer = s:GetAnalyzerPath()
  if !filereadable(analyzer)
    echohl WarningMsg
    echom 'fugitive-refactor: analyzer not found: ' . analyzer
    echohl None
    return
  endif
  
  " Run Python analyzer
  let cmd = 'python "' . analyzer . '" "' . old_file . '" "' . new_file . '" --threshold=' . threshold
  let output = system(cmd)
  
  if v:shell_error
    echohl ErrorMsg
    echom 'fugitive-refactor: analyzer error: ' . output[:100]
    echohl None
    return
  endif
  
  " Parse JSON output
  try
    let result = json_decode(output)
  catch
    echohl ErrorMsg
    echom 'fugitive-refactor: failed to parse analyzer output'
    echohl None
    return
  endtry
  
  " Check for errors
  if has_key(result, 'error') && !empty(result.error)
    echohl WarningMsg
    echom 'fugitive-refactor: ' . result.error
    echohl None
    return
  endif
  
  " Apply highlights
  let blocks = get(result, 'blocks', [])
  if !empty(blocks)
    call fugitive#refactor#ApplyHighlights(blocks, old_winnr, new_winnr)
    let block_count = get(result, 'block_count', 0)
    let total_lines = get(result, 'total_lines', 0)
    echohl MoreMsg
    echo 'GdiffRefactor: Found ' . block_count . ' block(s) with ' . total_lines . ' refactored lines'
    echohl None
  else
    echohl WarningMsg
    echo 'GdiffRefactor: No refactored blocks detected (need 2+ consecutive matching lines)'
    echohl None
  endif
  
  " Clean up temp files if we created any
  if old_file =~# '^\%(/tmp\|C:\\Users\\.*\\AppData\\Local\\Temp\)'
    call delete(old_file)
  endif
  if new_file =~# '^\%(/tmp\|C:\\Users\\.*\\AppData\\Local\\Temp\)'
    call delete(new_file)
  endif
endfunction

" GdiffRefactor implementation - Gdiffsplit + refactor detection
" Usage: :GdiffRefactor [args] - same args as :Gdiffsplit
function! fugitive#refactor#Diffsplit(mods, args) abort
  " First run the normal Gdiffsplit
  execute a:mods . ' Gdiffsplit ' . a:args
  " Then analyze for refactored code
  call fugitive#refactor#Analyze()
endfunction
