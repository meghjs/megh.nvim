" Megh templates indent like HTML; `:lua vim.lsp.buf.format()` also indents
" block directives (@if ... @endif).
if exists('b:did_indent') | finish | endif
runtime! indent/html.vim
