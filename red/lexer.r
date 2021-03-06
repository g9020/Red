REBOL [
	Title:   "Red Lexical Scanner"
	Author:  "Nenad Rakocevic"
	File: 	 %lexer.r
	Rights:  "Copyright (C) 2011 Nenad Rakocevic. All rights reserved."
	License: "BSD-3 - https://github.com/dockimbel/Red/blob/master/BSD-3-License.txt"
]

lexer: context [
	verbose: 0
	
	line: 	none									;-- source code lines counter
	lines:	[]										;-- offsets of newlines marker in current block
	count?: yes										;-- if TRUE, lines counter is enabled
	pos:	none									;-- source input position (error reporting)
	s:		none									;-- mark start position of new value
	e:		none									;-- mark end position of new value
	value:	none									;-- new value
	fail?:	none									;-- used for failing some parsing rules
	type:	none									;-- define the type of the new value
	
	;====== Parsing rules ======
	
	digit: charset "0123465798"
	hexa:  union digit charset "ABCDEF" 
	
	;-- UTF-8 encoding rules from: http://tools.ietf.org/html/rfc3629#section-4
	UTF-8-BOM: #{EFBBBF}
	ws-ASCII: charset " ^-^M"						;-- ASCII common whitespaces
	ws-U+2k: charset [#"^(80)" - #"^(8A)"]			;-- Unicode spaces in the U+2000-U+200A range
	
	UTF8-tail: charset [#"^(80)" - #"^(BF)"]
		
	UTF8-1: charset [#"^(00)" - #"^(7F)"]
	
	UTF8-2: reduce [
		charset [#"^(C2)" - #"^(DF)"]
		UTF8-tail
	]
	
	UTF8-3: reduce [
		#{E0} charset [#"^(A0)" - #"^(BF)"] UTF8-tail
		'| charset [#"^(E1)" - #"^(EC)"] 2 UTF8-tail
		'| #{ED} charset [#"^(80)" - #"^(9F)"] UTF8-tail
		'| charset [#"^(EE)" - #"^(EF)"] 2 UTF8-tail
	]
	
	UTF8-4: reduce [
		#{F0} charset [#"^(90)" - #"^(BF)"] 2 UTF8-tail
		'| charset [#"^(F1)" - #"^(F3)"] 3 UTF8-tail
		'| #{F4} charset [#"^(80)" - #"^(8F)"] 2 UTF8-tail
	]
	
	UTF8-char: [pos: UTF8-1 | UTF8-2 | UTF8-3 | UTF8-4]
	
	not-word-char:  charset {/\^^,'[](){}"#%$@:;}
	not-word-1st:	union not-word-char digit
	not-file-char:  charset {[](){}"%@:;}
	not-str-char:   #"^""
	not-mstr-char:  #"}"
	caret-char:	    charset [#"@" - #"_"]
	printable-char: charset [#"^(20)" - #"^(7E)"]
	char-char:		exclude printable-char charset {"^^}
	integer-end:	charset {^{"])}
	stop: 		    none
	
	control-char: reduce [
		charset [#"^(00)" - #"^(1F)"] 				;-- ASCII control characters
		'| #"^(C2)" charset [#"^(80)" - #"^(9F)"] 	;-- C2 control characters
	]
	
	UTF8-filtered-char: [
		[pos: stop :pos (fail?: [end skip]) | UTF8-char e: (fail?: none)]
		fail?
	]
	
	;-- Whitespaces list from: http://en.wikipedia.org/wiki/Whitespace_character
	ws: [
		pos: #"^/" (
			if count? [
				line: line + 1 
				append/only lines stack/tail?
			]
		)
		| ws-ASCII									;-- only the common whitespaces are matched
		| #{C2} [
			#{85}									;-- U+0085 (Newline)
			| #{A0}									;-- U+00A0 (No-break space)
		]
		| #{E1} [
			#{9A80}									;-- U+1680 (Ogham space mark)
			| #{A08E}								;-- U+180E (Mongolian vowel separator)
		]
		| #{E2} [
			#{80} [
				ws-U+2k								;-- U+2000-U+200A range
				| #{A8}								;-- U+2028 (Line separator)
				| #{A9}								;-- U+2029 (Paragraph separator)
				| #{AF}								;-- U+202F (Narrow no-break space)
			]
			| #{819F}								;-- U+205F (Medium mathematical space)
		]
		| #{E38080}									;-- U+3000 (Ideographic space)
	]
	
	newline-char: [
		#"^/"
		| #{C285}									;-- U+0085 (Newline)
		| #{E280} [
			#{A8}									;-- U+2028 (Line separator)
			| #{A9}									;-- U+2029 (Paragraph separator)
		]
	]
	
	counted-newline: [pos: #"^/" (line: line + 1)]
	
	ws-no-count: [(count?: no) ws (count?: yes)]
	
	any-ws: [pos: any ws]
	
	symbol-rule: [
		(stop: [not-word-char | ws-no-count | control-char])
		some UTF8-filtered-char e:
	]
	
	begin-symbol-rule: [							;-- 1st char in symbols is restricted
		(stop: [not-word-1st | ws-no-count | control-char])
		UTF8-filtered-char
		opt symbol-rule
	]
	
	path-rule: [some [slash [begin-symbol-rule | paren-rule]] e:]
	
	word-rule: 	[
		(type: word!) s: begin-symbol-rule 
		opt [path-rule (type: path!)] 
		opt [#":" (type: either type = word! [set-word!][set-path!])]
	]
	
	get-word-rule: [#":" (type: get-word!) s: begin-symbol-rule]
	
	lit-word-rule: [
		#"'" (type: lit-word!) s: begin-symbol-rule
		opt [path-rule (type: lit-path!)]
	]
	
	issue-rule: [#"#" (type: issue!) s: symbol-rule]
	
	refinement-rule: [slash (type: refinement!) s: symbol-rule]
	
	slash-rule: [s: [slash opt slash] e:]
		
	integer-rule: [
		(type: integer!)
		opt [#"-" | #"+"] digit any [digit | #"'" digit] e:
		pos: [										;-- protection rule from typo with sticky words
			[integer-end | ws-no-count | end] (fail?: none)
			| skip (fail?: [end skip]) 
		] :pos 
		fail?
	]
		
	block-rule: [#"[" (stack/push block!) any-value #"]" (value: stack/pop block!)]
	
	paren-rule: [#"(" (stack/push paren!) any-value	#")" (value: stack/pop paren!)]
	
	escaped-char: [
		"^^(" [
			s: [6 hexa | 4 hexa | 2 hexa] e: (		;-- Unicode values allowed up to 10FFFFh
				value: encode-UTF8-char s e
			)
			| [
				"null" 	 (value: #"^(00)")
				| "back" (value: #"^(08)")
				| "tab"  (value: #"^(09)")
				| "line" (value: #"^(0A)")
				| "page" (value: #"^(0C)")
				| "esc"  (value: #"^(1B)")
				| "del"	 (value: #"^(7F)")
			] 
		] #")"
		| #"^^" [
			s: caret-char (value: to char! s/1 - #"@") 
			| [
				#"/" 	(value: #"^/")
				| #"-"	(value: #"^-")
				| #"?" 	(value: #"^(del)")
			]
		]
	]
	
	char-rule: [
		{#"} (type: char! fail?: none) [
			s: char-char (value: to char! s/1)		;-- allowed UTF-1 chars
			| newline-char (fail?: [end skip])		;-- fail rule
			| copy value [UTF8-2 | UTF8-3 | UTF8-4]	;-- allowed Unicode chars
			| escaped-char
		] fail? {"}
	]
	
	line-string: [
		{"} s: (type: string! stop: [not-str-char | newline-char])
		any UTF8-filtered-char
		e: {"}
	]
	
	multiline-string: [
		#"{" s: (type: string! stop: not-mstr-char)
		any [counted-newline | "^^}" | UTF8-filtered-char]
		e: #"}"
	]
	
	string-rule: [line-string | multiline-string]
	
	binary-rule: [
		"#{" (type: binary!) 
		s: any [counted-newline | 2 hexa | ws-no-count | comment-rule]
		e: #"}"
	]
	
	file-rule: [
		#"%" (type: file! stop: [not-file-char | ws-no-count])
		s: some UTF8-filtered-char e:
	]
	
	escaped-rule: [
		"#[" any-ws [
			"none" 	  (value: none)
			| "true"  (value: true)
			| "false" (value: false)
			| s: [
				"none!" | "logic!" | "block!" | "integer!" | "word!" 
				| "set-word!" | "get-word!" | "lit-word!" | "refinement!"
				| "binary!" | "string!"	| "char!" | "bitset!" | "path!"
				| "set-path!" | "lit-path!" | "native!"	| "action!"
				| "issue!" | "paren!" | "function!"
			] e: (value: get to word! copy/part s e)
		]  any-ws #"]"
	]
	
	comment-rule: [#";" to #"^/"]
	
	multiline-comment-rule: [
		"comment" any-ws #"{" (stop: not-mstr-char) any [
			counted-newline | "^^}" | UTF8-filtered-char
		] #"}"
	]
	
	wrong-delimiters: [
		pos: [
			  #"]" (value: #"[") | #")" (value: #"(")
			| #"[" (value: #"]") | #"(" (value: #")")
		] :pos
		(throw-error/with ["missing matching" value])
	]

	literal-value: [
		pos: (e: none) s: [
			comment-rule
			| multiline-comment-rule
			| integer-rule	  (stack/push load-integer   copy/part s e)
			| word-rule		  (stack/push to type		 copy/part s e)
			| lit-word-rule	  (stack/push to type		 copy/part s e)
			| get-word-rule	  (stack/push to get-word!   copy/part s e)
			| refinement-rule (stack/push to refinement! copy/part s e)
			| slash-rule	  (stack/push to word! 	   	 copy/part s e)
			| issue-rule	  (stack/push to issue!	   	 copy/part s e)
			| file-rule		  (stack/push to file!		 copy/part s e)
			| char-rule		  (stack/push value)
			| block-rule	  (stack/push value)
			| paren-rule	  (stack/push value)
			| escaped-rule    (stack/push value)
			| string-rule	  (stack/push load-string s e)
			| binary-rule	  (stack/push load-binary s e)
		]
	]
	
	any-value: [pos: any [literal-value | ws]]

	header: [
		pos: thru "Red" any-ws block-rule (stack/push value)
		| (throw-error/with "Invalid Red program") end skip
	]

	program: [
		pos: opt UTF-8-BOM
		header
		any-value
		opt wrong-delimiters
	]
	
	;====== Helper functions ======
	
	stack: context [
		stk: []
		
		push: func [value][
			either any [value = block! value = paren!][		
				insert/only tail stk value: make value 1			
				value
			][
				insert/only tail last stk :value
			]
		]
		
		pop: func [type [datatype!]][
			if type <> type? last stk [
				throw-error/with ["invalid" mold type "closing delimiter"]
			]
			also last stk remove back tail stk
		]
		
		tail?: does [tail last stk]
		reset: does [clear stk]
	]
	
	throw-error: func [/with msg [string! block!]][
		print rejoin [
			"*** Syntax Error: " either with [
				uppercase/part reform msg 1
			][
				reform ["Invalid" mold type "value"]
			]
			"^/*** line: " line
			"^/*** at: " mold copy/part pos 40
		]
		halt
	]

	add-line-markers: func [blk [block!]][	
		foreach pos lines [new-line pos yes]
		clear lines
	]
	
	encode-UTF8-char: func [s [string!] e [string!] /local c code new][	
		c: trim/head debase/base copy/part s e 16
		code: to integer! c
		
		case [
			code <= 127  [new: to char! last c]		;-- c <= 7Fh
			code <= 2047 [							;-- c <= 07FFh
				new: copy #{0000}
				new/1: #"^(C0)"
					or (shift/left to integer! (either code <= 255 [0][c/1]) and 7 2)
					or shift/logical to integer! last c 6
				new/2: #"^(80)" or (63 and last c)
			]
			code <= 65535 [							;-- c <= FFFFh
				new: copy #{E00000}
				new/1: #"^(E0)" or shift/logical to integer! c/1 4
				new/2: #"^(80)" 
					or (shift/left to integer! c/1 and 15 2)
					or shift/logical to integer! c/2 6
				new/3: #"^(80)" or (c/2 and 63)
			]
			code <= 1114111 [						;-- c <= 10FFFFh
				new: copy #{F0000000}
				new/2: #"^(80)"
					or (shift/left to integer! c/1 and 3 4)
					or (shift/logical to integer! c/2 4)
				new/3: #"^(80)"
					or (shift/left to integer! c/2 and 15 2)
					or shift/logical to integer! c/3 6
				new/4: #"^(80)" or (c/3 and 63)
			]
			'else [
				throw-error/with "Codepoints above U+10FFFF are not supported"
			]
		]
		new
	]

	load-integer: func [s [string!]][
		unless attempt [s: to integer! s][throw-error]
		s
	]

	load-string: func [s [string!] e [string!] /local new][
		new: make string! offset? s e				;-- allocated size close to final size

		parse/all/case s [
			some [
				escaped-char (insert tail new value)
				| s: UTF8-filtered-char e: (		;-- already set to right filter	
					insert/part tail new s e
				)
			]										;-- exit on matching " or }
		]
		new
	]
	
	load-binary: func [s [string!] e [string!] /local new byte][
		new: make binary! (offset? s e) / 2			;-- allocated size above final size

		parse/all/case s [
			some [
				copy byte 2 hexa (insert tail new debase/base byte 16)
				| ws | comment-rule
				| #"}" end skip
			]
		]
		new
	]
	
	run: func [src [string! binary!] /local blk][
		line: 1
		count?: yes
		
		blk: stack/push block!						;-- root block

		unless parse/all/case src program [throw-error]
		
		add-line-markers blk
		stack/reset
		blk
	]
]