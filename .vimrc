" === Core Settings ===
set nocompatible                  " Enable modern Vim features
syntax enable                     " Enable syntax highlighting
filetype plugin indent on         " Enable file type detection
set encoding=utf-8                " Use UTF-8 encoding
set background=dark               " Use dark background
set shortmess+=cAIF               " Suppress various messages (completion, attention, intro, file info)

" === Leader Key Configuration ===
let mapleader = ","               " Use comma for leader
let maplocalleader = " "          " Use space for localleader

" === UI Configuration ===
set number relativenumber         " Hybrid line numbers
set signcolumn=yes                " Always show sign column
set cursorline                    " Highlight current line
set colorcolumn=80                " Mark 80 character limit
set textwidth=80                  " Text width for automatic wrapping
set scrolloff=3                   " Keep 3 lines visible above/below cursor
set splitright                    " Open vertical splits to the right
set wildmenu                      " Enhanced command completion
set wildmode=list:full            " List all matches and complete first match
set gfn=Monaco:h14                " GUI font
set updatetime=1000               " Faster completion
set ttyfast                       " Faster terminal connection
set lazyredraw                    " Don't redraw during macros
set timeout timeoutlen=1000 ttimeoutlen=50  " Faster key response

" === Terminal Settings ===
if has('termguicolors')
    set termguicolors
endif

" === File Management ===
set nobackup
set noswapfile
set nowritebackup
set undofile
set undodir=~/.vim/undodir        " Persistent undo history
set autoread                      " Reload files changed outside vim
set hidden                        " Allow hidden buffers

" === Search and Replace ===
set hlsearch                      " Highlight search results
set incsearch                     " Incremental search
set ignorecase                    " Case-insensitive search
set smartcase                     " Case-sensitive if uppercase present
set gdefault                      " Global replace by default

" === Indentation and Tabs ===
set expandtab                     " Use spaces instead of tabs
set shiftwidth=2                  " Number of spaces for auto-indenting
set tabstop=2                     " Number of spaces that a <Tab> counts for
set softtabstop=2                 " Number of spaces that a <Tab> counts for while editing

" === Clipboard Configuration ===
set clipboard^=unnamed,unnamedplus " Use system clipboard

" === Python Configuration ===
let g:python3_host_prog = '/opt/homebrew/bin/python3'

" === Plugin Management (vim-plug) ===
call plug#begin('~/vimplugins')

" === Core Development Plugins ===
Plug 'neoclide/coc.nvim', {'branch': 'release'}
Plug 'github/copilot.vim'
" Plug 'CoderCookE/vim-chatgpt'

" === Navigation and Search ===
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'justinmk/vim-sneak'
Plug 'junegunn/vim-peekaboo'
Plug 'morhetz/gruvbox'
" === Text Manipulation ===
Plug 'junegunn/vim-easy-align'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-unimpaired'
Plug 'tpope/vim-obsession'
Plug 'tpope/vim-repeat'
Plug 'SirVer/ultisnips'

" === Language Support ===
Plug 'lervag/vimtex', { 'for': 'tex' }
Plug 'rgt47/zzvim-R'
" Plug 'rgt47/zzvim-R', { 'branch': 'feature/object-browser' }
" set runtimepath+=/Users/zenn/Dropbox/prj/d05/zzvim-R
 " set runtimepath+=/Users/zenn/Dropbox/prj/d05/zzvim-R_fullbackup2
" === UI Enhancement ===
Plug 'vim-airline/vim-airline'
Plug 'machakann/vim-highlightedyank'
Plug 'rafi/awesome-vim-colorschemes'

call plug#end()

" === ChatGPT Configuration ===
let g:chat_gpt_max_tokens=2000
let g:chat_gpt_model='gpt-3.5-turbo-16k'
let g:chat_gpt_session_mode=0
let g:chat_gpt_temperature = 0.5
let g:chat_gpt_lang = 'English'
let g:chat_gpt_split_direction = 'vertical'
let g:chat_gpt_key=$OPENAI_API_KEY

" ChatGPT mappings
nnoremap <leader>c :ChatGPT<CR>
nnoremap <leader>cc :ChatGPTCompact<CR>
nnoremap <leader>ce :ChatGPTEdit<CR>
vnoremap <leader>ce :ChatGPTEditSelection<CR>

" === CoC Configuration ===
" General CoC settings
autocmd BufWritePre *.Rmd,*.R :CocCommand editor.action.format
inoremap <silent><expr> <C-Space> coc#refresh()  " Force open CoC menu

