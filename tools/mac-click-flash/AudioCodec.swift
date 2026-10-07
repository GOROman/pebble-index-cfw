import Foundation

enum AudioCodec {
    static let sampleRate = 8000
    static let maxSamples = 49152
    static let steps = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
        253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
        1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
        3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
        12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
    ]
    static let indices = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

    enum Failure: Error { case invalidLength }

    // The firmware starts predictor/index at zero and sends the low nibble first.
    static func wav(adpcm: Data, samples: Int) throws -> Data {
        guard samples > 0, samples <= maxSamples, adpcm.count == (samples + 1) / 2 else {
            throw Failure.invalidLength
        }
        let bytes = Array(adpcm)
        var pcm = Data(capacity: samples * 2)
        var predictor = 0
        var index = 0
        for i in 0..<samples {
            let byte = Int(bytes[i / 2])
            let code = i % 2 == 0 ? byte & 15 : byte >> 4
            let step = steps[index]
            var delta = step >> 3
            if code & 4 != 0 { delta += step }
            if code & 2 != 0 { delta += step >> 1 }
            if code & 1 != 0 { delta += step >> 2 }
            predictor = max(-32768, min(32767, predictor + (code & 8 != 0 ? -delta : delta)))
            index = max(0, min(88, index + indices[code]))
            append16(UInt16(bitPattern: Int16(predictor)), to: &pcm)
        }
        var output = Data("RIFF".utf8)
        append32(UInt32(36 + pcm.count), to: &output)
        output.append(Data("WAVEfmt ".utf8))
        append32(16, to: &output)
        append16(1, to: &output) // PCM
        append16(1, to: &output) // mono
        append32(UInt32(sampleRate), to: &output)
        append32(UInt32(sampleRate * 2), to: &output)
        append16(2, to: &output)
        append16(16, to: &output)
        output.append(Data("data".utf8))
        append32(UInt32(pcm.count), to: &output)
        output.append(pcm)
        return output
    }

    private static func append16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8(value >> 8))
    }

    private static func append32(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> shift) & 0xff)) }
    }
}
