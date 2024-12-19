import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ServerViewModel()
    @State private var showingSetting = false
    @State private var showingAddSheet = false
    @State private var editingServer: ClashServer?
    @State private var selectedQuickLaunchServer: ClashServer?
    @State private var showQuickLaunchDestination = false
    @State private var showingAddOpenWRTSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.servers.isEmpty {
                    VStack(spacing: 20) {
                        Spacer()
                            .frame(height: 60)
                        
                        Image(systemName: "server.rack")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.bottom, 10)
                        
                        Text("没有服务器")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("点击添加按钮来添加一个新的服务器")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button(action: {
                            showingAddSheet = true
                        }) {
                            Text("添加服务器")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 160, height: 44)
                                .background(Color.blue)
                                .cornerRadius(22)
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 20) {
                        // 服务器卡片列表
                        ForEach(viewModel.servers) { server in
                            NavigationLink(destination: ServerDetailView(server: server)) {
                                ServerRowView(server: server)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            viewModel.deleteServer(server)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                        
                                        Button {
                                            editingServer = server
                                        } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                        
                                        Button {
                                            viewModel.setQuickLaunch(server)
                                        } label: {
                                            Label(server.isQuickLaunch ? "取消快速启动" : "设为快速启动", 
                                                  systemImage: server.isQuickLaunch ? "bolt.slash.circle" : "bolt.circle")
                                        }
                                    }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Clash Dash")
            .navigationDestination(isPresented: $showQuickLaunchDestination) {
                if let server = selectedQuickLaunchServer ?? viewModel.servers.first {
                    ServerDetailView(server: server)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingSetting = true }) {
                        Image(systemName: "gear")
                    }
                    
                }
                
            }
            .sheet(isPresented: $showingAddSheet) {
                AddServerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSetting) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(item: $editingServer) { server in
                EditServerView(viewModel: viewModel, server: server)
            }
            .refreshable {
                await viewModel.checkAllServersStatus()
            }
            .alert("连接错误", isPresented: $viewModel.showError) {
                Button("确定", role: .cancel) {}
            } message: {
                if let details = viewModel.errorDetails {
                    Text("\(viewModel.errorMessage ?? "")\n\n\(details)")
                } else {
                    Text(viewModel.errorMessage ?? "")
                }
            }
        }
        .onAppear {
            if let quickLaunchServer = viewModel.servers.first(where: { $0.isQuickLaunch }) {
                selectedQuickLaunchServer = quickLaunchServer
                showQuickLaunchDestination = true
            }
        }
    }
}

struct ServerRowView: View {
    let server: ClashServer
    
    private var versionDisplay: String {
        guard let version = server.version else { return "" }
        return version.count > 15 ? String(version.prefix(15)) + "..." : version
    }
    
    private var statusIcon: String {
        switch server.status {
        case .ok: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .unauthorized: return "lock.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // 状态指示器
            ZStack {
                Circle()
                    .fill(server.status.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: statusIcon)
                    .foregroundColor(server.status.color)
            }
            
            // 服务器信息
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(server.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if server.isQuickLaunch {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundColor(.yellow)
                            .font(.subheadline)
                    }
                }
                
                if server.status == .ok {
                    HStack(spacing: 4) {
                        // 服务器来源标签
                        Label {
                            Text("Clash 控制器")
                                .foregroundColor(.secondary)
                        } icon: {
                            Image(systemName: "server.rack")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        
                        if server.source == .clashController {
                            Text("•")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            // 版本信息
                            Label {
                                Text(versionDisplay)
                                    .foregroundColor(.secondary)
                            } icon: {
                                Image(systemName: "tag")
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)
                            .lineLimit(1)
                        }
                    }
                } else if let errorMessage = server.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(server.status.color)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(height: 80)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
}

struct SettingsLinkRow<Destination: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    let destination: Destination
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 32)
                
                Text(title)
                    .font(.body)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}

