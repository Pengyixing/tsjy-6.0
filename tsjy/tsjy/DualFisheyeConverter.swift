import CoreImage
import CoreVideo
import Foundation

final class DualFisheyeConverter {
    private let context = CIContext(options: [
        .cacheIntermediates: false
    ])
    private let roiCallback: CIKernelROICallback = { _, rect in rect }

    private var pixelBufferPool: CVPixelBufferPool?
    private var poolDimensions = CGSize.zero

    func convert(_ pixelBuffer: CVPixelBuffer, settings: PanoramaProjectionSettings) -> CVPixelBuffer? {
        if settings.sourceLayout == .passthrough {
            return pixelBuffer
        }

        let inputImage = CIImage(cvPixelBuffer: pixelBuffer)
        let inputExtent = inputImage.extent
        guard inputExtent.width > 0, inputExtent.height > 0 else { return nil }

        let outputWidth = CGFloat(max(inputExtent.width, inputExtent.height * 2, 1920))
        let outputHeight = outputWidth / 2
        let outputExtent = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)

        guard let outputBuffer = makeOutputBuffer(width: Int(outputWidth), height: Int(outputHeight)) else {
            return nil
        }

        let outputImage: CIImage?
        switch settings.sourceLayout {
        case .passthrough:
            outputImage = inputImage
        case .topBottomFisheye:
            outputImage = Self.topBottomKernel?.apply(
                extent: outputExtent,
                roiCallback: roiCallback,
                arguments: [
                    inputImage,
                    CIVector(x: outputWidth, y: outputHeight)
                ]
            )
        case .sideBySideFisheye:
            outputImage = Self.fisheyeKernel?.apply(
                extent: outputExtent,
                roiCallback: roiCallback,
                arguments: [
                    inputImage,
                    CIVector(x: outputWidth, y: outputHeight)
                ]
            )
        }

        guard let outputImage else { return nil }

        context.render(outputImage, to: outputBuffer, bounds: outputExtent, colorSpace: CGColorSpaceCreateDeviceRGB())
        return outputBuffer
    }

    private func makeOutputBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let dimensions = CGSize(width: width, height: height)
        if pixelBufferPool == nil || poolDimensions != dimensions {
            pixelBufferPool = nil
            poolDimensions = dimensions
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true
            ]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pixelBufferPool)
        }

        guard let pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
        return pixelBuffer
    }

    private static let fisheyeKernel: CIKernel? = {
        let source = """
        vec4 sampleLens(sampler image, vec2 center, float radius, vec3 direction, float yaw) {
            float c = cos(yaw);
            float s = sin(yaw);
            vec3 rotated = vec3(direction.x * c - direction.z * s,
                                direction.y,
                                direction.x * s + direction.z * c);

            float theta = acos(clamp(rotated.z, -1.0, 1.0));
            float lensRadius = radius * theta / 1.57079632679;
            float azimuth = atan(rotated.y, rotated.x);
            vec2 samplePoint = vec2(center.x + lensRadius * cos(azimuth),
                                    center.y - lensRadius * sin(azimuth));

            if (distance(samplePoint, center) > radius) {
                return vec4(0.0);
            }

            return sample(image, samplerTransform(image, samplePoint));
        }

        kernel vec4 dualFisheyeToEquirect(
            sampler image,
            vec2 outputSize
        ) {
            vec2 dc = destCoord();
            float u = dc.x / outputSize.x;
            float v = dc.y / outputSize.y;

            float lon = (u - 0.5) * 6.28318530718;
            float lat = (0.5 - v) * 3.14159265359;

            vec3 world = vec3(cos(lat) * sin(lon),
                              sin(lat),
                              cos(lat) * cos(lon));

            vec3 backWorld = vec3(-world.x, world.y, -world.z);
            
            // Hardcode standard side-by-side centers and radius
            float r = min(outputSize.x * 0.25, outputSize.y * 0.5) * 0.94;
            vec2 fc = vec2(outputSize.x * 0.25, outputSize.y * 0.5);
            vec2 bc = vec2(outputSize.x * 0.75, outputSize.y * 0.5);

            vec4 front = sampleLens(image, fc, r, world, 0.0);
            vec4 back = sampleLens(image, bc, r, backWorld, 0.0);

            if (front.a < 0.001) { return back; }
            if (back.a < 0.001) { return front; }

            float blend = smoothstep(-0.02, 0.02, world.z);
            return mix(back, front, blend);
        }
        """
        return CIKernel(source: source)
    }()

    private static let topBottomKernel: CIKernel? = {
        let source = """
        float wrapPi(float value) {
            float twoPi = 6.28318530718;
            float shifted = value + 3.14159265359;
            shifted = shifted - floor(shifted / twoPi) * twoPi;
            return shifted - 3.14159265359;
        }

        vec4 sampleHalf(sampler image, float unitU, float unitV, float yOffset) {
            vec2 size = samplerSize(image);
            float width = size.x;
            float halfHeight = size.y * 0.5;

            float x = clamp(unitU, 0.0, 1.0) * (width - 1.0);
            float y = clamp(unitV, 0.0, 1.0) * (halfHeight - 1.0) + yOffset * size.y;

            vec2 point = vec2(clamp(x, 0.0, width - 1.0), clamp(y, 0.0, size.y - 1.0));
            return sample(image, samplerTransform(image, point));
        }

        kernel vec4 topBottomToEquirect(
            sampler image,
            vec2 outputSize
        ) {
            vec2 dc = destCoord();
            float u = dc.x / outputSize.x;
            float v = dc.y / outputSize.y;

            float lon = (u - 0.5) * 6.28318530718;
            float lat = (0.5 - v) * 3.14159265359;

            vec3 world = vec3(cos(lat) * sin(lon),
                              sin(lat),
                              cos(lat) * cos(lon));

            float seamWidth = 0.03;
            float halfHFOV = 1.57079632679;

            float frontLon = wrapPi(lon);
            float backLon = wrapPi(lon - 3.14159265359);

            float frontWeight = 1.0 - smoothstep(halfHFOV - seamWidth, halfHFOV + seamWidth, abs(frontLon));
            float backWeight = 1.0 - smoothstep(halfHFOV - seamWidth, halfHFOV + seamWidth, abs(backLon));

            float frontU = frontLon / 3.14159265359 + 0.5;
            float backU = backLon / 3.14159265359 + 0.5;

            // Use sphere-space Y instead of linear latitude so top and bottom wrap as a sphere,
            // avoiding the cylindrical stretch caused by forcing each half into a flat band.
            float frontV = 0.5 - world.y * 0.5;
            float backV = 0.5 - world.y * 0.5;

            vec4 front = sampleHalf(image, frontU, frontV, 0.0);
            vec4 back = sampleHalf(image, backU, backV, 0.5);

            if (frontWeight < 0.001 && backWeight < 0.001) {
                return vec4(0.0);
            }
            float total = max(frontWeight + backWeight, 0.0001);
            return (front * frontWeight + back * backWeight) / total;
        }
        """
        return CIKernel(source: source)
    }()
}
