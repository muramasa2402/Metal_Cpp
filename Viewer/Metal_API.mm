#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <MetalKit/MetalKit.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import "include/Metal_API.h"
using namespace mtl_cpp;

void MetalObject::_free() {
    if (_ptr) CFRelease(_ptr);
    _ptr = nullptr;
}

void Buffer::flush(int start, int length) {
    if (mode_ == Managed && _ptr) {
        id <MTLBuffer> b = (__bridge id <MTLBuffer>)(_ptr);
        NSUInteger l = (length == -1 ? length_ : length);
        if (start < 0 || start > length_ || l + start > length_ || l < 0) {
            @throw [NSException
                    exceptionWithName:@"IndexOutOfBounds"
                    reason:@"Range to flush is out of bounds"
                    userInfo:nil];
        }
        [b didModifyRange:NSMakeRange(start, l)];
    }
}

Metal_API* Metal_API::_context = nullptr;
bool Metal_API::_assigned = false;

Metal_API::Metal_API() {
    if (_assigned) {
        throw std::runtime_error("Metal_API can only be constructed once");
    }
    _context = this;
    _assigned = true;
}

Metal_API::~Metal_API()  { _context = nullptr; }

void Metal_API::terminateContext() {
    _context = nullptr;
}

void Metal_API::initialize(void* view) {
    if (_context) _context->onInitialize(view);
}

void Metal_API::draw(void* view) {
    if (_context) _context->onDraw(view);
}

void Metal_API::resize(void *view, unsigned long const size[2]) {
    if (_context) _context->onSizeChange(view, size);
}

Device Metal_API::getDevice() {
    @autoreleasepool {
        auto d = MTLCreateSystemDefaultDevice();
        auto ptr = (void*)CFBridgingRetain(d);
        return Device(ptr);
    }
}

CommandQueue Metal_API::createCommandQueue(Device const& device) {
    @autoreleasepool {
        auto cq = [(__bridge id <MTLDevice>)(device._ptr) newCommandQueue];
        auto ptr = (void*)CFBridgingRetain(cq);
        return CommandQueue(ptr);
    }
}

Library Metal_API::compileLibrary(Device const& device, char const* code, bool fast_math) {
    NSError* error = nil;
    MTLCompileOptions* opt = [[MTLCompileOptions alloc] init];
    opt.fastMathEnabled = fast_math;
    opt.languageVersion = MTLLanguageVersion2_2;
    id <MTLLibrary> lib = [(__bridge id <MTLDevice>)(device._ptr)
                           newLibraryWithSource:[NSString stringWithUTF8String:code]
                           options:opt
                           error:&error];
    if (error) { NSLog(@"%@", error); exit(-1); }
    auto ptr = (void*)CFBridgingRetain(lib);
    return Library(ptr);
}

Function Metal_API::getFunction(char const* kernel_name, Library const& library) {
    id <MTLFunction> func = [(__bridge id <MTLLibrary>)(library._ptr)
                             newFunctionWithName:[NSString stringWithUTF8String:kernel_name]];
    auto ptr = (void*)CFBridgingRetain(func);
    return Function(ptr);
}

CommandBuffer Metal_API::getCommandBuffer(CommandQueue const& queue) {
    id <MTLCommandBuffer> buf = [(__bridge id <MTLCommandQueue>)(queue._ptr) commandBuffer];
    auto ptr = (void*)CFBridgingRetain(buf);
    return CommandBuffer(ptr);
}

ComputePipelineState Metal_API::createComputeState(Device const& device, Function const& kernel) {
    @autoreleasepool {
        NSError* error = nil;
        id <MTLComputePipelineState> state = [(__bridge id <MTLDevice>)(device._ptr)
                                              newComputePipelineStateWithFunction:
                                              (__bridge id <MTLFunction>)(kernel._ptr)
                                              error:&error];
        if (error) { NSLog(@"%@", error); exit(-1); }
        auto ptr = (void*)CFBridgingRetain(state);
        return ComputePipelineState(ptr);
    }
}

