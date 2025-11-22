const std = @import("std");

extern fn md_html(
    input: [*]const u8,
    input_size: usize,
) c_int;

//int
//md_html(const MD_CHAR* input, MD_SIZE input_size,
//        void (*process_output)(const MD_CHAR*, MD_SIZE, void*),
//        void* userdata, unsigned parser_flags, unsigned renderer_flags)
//{
