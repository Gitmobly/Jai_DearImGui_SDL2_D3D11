#import "Basic";
ImGui :: #import "ImGui";
#import "SDL";
#import "Math";
#import "d3d11";
#import "d3d_compiler";

imgui_begin_frame :: (w: *SDL_Window) {
    ImGui_ImplSdl_NewFrame(w);
    ImGui.NewFrame();
    ImGui.SetNextWindowPos(.{20, 20}, ImGui.Cond.FirstUseEver, .{0, 0});
    show := true;
    ImGui.ShowDemoWindow(*show);
}

imgui_end_frame :: () {
    ImGui.Render();
    ImGui_ImplSdl_RenderDrawLists(ImGui.GetDrawData());
    if ImGui.GetMouseCursor() == {
    case .Arrow; SDL_SetCursor(cursor_arrow);
    case .TextInput; SDL_SetCursor(cursor_text_input);
    case .Hand; SDL_SetCursor(cursor_move);
    case .ResizeNS; SDL_SetCursor(cursor_resize_ns);
    case .ResizeEW; SDL_SetCursor(cursor_resize_ew);
    case .ResizeNESW; SDL_SetCursor(cursor_resize_nesw);
    case .ResizeNWSE; SDL_SetCursor(cursor_resize_nwse);
    }
}

/* -------------------------------------
* (JJB): Port of the GL Imgui SDL Example
*/

g_Time: u64 = 0;
g_MousePressed := bool.[false, false, false];
g_MouseWheel: float = 0.0;

g_pd3dDevice: *ID3D11Device;
g_pd3dDeviceContext: *ID3D11DeviceContext;
g_pFontTextureView: *ID3D11ShaderResourceView;
g_pFontSampler: *ID3D11SamplerState;
g_pVertexConstantBuffer: *ID3D11Buffer;
g_pVertexShader: *ID3D11VertexShader;
g_pInputLayout: *ID3D11InputLayout;
g_pPixelShader: *ID3D11PixelShader;
g_pVertexBuffer: *ID3D11Buffer;
g_pIndexBuffer: *ID3D11Buffer;
g_pBlendState: *ID3D11BlendState;
g_pDepthStencilState: *ID3D11DepthStencilState;
g_pRasterizerState: *ID3D11RasterizerState;

g_VertexBufferSize: s32 = 5000;
g_IndexBufferSize: s32 = 10000;

cursor_arrow: *SDL_Cursor;
cursor_text_input: *SDL_Cursor;
cursor_move: *SDL_Cursor;
cursor_resize_ns: *SDL_Cursor;
cursor_resize_ew: *SDL_Cursor;
cursor_resize_nesw: *SDL_Cursor;
cursor_resize_nwse: *SDL_Cursor;

VERTEX_CONSTANT_BUFFER :: struct {
    mvp: Matrix4;
}

