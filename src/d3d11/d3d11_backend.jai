#import "d3d11";
#import "d3d_compiler";
#import "dxgi";
#import "File";

driver_type := D3D_DRIVER_TYPE.NULL;
feature_level := D3D_FEATURE_LEVEL._11_0;

D3D11_Device :: struct {
    d3d_device: *ID3D11Device;
    d3d_context: *ID3D11DeviceContext;
    swap_chain: *IDXGISwapChain;

    render_target_view: *ID3D11RenderTargetView;
    depth_buffer_view: *ID3D11DepthStencilView;

    rasterizer_state: *ID3D11RasterizerState;
    sampler_state: *ID3D11SamplerState;
    depth_stencil_state: *ID3D11DepthStencilState;
}

d3d11_init_device :: (r: *Renderer, a: *Allocators) -> bool {
    if r.backend != .D3D11 return false;

    device := New(D3D11_Device,, a.persistent);
    r.device = cast(*void)device;

    hr: HRESULT = S_OK;

    log_debug("Create device & device context.\n");

    flags: D3D11_CREATE_DEVICE_FLAG;
    flags |= .DEBUG;

    driver_types := D3D_DRIVER_TYPE.[.HARDWARE, .WARP, .REFERENCE];
    feature_levels := D3D_FEATURE_LEVEL.[._11_1, ._11_0, ._10_1, ._10_0];

    for 0..driver_types.count - 1 {
        driver_type = driver_types[it];
        hr = D3D11CreateDevice(null, driver_type, null, flags, feature_levels.data, feature_levels.count, D3D11_SDK_VERSION, *device.d3d_device, *feature_level, *device.d3d_context);

        if hr == E_INVALIDARG {
            hr = D3D11CreateDevice(null, driver_type, null, flags, feature_levels.data + 1, feature_levels.count - 1, D3D11_SDK_VERSION, *device.d3d_device, *feature_level, *device.d3d_context);
        }

        if SUCCEEDED(hr) break;
    }
    if FAILED(hr) {
        log_err("D3D11CreateDevice failed.\n");
        return false;
    }

    assert(*device.d3d_device != null);
    log_info("Created D3D11 device % with feature level %\n", *device.d3d_device, feature_level);

    dxgi_factory: *IDXGIFactory1;
     {
        dxgi_device: *IDXGIDevice;
        hr = IUnknown_QueryInterface(device.d3d_device, *uid(IDXGIDevice_UUID), xx *dxgi_device);
        if SUCCEEDED(hr) {
            adapter: *IDXGIAdapter;
            hr = IDXGIDevice_GetAdapter(dxgi_device, *adapter);
            if SUCCEEDED(hr) {
                hr = IDXGIObject_GetParent(adapter, *uid(IDXGIFactory1_UUID), xx *dxgi_factory);
                IUnknown_Release(adapter);
            }
            IUnknown_Release(dxgi_device);
        } else {
            log_err("QueryInterface FAILED\n");
        }
    }
    if FAILED(hr) {
        log_err("GetAdapter failed.\n");
        return false;
    }

    log_debug("Create swap chain.\n");

    width := r.w;
    height := r.h;

     {
        sd: DXGI_SWAP_CHAIN_DESC;
        sd.BufferCount = 1;
        sd.BufferDesc.Width = xx width;
        sd.BufferDesc.Height = xx height;
        sd.BufferDesc.Format = .R8G8B8A8_UNORM;
        sd.BufferDesc.RefreshRate.Numerator = 60;
        sd.BufferDesc.RefreshRate.Denominator = 1;
        sd.BufferUsage = .RENDER_TARGET_OUTPUT;
        sd.OutputWindow = r.window_handle;
        sd.SampleDesc.Count = 1;
        sd.SampleDesc.Quality = 0;
        sd.Windowed = BOOL.TRUE;

        hr = IDXGIFactory_CreateSwapChain(dxgi_factory, device.d3d_device, *sd, *device.swap_chain);
        if FAILED(hr) {
            log_error("CreateSwapChain failed: %", hr);
        }
    }

    IDXGIFactory_MakeWindowAssociation(dxgi_factory, r.window_handle, cast(u32)DXGI_MWA.NO_ALT_ENTER);
    IUnknown_Release(dxgi_factory);

    if FAILED(hr) return false;

    log_debug("Create a render target view\n");

    back_buffer: *ID3D11Texture2D;
    hr = IDXGISwapChain_GetBuffer(device.swap_chain, 0, *uid(ID3D11Texture2D_UUID), xx *back_buffer);
    if FAILED(hr) {
        log_error("GetBuffer failed: %", hr);
        return false;
    }

    hr = ID3D11Device_CreateRenderTargetView(device.d3d_device, back_buffer, null, *device.render_target_view);
    if FAILED(hr) {
        log_error("CreateRenderTargetView failed: %", hr);
        return false;
    }

    log_debug("Create a depth buffer view\n");

    db: D3D11_TEXTURE2D_DESC;
    ID3D11Texture2D_GetDesc(back_buffer, *db);
    IUnknown_Release(back_buffer);
    db.Format = .DXGI_FORMAT_D24_UNORM_S8_UINT;
    db.BindFlags = .DEPTH_STENCIL;

    depth_buffer: *ID3D11Texture2D;
    hr = ID3D11Device_CreateTexture2D(device.d3d_device, *db, null, *depth_buffer);
    if FAILED(hr) {
        log_error("CreateTexture2D failed: %", hr);
        return false;
    }

    ID3D11DeviceContext_OMSetRenderTargets(device.d3d_context, 1, *device.render_target_view, device.depth_buffer_view);

    return true;
}

