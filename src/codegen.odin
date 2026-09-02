package raven

import "core:fmt"
import "core:os"
import "core:strconv"

ELF_HEADER_SIZE :: 64
PHDR_SIZE       :: 56
BASE_ADDR       :: 0x400000

Codegen :: struct {
	code:              [dynamic]u8,
	data_sec:          [dynamic]u8,
	string_map:        map[string]u64,
	stack_offsets:     map[string]i32,
	curr_stack_offset: i32,
}

init_codegen :: proc() -> Codegen {
	return Codegen{
		code = make([dynamic]u8),
		data_sec = make([dynamic]u8),
		string_map = make(map[string]u64),
		stack_offsets = make(map[string]i32),
		curr_stack_offset = -8,
	}
}

emit_byte :: proc(cg: ^Codegen, byte: u8) {
	append(&cg.code, byte)
}

emit_bytes :: proc(cg: ^Codegen, bytes: []u8) {
	for b in bytes {
		append(&cg.code, b)
	}
}

emit_u16 :: proc(cg: ^Codegen, val: u16) {
	emit_byte(cg, u8(val & 0xFF))
	emit_byte(cg, u8((val >> 8) & 0xFF))
}

emit_u32 :: proc(cg: ^Codegen, val: u32) {
	for i in 0..<4 {
		emit_byte(cg, u8((val >> uint(i * 8)) & 0xFF))
	}
}

emit_u64 :: proc(cg: ^Codegen, val: u64) {
	for i in 0..<8 {
		emit_byte(cg, u8((val >> uint(i * 8)) & 0xFF))
	}
}

add_string_literal :: proc(cg: ^Codegen, str_val: string) -> u64 {
	if addr, exists := cg.string_map[str_val]; exists {
		return addr
	}

	offset := u64(len(cg.data_sec))
	for i in 0..<len(str_val) {
		append(&cg.data_sec, str_val[i])
	}
	append(&cg.data_sec, '\n')

	cg.string_map[str_val] = offset
	return offset
}

emit_sys_write :: proc(cg: ^Codegen, str_addr: u64, str_len: u64) {
	emit_bytes(cg, []u8{0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00}) // mov rax, 1
	emit_bytes(cg, []u8{0x48, 0xC7, 0xC7, 0x01, 0x00, 0x00, 0x00}) // mov rdi, 1
	emit_bytes(cg, []u8{0x48, 0xBE})                               // mov rsi, imm64
	emit_u64(cg, str_addr)
	emit_bytes(cg, []u8{0x48, 0xBA})                               // mov rdx, imm64
	emit_u64(cg, str_len)
	emit_bytes(cg, []u8{0x0F, 0x05})                               // syscall
}

emit_prologue :: proc(cg: ^Codegen) {
	emit_bytes(cg, []u8{0x55, 0x48, 0x89, 0xE5})                  // push rbp; mov rbp, rsp
	emit_bytes(cg, []u8{0x48, 0x81, 0xEC, 0x00, 0x01, 0x00, 0x00}) // sub rsp, 256
}

emit_epilogue :: proc(cg: ^Codegen) {
	emit_bytes(cg, []u8{0x48, 0x89, 0xEC, 0x5D})                  // mov rsp, rbp; pop rbp
	emit_bytes(cg, []u8{
		0x48, 0x31, 0xFF,                                           // xor rdi, rdi
		0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,                   // mov rax, 60 (sys_exit)
		0x0F, 0x05,                                                 // syscall
	})
}

