package raven

import "core:fmt"
import "core:os"
import "core:path/filepath"

main :: proc() {
	if len(os.args) < 2 {
		fmt.println("usg: raven <file.rvn>")
		return
	}

	file_path := os.args[1]
	output_bin := "out.bin"
	_ = os.remove(output_bin)
	source_bytes, err := os.read_entire_file_from_path(file_path, context.temp_allocator)
	if err != nil {
		fmt.printf("err: Could not read file %s\n", file_path)
		return
	}

	loaded_modules := make(map[string]bool)
	loaded_modules[file_path] = true
	parser := init_parser(string(source_bytes), filepath.dir(file_path), &loaded_modules)
	ast_root := parse_program(&parser)
	if parser.syntax_errors > 0 {
		fmt.printf("Compilation failed with %d syntax error(s).\n", parser.syntax_errors)
		os.exit(1)
	}

	cg := init_codegen()
	compile_ast(&cg, ast_root)

	if write_executable(&cg, output_bin) {
		fmt.printf("Successfully compiled %s to ELF binary '%s' (%d bytes total).\n", file_path, output_bin, len(cg.code))
	} else {
		fmt.printf("Failed to write executable file %s\n", output_bin)
	}
}
