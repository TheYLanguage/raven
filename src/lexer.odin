package raven

import "core:fmt"
import "core:unicode/utf8"

Token_Type :: enum {
	EOF,
	Invalid,

	Pack,
	Mod,
	Import,
	Proc,
	Early,
	For,
	In,
	If,

	Identifier,
	Int_Literal,
	String_Literal,

	Colon,
	Semicolon,
	Assign,
	Colon_Assign,
	Plus,
	Arrow_Eq,
	LBrace,
	RBrace,
	LParen,
	RParen,
	Dot,
}

Token :: struct {
	type: Token_Type,
	text: string,
	line: int,
}

Lexer :: struct {
	source: string,
	offset: int,
	line:   int,
}

init_lexer :: proc(source: string) -> Lexer {
	return Lexer{source = source, offset = 0, line = 1}
}

peek_char :: proc(l: ^Lexer) -> rune {
	if l.offset >= len(l.source) {
		return 0
	}
	r, _ := utf8.decode_rune_in_string(l.source[l.offset:])
	return r
}

read_char :: proc(l: ^Lexer) -> rune {
	if l.offset >= len(l.source) {
		return 0
	}
	r, width := utf8.decode_rune_in_string(l.source[l.offset:])
	l.offset += width
	if r == '\n' {
		l.line += 1
	}
	return r
}

skip_whitespace :: proc(l: ^Lexer) {
	for l.offset < len(l.source) {
		ch := peek_char(l)
		if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
			read_char(l)
		} else if ch == '#' {
			for l.offset < len(l.source) && peek_char(l) != '\n' {
				read_char(l)
			}
		} else {
			break
		}
	}
}

is_alpha :: proc(ch: rune) -> bool {
	return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_'
}

is_digit :: proc(ch: rune) -> bool {
	return ch >= '0' && ch <= '9'
}

next_token :: proc(l: ^Lexer) -> Token {
	skip_whitespace(l)

	if l.offset >= len(l.source) {
		return Token{type = .EOF, text = "", line = l.line}
	}

	start_line := l.line
	ch := read_char(l)

	if is_alpha(ch) {
		start := l.offset - utf8.rune_size(ch)
		for l.offset < len(l.source) && (is_alpha(peek_char(l)) || is_digit(peek_char(l))) {
			read_char(l)
		}
		text := l.source[start:l.offset]
		
		switch text {
		case "pack":
			return Token{type = .Pack, text = text, line = start_line}
		case "mod":
			return Token{type = .Mod, text = text, line = start_line}
		case "import":
			return Token{type = .Import, text = text, line = start_line}
		case "proc":
			return Token{type = .Proc, text = text, line = start_line}
		case "early":
			return Token{type = .Early, text = text, line = start_line}
		case "for":
			return Token{type = .For, text = text, line = start_line}
		case "in":
			return Token{type = .In, text = text, line = start_line}
		case "if":
			return Token{type = .If, text = text, line = start_line}
		}
		return Token{type = .Identifier, text = text, line = start_line}
	}

	if is_digit(ch) {
		start := l.offset - utf8.rune_size(ch)
		for l.offset < len(l.source) && is_digit(peek_char(l)) {
			read_char(l)
		}
		return Token{type = .Int_Literal, text = l.source[start:l.offset], line = start_line}
	}

	if ch == '"' {
		start := l.offset
		for l.offset < len(l.source) && peek_char(l) != '"' {
			read_char(l)
		}
		text := l.source[start:l.offset]
		if l.offset < len(l.source) {
			read_char(l)
		}
		return Token{type = .String_Literal, text = text, line = start_line}
	}

	switch ch {
	case ':':
		if peek_char(l) == '=' {
			read_char(l)
			return Token{type = .Colon_Assign, text = ":=", line = start_line}
		}
		return Token{type = .Colon, text = ":", line = start_line}
	case ';':
		return Token{type = .Semicolon, text = ";", line = start_line}
	case '=':
		return Token{type = .Assign, text = "=", line = start_line}
	case '+':
		return Token{type = .Plus, text = "+", line = start_line}
	case '{':
		return Token{type = .LBrace, text = "{", line = start_line}
	case '}':
		return Token{type = .RBrace, text = "}", line = start_line}
	case '(':
		return Token{type = .LParen, text = "(", line = start_line}
	case ')':
		return Token{type = .RParen, text = ")", line = start_line}
	case '.':
		return Token{type = .Dot, text = ".", line = start_line}
	case '-':
		if peek_char(l) == '>' {
			read_char(l)
			skip_whitespace(l)
			if peek_char(l) == '=' {
				read_char(l)
				return Token{type = .Arrow_Eq, text = "-> =", line = start_line}
			}
		}
	}

	return Token{type = .Invalid, text = utf8.runes_to_string([]rune{ch}), line = start_line}
}