ImGui_ImplSdl_RenderDrawLists :: (draw_data: *ImGui.ImDrawData) #c_call {
    if draw_data.DisplaySize.x <= 0 || draw_data.DisplaySize.y <= 0 return;

    ctx := g_pd3dDeviceContext;

    push_context {
        if !g_pVertexBuffer || g_VertexBufferSize < draw_data.TotalVtxCount {
            if g_pVertexBuffer {IUnknown_Release(g_pVertexBuffer); g_pVertexBuffer = null;}
            g_VertexBufferSize = draw_data.TotalVtxCount + 5000;
            desc: D3D11_BUFFER_DESC;
            desc.Usage = .DYNAMIC;
            desc.ByteWidth = cast(u32)(g_VertexBufferSize * size_of(ImGui.ImDrawVert));
            desc.BindFlags = .VERTEX_BUFFER;
            desc.CPUAccessFlags = .WRITE;
            if ID3D11Device_CreateBuffer(g_pd3dDevice, *desc, null, *g_pVertexBuffer) < 0 return;
        }
        if !g_pIndexBuffer || g_IndexBufferSize < draw_data.TotalIdxCount {
            if g_pIndexBuffer {IUnknown_Release(g_pIndexBuffer); g_pIndexBuffer = null;}
            g_IndexBufferSize = draw_data.TotalIdxCount + 10000;
            desc: D3D11_BUFFER_DESC;
            desc.Usage = .DYNAMIC;
            desc.ByteWidth = cast(u32)(g_IndexBufferSize * size_of(ImGui.ImDrawIdx));
            desc.BindFlags = .INDEX_BUFFER;
            desc.CPUAccessFlags = .WRITE;
            if ID3D11Device_CreateBuffer(g_pd3dDevice, *desc, null, *g_pIndexBuffer) < 0 return;
        }

        vtx_resource, idx_resource: D3D11_MAPPED_SUBRESOURCE;
        if ID3D11DeviceContext_Map(ctx, g_pVertexBuffer, 0, .WRITE_DISCARD, 0, *vtx_resource) != 0 return;
        if ID3D11DeviceContext_Map(ctx, g_pIndexBuffer, 0, .WRITE_DISCARD, 0, *idx_resource) != 0 return;
        vtx_dst := cast(*ImGui.ImDrawVert)vtx_resource.pData;
        idx_dst := cast(*ImGui.ImDrawIdx)idx_resource.pData;
        for n: 0..draw_data.CmdListsCount - 1 {
            cmd_list := draw_data.CmdLists[n];
            memcpy(vtx_dst, cmd_list.VtxBuffer.Data, cmd_list.VtxBuffer.Size * size_of(ImGui.ImDrawVert));
            memcpy(idx_dst, cmd_list.IdxBuffer.Data, cmd_list.IdxBuffer.Size * size_of(ImGui.ImDrawIdx));
            vtx_dst += cmd_list.VtxBuffer.Size;
            idx_dst += cmd_list.IdxBuffer.Size;
        }
        ID3D11DeviceContext_Unmap(ctx, g_pVertexBuffer, 0);
        ID3D11DeviceContext_Unmap(ctx, g_pIndexBuffer, 0);

         {
            mapped_resource: D3D11_MAPPED_SUBRESOURCE;
            if ID3D11DeviceContext_Map(ctx, g_pVertexConstantBuffer, 0, .WRITE_DISCARD, 0, *mapped_resource) != 0 return;
            constant_buffer := cast(*VERTEX_CONSTANT_BUFFER)mapped_resource.pData;

            L := draw_data.DisplayPos.x;
            R := draw_data.DisplayPos.x + draw_data.DisplaySize.x;
            T := draw_data.DisplayPos.y;
            B := draw_data.DisplayPos.y + draw_data.DisplaySize.y;

            mvp: Matrix4;
            mvp._11 = 2.0 / (R - L);
            mvp._12 = 0.0;
            mvp._13 = 0.0;
            mvp._14 = 0.0;
            mvp._21 = 0.0;
            mvp._22 = 2.0 / (T - B);
            mvp._23 = 0.0;
            mvp._24 = 0.0;
            mvp._31 = 0.0;
            mvp._32 = 0.0;
            mvp._33 = 0.5;
            mvp._34 = 0.0;
            mvp._41 = (R + L) / (L - R);
            mvp._42 = (T + B) / (B - T);
            mvp._43 = 0.5;
            mvp._44 = 1.0;
            constant_buffer.mvp = mvp;
            ID3D11DeviceContext_Unmap(ctx, g_pVertexConstantBuffer, 0);
        }

        old: struct {
            ScissorRectsCount, ViewportsCount: u32;
            ScissorRects: [D3D11_VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE]D3D11_RECT;
            Viewports: [D3D11_VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE]D3D11_VIEWPORT;
            RS: *ID3D11RasterizerState;
            BlendState: *ID3D11BlendState;
            BlendFactor: [4]float;
            SampleMask: u32;
            StencilRef: u32;
            DepthStencilState: *ID3D11DepthStencilState;
            PSShaderResource: *ID3D11ShaderResourceView;
            PSSampler: *ID3D11SamplerState;
            PS: *ID3D11PixelShader;
            VS: *ID3D11VertexShader;
            PSInstancesCount, VSInstancesCount: u32;
            PSInstances, VSInstances: [256]*ID3D11ClassInstance;
            PrimitiveTopology: D3D11_PRIMITIVE_TOPOLOGY;
            IndexBuffer: *ID3D11Buffer;
            VertexBuffer: *ID3D11Buffer;
            VertexConstantBuffer: *ID3D11Buffer;
            IndexBufferOffset, VertexBufferStride, VertexBufferOffset: u32;
            IndexBufferFormat: DXGI_FORMAT;
            InputLayout: *ID3D11InputLayout;
        }

        old.ScissorRectsCount = D3D11_VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE;
        old.ViewportsCount = D3D11_VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE;
        ID3D11DeviceContext_RSGetScissorRects(ctx, *old.ScissorRectsCount, old.ScissorRects.data);
        ID3D11DeviceContext_RSGetViewports(ctx, *old.ViewportsCount, old.Viewports.data);
        ID3D11DeviceContext_RSGetState(ctx, *old.RS);
        ID3D11DeviceContext_OMGetBlendState(ctx, *old.BlendState, *old.BlendFactor, *old.SampleMask);
        ID3D11DeviceContext_OMGetDepthStencilState(ctx, *old.DepthStencilState, *old.StencilRef);
        ID3D11DeviceContext_PSGetShaderResources(ctx, 0, 1, *old.PSShaderResource);
        ID3D11DeviceContext_PSGetSamplers(ctx, 0, 1, *old.PSSampler);
        old.PSInstancesCount = 256;
        old.VSInstancesCount = 256;
        ID3D11DeviceContext_PSGetShader(ctx, *old.PS, old.PSInstances.data, *old.PSInstancesCount);
        ID3D11DeviceContext_VSGetShader(ctx, *old.VS, old.VSInstances.data, *old.VSInstancesCount);
        ID3D11DeviceContext_VSGetConstantBuffers(ctx, 0, 1, *old.VertexConstantBuffer);
        ID3D11DeviceContext_IAGetPrimitiveTopology(ctx, *old.PrimitiveTopology);
        ID3D11DeviceContext_IAGetIndexBuffer(ctx, *old.IndexBuffer, *old.IndexBufferFormat, *old.IndexBufferOffset);
        ID3D11DeviceContext_IAGetVertexBuffers(ctx, 0, 1, *old.VertexBuffer, *old.VertexBufferStride, *old.VertexBufferOffset);
        ID3D11DeviceContext_IAGetInputLayout(ctx, *old.InputLayout);

        ImGui_ImplDX11_SetupRenderState(draw_data, ctx);

        global_idx_offset: s32 = 0;
        global_vtx_offset: s32 = 0;
        clip_off := draw_data.DisplayPos;
        for n: 0..draw_data.CmdListsCount - 1 {
            cmd_list := draw_data.CmdLists[n];
            for cmd_i: 0..cmd_list.CmdBuffer.Size - 1 {
                pcmd := *cmd_list.CmdBuffer.Data[cmd_i];
                if pcmd.UserCallback {
                    pcmd.UserCallback(cmd_list, pcmd);
                } else {
                    r: D3D11_RECT;
                    r.left = cast(s32)(pcmd.ClipRect.x - clip_off.x);
                    r.top = cast(s32)(pcmd.ClipRect.y - clip_off.y);
                    r.right = cast(s32)(pcmd.ClipRect.z - clip_off.x);
                    r.bottom = cast(s32)(pcmd.ClipRect.w - clip_off.y);
                    ID3D11DeviceContext_RSSetScissorRects(ctx, 1, *r);

                    texture_srv := cast(*ID3D11ShaderResourceView)pcmd.TextureId;
                    ID3D11DeviceContext_PSSetShaderResources(ctx, 0, 1, *texture_srv);

                    ID3D11DeviceContext_DrawIndexed(ctx, pcmd.ElemCount, cast(u32)(pcmd.IdxOffset + xx global_idx_offset), cast(s32)(pcmd.VtxOffset + xx global_vtx_offset));
                }
            }
            global_idx_offset += cmd_list.IdxBuffer.Size;
            global_vtx_offset += cmd_list.VtxBuffer.Size;
        }

        ID3D11DeviceContext_RSSetScissorRects(ctx, old.ScissorRectsCount, old.ScissorRects.data);
        ID3D11DeviceContext_RSSetViewports(ctx, old.ViewportsCount, old.Viewports.data);
        ID3D11DeviceContext_RSSetState(ctx, old.RS); if old.RS {IUnknown_Release(old.RS);}
        ID3D11DeviceContext_OMSetBlendState(ctx, old.BlendState, *old.BlendFactor, old.SampleMask); if old.BlendState {IUnknown_Release(old.BlendState);}
        ID3D11DeviceContext_OMSetDepthStencilState(ctx, old.DepthStencilState, old.StencilRef); if old.DepthStencilState {IUnknown_Release(old.DepthStencilState);}
        ID3D11DeviceContext_PSSetShaderResources(ctx, 0, 1, *old.PSShaderResource); if old.PSShaderResource {IUnknown_Release(old.PSShaderResource);}
        ID3D11DeviceContext_PSSetSamplers(ctx, 0, 1, *old.PSSampler); if old.PSSampler {IUnknown_Release(old.PSSampler);}
        ID3D11DeviceContext_PSSetShader(ctx, old.PS, old.PSInstances.data, old.PSInstancesCount); if old.PS {IUnknown_Release(old.PS);}
        if old.PSInstancesCount > 0 && old.PSInstancesCount <= 256 {
            for i: 0..old.PSInstancesCount - 1 {if old.PSInstances[i] {IUnknown_Release(old.PSInstances[i]);}}
        }
        ID3D11DeviceContext_VSSetShader(ctx, old.VS, old.VSInstances.data, old.VSInstancesCount); if old.VS {IUnknown_Release(old.VS);}
        if old.VSInstancesCount > 0 && old.VSInstancesCount <= 256 {
            for i: 0..old.VSInstancesCount - 1 {if old.VSInstances[i] {IUnknown_Release(old.VSInstances[i]);}}
        }
        ID3D11DeviceContext_VSSetConstantBuffers(ctx, 0, 1, *old.VertexConstantBuffer); if old.VertexConstantBuffer {IUnknown_Release(old.VertexConstantBuffer);}
        ID3D11DeviceContext_IASetPrimitiveTopology(ctx, old.PrimitiveTopology);
        ID3D11DeviceContext_IASetIndexBuffer(ctx, old.IndexBuffer, old.IndexBufferFormat, old.IndexBufferOffset); if old.IndexBuffer {IUnknown_Release(old.IndexBuffer);}
        ID3D11DeviceContext_IASetVertexBuffers(ctx, 0, 1, *old.VertexBuffer, *old.VertexBufferStride, *old.VertexBufferOffset); if old.VertexBuffer {IUnknown_Release(old.VertexBuffer);}
        ID3D11DeviceContext_IASetInputLayout(ctx, old.InputLayout); if old.InputLayout {IUnknown_Release(old.InputLayout);}
    }
}

