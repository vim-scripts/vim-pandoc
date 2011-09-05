"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" ftplugin/functions.vim
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" 1. Pandoc commands
" ===================================================================
python<<EOF
import vim
import sys
import re, string
from os.path import exists
from subprocess import Popen, PIPE

# platform dependent variables
if sys.platform == "darwin":
	open_command = "open" #OSX
elif sys.platform.startswith("linux"):
	open_command = "xdg-open" # freedesktop/linux
elif sys.platform.startswith("win"):
	open_command = 'cmd /x \"start' # Windows

# we might use this for adjusting paths
if sys.platform.startswith("win"):
	vim.command('let g:paths_style = "win"')
	vim.command('let g:paths_sep = "\\"')
else:
	vim.command('let g:paths_style = "posix"')
	vim.command('let g:paths_sep = "/"')

# On windows, we pass commands as an argument to `start`, which is a cmd.exe builtin, so we have to quote it
if sys.platform.startswith("win"):
	open_command_tail = '"'
else:
	open_command_tail = ''

def pandoc_open_uri():
	line = vim.current.line
	pos = vim.current.window.cursor[1] - 1
	url = ""
	
	# graciously taken from
	# http://stackoverflow.com/questions/1986059/grubers-url-regular-expression-in-python/1986151#1986151
	pat = r'\b(([\w-]+://?|www[.])[^\s()<>]+(?:\([\w\d]+\)|([^%s\s]|/)))'
	pat = pat % re.escape(string.punctuation)
	for match in re.finditer(pat, line):
		if match.start() - 1 <= pos and match.end() - 2 >= pos:
			url = match.group()
			break
	if url != '':
		Popen([open_command, url + open_command_tail], stdout=PIPE, stderr=PIPE)
		print url
	else:
		print "No URI found."

def pandoc_get_reflabel():
	pos = vim.current.window.cursor
	current_line = vim.current.line
	cursor_idx = pos[1] - 1
	label = None
	ref = None
	
	# we first search for explicit and non empty implicit refs
	label_regex = "\[.*\]"
	for label_found in re.finditer(label_regex, current_line):
		if label_found.start() -1 <= cursor_idx and label_found.end() - 2 >= cursor_idx:
			label = label_found.group()
			if re.match("\[.*?\]\[.*?]", label):
				if ref == '':
					ref = label.split("][")[0][1:]
				else:
					ref = label.split("][")[1][:-1]
				label = "[" + ref  + "]"
				break
	
	# we now search for empty implicit refs or footnotes
	if not ref:
		label_regex = "\[.*?\]"
		for label_found in re.finditer(label_regex, current_line):
			if label_found.start() - 1 <= cursor_idx and label_found.end() - 2 >= cursor_idx:
				label = label_found.group()
				break

	return label

def pandoc_go_to_ref():
	ref_label = pandoc_get_reflabel()
	if ref_label:
		ref = ref_label[1:-1]
		# we build a list of the labels and their position in the file
		labels = {}
		lineno = 0
		for line in vim.current.buffer:
			match = re.match("^\s?\[.*(?=]:)", line)
			lineno += 1
			if match:
				labels[match.group()[1:]] = lineno

		if labels.has_key(ref):
			vim.command(str(labels[ref]))

def pandoc_go_back_from_ref():
	label_regex = ''
	
	match = re.match("^\s?\[.*](?=:)", vim.current.line)
	if match:
		label_regex = match.group().replace("[", "\[").replace("]", "\]").replace("^", "\^")
	else:
		label = pandoc_get_reflabel()
		if label:
			label_regex = label.replace("[", "\[").replace("]", "\]").replace("^", "\^")
	
	if label_regex != '':
		found = False
		lineno = vim.current.window.cursor[0]
		for line in reversed(vim.current.buffer[:lineno-1]):
			lineno = lineno - 1
			matches_in_this_line = list(re.finditer(label_regex, line))
			for ref in reversed(matches_in_this_line):
				vim.command(str(lineno) + " normal" + str(ref.start()) + "l")
				found = True
				break
			if found:
				break

