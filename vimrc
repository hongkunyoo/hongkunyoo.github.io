" Using vim-plug: https://github.com/junegunn/vim-plug
"install vim-plug:
"    curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
call plug#begin('~/.vim/plugged')

" Declare the list of plugins.
Plug 'scrooloose/nerdtree'
Plug 'tpope/vim-sensible'
Plug 'junegunn/seoul256.vim'

" List ends here. Plugins become visible to Vim after this call.
call plug#end()

" ---------- seoul256 ----------- "
let g:seoul256_background = 233 
colo seoul256


" ---------- NERDTREE ----------- "
nnoremap <C-n> :NERDTree<CR>
"autocmd VimEnter * NERDTree | wincmd p

autocmd BufEnter * if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() |
    \ quit | endif

" ---------- vim settings ----------- "
set nu
set hls 
set autoindent
set smartindent
set expandtab smarttab
set tabstop=2
set shiftwidth=2
set clipboard=unnamed
set nocursorline
set encoding=utf-8
set showcmd
set ignorecase smartcase
set showmatch
set list
set mouse=


" ---------- vim keymap ----------- "
" disable Ctrl-a increment
map <C-a> <Nop>
