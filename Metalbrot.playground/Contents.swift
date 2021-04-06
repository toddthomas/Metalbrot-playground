import MetalKit
import PlaygroundSupport

guard let device = MTLCreateSystemDefaultDevice() else {
  fatalError("Unable to access a GPU.")
}
print(device.name)

let frame = CGRect(x: 0, y: 0, width: 800, height: 800)
let metalView = MTKView(frame: frame, device: device)

struct ViewParams {
  let minimumReal: Float
  let maximumImaginary: Float
  let horizontalStride: Float
  let verticalStride: Float
}

let lowerLeft = simd_float2(x: -2.0, y: -1.25)
let upperRight = simd_float2(x: 0.5, y: 1.25)
var viewParams = ViewParams(
  minimumReal: lowerLeft.x,
  maximumImaginary: upperRight.y,
  horizontalStride: (upperRight.x - lowerLeft.x) / Float(frame.width),
  verticalStride: (upperRight.y - lowerLeft.y) / Float(frame.height)
)
print(viewParams)

let positions: [simd_float4] = [
  simd_float4(-1.0, 1.0, 0.0, 1.0),
  simd_float4(1.0, 1.0, 0.0, 1.0),
  simd_float4(-1.0, -1.0, 0.0, 1.0),
  simd_float4(1.0, 1.0, 0.0, 1.0),
  simd_float4(1.0, -1.0, 0.0, 1.0),
  simd_float4(-1.0, -1.0, 0.0, 1.0)
]

let shaders = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
  float4 position [[position]];
};

[[vertex]] VertexOut
vertex_main(
  device const float4 * const positionList [[buffer(0)]],
  const uint vertexId [[vertex_id]]
) {
  VertexOut out {
    .position = positionList[vertexId],
  };
  return out;
}

struct ViewParams {
  float minimumReal;
  float maximumImaginary;
  float horizontalStride;
  float verticalStride;
};

[[fragment]] float4
fragment_main(
  const VertexOut in [[stage_in]],
  constant ViewParams &viewParams [[buffer(1)]]
) {
  const float2 c = float2(
    viewParams.minimumReal + in.position.x * viewParams.horizontalStride,
    viewParams.maximumImaginary - in.position.y * viewParams.verticalStride
  );

  float2 z = float2(0, 0);
  const uint maxIterations = 60;
  uint i = 0;

  while (i < maxIterations) {
    float2 zSquared = float2(z.x*z.x - z.y*z.y, z.x*z.y + z.y*z.x);
    z.x = zSquared.x + c.x;
    z.y = zSquared.y + c.y;
    ++i;
    if ((z.x*z.x + z.y*z.y) > 4.0f) {
      break;
    }
  }

  if (i >= maxIterations) {
    return float4(0, 0, 0, 1);
  } else {
    float normalized = float(i) / (maxIterations - 1);
    return float4(normalized, normalized, normalized, 1);
  }
}
"""

let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

let library = try! device.makeLibrary(source: shaders, options: nil)
let vertexFunction = library.makeFunction(name: "vertex_main")
let fragmentFunction = library.makeFunction(name: "fragment_main")
pipelineStateDescriptor.vertexFunction = vertexFunction
pipelineStateDescriptor.fragmentFunction = fragmentFunction

let pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
guard let commandQueue = device.makeCommandQueue(),
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let descriptor = metalView.currentRenderPassDescriptor,
      let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
      let drawable = metalView.currentDrawable else {
  fatalError("Problem setting up to draw a frame.")
}

commandEncoder.setRenderPipelineState(pipelineState)

let positionLength = MemoryLayout<simd_float4>.stride * positions.count
let positionBuffer = device.makeBuffer(bytes: positions, length: positionLength, options: [])!
commandEncoder.setVertexBuffer(positionBuffer, offset: 0, index: 0)
commandEncoder.setFragmentBytes(&viewParams, length: MemoryLayout<ViewParams>.stride, index: 1)
commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: positions.count)

commandEncoder.endEncoding()

commandBuffer.present(drawable)
commandBuffer.commit()

PlaygroundPage.current.liveView = metalView
