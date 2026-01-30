#import "Basic";
#import "Windows";
#import "Windows_Utf8";
#import "Math";
#import "SDL";
#import "Flat_Pool";

#load "render.jai";
#load "log.jai";
#load "ui.jai";

DEBUG :: 1;
DEFAULT_WIDTH :: 800;
DEFAULT_HEIGHT :: 600;

App_State :: struct {
    app_running: bool;
    window: *SDL_Window;
}

Allocators :: struct {
    persistent: *Allocator;
}

main :: () {
    perm_pool: Flat_Pool;

    persistent: Allocator;
    persistent.proc = flat_pool_allocator_proc;
    persistent.data = *perm_pool;

    allocators: Allocators;
    allocators.persistent = *persistent;

    a: *App_State = New(App_State,, allocators.persistent);

    init_window_success, window := init_window();
    if !init_window_success {
        log_err("init_window failed!\n");
        return;
    }

    a.window = window;
    wm_info: SDL_SysWMinfo;
    SDL_VERSION(*wm_info.version);
    SDL_GetWindowWMInfo(window, *wm_info);
    hwnd := cast(HWND)wm_info.info.win.window;

    imgui_context := ImGui.CreateContext();

    renderer := renderer_init(*allocators, hwnd, DEFAULT_WIDTH, DEFAULT_HEIGHT);
    renderer.init_imgui_ui(renderer, a.window);

    display_mode: SDL_DisplayMode;
    SDL_GetDisplayMode(0, 0, *display_mode);

    a.app_running = true;
    while (a.app_running) {
        event: SDL_Event;
        handle_events(a, *event, renderer);

        renderer.render(renderer);

        imgui_begin_frame(a.window);
        imgui_end_frame();

        renderer.present(renderer);
    }

    fini(allocators.persistent.data);
    ImGui_ImplSdl_Shutdown();
    ImGui.DestroyContext(imgui_context);
    SDL_DestroyWindow(window);
    SDL_Quit();
}

init_window :: () -> bool, *SDL_Window {
    SDL_Init(SDL_INIT_VIDEO);

    window_flags := cast(SDL_WindowFlags)(SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    window := SDL_CreateWindow("A Lost Composer",
                               SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, DEFAULT_WIDTH, DEFAULT_HEIGHT,
                               window_flags);

    if window == null {
        log_err("Could not create window: %\n", to_string(SDL_GetError()));
        return false, null;
    }

    log_info("Window initialized at %x%!\n", DEFAULT_WIDTH, DEFAULT_HEIGHT);

    return true, window;
}

handle_events :: (a: *App_State, event: *SDL_Event, renderer: *Renderer) {
    while (SDL_PollEvent(event)) {
        ImGui_ImplSdl_ProcessEvent(event);
        if (event.type) == {
        case SDL_QUIT; {
                a.app_running = false;
            }
        case SDL_KEYDOWN; #through;
        case SDL_KEYUP; {
                if event.key.keysym.sym == {
                case SDLK_ESCAPE; a.app_running = false;
                }
            }
        case SDL_WINDOWEVENT; {
                if (event.window.event == SDL_WINDOWEVENT_SIZE_CHANGED) {
                    w := event.window.data1;
                    h := event.window.data2;
                    renderer.w = w;
                    renderer.h = h;
                    renderer.resize(renderer);
                }
            }
        }
    }
}
