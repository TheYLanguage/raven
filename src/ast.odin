package raven

AST_Node :: struct {
	derived: AST_Node_Data,
	line:    int,
}

AST_Node_Data :: union {
	^Program_Node,
	^Var_Decl_Node,
	^Proc_Decl_Node,
	^Block_Node,
	^Binary_Expr_Node,
	^Literal_Node,
	^For_Range_Node,
	^For_Infinite_Node,
	^If_Stmt_Node,
	^Import_Node,
}

Import_Node :: struct {
	path: string,
	node: AST_Node,
}

Program_Node :: struct {
	pack_name: string,
	mod_name:  string,
	imports:   [dynamic]AST_Node,
	decls:     [dynamic]AST_Node,
}

Var_Decl_Node :: struct {
	name:     string,
	is_early: bool,
	value:    AST_Node,
}

Proc_Decl_Node :: struct {
	name: string,
	body: AST_Node,
}

Block_Node :: struct {
	stmts: [dynamic]AST_Node,
}

Binary_Expr_Node :: struct {
	op:    string,
	left:  AST_Node,
	right: AST_Node,
}

Literal_Node :: struct {
	value: string,
}

For_Range_Node :: struct {
	var_name: string,
	start:    AST_Node,
	end:      AST_Node,
	body:     AST_Node,
}

For_Infinite_Node :: struct {
	body: AST_Node,
}

If_Stmt_Node :: struct {
	condition: AST_Node,
	body:      AST_Node,
}