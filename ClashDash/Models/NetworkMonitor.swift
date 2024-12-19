import Foundation
import SwiftUI

class NetworkMonitor: ObservableObject {
    @Published var uploadSpeed: String = "0 B/s"
    @Published var downloadSpeed: String = "0 B/s"
    @Published var totalUpload = "0 MB"
    @Published var totalDownload = "0 MB"
    @Published var activeConnections = 0
    @Published var memoryUsage = "0 MB"
    @Published var speedHistory: [SpeedRecord] = []
    @Published var memoryHistory: [MemoryRecord] = []
    
    private var trafficTask: URLSessionWebSocketTask?
    private var memoryTask: URLSessionWebSocketTask?
    private var connectionsTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var server: ClashServer?
    private var isConnected = [ConnectionType: Bool]()
    private var isMonitoring = false
    private var isViewActive = false
    private var activeView: String = ""
    
    private enum ConnectionType: String {
        case traffic = "Traffic"
        case memory = "Memory"
        case connections = "Connections"
    }
    
    func startMonitoring(server: ClashServer, viewId: String = "overview") {
        self.server = server
        self.activeView = viewId
        isViewActive = true
        
        if !isMonitoring {
            isMonitoring = true
            connectToTraffic(server: server)
            connectToConnections(server: server)
            
            if server.serverType == .meta {
                connectToMemory(server: server)
            } else {
                DispatchQueue.main.async {
                    self.memoryUsage = "N/A"
                }
            }
        }
    }
    
    func pauseMonitoring() {
        isViewActive = false
        print("暂停监控")
    }
    
    func resumeMonitoring() {
        guard let server = server else { return }
        isViewActive = true
        print("恢复监控")
        
        if !isConnected[.traffic, default: false] {
            connectToTraffic(server: server)
        }
        if !isConnected[.connections, default: false] {
            connectToConnections(server: server)
        }
        
        if server.serverType == .meta && !isConnected[.memory, default: false] {
            connectToMemory(server: server)
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        isViewActive = false
        activeView = ""
        
        trafficTask?.cancel(with: .goingAway, reason: nil)
        connectionsTask?.cancel(with: .goingAway, reason: nil)
        
        if server?.serverType == .meta {
            memoryTask?.cancel(with: .goingAway, reason: nil)
        }
        
        isConnected.removeAll()
        server = nil
    }
    
    private func getWebSocketURL(for path: String, server: ClashServer) -> URL? {
        let scheme = server.useSSL ? "wss" : "ws"
        let urlString = "\(scheme)://\(server.url):\(server.port)/\(path)"
        return URL(string: urlString)
    }
    
    private func connectToTraffic(server: ClashServer) {
        guard let url = getWebSocketURL(for: "traffic", server: server) else { return }
        guard !isConnected[.traffic, default: false] else { return }
        
        print("正在连接 Traffic WebSocket (\(url.absoluteString))...")
        
        var request = URLRequest(url: url)
        if !server.secret.isEmpty {
            request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        }
        
        trafficTask = session.webSocketTask(with: request)
        trafficTask?.resume()
        receiveTrafficData()
    }
    
    private func connectToMemory(server: ClashServer) {
        guard let url = getWebSocketURL(for: "memory", server: server) else { return }
        guard !isConnected[.memory, default: false] else { return }
        
        print("正在连接 Memory WebSocket (\(url.absoluteString))...")
        
        var request = URLRequest(url: url)
        if !server.secret.isEmpty {
            request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        }
        
        memoryTask = session.webSocketTask(with: request)
        memoryTask?.resume()
        receiveMemoryData()
    }
    
    private func connectToConnections(server: ClashServer) {
        guard let url = getWebSocketURL(for: "connections", server: server) else { return }
        guard !isConnected[.connections, default: false] else { return }
        
        print("正在连接 Connections WebSocket (\(url.absoluteString))...")
        
        var request = URLRequest(url: url)
        if !server.secret.isEmpty {
            request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        }
        
        connectionsTask = session.webSocketTask(with: request)
        connectionsTask?.resume()
        receiveConnectionsData()
    }
    
    private func handleWebSocketError(_ error: Error, type: ConnectionType) {
        print("\(type.rawValue) WebSocket 错误: \(error.localizedDescription)")
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .secureConnectionFailed, .serverCertificateHasBadDate,
                 .serverCertificateUntrusted, .serverCertificateNotYetValid:
                print("SSL/TLS 错误: \(urlError.localizedDescription)")
            case .notConnectedToInternet:
                print("网络连接已断开")
            default:
                print("其他错误: \(urlError.localizedDescription)")
            }
        }
        
