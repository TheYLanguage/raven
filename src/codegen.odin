package raven

import "core:fmt"
import "core:os"

ELF_HEADER_SIZE :: 64
PHDR_SIZE       :: 56
BASE_ADDR       :: 0x400000

Codegen :: struct {
	code:      [dynamic]u8,
	data_sec:  [dynamic]u8,
	string_map: map[string]u64,
}

init_codegen :: proc() -> Codegen {
	return Codegen{
		code = make([dynamic]u8),
		data_sec = make([dynamic]u8),
		string_map = make(map[string]u64),
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
	// mov rax, 1 (sys_write)
	emit_bytes(cg, []u8{0x48, 0xC7, 0xC0, 0x01, 0x00, 0x00, 0x00})
	
	// mov rdi, 1 (stdout)
	emit_bytes(cg, []u8{0x48, 0xC7, 0xC7, 0x01, 0x00, 0x00, 0x00})
	
	// mov rsi, str_addr
	emit_bytes(cg, []u8{0x48, 0xBE})
	emit_u64(cg, str_addr)

	// mov rdx, str_len
	emit_bytes(cg, []u8{0x48, 0xBA})
	emit_u64(cg, str_len)

	// syscall
	emit_bytes(cg, []u8{0x0F, 0x05})
}

emit_prologue :: proc(cg: ^Codegen) {
	emit_bytes(cg, []u8{0x55, 0x48, 0x89, 0xE5})
}

emit_epilogue :: proc(cg: ^Codegen) {
	// sys_exit(0)
	emit_bytes(cg, []u8{
		0x48, 0x31, 0xFF,
		0x48, 0xC7, 0xC0, 0x3C, 0x00, 0x00, 0x00,
		0x0F, 0x05,
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
	case ^Literal_Node:
		if len(n.value) >= 12 && n.value[0:12] == "fmt.println(" {
			raw_str := n.value[13:len(n.value)-2]
			offset := add_string_literal(cg, raw_str)

			code_offset := u64(ELF_HEADER_SIZE + PHDR_SIZE)
			str_addr := BASE_ADDR + code_offset + u64(len(cg.code)) + offset

			emit_sys_write(cg, str_addr, u64(len(raw_str) + 1))
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
	emit_u32(cg, 7) // PF_R | PF_W | PF_X
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