ImGui_ImplDX11_SetupRenderState :: (draw_data: *ImGui.ImDrawData, ctx: *ID3D11DeviceContext) {
    vp: D3D11_VIEWPORT;
    vp.Width = draw_data.DisplaySize.x;
    vp.Height = draw_data.DisplaySize.y;
    vp.MinDepth = 0.0;
    vp.MaxDepth = 1.0;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;
    ID3D11DeviceContext_RSSetViewports(ctx, 1, *vp);

    stride: u32 = size_of(ImGui.ImDrawVert);
    offset: u32 = 0;
    ID3D11DeviceContext_IASetInputLayout(ctx, g_pInputLayout);
    ID3D11DeviceContext_IASetVertexBuffers(ctx, 0, 1, *g_pVertexBuffer, *stride, *offset);
    ID3D11DeviceContext_IASetIndexBuffer(ctx, g_pIndexBuffer, ifx size_of(ImGui.ImDrawIdx) == 2 then .R16_UINT else .R32_UINT, 0);
    ID3D11DeviceContext_IASetPrimitiveTopology(ctx, .TRIANGLELIST);
    ID3D11DeviceContext_VSSetShader(ctx, g_pVertexShader, null, 0);
    ID3D11DeviceContext_VSSetConstantBuffers(ctx, 0, 1, *g_pVertexConstantBuffer);
    ID3D11DeviceContext_PSSetShader(ctx, g_pPixelShader, null, 0);
    ID3D11DeviceContext_PSSetSamplers(ctx, 0, 1, *g_pFontSampler);
    ID3D11DeviceContext_GSSetShader(ctx, null, null, 0);
    ID3D11DeviceContext_HSSetShader(ctx, null, null, 0);
    ID3D11DeviceContext_DSSetShader(ctx, null, null, 0);
    ID3D11DeviceContext_CSSetShader(ctx, null, null, 0);

    blend_factor := float.[0, 0, 0, 0];
    ID3D11DeviceContext_OMSetBlendState(ctx, g_pBlendState, *blend_factor, 0xffffffff);
    ID3D11DeviceContext_OMSetDepthStencilState(ctx, g_pDepthStencilState, 0);
    ID3D11DeviceContext_RSSetState(ctx, g_pRasterizerState);
}