compile_ast :: proc(cg: ^Codegen, node: AST_Node) {
	#partial switch n in node.derived {
	case ^Program_Node:
		for decl in n.decls {
			compile_ast(cg, decl)
		}
	case ^Proc_Decl_Node:
		emit_prologue(cg)
		compile_ast(cg, n.body)
		emit_epilogue(cg)
	case ^Block_Node:
		for stmt in n.stmts {
			compile_ast(cg, stmt)
		}
	case ^Var_Decl_Node:
		compile_ast(cg, n.value)
		offset := cg.curr_stack_offset
		cg.stack_offsets[n.name] = offset
		cg.curr_stack_offset -= 8

		// mov [rbp + offset], rax
		emit_bytes(cg, []u8{0x48, 0x89, 0x85})
		emit_u32(cg, u32(offset))

	case ^Binary_Expr_Node:
		// Evaluate right side and store temporarily on stack
		compile_ast(cg, n.right)
		emit_bytes(cg, []u8{0x50}) // push rax

		// Evaluate left side into rax
		compile_ast(cg, n.left)
		emit_bytes(cg, []u8{0x5B}) // pop rbx

		// Execute arithmetic operation (rax = left, rbx = right)
		switch n.op {
		case "+":
			// add rax, rbx
			emit_bytes(cg, []u8{0x48, 0x01, 0xC8})
		case "-":
			// sub rax, rbx
			emit_bytes(cg, []u8{0x48, 0x29, 0xC8})
		case "*":
			// imul rax, rbx
			emit_bytes(cg, []u8{0x48, 0x0F, 0xAF, 0xC3})
		case "/":
			// cqo (sign extend rax into rdx:rax)
			emit_bytes(cg, []u8{0x48, 0x99})
			// idiv rbx
			emit_bytes(cg, []u8{0x48, 0xF7, 0xF3})
		}

	case ^For_Infinite_Node:
		loop_start := len(cg.code)
		compile_ast(cg, n.body)

		rel_back := i32(loop_start - (len(cg.code) + 5))
		emit_bytes(cg, []u8{0xE9})
		emit_u32(cg, u32(rel_back))

	case ^If_Stmt_Node:
		compile_ast(cg, n.condition)

		emit_bytes(cg, []u8{0x48, 0x85, 0xC0}) // test rax, rax
		emit_bytes(cg, []u8{0x0F, 0x84, 0x00, 0x00, 0x00, 0x00}) // jz target
		jump_out_patch := len(cg.code) - 4

		compile_ast(cg, n.body)

		after_body := len(cg.code)
		rel_out := i32(after_body - (jump_out_patch + 4))

		cg.code[jump_out_patch]     = u8(rel_out & 0xFF)
		cg.code[jump_out_patch + 1] = u8((rel_out >> 8) & 0xFF)
		cg.code[jump_out_patch + 2] = u8((rel_out >> 16) & 0xFF)
		cg.code[jump_out_patch + 3] = u8((rel_out >> 24) & 0xFF)

	case ^For_Range_Node:
		compile_ast(cg, n.start)
		loop_var_offset := cg.curr_stack_offset
		cg.stack_offsets[n.var_name] = loop_var_offset
		cg.curr_stack_offset -= 8

		emit_bytes(cg, []u8{0x48, 0x89, 0x85})
		emit_u32(cg, u32(loop_var_offset))

		compile_ast(cg, n.end)
		end_var_offset := cg.curr_stack_offset
		cg.curr_stack_offset -= 8

		emit_bytes(cg, []u8{0x48, 0x89, 0x85})
		emit_u32(cg, u32(end_var_offset))

		loop_start := len(cg.code)

		emit_bytes(cg, []u8{0x48, 0x8B, 0x85})
		emit_u32(cg, u32(loop_var_offset))
		emit_bytes(cg, []u8{0x48, 0x3B, 0x85})
		emit_u32(cg, u32(end_var_offset))

		emit_bytes(cg, []u8{0x0F, 0x8F, 0x00, 0x00, 0x00, 0x00})
		jump_out_patch := len(cg.code) - 4

		compile_ast(cg, n.body)

		emit_bytes(cg, []u8{0x48, 0x8B, 0x85})
		emit_u32(cg, u32(loop_var_offset))
		emit_bytes(cg, []u8{0x48, 0xFF, 0xC0})
		emit_bytes(cg, []u8{0x48, 0x89, 0x85})
		emit_u32(cg, u32(loop_var_offset))

		rel_back := i32(loop_start - (len(cg.code) + 5))
		emit_bytes(cg, []u8{0xE9})
		emit_u32(cg, u32(rel_back))

		loop_end := len(cg.code)
		rel_out := i32(loop_end - (jump_out_patch + 4))

		cg.code[jump_out_patch]     = u8(rel_out & 0xFF)
		cg.code[jump_out_patch + 1] = u8((rel_out >> 8) & 0xFF)
		cg.code[jump_out_patch + 2] = u8((rel_out >> 16) & 0xFF)
		cg.code[jump_out_patch + 3] = u8((rel_out >> 24) & 0xFF)

	case ^Literal_Node:
		if n.value == "true" {
			emit_bytes(cg, []u8{0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00})
		} else if n.value == "false" {
			emit_bytes(cg, []u8{0x48, 0xC7, 0xC0, 0x00, 0x00, 0x00, 0x00})
		} else if offset, is_var := cg.stack_offsets[n.value]; is_var {
			// mov rax, [rbp + offset]
			emit_bytes(cg, []u8{0x48, 0x8B, 0x85})
			emit_u32(cg, u32(offset))
		} else if val, ok := strconv.parse_int(n.value, 10); ok {
			// mov rax, imm32
			emit_bytes(cg, []u8{0x48, 0xC7, 0xC0})
			emit_u32(cg, u32(val))
		} else if len(n.value) >= 12 && n.value[0:12] == "fmt.println(" {
			raw_str := n.value[13:len(n.value)-2]
			offset := add_string_literal(cg, raw_str)

			code_offset := u64(ELF_HEADER_SIZE + PHDR_SIZE)
			str_addr := BASE_ADDR + code_offset + u64(len(cg.code)) + offset

			emit_sys_write(cg, str_addr, u64(len(raw_str) + 1))
		} else {
			emit_bytes(cg, []u8{0x48, 0xC7, 0xC0, 0x00, 0x00, 0x00, 0x00})
		}
	}
}