d3d11_cleanup_device :: (r: *Renderer) {
    device := cast(*D3D11_Device)r.device;

    if device.d3d_context ID3D11DeviceContext_ClearState(device.d3d_context);

    if device.d3d_device IUnknown_Release(device.d3d_device);
    if device.d3d_context IUnknown_Release(device.d3d_context);
    if device.swap_chain IUnknown_Release(device.swap_chain);

    if device.render_target_view IUnknown_Release(device.render_target_view);
    if device.depth_buffer_view IUnknown_Release(device.depth_buffer_view);

    if device.rasterizer_state IUnknown_Release(device.rasterizer_state);
    if device.sampler_state IUnknown_Release(device.sampler_state);
    if device.depth_stencil_state IUnknown_Release(device.depth_stencil_state);
}

d3d11_render :: (r: *Renderer) {
    device := cast(*D3D11_Device)r.device;

    color: [4]float = float.[0.1, 0.1, 0.1, 1.0];
    ID3D11DeviceContext_ClearRenderTargetView(device.d3d_context, device.render_target_view, *color);
}

d3d11_present :: (r: *Renderer) {
    device := cast(*D3D11_Device)r.device;
    hr := IDXGISwapChain_Present(device.swap_chain, 0, 0);
    if FAILED(hr) {
        log_error("Present failed: %", hr);
    }
}

d3d11_resize :: (r: *Renderer) -> bool {
    device := cast(*D3D11_Device)r.device;

    if (device.render_target_view) IUnknown_Release(device.render_target_view);
    if (device.depth_buffer_view) IUnknown_Release(device.depth_buffer_view);

    log_debug("Resize swap chain.\n");

    hr := IDXGISwapChain_ResizeBuffers(device.swap_chain, 0, xx r.w, xx r.h, .UNKNOWN, 0);
    if (FAILED(hr)) {
        log_err("ResizeBuffers failed: %", hr);
        return false;
    }

    log_debug("Recreate a render target view\n");

    back_buffer: *ID3D11Texture2D;
    hr = IDXGISwapChain_GetBuffer(device.swap_chain, 0, *uid(ID3D11Texture2D_UUID), xx *back_buffer);
    if FAILED(hr) {
        log_err("GetBuffer failed: %", hr);
        return false;
    }

    hr = ID3D11Device_CreateRenderTargetView(device.d3d_device, back_buffer, null, *device.render_target_view);
    if FAILED(hr) {
        log_err("CreateRenderTargetView failed: %", hr);
        return false;
    }

    log_debug("Recreate a depth buffer view\n");

    db: D3D11_TEXTURE2D_DESC;
    ID3D11Texture2D_GetDesc(back_buffer, *db);
    IUnknown_Release(back_buffer);
    db.Format = .DXGI_FORMAT_D24_UNORM_S8_UINT;
    db.BindFlags = .DEPTH_STENCIL;

    depth_buffer: *ID3D11Texture2D;
    hr = ID3D11Device_CreateTexture2D(device.d3d_device, *db, null, *depth_buffer);
    if FAILED(hr) {
        log_err("CreateTexture2D failed: %", hr);
        return false;
    }

    hr = ID3D11Device_CreateDepthStencilView(device.d3d_device, depth_buffer, null, *device.depth_buffer_view);
    IUnknown_Release(depth_buffer);
    if FAILED(hr) {
        log_err("CreateDepthStencilView failed: %", hr);
        return false;
    }

    ID3D11DeviceContext_OMSetRenderTargets(device.d3d_context, 1, *device.render_target_view, device.depth_buffer_view);

    vp: D3D11_VIEWPORT;
    vp.Width = xx r.w;
    vp.Height = xx r.h;
    vp.MinDepth = 0.0;
    vp.MaxDepth = 1.0;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;

    ID3D11DeviceContext_RSSetViewports(device.d3d_context, 1, *vp);

    return true;
}

d3d11_init_imgui_ui :: (r: *Renderer, w: *void) {
    device := cast(*D3D11_Device)r.device;
    ImGui_ImplSdl_Init(cast(*SDL_Window)w, device.d3d_device, device.d3d_context);
    ImGui.StyleColorsClassic();
}
