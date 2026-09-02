package raven

import "core:fmt"
import "core:os"

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("usg: raven <file.rvn>")
		return
	}

	file_path := os.args[1]
	source_bytes, ok := os.read_entire_file_from_filename(file_path)
	if !ok {
		fmt.printf("err: Could not read file %s\n", file_path)
		return
	}

	source := string(source_bytes)
	parser := init_parser(source)
	ast_root := parse_program(&parser)

	cg := init_codegen()
	compile_ast(&cg, ast_root)

	output_bin := "out.bin"
	if write_executable(&cg, output_bin) {
		fmt.printf("Successfully compiled %s to ELF binary '%s' (%d bytes total).\n", file_path, output_bin, len(cg.code))
	} else {
		fmt.printf("Failed to write executable file %s\n", output_bin)
	}
}