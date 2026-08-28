import SwiftUI

struct WristMenuView: View {
    static let actionRailItemIDs = ["armControl", "emergencyStop", "releaseEmergencyStop", "controlWindow", "livePanorama"]

    @Environment(AppModel.self) private var appModel

    var onSelectSource: (ContentSourceItem) -> Void
    var onOpenControl: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(.white.opacity(0.2))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    actionRail
                    sourceList
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 420)
        .glassBackgroundEffect()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("现场控制中心")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(appModel.connectionStatus.contains("已连接") ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(appModel.connectionStatus)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            
            Button {
                appModel.isUIFixed.toggle()
            } label: {
                Image(systemName: appModel.isUIFixed ? "pin.fill" : "pin.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .background(appModel.isUIFixed ? Color.accentColor : Color.white.opacity(0.1))
            .clipShape(Circle())
            .help(appModel.isUIFixed ? "取消固定" : "固定在空间")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var actionRail: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    appModel.armControl()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: appModel.isSessionArmed ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: 24))
                        Text(appModel.isSessionArmed ? "已授权" : "先授权")
                            .font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(appModel.isSessionArmed ? .green : .blue)
                .disabled(appModel.isSessionArmed)

                Button(role: .destructive) {
                    appModel.emergencyStop()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 24))
                        Text("急停")
                            .font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Button {
                appModel.releaseEmergencyStop()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 20))
                    Text("解除急停")
                        .font(.footnote.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)

            HStack(spacing: 12) {
                Button {
                    onOpenControl()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 24))
                        Text("设备控制")
                            .font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button {
                    appModel.useLivePanoramaFeed()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "pano.fill")
                            .font(.system(size: 24))
                        Text("现场全景")
                            .font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
            }
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("监控内容源")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            
            if appModel.sources.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("等待网关下发内容源...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .background(.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(spacing: 8) {
                    ForEach(appModel.sources) { source in
                        Button {
                            onSelectSource(source)
                        } label: {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: source.type.symbolName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                    
                                    HStack(spacing: 6) {
                                        Text(source.group)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        if let cacheStatus = appModel.cacheStatusText(for: source.id), source.type.isPanoramaScene {
                                            Circle()
                                                .fill(cacheStatus == "本地已缓存" ? Color.green : Color.orange)
                                                .frame(width: 4, height: 4)
                                            Text(cacheStatus)
                                                .font(.caption2)
                                                .foregroundStyle(cacheStatus == "本地已缓存" ? .green : .secondary)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                if source.defaultVisible == true {
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                        .foregroundStyle(.yellow)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                }
            }
        }
    }
}

#Preview {
    WristMenuView(onSelectSource: { _ in }, onOpenControl: {})
        .environment(AppModel())
}
