import Foundation
import zlib

extension Data {
    /// 針對 Node.js zlib.gzipSync 產生的數據進行解壓縮
    func gunzipped() -> Data? {
        guard !self.isEmpty else { return nil }
        
        var stream = z_stream()
        var status: Int32
        
        // 16 + 15 = 31: Enable gzip decoding and automatic header detection
        status = inflateInit2_(&stream, 31, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
        
        guard status == Z_OK else { return nil }
        
        var data = Data(capacity: self.count * 2)
        let chunk = 16384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer {
            buffer.deallocate()
            inflateEnd(&stream)
        }
        
        self.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: baseAddress)
            stream.avail_in = uInt(bytes.count)
            
            repeat {
                stream.next_out = buffer
                stream.avail_out = uInt(chunk)
                
                status = inflate(&stream, Z_NO_FLUSH)
                
                if status != Z_OK && status != Z_STREAM_END {
                    break
                }
                
                let count = chunk - Int(stream.avail_out)
                if count > 0 {
                    data.append(buffer, count: count)
                }
            } while status == Z_OK
        }
        
        return status == Z_STREAM_END ? data : nil
    }
    
    func gzipped() -> Data? {
        guard !self.isEmpty else { return nil }
        
        var stream = z_stream()
        
        // 31 = 15 + 16 (GZIP format)
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        
        var data = Data(capacity: 16384)
        let chunk = 16384
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer {
            buffer.deallocate()
            deflateEnd(&stream)
        }
        
        return self.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Data? in
            guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer<UInt8>(mutating: baseAddress)
            stream.avail_in = uInt(bytes.count)
            
            var status: Int32
            repeat {
                stream.next_out = buffer
                stream.avail_out = uInt(chunk)
                
                status = deflate(&stream, Z_FINISH)
                
                let count = chunk - Int(stream.avail_out)
                if count > 0 {
                    data.append(buffer, count: count)
                }
            } while status == Z_OK
            
            return status == Z_STREAM_END ? data : nil
        }
    }
}

extension String {
    /// 清理 Base64 字串中可能存在的非法字元 (如換行或空白)
    func cleanBase64() -> String {
    // 僅保留 A-Z, a-z, 0-9, +, /, = 這些 Base64 標準字元
        return self.components(separatedBy: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=").inverted)
            .joined()
    }
}
