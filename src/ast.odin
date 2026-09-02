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
}

Program_Node :: struct {
	pack_name: string,
	mod_name:  string,
	imports:   [dynamic]string,
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