RenderPipelineState Metal_API::createRenderState(void* view,
                                                 Library const& library,
                                                 Device const& device,
                                                 unsigned long samples,
                                                 char const* vertex,
                                                 char const* fragment) {
    @autoreleasepool {
        NSError* error = nil;
        auto lib = (__bridge id <MTLLibrary>)(library._ptr);
        auto v = (__bridge MTKView*)(view);
        MTLRenderPipelineDescriptor* desc = [[MTLRenderPipelineDescriptor alloc] init];
        desc.vertexFunction = [lib
                               newFunctionWithName:[NSString stringWithUTF8String:vertex]];
        desc.fragmentFunction = [lib
                                 newFunctionWithName:[NSString stringWithUTF8String:fragment]];
        
        desc.colorAttachments[0].pixelFormat = v.colorPixelFormat;
        desc.colorAttachments[0].blendingEnabled = true;
        desc.sampleCount = samples;
        
        desc.colorAttachments[0].rgbBlendOperation =    MTLBlendOperationAdd;
        desc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
        desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
        
        desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        desc.depthAttachmentPixelFormat = v.depthStencilPixelFormat;
        
        id <MTLRenderPipelineState> state = [(__bridge id <MTLDevice>)(device._ptr)
                                             newRenderPipelineStateWithDescriptor:desc
                                             error:&error];
        if (error) { NSLog(@"Failed to created pipeline state, error %@", error); }
        auto ptr = (void*)CFBridgingRetain(state);
        return RenderPipelineState(ptr);
    }
}


ComputeCommandEncoder Metal_API::getComputeCommandEncoder(CommandBuffer const& buffer, DispatchType mode) {
    id<MTLComputeCommandEncoder> encoder = [(__bridge id<MTLCommandBuffer>)(buffer._ptr)
                                            computeCommandEncoder];
    auto ptr = (void*)CFBridgingRetain(encoder);
    return ComputeCommandEncoder(ptr);
}

RenderCommandEncoder Metal_API::getRenderCommandEncoder(void* view,
                                                        CommandBuffer const& buffer,
                                                        Texture const &texture,
                                                        int const samples,
                                                        float const* sample_pos[]) {
    @autoreleasepool {
        auto v = (__bridge MTKView*)(view);
        auto rpd = v.currentRenderPassDescriptor;
        rpd.colorAttachments[0].texture = (__bridge id<MTLTexture>)(texture._ptr);
        rpd.colorAttachments[0].resolveTexture = v.currentDrawable.texture;
        rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
        rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
        rpd.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
        if (!sample_pos)  {
            MTLSamplePosition samplePositions[4];
            float const pos[4][2] = {{0.25,0.75},{0.75,0.75},{0.25,0.25},{0.75,0.25}};
            for (int i = 0; i < 4; ++i)
                samplePositions[i] = MTLSamplePositionMake(pos[i][0], pos[i][1]);
            [rpd setSamplePositions:samplePositions count:4];
        } else {
            MTLSamplePosition samplePositions[samples];
            for (int i = 0; i < samples; ++i)
                samplePositions[i] = MTLSamplePositionMake(sample_pos[i][0], sample_pos[i][1]);
            [rpd setSamplePositions:samplePositions count:samples];
        }
        auto encoder = [(__bridge id<MTLCommandBuffer>)(buffer._ptr)
                        renderCommandEncoderWithDescriptor:rpd];
        auto ptr = (void*)CFBridgingRetain(encoder);
        return RenderCommandEncoder(ptr);
    }
}

BlitCommandEncoder Metal_API::getBlitCommandEncoder(CommandBuffer const& buffer) {
    auto encoder = [(__bridge id<MTLCommandBuffer>)(buffer._ptr) blitCommandEncoder];
    auto ptr = (void*)CFBridgingRetain(encoder);
    return BlitCommandEncoder(ptr);
}

void Metal_API::setState(RenderCommandEncoder const& encoder, RenderPipelineState const &state) {
    [(__bridge id<MTLRenderCommandEncoder>)(encoder._ptr)
     setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)(state._ptr)];
}
void Metal_API::setState(ComputeCommandEncoder const& encoder, ComputePipelineState const &state) {
    [(__bridge id<MTLComputeCommandEncoder>)(encoder._ptr)
     setComputePipelineState:(__bridge id<MTLComputePipelineState>)(state._ptr)];
}

void Metal_API::endEncoding(ComputeCommandEncoder &encoder) {
    [(__bridge id<MTLComputeCommandEncoder>)(encoder._ptr) endEncoding];
    encoder._free();
}

void Metal_API::endEncoding(RenderCommandEncoder &encoder) {
    [(__bridge id<MTLRenderCommandEncoder>)(encoder._ptr) endEncoding];
    encoder._free();
}