def pandoc_execute(command, open_when_done=True):
	command = command.split()
	
	# first, we evaluate the output extension
	if command[0] == "markdown2pdf": # always outputs pdfs
		out_extension = "pdf"
	else:
		try:
			out_extension = command[command.index("-t") + 1]
		except ValueError:
			out_extension = "html"
	out = vim.eval('expand("%:r")') + "." + out_extension
	command.extend(["-o", out])
	command.append(vim.current.buffer.name)

	# we evaluate global vim variables. This way, we can register commands that 
	# pass the value of our variables (e.g, g:pandoc_bibfile).
	for value in command:
		if value.startswith("g:"):
			vim_value = vim.eval(value)
			if vim_value == "":
				if command[command.index(value) - 1] == "--bibliography":
					command.remove(command[command.index(value) - 1])
					command.remove(value)
				else:
					command[command.index(value)] = vim_value
			else:
				command[command.index(value)] = vim_value


	# we run pandoc with our arguments
	output = Popen(command, stdout=PIPE, stderr=PIPE).communicate()

	# we create a temporary buffer where the command and its output will be shown
	
	# this builds a list of lines we are going to write to the buffer
	lines = [">> " + line for line in "\n".join(output).split("\n") if line != '']
	lines.insert(0, "▶ " + " ".join(command))
	lines.insert(0, "# Press <Esc> to close this ")

	# we always splitbelow
	splitbelow = bool(int(vim.eval("&splitbelow")))
	if not splitbelow:
		vim.command("set splitbelow")
	
	vim.command("3new")
	vim.current.buffer.append(lines)
	vim.command("normal dd")
	vim.command("setlocal nomodified")
	vim.command("setlocal nomodifiable")
	# pressing <esc> on the buffer will delete it
	vim.command("map <buffer> <esc> :bd<cr>")
	# we will highlight some elements in the buffer
	vim.command("syn match PandocOutputMarks /^>>/")
	vim.command("syn match PandocCommand /^▶.*$/hs=s+1")
	vim.command("syn match PandocInstructions /^#.*$/")
	vim.command("hi! link PandocOutputMarks Operator")
	vim.command("hi! link PandocCommand Statement")
	vim.command("hi! link PandocInstructions Comment")

	# we revert splitbelow to its original value
	if not splitbelow:
		vim.command("set nosplitbelow")

	# finally, we open the created file
	if exists(out) and open_when_done:
		Popen([open_command, out + open_command_tail], stdout=PIPE, stderr=PIPE)

# We register openers with PandocRegisterExecutor. 
# We take its first argument as the name of a vim ex command, the second
# argument as a mapping, the third argument as a flag determing whether to
# open the resulting file,  and the rest as the description of a command,
# which we'll pass to pandoc_open.

# pandoc_register_opener(...) adds a tuple of those elements to a list of openers. This list will be 
# read from by ftplugin/pandoc.vim and commands and mappings will be created from it.
pandoc_executors = []
def pandoc_register_executor(com_ref):
	args = com_ref.split()
	name = args[0]
	mapping = args[1]
	open_when_done = args[2]
	command = args[3:]
	pandoc_executors.append((name, mapping, open_when_done, " ".join(command)))
EOF

command! -nargs=? PandocRegisterExecutor exec 'py pandoc_register_executor("<args>")'

" We register here some default executors. The user can define other custom
" commands in his .vimrc.
"
" Generate html and open in default html viewer
PandocRegisterExecutor PandocHtmlOpen <LocalLeader>html 1 pandoc -t html -Ss
" Generate pdf w/ citeproc and open in default pdf viewer
PandocRegisterExecutor PandocPdfOpen <LocalLeader>pdf 1 markdown2pdf --bibliography g:pandoc_bibfile
" Generate odt w/ citeproc and open in default odt viewer
PandocRegisterExecutor PandocOdtOpen <LocalLeader>odt 1 pandoc -t odt --bibliography g:pandoc_bibfile

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" 2. Folding
" ===============================================================================
"
" Taken from
" http://stackoverflow.com/questions/3828606/vim-markdown-folding/4677454#4677454
"
function! MarkdownLevel()
    if getline(v:lnum) =~ '^# .*$'
        return ">1"
    endif
    if getline(v:lnum) =~ '^## .*$'
        return ">2"
    endif
    if getline(v:lnum) =~ '^### .*$'
        return ">3"
    endif
    if getline(v:lnum) =~ '^#### .*$'
        return ">4"
    endif
    if getline(v:lnum) =~ '^##### .*$'
        return ">5"
    endif
    if getline(v:lnum) =~ '^###### .*$'
        return ">6"
    endif
	if getline(v:lnum) =~ '^[^-=].\+$' && getline(v:lnum+1) =~ '^=\+$'
		return ">1"
	endif
	if getline(v:lnum) =~ '^[^-=].\+$' && getline(v:lnum+1) =~ '^-\+$'
		return ">2"
	endif
    return "="