ImGui_ImplSdl_GetClipboardText :: (data: *void) -> *u8 #c_call {
    return SDL_GetClipboardText();
}

ImGui_ImplSdl_SetClipboardText :: (data: *void, text: *u8) #c_call {
    SDL_SetClipboardText(text);
}

ImGui_ImplSdl_ProcessEvent :: (event: *SDL_Event) -> bool {
    io := ImGui.GetIO();
    if event.type == {
    case SDL_MOUSEWHEEL;
        if event.wheel.y > 0 g_MouseWheel = 1;
        if event.wheel.y < 0 g_MouseWheel = -1;
        return true;
    case SDL_MOUSEBUTTONDOWN;
        if event.button.button == SDL_BUTTON_LEFT g_MousePressed[0] = true;
        if event.button.button == SDL_BUTTON_RIGHT g_MousePressed[1] = true;
        if event.button.button == SDL_BUTTON_MIDDLE g_MousePressed[2] = true;
        return true;
    case SDL_TEXTINPUT;
        io.AddInputCharactersUTF8(io, xx event.text.text.data);
        return true;
    case SDL_KEYDOWN; #through;
    case SDL_KEYUP;
        key := event.key.keysym.sym & (xx ~(1 << 30));
        io.KeysDown[key] = (event.type == SDL_KEYDOWN);
        kmod := SDL_GetModState();
        io.KeyShift = ((kmod & KMOD_SHIFT) != 0);
        io.KeyCtrl = ((kmod & KMOD_CTRL) != 0);
        io.KeyAlt = ((kmod & KMOD_ALT) != 0);
        io.KeySuper = ((kmod & KMOD_GUI) != 0);
        return true;
    }
    return false;
}

