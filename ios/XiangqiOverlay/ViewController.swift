import UIKit

/// 阶段 2a：连上电脑端分析服务，读取 /api/overlay 并显示最新提示。
/// 这一版刻意不引入 App Extension、App Group 或任何 entitlement，
/// 目的是先验证「云 macOS CI 出未签名 IPA → Windows 免费自签安装」整条链路。
/// 屏幕采集(BUE)与自定义 PiP 浮窗在链路跑通后再叠加。
private struct OverlayState: Decodable {
    let title: String?
    let subtitle: String?
    let bestmove: String?
    let scoreRed: Int?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, bestmove
        case scoreRed = "score_red"
    }
}

final class ViewController: UIViewController {
    private let addressField = UITextField()
    private let startButton = UIButton(type: .system)
    private let stateLabel = UILabel()
    private let moveLabel = UILabel()
    private let detailLabel = UILabel()
    private let hintLabel = UILabel()

    private var timer: Timer?
    private var baseURL = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.965, green: 0.960, blue: 0.945, alpha: 1)
        title = "象棋浮窗"
        setupUI()
        addressField.text = UserDefaults.standard.string(forKey: "serverAddress")
            ?? "http://172.20.10.3:8765"
    }

    private func setupUI() {
        addressField.borderStyle = .roundedRect
        addressField.placeholder = "http://电脑热点IP:8765"
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.font = .systemFont(ofSize: 14)

        startButton.setTitle("连接电脑", for: .normal)
        startButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        startButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)

        stateLabel.font = .systemFont(ofSize: 12)
        stateLabel.textColor = .secondaryLabel
        stateLabel.numberOfLines = 0
        stateLabel.text = "未连接"

        moveLabel.font = .boldSystemFont(ofSize: 46)
        moveLabel.textColor = .systemRed
        moveLabel.textAlignment = .center
        moveLabel.adjustsFontSizeToFitWidth = true
        moveLabel.text = "—"

        detailLabel.font = .systemFont(ofSize: 16)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0
        detailLabel.text = ""

        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .tertiaryLabel
        hintLabel.numberOfLines = 0
        hintLabel.text = "当前为链路验证版：只显示电脑端推送的提示，不采集屏幕。\n"
            + "网页版画中画浮窗请在 Safari 打开同一地址使用。"

        let stack = UIStackView(arrangedSubviews: [
            addressField, startButton, stateLabel, moveLabel, detailLabel, hintLabel
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
        ])
        addressField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        startButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    @objc private func toggle() {
        if timer != nil {
            stop()
            return
        }
        let raw = addressField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty, URL(string: raw) != nil else {
            stateLabel.text = "地址不合法，请填 http://IP:8765"
            return
        }
        baseURL = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        UserDefaults.standard.set(baseURL, forKey: "serverAddress")
        start()
    }

    private func start() {
        startButton.setTitle("断开", for: .normal)
        stateLabel.text = "连接中…"
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        stateLabel.text = "已断开"
        startButton.setTitle("连接电脑", for: .normal)
    }

    private func poll() {
        guard let url = URL(string: baseURL + "/api/overlay") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.stateLabel.text = "连接失败：\(error.localizedDescription)"
                    return
                }
                guard let data,
                      let state = try? JSONDecoder().decode(OverlayState.self, from: data) else {
                    self.stateLabel.text = "数据解析失败"
                    return
                }
                self.stateLabel.text = "已连接 · 每秒刷新 · \(self.baseURL)"
                self.moveLabel.text = state.title ?? "—"
                self.detailLabel.text = state.subtitle ?? ""
            }
        }.resume()
    }
}