void Metal_API::dispatchThreads(ComputeCommandEncoder const &encoder,
                                unsigned long const global_dim[3],
                                unsigned long const local_dim[3]) {
    [(__bridge id<MTLComputeCommandEncoder>)(encoder._ptr)
     dispatchThreads:MTLSizeMake(global_dim[0], global_dim[1], global_dim[2])
     threadsPerThreadgroup:MTLSizeMake(local_dim[0], local_dim[1], local_dim[2])];
}

unsigned long Metal_API::maxBlockSize(ComputePipelineState const& state) {
    return [(__bridge id<MTLComputePipelineState>)(state._ptr) maxTotalThreadsPerThreadgroup];
}
unsigned long Metal_API::maxWarpSize(ComputePipelineState const& state) {
    return [(__bridge id<MTLComputePipelineState>)(state._ptr) threadExecutionWidth];
}

void Metal_API::bufferToBuffer(BlitCommandEncoder const& encoder,
                               Buffer const& src, unsigned long src_offset,
                               Buffer const& dst, unsigned long dst_offset, unsigned long size) {
    [(__bridge id<MTLBlitCommandEncoder>)(encoder._ptr)
     copyFromBuffer:(__bridge id<MTLBuffer>)(src._ptr)
     sourceOffset:src_offset
     toBuffer:(__bridge id<MTLBuffer>)(dst._ptr)
     destinationOffset:dst_offset
     size:size];
}
void Metal_API::setBuffer(BlitCommandEncoder const& encoder,
                          Buffer const& buffer, unsigned long start,
                          unsigned long size, unsigned char byte) {
    [(__bridge id<MTLBlitCommandEncoder>)(encoder._ptr)
     fillBuffer:(__bridge id<MTLBuffer>)(buffer._ptr)
     range:NSMakeRange(start, size)
     value:byte];
}
void Metal_API::syncResource(BlitCommandEncoder const& encoder, Buffer const& resource) {
    [(__bridge id<MTLBlitCommandEncoder>)(encoder._ptr)
     synchronizeResource:(__bridge id<MTLBuffer>)(resource._ptr)];
}

void Metal_API::syncResource(BlitCommandEncoder const& encoder, Texture const& resource) {
    [(__bridge id<MTLBlitCommandEncoder>)(encoder._ptr)
     synchronizeResource:(__bridge id<MTLTexture>)(resource._ptr)];
}

Buffer Metal_API::mallocBuffer(Device const &device, void const* data,
                               unsigned long size, ResourceOptions mode) {
    if (mode == Private) {
        @throw [NSException
                exceptionWithName:@"InvalidArgument"
                reason:@"Cannot initialize private buffer"
                userInfo:nil];
    }
    id <MTLBuffer> buf = [(__bridge id <MTLDevice>)(device._ptr)
                          newBufferWithBytes:data
                          length:size
                          options:GetEnum<ResourceOptions, MTLResourceOptions>(mode)];
    auto ptr = (void*)CFBridgingRetain(buf);
    return Buffer(ptr, [buf contents], size, mode);
}

Buffer Metal_API::mallocBuffer(Device const &device, unsigned long size, ResourceOptions mode) {
    id <MTLBuffer> buf = [(__bridge id <MTLDevice>)(device._ptr)
                          newBufferWithLength:size
                          options:GetEnum<ResourceOptions, MTLResourceOptions>(mode)];
    auto ptr = (void*)CFBridgingRetain(buf);
    return Buffer(ptr, mode == Private ? nullptr : [buf contents], size, mode);
}

Texture Metal_API::createMultiSamplingTexture(void* view, Device const& device, unsigned long width, unsigned long height, unsigned long samples) {
    @autoreleasepool {
        auto v = (__bridge MTKView*)(view);
        MTLTextureDescriptor* tex = [[MTLTextureDescriptor alloc] init];
        tex.textureType = MTLTextureType2DMultisampleArray;
        tex.width = width;
        tex.height = height;
        tex.sampleCount = samples;
        tex.pixelFormat = v.colorPixelFormat;
        tex.usage = MTLTextureUsageRenderTarget;
        tex.storageMode = MTLStorageModePrivate;
        auto texture = [(__bridge id <MTLDevice>)(device._ptr) newTextureWithDescriptor:tex];
        auto ptr = (void*)CFBridgingRetain(texture);
        return Texture(ptr);
    }
}

void Metal_API::setComputeBuffer(ComputeCommandEncoder const& encoder, Buffer const &buffer, unsigned long offset, unsigned long index) {
    [(__bridge id<MTLComputeCommandEncoder>)(encoder._ptr)
     setBuffer: (__bridge id<MTLBuffer>)(buffer._ptr)
     offset:offset atIndex:index];
}

