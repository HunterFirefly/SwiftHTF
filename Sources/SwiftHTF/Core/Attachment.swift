import Foundation

/// Phase 期间产生的二进制附件（截图、原始日志、波形 CSV、抓包等）。
///
/// 内容以 `Data` 内嵌存储；JSON 编码时 `data` 字段自动 base64 编码，
/// 便于直接落盘 / 上传。后续若引入 sidecar 文件落盘策略，会扩展为可选的外部引用。
public struct Attachment: Sendable, Codable, Equatable {
    public let name: String
    public let mimeType: String
    public let data: Data
    public let timestamp: Date

    public init(
        name: String,
        mimeType: String,
        data: Data,
        timestamp: Date = Date()
    ) {
        self.name = name
        self.mimeType = mimeType
        self.data = data
        self.timestamp = timestamp
    }

    /// 字节数（便于输出层显示，不参与 Codable）
    public var size: Int { data.count }
}

// MARK: - 文件扩展名 → MIME 推断

extension Attachment {
    /// 从文件扩展名推断 MIME；未知返回 `application/octet-stream`。
    public static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        case "pdf": return "application/pdf"
        case "txt", "log": return "text/plain"
        case "csv": return "text/csv"
        case "json": return "application/json"
        case "xml": return "application/xml"
        case "html", "htm": return "text/html"
        case "zip": return "application/zip"
        default: return "application/octet-stream"
        }
    }
}