ImGui_ImplDX11_CreateFontsTexture :: () -> bool {
    io := ImGui.GetIO();
    pixels: *u8;
    width, height: s32;
    io.Fonts.GetTexDataAsRGBA32(io.Fonts, *pixels, *width, *height, null);

     {
        desc: D3D11_TEXTURE2D_DESC;
        desc.Width = cast(u32)width;
        desc.Height = cast(u32)height;
        desc.MipLevels = 1;
        desc.ArraySize = 1;
        desc.Format = .R8G8B8A8_UNORM;
        desc.SampleDesc.Count = 1;
        desc.Usage = .DEFAULT;
        desc.BindFlags = .SHADER_RESOURCE;

        pTexture: *ID3D11Texture2D;
        subResource: D3D11_SUBRESOURCE_DATA;
        subResource.pSysMem = pixels;
        subResource.SysMemPitch = cast(u32)(width * 4);
        ID3D11Device_CreateTexture2D(g_pd3dDevice, *desc, *subResource, *pTexture);

        srvDesc: D3D11_SHADER_RESOURCE_VIEW_DESC;
        srvDesc.Format = .R8G8B8A8_UNORM;
        srvDesc.ViewDimension = .TEXTURE2D;
        srvDesc.Texture2D.MipLevels = 1;
        ID3D11Device_CreateShaderResourceView(g_pd3dDevice, pTexture, *srvDesc, *g_pFontTextureView);
        IUnknown_Release(pTexture);
    }

    io.Fonts.TexID = xx g_pFontTextureView;

     {
        desc: D3D11_SAMPLER_DESC;
        desc.Filter = .MIN_MAG_MIP_LINEAR;
        desc.AddressU = .WRAP;
        desc.AddressV = .WRAP;
        desc.AddressW = .WRAP;
        desc.ComparisonFunc = .ALWAYS;
        ID3D11Device_CreateSamplerState(g_pd3dDevice, *desc, *g_pFontSampler);
    }

    return true;
}

