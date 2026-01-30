get_current_time :: () {
    Clock :: (x: Any) -> FormatInt {
        return formatInt(x, minimum_digits = 2);
    }

    now := current_time_monotonic();
    calendar := to_calendar(now, .LOCAL);
    print("[%:%:%:% :: ", Clock(calendar.hour), Clock(calendar.minute), Clock(calendar.second), Clock(calendar.millisecond));
}

log_debug :: (format_string: string, args: ..Any, loc := #caller_location, flags := Log_Flags.NONE, user_flags: u32 = 0, section: *Log_Section = null) {
    new_flags := flags | .VERBOSE_ONLY;
    get_current_time();
    write_string("APP :: DEBUG] ");
    log(format_string, ..args, loc, new_flags, user_flags, section);
} @PrintLike

log_info :: (format_string: string, args: ..Any, loc := #caller_location, flags := Log_Flags.NONE, user_flags: u32 = 0, section: *Log_Section = null) {
    get_current_time();
    write_string("APP ::  INFO]  ");
    log(format_string, ..args, loc, flags, user_flags, section);
} @PrintLike

log_err :: (format_string: string, args: ..Any, loc := #caller_location, flags := Log_Flags.NONE, user_flags: u32 = 0, section: *Log_Section = null) {
    new_flags := flags | .ERROR;
    get_current_time();
    write_string("APP :: ERROR] ");
    log(format_string, ..args, loc, new_flags, user_flags, section);
} @PrintLike