        isConnected[type] = false
        retryConnection(type: type)
    }
    
    private func receiveTrafficData() {
        trafficTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                if !self.isConnected[.traffic, default: false] {
                    print("Traffic WebSocket 已连接")
                    self.isConnected[.traffic] = true
                }
                
                switch message {
                case .string(let text):
                    self.handleTrafficData(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleTrafficData(text)
                    }
                @unknown default:
                    break
                }
                self.receiveTrafficData() // 继续接收数据
                
            case .failure(let error):
                self.handleWebSocketError(error, type: .traffic)
            }
        }
    }
    
    private func receiveMemoryData() {
        memoryTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                if !self.isConnected[.memory, default: false] {
                    print("Memory WebSocket 已连接")
                    self.isConnected[.memory] = true
                }
                
                switch message {
                case .string(let text):
                    self.handleMemoryData(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMemoryData(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMemoryData() // 继续接收数据
                
            case .failure(let error):
                self.handleWebSocketError(error, type: .memory)
            }
        }
    }
    
    private func receiveConnectionsData() {
        connectionsTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                if !self.isConnected[.connections, default: false] {
                    print("Connections WebSocket 已连接")
                    self.isConnected[.connections] = true
                }
                
                switch message {
                case .string(let text):
                    self.handleConnectionsData(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleConnectionsData(text)
                    }
                @unknown default:
                    break
                }
                self.receiveConnectionsData() // 继续接收数据
                
            case .failure(let error):
                self.handleWebSocketError(error, type: .connections)
            }
        }
    }
    
    private func handleTrafficData(_ text: String) {
        guard let data = text.data(using: .utf8),
              let traffic = try? JSONDecoder().decode(TrafficData.self, from: data) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.updateTraffic(traffic)
        }
    }
    
    private func updateTraffic(_ traffic: TrafficData) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 更新速度显示
            self.uploadSpeed = formatSpeed(traffic.up)
            self.downloadSpeed = formatSpeed(traffic.down)
            
            // 创建新记录
            let record = SpeedRecord(
                timestamp: Date(),
                upload: Double(traffic.up),
                download: Double(traffic.down)
            )
            
            // 确保历史记录不会无限增长
            if self.speedHistory.count > 30 {
                self.speedHistory.removeFirst()
            }
            
            // 添加新记录并进行平滑处理
            if !self.speedHistory.isEmpty {
                let lastRecord = self.speedHistory.last!
                
                // 计算平滑值
                let smoothingFactor = 0.1 // 平滑系数，可以根据需要调整
                let smoothedUpload = lastRecord.upload * (1 - smoothingFactor) + Double(traffic.up) * smoothingFactor
                let smoothedDownload = lastRecord.download * (1 - smoothingFactor) + Double(traffic.down) * smoothingFactor
                
                // 创建平滑后的记录
                let smoothedRecord = SpeedRecord(
                    timestamp: Date(),
                    upload: smoothedUpload,
                    download: smoothedDownload
                )
                
                self.speedHistory.append(smoothedRecord)
            } else {
                self.speedHistory.append(record)
            }
        }
    }
    
    private func handleMemoryData(_ text: String) {
        guard let data = text.data(using: .utf8),
              let memory = try? JSONDecoder().decode(MemoryData.self, from: data) else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.memoryUsage = self?.formatBytes(memory.inuse) ?? "0 MB"
            
            let newMemoryRecord = MemoryRecord(
                timestamp: Date(),
                usage: Double(memory.inuse) / 1024 / 1024 // 转换为 MB
            )
            self?.memoryHistory.append(newMemoryRecord)
            if self?.memoryHistory.count ?? 0 > 60 {
                self?.memoryHistory.removeFirst()
            }
        }
    }
    
    private func handleConnectionsData(_ text: String) {
        // print("收到连接数据: \(text)")  // 添加调试日志
        
        guard let data = text.data(using: .utf8) else {
            print("无法将文本转换为数据")
            return
        }
        
        do {
            let connections = try JSONDecoder().decode(ConnectionsData.self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.activeConnections = connections.connections.count
                self?.totalUpload = self?.formatBytes(connections.uploadTotal) ?? "0 MB"
                self?.totalDownload = self?.formatBytes(connections.downloadTotal) ?? "0 MB"
            }
        } catch {
            print("解析连接数据失败: \(error)")
        }
    }
    
    private func formatSpeed(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1024 {
            return String(format: "%.1f KB/s", kb)
        }
        let mb = kb / 1024
        return String(format: "%.1f MB/s", mb)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1024 / 1024
        if mb < 1024 {
            return String(format: "%.1f MB", mb)
        }
        let gb = mb / 1024
        return String(format: "%.2f GB", gb)
    }
    
    private func retryConnection(type: ConnectionType) {
        guard let server = server,
              isMonitoring,
              isViewActive else { return }
        
        print("准备重试连接 \(type.rawValue) WebSocket")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self,
                  self.isMonitoring,
                  self.isViewActive else { return }
            
            print("开始重新连接 \(type.rawValue) WebSocket...")
            switch type {
            case .traffic:
                self.connectToTraffic(server: server)
            case .memory:
                self.connectToMemory(server: server)
            case .connections:
                self.connectToConnections(server: server)
            }
        }
    }
}

