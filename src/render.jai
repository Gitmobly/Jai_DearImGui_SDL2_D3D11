#load "d3d11/d3d11_backend.jai";
#import "Basic";

Supported_Renderer_Backends :: enum {
    NONE;
    D3D11;
}

Renderer :: struct {
    window_handle: *void;
    w: s32;
    h: s32;

    backend: Supported_Renderer_Backends;
    device: *void;
    resources: *void;

    init_device: (*Renderer, *Allocators) -> bool;
    cleanup_device: (*Renderer);

    render: (*Renderer);
    present: (*Renderer);

    resize: (r: *Renderer) -> bool;

    init_imgui_ui: (r: *Renderer, *void);
}

renderer_init :: (a: *Allocators, window_handle: *void, w: s32, h: s32) -> *Renderer {
    r: *Renderer = New(Renderer,, a.persistent);
    r.backend = .D3D11;
    r.window_handle = window_handle;
    r.w = w;
    r.h = h;

    if r.backend == {
    case .D3D11; {
            r.init_device = d3d11_init_device;
            r.cleanup_device = d3d11_cleanup_device;

            r.render = d3d11_render;
            r.present = d3d11_present;

            r.resize = d3d11_resize;

            r.init_imgui_ui = d3d11_init_imgui_ui;
        }
    case .NONE;
    case; print("Attempted to use unsupported rendering backend.\n"); return null;
    }

    if !r.init_device(r, a) {
        print("Could not init renderer.\n");
        r.cleanup_device(r);
        return null;
    }

    return r;
}