endfunction

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" # Save folding between sessions
" 
" FM: I recommend `viewoptions` set to "folds,cursor" only. 
"  
if !exists("g:pandoc_no_folding") || !g:pandoc_no_folding
	autocmd BufWinLeave * if expand(&filetype) == "pandoc" | mkview | endif
	autocmd BufWinEnter * if expand(&filetype) == "pandoc" | loadview | endif
endif

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" 3. Completion
" =============================================================================
"
let s:completion_type = ''

function! Pandoc_Find_Bibfile()
	if !exists('g:pandoc_bibfile')
		" A list of supported bibliographic database extensions, in reverse
		" order of priority:
		let bib_extensions = [ 'json', 'ris', 'mods', 'biblatex', 'bib' ]

		" Build up a list of paths to search, in reverse order of priority:
		"
		" First look for a file with the same basename as current file
		let bib_paths = [ expand("%:p:r") ]
		" Next look for a file with basename `default` in the same 
		" directory as current file
		let bib_paths = [ expand("%:p:h") . g:paths_sep ."default" ] + bib_paths
		" Next look for a file with basename `default` in the pandoc
		" data directory
		if eval("g:paths_style") == "posix"
			let bib_paths = [ $HOME . '/.pandoc/default' ] + bib_paths
		else
			let bib_paths = [ %APPDATA% . '\pandoc\default' ] + bib_paths
		endif
		" Next look in the local texmf directory
		if executable('kpsewhich')
			let local_texmf = system("kpsewhich -var-value TEXMFHOME")
			let local_texmf = local_texmf[:-2]
			let bib_paths = [ local_texmf . g:paths_sep . 'default' ] + bib_paths
		endif
		" Now search for the file!
		let g:pandoc_bibfile = ""
		for bib_path in bib_paths
			for bib_extension in bib_extensions
				if filereadable(bib_path . "." . bib_extension)
					let g:pandoc_bibfile = bib_path . "." . bib_extension
					let g:pandoc_bibtype = bib_extension
				endif
			endfor
		endfor
	else
	    let g:pandoc_bibtype = matchstr(g:pandoc_bibfile, '\zs\.[^\.]*')
	endif
endfunction

function! Pandoc_Complete(findstart, base)
	if a:findstart
		" return the starting position of the word
		let line = getline('.')
		let pos = col('.') - 1
		while pos > 0 && line[pos - 1] !~ '\\\|{\|\[\|<\|\s\|@\|\^'
			let pos -= 1
		endwhile

		let line_start = line[:pos-1]
		if line_start =~ '.*@$'
			let s:completion_type = 'bib'
		endif
		return pos
	else
		"return suggestions in an array
		let suggestions = []
		if s:completion_type == 'bib'
			" suggest BibTeX entries
			let suggestions = Pandoc_BibKey(a:base)
		endif
		return suggestions
	endif
endfunction

function! Pandoc_BibKey(partkey) 
ruby << EOL
	bib = VIM::evaluate('g:pandoc_bibfile')
	bibtype = VIM::evaluate('g:pandoc_bibtype').downcase!
	string = VIM::evaluate('a:partkey')

	File.open(bib) { |file|
		text = file.read
		if bibtype == 'mods'
			# match mods keys
			keys = text.scan(/<mods ID=\"(#{string}.*?)\">/i)
		elsif bibtype == 'ris'
			# match RIS keys
			keys = text.scan(/^ID\s+-\s+(#{string}.*)$/i)
		elsif bibtype == 'json'
			# match JSON CSL keys
			keys = text.scan(/\"id\":\s+\"(#{string}.*?)\"/i)
		else
			# match bibtex keys
			keys = text.scan(/@.*?\{[\s]*(#{string}.*?),/i)
		end
		keys.flatten!
		keys.uniq!
		keys.sort!
		keystring = keys.inspect
		VIM::command('return ' + keystring )
	}
EOL
endfunction

" Used for setting g:SuperTabCompletionContexts
function! PandocContext()
	" return the starting position of the word
	let line = getline('.')
	let pos = col('.') - 1
	while pos > 0 && line[pos - 1] !~ '\\\|{\|\[\|<\|\s\|@\|\^'
		let pos -= 1
	endwhile
	if line[pos - 1] == "@"
		return "\<c-x>\<c-o>"
	endif
endfunction