void Metal_API::setBytes(ComputeCommandEncoder const& encoder, void const* data,
                         unsigned long size, unsigned long index) {
    [(__bridge id<MTLComputeCommandEncoder>)(encoder._ptr) setBytes:data length:size atIndex:index];
}

void Metal_API::setVertexBuffer(RenderCommandEncoder const& encoder, Buffer const &buffer, unsigned long offset, unsigned long index) {
    [(__bridge id<MTLRenderCommandEncoder>)(encoder._ptr)
     setVertexBuffer: (__bridge id<MTLBuffer>)(buffer._ptr)
     offset:offset atIndex:index];
}

void Metal_API::setFragmentBuffer(RenderCommandEncoder const& encoder, Buffer const &buffer, unsigned long offset, unsigned long index) {
    [(__bridge id<MTLRenderCommandEncoder>)(encoder._ptr)
     setFragmentBuffer: (__bridge id<MTLBuffer>)(buffer._ptr)
     offset:offset atIndex:index];
}

void Metal_API::mallocSharedMemory(const ComputeCommandEncoder &encoder, unsigned long size, unsigned long index) {
    [(__bridge id<MTLComputeCommandEncoder>)(encoder._ptr) setThreadgroupMemoryLength:size
                                                                              atIndex:index];
}

double Metal_API::getTime() { return CACurrentMediaTime(); }

void Metal_API::addCompletionHandler(CommandBuffer const& command_buffer,
                                     std::function<void()> on_complete) {
    __block std::function<void()> func = std::move(on_complete);
    [(__bridge id <MTLCommandBuffer>)(command_buffer._ptr)
     addCompletedHandler:^(id<MTLCommandBuffer> _Nullable) {
        func();
    }];
}

void Metal_API::addScheduleHandler(CommandBuffer const& command_buffer,
                                   std::function<void()> on_schedule) {
    __block std::function<void()> func = std::move(on_schedule);
    [(__bridge id <MTLCommandBuffer>)(command_buffer._ptr)
     addCompletedHandler:^(id<MTLCommandBuffer> _Nullable) {
        func();
    }];
}

void Metal_API::presentDrawable(void* view, CommandBuffer const& command_buffer, double at_time) {
    auto v = (__bridge MTKView*)(view);
    [(__bridge id <MTLCommandBuffer>)(command_buffer._ptr)
     presentDrawable:v.currentDrawable atTime:at_time];
}

void Metal_API::commitCommandBuffer(CommandBuffer const& command_buffer) {
    [(__bridge id <MTLCommandBuffer>)(command_buffer._ptr) commit];
}

void Metal_API::waitUntilScheduled(CommandBuffer const&buffer) {
    [(__bridge id <MTLCommandBuffer>)(buffer._ptr) waitUntilScheduled];
}
void Metal_API::waitUntilCompleted(CommandBuffer const&buffer) {
    [(__bridge id <MTLCommandBuffer>)(buffer._ptr) waitUntilCompleted];
}
#define ULONG unsigned long
void Metal_API::drawMesh(RenderCommandEncoder const& encoder, PrimitiveType type, ULONG vert_start, ULONG vert_count, ULONG instances, ULONG instance_base) {
    auto enc = (__bridge id<MTLRenderCommandEncoder>)(encoder._ptr);
    
    [enc drawPrimitives:GetEnum<PrimitiveType, MTLPrimitiveType>(type)
            vertexStart:vert_start
            vertexCount:vert_count
          instanceCount:instances
           baseInstance:instance_base];
    
}
void Metal_API::drawMesh(RenderCommandEncoder const& encoder, PrimitiveType type, ULONG idx_count, IndexType idx_type, Buffer const& idx, ULONG idx_offset, ULONG instances, ULONG vert_base, ULONG instance_base) {
    auto enc = (__bridge id<MTLRenderCommandEncoder>)(encoder._ptr);
    auto indices = (__bridge id<MTLBuffer>)(idx._ptr);
    [enc drawIndexedPrimitives:GetEnum<PrimitiveType, MTLPrimitiveType>(type)
                    indexCount:idx_count
                     indexType:GetEnum<IndexType, MTLIndexType>(idx_type)
                   indexBuffer:indices
             indexBufferOffset:idx_offset
                 instanceCount:instances
                    baseVertex:vert_base
                  baseInstance:instance_base];
    
}
#undef ULONG
