// 
// Build script.
// Set the icon by running with: +Icon -icon icon.ico
// @TODO(JJB): load correct platform layer depending on platform 
// 

#load "src/win32_main.jai";

#run {
    args := get_build_options().compile_time_command_line;

    make_directory_if_it_does_not_exist("./build/");

    copy_directory("./resources/", "./build/resources");

    set_build_options_dc(.{
                           output_path = "build",
                           output_executable_name = "alc"});
}

#import "Compiler";
#import "File_Utilities";