// 数据模型
struct TrafficData: Codable {
    let up: Int
    let down: Int
}

struct MemoryData: Codable {
    let inuse: Int
    let oslimit: Int
}

struct ConnectionsData: Codable {
    let downloadTotal: Int
    let uploadTotal: Int
    let connections: [Connection]
    let memory: Int?
    
    private enum CodingKeys: String, CodingKey {
        case downloadTotal, uploadTotal, connections, memory
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadTotal = try container.decode(Int.self, forKey: .downloadTotal)
        uploadTotal = try container.decode(Int.self, forKey: .uploadTotal)
        memory = try container.decodeIfPresent(Int.self, forKey: .memory)
        
        do {
            connections = try container.decode([Connection].self, forKey: .connections)
        } catch {
            let rawConnections = try container.decode([PremiumConnection].self, forKey: .connections)
            connections = rawConnections.map { premiumConn in
                Connection(
                    id: premiumConn.id,
                    metadata: ConnectionMetadata(
                        network: premiumConn.metadata.network,
                        type: premiumConn.metadata.type,
                        sourceIP: premiumConn.metadata.sourceIP,
                        destinationIP: premiumConn.metadata.destinationIP,
                        sourcePort: premiumConn.metadata.sourcePort,
                        destinationPort: premiumConn.metadata.destinationPort,
                        host: premiumConn.metadata.host,
                        dnsMode: premiumConn.metadata.dnsMode,
                        processPath: premiumConn.metadata.processPath ?? "",
                        specialProxy: premiumConn.metadata.specialProxy ?? "",
                        sourceGeoIP: nil,
                        destinationGeoIP: nil,
                        sourceIPASN: nil,
                        destinationIPASN: nil,
                        inboundIP: nil,
                        inboundPort: nil,
                        inboundName: nil,
                        inboundUser: nil,
                        uid: nil,
                        process: nil,
                        specialRules: nil,
                        remoteDestination: nil,
                        dscp: nil,
                        sniffHost: nil
                    ),
                    upload: premiumConn.upload,
                    download: premiumConn.download,
                    start: premiumConn.start,
                    chains: premiumConn.chains,
                    rule: premiumConn.rule,
                    rulePayload: premiumConn.rulePayload
                )
            }
        }
    }
}

// Premium 服务器的连接数据结构
struct PremiumConnection: Codable {
    let id: String
    let metadata: PremiumMetadata
    let upload: Int
    let download: Int
    let start: String
    let chains: [String]
    let rule: String
    let rulePayload: String
}

struct PremiumMetadata: Codable {
    let network: String
    let type: String
    let sourceIP: String
    let destinationIP: String
    let sourcePort: String
    let destinationPort: String
    let host: String
    let dnsMode: String
    let processPath: String?
    let specialProxy: String?
}

struct Connection: Codable {
    let id: String
    let metadata: ConnectionMetadata
    let upload: Int
    let download: Int
    let start: String
    let chains: [String]
    let rule: String
    let rulePayload: String
    let downloadSpeed: Double
    let uploadSpeed: Double
    let isAlive: Bool
    
    init(id: String, metadata: ConnectionMetadata, upload: Int, download: Int, start: String, chains: [String], rule: String, rulePayload: String, downloadSpeed: Double = 0, uploadSpeed: Double = 0, isAlive: Bool = true) {
        self.id = id
        self.metadata = metadata
        self.upload = upload
        self.download = download
        self.start = start
        self.chains = chains
        self.rule = rule
        self.rulePayload = rulePayload
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.isAlive = isAlive
    }
}

struct SpeedRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let upload: Double
    let download: Double
}

struct MemoryRecord: Identifiable {
    let id = UUID()
    let timestamp: Date
    let usage: Double
} 