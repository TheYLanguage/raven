package raven

import "core:fmt"
import "core:os"

Parser :: struct {
	lexer:    Lexer,
	curr_tok: Token,
}

init_parser :: proc(source: string) -> Parser {
	p := Parser{lexer = init_lexer(source)}
	p.curr_tok = next_token(&p.lexer)
	return p
}

advance :: proc(p: ^Parser) {
	p.curr_tok = next_token(&p.lexer)
}

expect :: proc(p: ^Parser, type: Token_Type) -> bool {
	if p.curr_tok.type == type {
		advance(p)
		return true
	}
	fmt.printf("Syntax Error on line %d: Expected %v, got %v (%s)\n", p.curr_tok.line, type, p.curr_tok.type, p.curr_tok.text)
	return false
}

parse_expression :: proc(p: ^Parser) -> AST_Node {
	left := parse_primary_expression(p)

	if p.curr_tok.type == .Plus {
		op_text := p.curr_tok.text
		advance(p)
		right := parse_expression(p)
		
		bin_expr := new(Binary_Expr_Node)
		bin_expr.op = op_text
		bin_expr.left = left
		bin_expr.right = right

		node := AST_Node{derived = bin_expr, line = p.curr_tok.line}
		return node
	}

	return left
}

parse_primary_expression :: proc(p: ^Parser) -> AST_Node {
	tok := p.curr_tok

	switch tok.type {
	case .Identifier:
		advance(p)
		if p.curr_tok.type == .Dot {
			advance(p)
			member := p.curr_tok.text
			expect(p, .Identifier)
			expect(p, .LParen)
			
			arg := parse_expression(p)
			expect(p, .RParen)

			lit := new(Literal_Node)
			lit.value = fmt.tprintf("%s.%s(%v)", tok.text, member, arg)
			return AST_Node{derived = lit, line = tok.line}
		}
		lit := new(Literal_Node)
		lit.value = tok.text
		return AST_Node{derived = lit, line = tok.line}

	case .Int_Literal, .String_Literal:
		advance(p)
		lit := new(Literal_Node)
		lit.value = tok.text
		return AST_Node{derived = lit, line = tok.line}

	case:
		advance(p)
		lit := new(Literal_Node)
		lit.value = "invalid"
		return AST_Node{derived = lit, line = tok.line}
	}
}

parse_statement :: proc(p: ^Parser) -> AST_Node {
	if p.curr_tok.type == .Early || p.curr_tok.type == .Identifier {
		is_early := false
		if p.curr_tok.type == .Early {
			is_early = true
			advance(p)
		}

		name := p.curr_tok.text
		advance(p)

		if p.curr_tok.type == .Colon_Assign {
			advance(p)
			val := parse_expression(p)
			expect(p, .Semicolon)

			var_decl := new(Var_Decl_Node)
			var_decl.name = name
			var_decl.is_early = is_early
			var_decl.value = val
			return AST_Node{derived = var_decl, line = p.curr_tok.line}
		}
	}

	expr := parse_expression(p)
	if p.curr_tok.type == .Semicolon {
		advance(p)
	}
	return expr
}

parse_block :: proc(p: ^Parser) -> AST_Node {
	expect(p, .LBrace)
	block := new(Block_Node)

	for p.curr_tok.type != .RBrace && p.curr_tok.type != .EOF {
		stmt := parse_statement(p)
		append(&block.stmts, stmt)
	}

	expect(p, .RBrace)
	return AST_Node{derived = block, line = p.curr_tok.line}
}

parse_program :: proc(p: ^Parser) -> AST_Node {
	prog := new(Program_Node)

	if p.curr_tok.type == .Pack {
		advance(p)
		prog.pack_name = p.curr_tok.text
		expect(p, .Identifier)
		expect(p, .Semicolon)
	}

	if p.curr_tok.type == .Mod {
		advance(p)
		prog.mod_name = p.curr_tok.text
		expect(p, .Identifier)
		expect(p, .Semicolon)
	}

	for p.curr_tok.type == .Import {
		advance(p)
		append(&prog.imports, p.curr_tok.text)
		expect(p, .String_Literal)
		expect(p, .Semicolon)
	}

	for p.curr_tok.type != .EOF {
		if p.curr_tok.type == .Proc {
			advance(p)
			expect(p, .Colon)
			proc_name := p.curr_tok.text
			expect(p, .Identifier)
			expect(p, .LParen)
			expect(p, .RParen)

			body := parse_block(p)

			proc_decl := new(Proc_Decl_Node)
			proc_decl.name = proc_name
			proc_decl.body = body

			append(&prog.decls, AST_Node{derived = proc_decl, line = p.curr_tok.line})
		} else {
			stmt := parse_statement(p)
			append(&prog.decls, stmt)
		}
	}

	return AST_Node{derived = prog, line = p.curr_tok.line}
}