" CoC navigation keys
inoremap <expr><C-j> coc#pum#visible() ? coc#pum#next(1) : "\<C-j>"
inoremap <expr><C-k> coc#pum#visible() ? coc#pum#prev(1) : "\<C-k>"
inoremap <expr><C-y> coc#pum#visible() ? coc#pum#confirm() : "\<C-y>"
inoremap <expr><S-Tab> coc#pum#visible() ? coc#pum#prev(1) : "\<S-Tab>"
inoremap <expr><CR> coc#pum#visible() ? coc#pum#confirm() : "\<CR>"

" Tab key handling (prioritizes CoC when menu is visible)
inoremap <expr><Tab> coc#pum#visible() ? coc#pum#next(1) : (copilot#GetDisplayedSuggestion().text != '' ? copilot#Accept("\<CR>") : "\<Tab>")

" === Copilot Configuration ===
let g:copilot_enabled = 1
let g:copilot_no_tab_map = v:true  " Don't use Tab mapping directly
let g:copilot_idle_delay = 2000    " Wait 2 seconds before showing suggestions

" Copilot appearance and keys
highlight CopilotSuggestion guifg=#00ff00 guibg=NONE ctermfg=10
imap <silent><expr> <C-l> copilot#Accept("\<CR>")

" Toggle Copilot function
function! ToggleCopilot() abort
    if copilot#Enabled()
        Copilot disable
        echo "Copilot disabled"
    else
        Copilot enable
        echo "Copilot enabled"
    endif
endfunction

nnoremap <leader><C-o> :call ToggleCopilot()<CR>
inoremap <leader><C-o> <Esc>:call ToggleCopilot()<CR>a

" === UltiSnips Configuration ===
let g:UltiSnipsExpandTrigger="<C-Tab>"
let g:UltiSnipsJumpForwardTrigger="<C-Tab>"
let g:UltiSnipsJumpBackwardTrigger="<C-S-Tab>"

" === UltiSnips and CoC Interaction Fix ===
" Temporarily disable CoC when editing snippets to prevent interference
" augroup UltiSnipsCoC
"   autocmd!
"   autocmd User UltiSnipsEnterFirstSnippet let b:coc_suggest_disable = 1
"   autocmd User UltiSnipsExitLastSnippet let b:coc_suggest_disable = 0
" augroup END

" Ensure Ctrl-Tab always jumps in snippets even if interrupted
function! JumpInSnippet()
  if UltiSnips#CanJump()
    call UltiSnips#JumpForwards()
    return ""
  else
    return "\<C-Tab>"
  endif
endfunction

inoremap <silent><expr> <C-Tab> JumpInSnippet()

" Helper function for backspace behavior
function! CheckBackspace() abort
    let col = col('.') - 1
    return !col || getline('.')[col - 1]  =~# '\s'
endfunction

" === Plugin Configurations ===
" vim-airline config
let g:airline#extensions#ale#enabled = 1
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#fzf#enabled = 1

" vimtex config
let g:vimtex_complete_close_braces=1
let g:vimtex_quickfix_mode=0

" ultisnips config
nnoremap <leader>U <Cmd>call UltiSnips#RefreshSnippets()<CR>
nnoremap <leader>u :UltiSnipsEdit<cr>

" vim-sneak config
let g:sneak#label = 1
let g:sneak#s_next = 1
let g:sneak#use_ic_scs = 1

" colorscheme
let g:gruvbox_contrast_dark='hard'
" colorscheme gruvbox
" === FZF Mappings ===
nnoremap <leader>z :Files<CR>
nnoremap <Leader>' :Marks<CR>
nnoremap <Leader>/ :BLines<CR>
nnoremap <Leader>b :Buffers<CR>
nnoremap <Leader>B :BuffersAll<CR>
nnoremap <Leader>r :Rg<CR>
nnoremap <Leader>s :Snippets<CR>

" Show all buffers including directory listings and special buffers
command! BuffersAll call fzf#run(fzf#wrap({
\ 'source': map(filter(range(1, bufnr('$')), 'bufexists(v:val) && buflisted(v:val) == 0 || buflisted(v:val) == 1'), 
\               'printf("%d: %s [%s]", v:val, empty(bufname(v:val)) ? "[No Name]" : fnamemodify(bufname(v:val), ":~:."), getbufvar(v:val, "&filetype"))'),
\ 'sink': {line -> execute('buffer ' . split(line, ':')[0])},
\ 'options': '--prompt="AllBuf> " --preview-window=down:2'
\ }))