ImGui_ImplDX11_CreateDeviceObjects :: () -> bool {
    if g_pd3dDevice == null return false;

    vertex_shader := #string END
        cbuffer vertexBuffer : register(b0) {
            float4x4 ProjectionMatrix;
        };
        struct VS_INPUT {
            float2 pos : POSITION;
            float2 uv  : TEXCOORD0;
            float4 col : COLOR0;
        };
        struct PS_INPUT {
            float4 pos : SV_POSITION;
            float4 col : COLOR0;
            float2 uv  : TEXCOORD0;
        };
        PS_INPUT main(VS_INPUT input) {
            PS_INPUT output;
            output.pos = mul(ProjectionMatrix, float4(input.pos.xy, 0.f, 1.f));
            output.col = input.col;
            output.uv  = input.uv;
            return output;
        }
    END

    vertexShaderBlob: *ID3DBlob;
    if D3DCompile(vertex_shader.data, cast(u64)vertex_shader.count, null, null, null, "main", "vs_4_0", 0, 0, *vertexShaderBlob, null) < 0
        return false;
    if ID3D11Device_CreateVertexShader(g_pd3dDevice, ID3D10Blob_GetBufferPointer(vertexShaderBlob), ID3D10Blob_GetBufferSize(vertexShaderBlob), null, *g_pVertexShader) < 0 {
        IUnknown_Release(vertexShaderBlob);
        return false;
    }

    local_layout := D3D11_INPUT_ELEMENT_DESC.[
                                              .{"POSITION", 0, .R32G32_FLOAT, 0, 0, .VERTEX_DATA, 0},
                                              .{"TEXCOORD", 0, .R32G32_FLOAT, 0, 8, .VERTEX_DATA, 0},
                                              .{"COLOR", 0, .R8G8B8A8_UNORM, 0, 16, .VERTEX_DATA, 0}];

    if ID3D11Device_CreateInputLayout(g_pd3dDevice, local_layout.data, 3, ID3D10Blob_GetBufferPointer(vertexShaderBlob), ID3D10Blob_GetBufferSize(vertexShaderBlob), *g_pInputLayout) < 0 {
        IUnknown_Release(vertexShaderBlob);
        return false;
    }
    IUnknown_Release(vertexShaderBlob);

     {
        desc: D3D11_BUFFER_DESC;
        desc.ByteWidth = size_of(VERTEX_CONSTANT_BUFFER);
        desc.Usage = .DYNAMIC;
        desc.BindFlags = .CONSTANT_BUFFER;
        desc.CPUAccessFlags = .WRITE;
        ID3D11Device_CreateBuffer(g_pd3dDevice, *desc, null, *g_pVertexConstantBuffer);
    }

    pixel_shader := #string END
        struct PS_INPUT {
            float4 pos : SV_POSITION;
            float4 col : COLOR0;
            float2 uv  : TEXCOORD0;
        };
        sampler sampler0;
        Texture2D texture0;
        float4 main(PS_INPUT input) : SV_Target {
            float4 out_col = input.col * texture0.Sample(sampler0, input.uv);
            return out_col;
        }
    END

    pixelShaderBlob: *ID3DBlob;
    if D3DCompile(pixel_shader.data, cast(u64)pixel_shader.count, null, null, null, "main", "ps_4_0", 0, 0, *pixelShaderBlob, null) < 0
        return false;
    if ID3D11Device_CreatePixelShader(g_pd3dDevice, ID3D10Blob_GetBufferPointer(pixelShaderBlob), ID3D10Blob_GetBufferSize(pixelShaderBlob), null, *g_pPixelShader) < 0 {
        IUnknown_Release(pixelShaderBlob);
        return false;
    }
    IUnknown_Release(pixelShaderBlob);

     {
        desc: D3D11_BLEND_DESC;
        desc.AlphaToCoverageEnable = 0;
        desc.RenderTarget[0].BlendEnable = 1;
        desc.RenderTarget[0].SrcBlend = .SRC_ALPHA;
        desc.RenderTarget[0].DestBlend = .INV_SRC_ALPHA;
        desc.RenderTarget[0].BlendOp = .ADD;
        desc.RenderTarget[0].SrcBlendAlpha = .ONE;
        desc.RenderTarget[0].DestBlendAlpha = .INV_SRC_ALPHA;
        desc.RenderTarget[0].BlendOpAlpha = .ADD;
        desc.RenderTarget[0].RenderTargetWriteMask = xx D3D11_COLOR_WRITE_ENABLE.ALL;
        ID3D11Device_CreateBlendState(g_pd3dDevice, *desc, *g_pBlendState);
    }

     {
        desc: D3D11_RASTERIZER_DESC;
        desc.FillMode = .SOLID;
        desc.CullMode = .NONE;
        desc.ScissorEnable = 1;
        desc.DepthClipEnable = 1;
        ID3D11Device_CreateRasterizerState(g_pd3dDevice, *desc, *g_pRasterizerState);
    }

     {
        desc: D3D11_DEPTH_STENCIL_DESC;
        desc.DepthEnable = 0;
        desc.DepthWriteMask = .ALL;
        desc.DepthFunc = .ALWAYS;
        desc.StencilEnable = 0;
        desc.FrontFace.StencilFailOp = .KEEP;
        desc.FrontFace.StencilDepthFailOp = .KEEP;
        desc.FrontFace.StencilPassOp = .KEEP;
        desc.FrontFace.StencilFunc = .ALWAYS;
        desc.BackFace = desc.FrontFace;
        ID3D11Device_CreateDepthStencilState(g_pd3dDevice, *desc, *g_pDepthStencilState);
    }

    ImGui_ImplDX11_CreateFontsTexture();

    return true;
}

