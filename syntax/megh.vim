" Megh templates (*.megh.html): HTML with Megh syntax on top, also inside
" attribute values, <script> and <style>.
if exists('b:current_syntax') | finish | endif

runtime! syntax/html.vim
unlet! b:current_syntax
" syntax/html.vim already includes JavaScript as @htmlJavaScript.

syn case match

" @name, not in emails (a@b.c) or after another @.
syn match meghDirective "\%(^\|[^[:alnum:]_@.]\)\@1<=@\h\w*" containedin=ALLBUT,meghComment,meghEcho,meghRaw,meghArgs,meghBlock

" @name(args) with JavaScript arguments.
syn region meghArgs matchgroup=meghDirective start="\%(^\|[^[:alnum:]_@.]\)\@1<=@\h\w*\s*(" end=")" keepend contains=@htmlJavaScript,meghParens containedin=ALLBUT,meghComment,meghEcho,meghRaw,meghArgs,meghBlock
syn region meghParens start="(" end=")" contained transparent contains=@htmlJavaScript,meghParens

" @js ... @endjs and @react(props) ... @endreact.
syn region meghBlock matchgroup=meghDirective start="\%(^\|[^[:alnum:]_@.]\)\@1<=@js\>\%(\s*(\)\@!" end="@endjs\>" keepend contains=@htmlJavaScript containedin=ALLBUT,meghComment,meghEcho,meghRaw,meghArgs,meghBlock
syn region meghBlock matchgroup=meghDirective start="\%(^\|[^[:alnum:]_@.]\)\@1<=@react\>" end="@endreact\>" keepend contains=@htmlJavaScript containedin=ALLBUT,meghComment,meghEcho,meghRaw,meghArgs,meghBlock

" {{ expr }} and {!! expr !!}.
syn region meghEcho matchgroup=meghDelimiter start="{{\%(--\)\@!" end="}}" keepend contains=@htmlJavaScript containedin=ALLBUT,meghComment,meghEcho,meghRaw,meghArgs,meghBlock
syn region meghRaw matchgroup=meghDelimiter start="{!!" end="!!}" keepend contains=@htmlJavaScript containedin=ALLBUT,meghComment,meghEcho,meghRaw,meghArgs,meghBlock

" {{-- comment --}}
syn region meghComment start="{{--" end="--}}" keepend contains=@Spell containedin=ALLBUT,meghComment,meghEcho,meghRaw,meghArgs,meghBlock

" @@name and @{{ print literally. Defined last so they win over the rules above.
syn match meghEscape "@@\h\w*\|@{{" containedin=ALLBUT,meghComment,meghEcho,meghRaw,meghArgs,meghBlock

hi def link meghDirective Keyword
hi def link meghDelimiter Delimiter
hi def link meghComment Comment
hi def link meghEscape Special

let b:current_syntax = 'megh'
