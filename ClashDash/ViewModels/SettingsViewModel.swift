import Foundation

class SettingsViewModel: ObservableObject {
    @Published var config: ClashConfig?
    @Published var mode: String = "rule"
    @Published var logLevel: String = "info"
    @Published var allowLan: Bool = true
    @Published var sniffing: Bool = false
    @Published var tunEnable: Bool = false
    @Published var tunDevice: String = ""
    @Published var tunStack: String = "gVisor"
    @Published var interfaceName: String = ""
    @Published var language: String = "zh-CN"
    @Published var tunAutoRoute: Bool = true
    @Published var tunAutoDetectInterface: Bool = true
    @Published var httpPort: String = "0"
    @Published var socksPort: String = "0"
    @Published var mixedPort: String = "0"
    @Published var redirPort: String = "0"
    @Published var tproxyPort: String = "0"
    @Published var tempHttpPort: String = "0"
    @Published var tempSocksPort: String = "0"
    @Published var tempMixedPort: String = "0"
    @Published var tempRedirPort: String = "0"
    @Published var tempTproxyPort: String = "0"
    
    private func makeRequest(path: String, server: ClashServer) -> URLRequest? {
        let scheme = server.useSSL ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(server.url):\(server.port)/\(path)") else {
            print("无效的 URL")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    func fetchConfig(server: ClashServer) {
        guard let request = makeRequest(path: "configs", server: server) else { return }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data else { return }
            
            if let config = try? JSONDecoder().decode(ClashConfig.self, from: data) {
                DispatchQueue.main.async {
                    self?.config = config
                    self?.updateUIFromConfig(config)
                }
            }
        }.resume()
    }
    
    private func updateUIFromConfig(_ config: ClashConfig) {
        self.mode = config.mode
        self.logLevel = config.logLevel
        self.allowLan = config.allowLan
        self.sniffing = config.sniffing ?? false
        
        if let tun = config.tun {
            self.tunEnable = tun.enable
            self.tunDevice = tun.device
            self.tunStack = tun.stack
            self.tunAutoRoute = tun.autoRoute
            self.tunAutoDetectInterface = tun.autoDetectInterface
        }
        
        if let interfaceName = config.interfaceName {
            self.interfaceName = interfaceName
        }
        
        self.httpPort = "\(config.port ?? 0)"
        self.tempHttpPort = self.httpPort
        self.socksPort = "\(config.socksPort ?? 0)"
        self.tempSocksPort = self.socksPort
        self.mixedPort = "\(config.mixedPort ?? 0)"
        self.tempMixedPort = self.mixedPort
        self.redirPort = "\(config.redirPort ?? 0)"
        self.tempRedirPort = self.redirPort
        self.tproxyPort = "\(config.tproxyPort ?? 0)"
        self.tempTproxyPort = self.tproxyPort
    }
    
    func updateConfig(_ path: String, value: Any, server: ClashServer) {
        guard var request = makeRequest(path: "configs", server: server) else { return }
        
        request.httpMethod = "PATCH"
        let payload = [path: value]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("设置更新成功：\(path) = \(value)")
            } else if let error = error {
                print("设置更新失败：\(path) = \(value)")
                print("错误：\(error.localizedDescription)")
            }
        }.resume()
    }
    
    // MARK: - Actions
    func reloadConfig(server: ClashServer) {
        guard let url = URL(string: "http://\(server.url):\(server.port)/configs?force=true") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("配置重载成功")
            } else if let error = error {
                print("配置重载失败：\(error.localizedDescription)")
            }
        }.resume()
    }
    
    func updateGeoDatabase(server: ClashServer) {
        guard let url = URL(string: "http://\(server.url):\(server.port)/configs/geo") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("GEO 数据库更新成功")
            } else if let error = error {
                print("GEO 数据库��新失败：\(error.localizedDescription)")
            }
        }.resume()
    }
    
    func clearFakeIP(server: ClashServer) {
        guard let url = URL(string: "http://\(server.url):\(server.port)/cache/fakeip/flush") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("FakeIP 缓存清除成功")
            } else if let error = error {
                print("FakeIP 缓存清除失败：\(error.localizedDescription)")
            }
        }.resume()
    }
    
    func restartCore(server: ClashServer) {
        guard let url = URL(string: "http://\(server.url):\(server.port)/restart") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("核心重启成功")
            } else if let error = error {
                print("核心重启失败：\(error.localizedDescription)")
            }
        }.resume()
    }
    
    func upgradeCore(server: ClashServer) {
        guard let url = URL(string: "http://\(server.url):\(server.port)/upgrade") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(server.secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [:])
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                print("核心更新成功")
            } else if let error = error {
                print("核心更新失败：\(error.localizedDescription)")
            }
        }.resume()
    }
    
    func validateAndUpdatePort(_ portString: String, configKey: String, server: ClashServer) -> Bool {
        guard let port = Int(portString),
              (0...65535).contains(port) else {
            return false
        }
        
        updateConfig(configKey, value: port, server: server)
        return true
    }
} 