ImGui_ImplDX11_InvalidateDeviceObjects :: () {
    if g_pd3dDevice == null return;

    if g_pFontSampler {IUnknown_Release(g_pFontSampler); g_pFontSampler = null;}
    if g_pFontTextureView {IUnknown_Release(g_pFontTextureView); g_pFontTextureView = null; ImGui.GetIO().Fonts.TexID = null;}
    if g_pIndexBuffer {IUnknown_Release(g_pIndexBuffer); g_pIndexBuffer = null;}
    if g_pVertexBuffer {IUnknown_Release(g_pVertexBuffer); g_pVertexBuffer = null;}
    if g_pBlendState {IUnknown_Release(g_pBlendState); g_pBlendState = null;}
    if g_pDepthStencilState {IUnknown_Release(g_pDepthStencilState); g_pDepthStencilState = null;}
    if g_pRasterizerState {IUnknown_Release(g_pRasterizerState); g_pRasterizerState = null;}
    if g_pPixelShader {IUnknown_Release(g_pPixelShader); g_pPixelShader = null;}
    if g_pVertexConstantBuffer {IUnknown_Release(g_pVertexConstantBuffer); g_pVertexConstantBuffer = null;}
    if g_pInputLayout {IUnknown_Release(g_pInputLayout); g_pInputLayout = null;}
    if g_pVertexShader {IUnknown_Release(g_pVertexShader); g_pVertexShader = null;}
}