emit_elf_header :: proc(cg: ^Codegen, code_size: u64, data_size: u64) {
	emit_bytes(cg, []u8{0x7F, 'E', 'L', 'F'})
	emit_byte(cg, 2)
	emit_byte(cg, 1)
	emit_byte(cg, 1)
	emit_byte(cg, 0)

	for _ in 0..<8 {
		emit_byte(cg, 0)
	}

	entry_point := u64(BASE_ADDR + ELF_HEADER_SIZE + PHDR_SIZE)

	emit_u16(cg, 2)
	emit_u16(cg, 0x3E)
	emit_u32(cg, 1)
	emit_u64(cg, entry_point)
	emit_u64(cg, u64(ELF_HEADER_SIZE))
	emit_u64(cg, 0)
	emit_u32(cg, 0)
	emit_u16(cg, u16(ELF_HEADER_SIZE))
	emit_u16(cg, u16(PHDR_SIZE))
	emit_u16(cg, 1)
	emit_u16(cg, 0)
	emit_u16(cg, 0)
	emit_u16(cg, 0)

	file_size := u64(ELF_HEADER_SIZE + PHDR_SIZE) + code_size + data_size

	emit_u32(cg, 1)
	emit_u32(cg, 7)
	emit_u64(cg, 0)
	emit_u64(cg, BASE_ADDR)
	emit_u64(cg, BASE_ADDR)
	emit_u64(cg, file_size)
	emit_u64(cg, file_size)
	emit_u64(cg, 0x1000)
}

write_executable :: proc(cg: ^Codegen, output_path: string) -> bool {
	raw_code := cg.code
	raw_data := cg.data_sec
	cg.code = make([dynamic]u8)

	emit_elf_header(cg, u64(len(raw_code)), u64(len(raw_data)))
	emit_bytes(cg, raw_code[:])
	emit_bytes(cg, raw_data[:])

	ok := os.write_entire_file(output_path, cg.code[:])
	return ok
}