" === Spell Check Configuration ===
set spelllang=en_us
nnoremap <leader>w z=   " List spelling suggestions
nnoremap <leader>e zg   " Add word to dictionary
nnoremap <leader>n ]s   " Next misspelled word
nnoremap <leader>p [s   " Previous misspelled word

" === Completion Menu Appearance ===
highlight Pmenu guifg=Black guibg=cyan gui=bold
highlight PmenuSel gui=bold guifg=White guibg=blue

" === Movement Enhancement ===
" Improved vertical movement
nnoremap zh 14H
xnoremap zh :<C-u>normal! gv14H<CR>
nnoremap zl 14L
xnoremap zl :<C-u>normal! gv14L<CR>
nnoremap zj 5j
xnoremap zj :<C-u>normal! gv5j<CR>
nnoremap zk 5k
xnoremap zk :<C-u>normal! gv5k<CR>

" === Key Mappings ===
" Function key mappings for buffer and tab navigation
nnoremap <F1> :bprev<CR>
nnoremap <F2> :bnext<CR>
nnoremap <F4> :tabprevious<CR>
nnoremap <F5> :tabnext<CR>

" Buffer navigation
nnoremap <leader>1 <C-w>:b1<CR>
nnoremap <leader>2 <C-w>:b2<CR>
nnoremap <leader>3 <C-w>:b3<CR>
nnoremap <leader>4 <C-w>:b4<CR>
nnoremap <leader>5 <C-w>:b5<CR>
nnoremap <leader>6 :vert sb2<cr>
nnoremap <leader>8 :vert sb3<cr>
nnoremap <leader>9 :vert sb4<cr>

" Window and mode navigation
nnoremap <leader><leader> <C-w>w
nnoremap <leader>f :tab split<cr>
nnoremap <leader>v :edit ~/.vimrc<cr>

" Text selection and formatting
nnoremap <leader>a ggVG  " Select all
nnoremap <leader>m vipgq " Format paragraph

" Movement optimizations
noremap : ;   " Swap ; and : for easier commands
noremap ; :
 " Swap $ and =
nnoremap == $
inoremap -- _

" Scroll mappings
nnoremap <space><leader> <C-u>  " Scroll up half page
nnoremap <space><space> <C-d>   " Scroll down half page

" Terminal mode mappings
tnoremap <Esc> <C-\><C-n>
tnoremap zq <C-\><C-n>
tnoremap <leader>f <C-w>:tab split<cr>
tnoremap <leader>g <C-w>:tabc<cr>
tnoremap <leader><leader> <C-w>w
tnoremap <leader>1 <C-w>:b1<CR>
tnoremap <leader>2 <C-w>:b2<CR>
tnoremap <leader>3 <C-w>:b3<CR>
tnoremap <leader>4 <C-w>:b4<CR>
tnoremap <leader>5 <C-w>:b5<CR>
tnoremap <F1> <C-w>:bprev<CR>
tnoremap <F2> <C-w>:bnext<CR>
tnoremap <F4> <C-w>:tabprevious<CR>
tnoremap <F5> <C-w>:tabnext<CR>
tnoremap <leader>b <C-w>:Buffers<CR>
tnoremap <leader>B <C-w>:BuffersAll<CR>
tnoremap ZZ <C-d>

" Completion menu navigation
inoremap <F10> <C-x><C-k>
inoremap <F12> <C-x><C-o>
" inoremap <silent> <Esc> <Esc>``^

" === RMarkdown Specific ===
nnoremap ZT :terminal Rscript -e "rmarkdown::render('%:p')" && exit<CR>:bd!<CR>

" === Auto Commands ===
augroup AutoSave
    autocmd!
    " Consider reducing frequency of autosave to reduce disk writes
    autocmd CursorHold,CursorHoldI * silent! update
    autocmd FocusGained * :let @z=@*
augroup END

augroup FileTypeSpecific
    autocmd!
    autocmd FileType quarto setlocal commentstring=#\ %s
    autocmd FileType rmd setlocal commentstring=#\ %s
augroup END

inoremap <F5> <C-r>=exists('b:coc_suggest_disable') ? b:coc_suggest_disable : 'not set'<CR>
" want cursor default of moving left after escaping insert mode to be
" suppressed even at line end. try these two lins. 
au InsertLeave * call cursor([getpos('.')[1], getpos('.')[2]+1])
set virtualedit=all
"
"
" Start EasyAlign in visual mode with `ga`
xmap ga <Plug>(EasyAlign)

" Start EasyAlign in normal mode with `ga`, prompts for delimiter
nmap ga <Plug>(EasyAlign)

" update buffer if disk file changed. to facilitate working with AI agents. 
set autoread
au CursorHold,CursorHoldI * checktime
au FocusGained,BufEnter * :silent! checktime