ImGui_ImplSdl_Init :: (window: *SDL_Window, device: *ID3D11Device, device_context: *ID3D11DeviceContext) -> bool {
    g_pd3dDevice = device;
    g_pd3dDeviceContext = device_context;

    io := ImGui.GetIO();
    io.KeyMap[ImGui.Key.Tab] = xx SDLK_TAB;
    io.KeyMap[ImGui.Key.LeftArrow] = xx SDL_SCANCODE_LEFT;
    io.KeyMap[ImGui.Key.RightArrow] = xx SDL_SCANCODE_RIGHT;
    io.KeyMap[ImGui.Key.UpArrow] = xx SDL_SCANCODE_UP;
    io.KeyMap[ImGui.Key.DownArrow] = xx SDL_SCANCODE_DOWN;
    io.KeyMap[ImGui.Key.PageUp] = xx SDL_SCANCODE_PAGEUP;
    io.KeyMap[ImGui.Key.PageDown] = xx SDL_SCANCODE_PAGEDOWN;
    io.KeyMap[ImGui.Key.Home] = xx SDL_SCANCODE_HOME;
    io.KeyMap[ImGui.Key.End] = xx SDL_SCANCODE_END;
    io.KeyMap[ImGui.Key.Delete] = xx SDLK_DELETE;
    io.KeyMap[ImGui.Key.Backspace] = xx SDLK_BACKSPACE;
    io.KeyMap[ImGui.Key.Enter] = xx SDLK_RETURN;
    io.KeyMap[ImGui.Key.Escape] = xx SDLK_ESCAPE;
    io.KeyMap[ImGui.Key.A] = xx SDLK_a;
    io.KeyMap[ImGui.Key.C] = xx SDLK_c;
    io.KeyMap[ImGui.Key.V] = xx SDLK_v;
    io.KeyMap[ImGui.Key.X] = xx SDLK_x;
    io.KeyMap[ImGui.Key.Y] = xx SDLK_y;
    io.KeyMap[ImGui.Key.Z] = xx SDLK_z;

    io.SetClipboardTextFn = ImGui_ImplSdl_SetClipboardText;
    io.GetClipboardTextFn = ImGui_ImplSdl_GetClipboardText;
    io.ClipboardUserData = null;

    #if OS == .WINDOWS {
        wmInfo: SDL_SysWMinfo;
        SDL_VERSION(*wmInfo.version);
        SDL_GetWindowWMInfo(window, *wmInfo);
        io.ImeWindowHandle = wmInfo.info.win.window;
    }

    cursor_arrow = SDL_CreateSystemCursor(.ARROW);
    cursor_text_input = SDL_CreateSystemCursor(.IBEAM);
    cursor_move = SDL_CreateSystemCursor(.HAND);
    cursor_resize_ns = SDL_CreateSystemCursor(.SIZENS);
    cursor_resize_ew = SDL_CreateSystemCursor(.SIZEWE);
    cursor_resize_nesw = SDL_CreateSystemCursor(.SIZENESW);
    cursor_resize_nwse = SDL_CreateSystemCursor(.SIZENWSE);

    return true;
}

ImGui_ImplSdl_Shutdown :: () {
    ImGui_ImplDX11_InvalidateDeviceObjects();
    g_pd3dDevice = null;
    g_pd3dDeviceContext = null;
}

ImGui_ImplSdl_NewFrame :: (window: *SDL_Window) {
    if !g_pFontTextureView ImGui_ImplDX11_CreateDeviceObjects();

    io := ImGui.GetIO();

    w, h: s32;
    SDL_GetWindowSize(window, *w, *h);
    io.DisplaySize = .{xx w, xx h};
    io.DisplayFramebufferScale = .{1.0, 1.0};

    frequency := SDL_GetPerformanceFrequency();
    current_time := SDL_GetPerformanceCounter();
    if g_Time > 0 {
        io.DeltaTime = cast(float)((cast(float64)(current_time - g_Time)) / frequency);
    } else {
        io.DeltaTime = (1.0 / 60.0);
    }
    g_Time = current_time;

    mx, my: s32;
    mouseMask := SDL_GetMouseState(*mx, *my);
    if (SDL_GetWindowFlags(window) & SDL_WINDOW_MOUSE_FOCUS) {
        io.MousePos = .{xx mx, xx my};
    } else {
        io.MousePos = .{-FLOAT32_MAX, -FLOAT32_MAX};
    }

    io.MouseDown[0] = (g_MousePressed[0] || (mouseMask & SDL_BUTTON(SDL_BUTTON_LEFT)) != 0);
    io.MouseDown[1] = (g_MousePressed[1] || (mouseMask & SDL_BUTTON(SDL_BUTTON_RIGHT)) != 0);
    io.MouseDown[2] = (g_MousePressed[2] || (mouseMask & SDL_BUTTON(SDL_BUTTON_MIDDLE)) != 0);
    g_MousePressed[0], g_MousePressed[1], g_MousePressed[2] = false, false, false;

    io.MouseWheel = g_MouseWheel;
    g_MouseWheel = 0.0;

    SDL_ShowCursor(xx (io.MouseDrawCursor == false));
}
