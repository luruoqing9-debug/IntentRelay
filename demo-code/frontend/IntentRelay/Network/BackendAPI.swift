import Foundation
import UIKit

/// 后端 API 统一入口
/// 所有网络请求通过此类发起，方便后续扩展
@MainActor
class BackendAPI {
    static let shared = BackendAPI()

    // 后端服务地址
    // 真机测试时需要改为 Mac 的局域网 IP（如 192.168.x.x:8080）
    var baseURL: String = "http://refinity-intentrelay.pub.hsuni.top:15902"

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300  // 5分钟，兼容 3D 生成
        config.timeoutIntervalForResource = 600  // 10分钟
        self.session = URLSession(configuration: config)
    }

    // MARK: - Memory QA

    /// 开始新一轮记忆问答（不传 answer 参数）
    func startMemoryQA() async throws -> MemoryQAResponse {
        try await postMemoryQA(answer: nil)
    }

    /// 回答当前问题（或传 "SKIP" 跳过）
    func answerMemoryQA(answer: String) async throws -> MemoryQAResponse {
        try await postMemoryQA(answer: answer)
    }

    private func postMemoryQA(answer: String?) async throws -> MemoryQAResponse {
        let url = URL(string: "\(baseURL)/memory_qa")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 始终发送 JSON body，避免 Flask 解析空 body 报错
        let body: [String: Any] = {
            if let answer {
                return ["answer": answer]
            } else {
                return [:]
            }
        }()
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return MemoryQAResponse(from: json)
    }

    // MARK: - Components Info

    func fetchComponentsInfo() async throws -> ComponentsInfoResponse {
        let url = URL(string: "\(baseURL)/components_info")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return ComponentsInfoResponse(from: json)
    }

    /// 更新记忆中的描述内容
    func updateDescription(targetName: String, descType: String, oldContent: String, newContent: String) async throws {
        let url = URL(string: "\(baseURL)/update_description")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "target_name": targetName,
            "desc_type": descType,
            "old_content": oldContent,
            "new_content": newContent
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let success = json["success"] as? Bool, success else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Uncertain Suggestions

    func fetchUncertainSuggestions() async throws -> UncertainSuggestionsResponse {
        let url = URL(string: "\(baseURL)/uncertain_suggestions")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return UncertainSuggestionsResponse(from: json)
    }

    func confirmSuggestion(target: String, type: String, content: String, suggestion: String) async throws -> ConfirmSuggestionResponse {
        let url = URL(string: "\(baseURL)/confirm_suggestion")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "target": target,
            "type": type,
            "content": content,
            "suggestion": suggestion
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return ConfirmSuggestionResponse(from: json)
    }

    // MARK: - Health Check

    func healthCheck() async throws -> HealthResponse {
        let url = URL(string: "\(baseURL)/health")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return HealthResponse(from: json)
    }

    // MARK: - Generate Prompt

    /// mode=1: 部件生成提示词
    func generateComponentPrompt(componentName: String) async throws -> GeneratePromptResponse {
        try await postGeneratePrompt(mode: 1, componentName: componentName)
    }

    /// mode=2: 整体生成提示词
    func generateOverallPrompt() async throws -> GeneratePromptResponse {
        try await postGeneratePrompt(mode: 2, componentName: nil)
    }

    private func postGeneratePrompt(mode: Int, componentName: String?) async throws -> GeneratePromptResponse {
        let url = URL(string: "\(baseURL)/generate_prompt")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["mode": mode]
        if let componentName {
            body["component_name"] = componentName
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return GeneratePromptResponse(from: json)
    }

    // MARK: - Upload Reference Image

    /// 上传参考图到 original_image/
    func uploadReferenceImage(_ image: UIImage, targetName: String) async throws {
        // PNG 优先，失败则回退 JPEG，都不行则跳过图片上传（不中断流程）
        // --- 旧代码注释 begin ---
        // let url = URL(string: "\(baseURL)/upload_reference_image")!
        // var request = URLRequest(url: url)
        // request.httpMethod = "POST"
        //
        // let boundary = UUID().uuidString
        // request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        //
        // var body = Data()
        // body.append("--\(boundary)\r\n".data(using: .utf8)!)
        // body.append("Content-Disposition: form-data; name=\"target_name\"\r\n\r\n".data(using: .utf8)!)
        // body.append("\(targetName)\r\n".data(using: .utf8)!)
        // if let imageData = image.pngData() {
        //     body.append("--\(boundary)\r\n".data(using: .utf8)!)
        //     body.append("Content-Disposition: form-data; name=\"image\"; filename=\"reference.png\"\r\n".data(using: .utf8)!)
        //     body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        //     body.append(imageData)
        //     body.append("\r\n".data(using: .utf8)!)
        // }
        // body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        //
        // let (_, response) = try await session.upload(for: request, from: body)
        // guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        //     throw APIError.invalidResponse
        // }
        // --- 旧代码注释 end ---

        let url = URL(string: "\(baseURL)/upload_reference_image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"target_name\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(targetName)\r\n".data(using: .utf8)!)

        // PNG 转失败则回退 JPEG，都不行则跳过图片部分
        if let imageData = image.pngData() ?? image.jpegData(compressionQuality: 0.9) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"reference.png\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (_, response) = try await session.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.invalidResponse
        }
    }

    // MARK: - Generate Image

    /// mode=1: 部件图像生成（返回 3 张候选图）
    func generateComponentImage(prompt: String, componentName: String) async throws -> GenerateImageResponse {
        try await postGenerateImage(mode: 1, prompt: prompt, componentName: componentName)
    }

    /// 用户选择一张部件候选图
    func selectComponentImage(componentName: String, selectedFilename: String) async throws -> GenerateImageResponse {
        let url = URL(string: "\(baseURL)/select_component_image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "component_name": componentName,
            "selected_filename": selectedFilename
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return GenerateImageResponse(from: json)
    }

    private func postGenerateImage(mode: Int, prompt: String, componentName: String) async throws -> GenerateImageResponse {
        let url = URL(string: "\(baseURL)/generate_image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "mode": mode,
            "prompt": prompt
        ]
        if mode == 1 {
            body["component_name"] = componentName
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return GenerateImageResponse(from: json)
    }

    // MARK: - Component List & Images (for OverallEdit)

    /// 获取后端已生成的部件列表（/components_list）
    func fetchComponentList() async throws -> [ComponentInfo] {
        let url = URL(string: "\(baseURL)/components_list")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var items: [ComponentInfo] = []
        if let componentsArray = json["components"] as? [[String: Any]] {
            for comp in componentsArray {
                let name = comp["name"] as? String ?? ""
                let imageURL = "\(baseURL)/images/processed/\(name).png"
                items.append(ComponentInfo(name: name, imageURL: imageURL))
            }
        }
        return items
    }

    /// 从 URL 下载 UIImage
    func downloadImage(from url: String) async -> UIImage? {
        let fullURL = url.hasPrefix("http") ? url : "\(baseURL)\(url)"
        guard let url = URL(string: fullURL) else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// 调用 /generate_image (mode=2) 生成整体图片
    func generateOverallImage(prompt: String, saveName: String = "overall") async throws -> GenerateImageResponse {
        let url = URL(string: "\(baseURL)/generate_image")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "mode": 2,
            "prompt": prompt,
            "save_name": saveName
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return GenerateImageResponse(from: json)
    }

    // MARK: - QA Switch (test mode)

    /// 调用 /qa_switch 测试模式，直接用问题调 LLM
    func qaSwitchTest(question: String) async throws -> QAAnswerResponse {
        let url = URL(string: "\(baseURL)/qa_switch")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["question": question]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return QAAnswerResponse(from: json)
    }

    // MARK: - Generate from Answer

    /// 调用 /generate_from_answer，用最新 AI 回答生成图像
    func generateFromAnswer(saveName: String = "ai_design", answer: String? = nil) async throws -> GenerateFromAnswerResponse {
        let url = URL(string: "\(baseURL)/generate_from_answer")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["save_name": saveName]
        if let answer {
            body["answer"] = answer
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return GenerateFromAnswerResponse(from: json)
    }

    // MARK: - Update Memory from Prompt

    /// 部件提示词更新记忆
    func updateMemoryFromPrompt(mode: Int, componentName: String, aiPrompt: String, userPrompt: String) async throws -> UpdateMemoryResponse {
        let url = URL(string: "\(baseURL)/update_memory_from_prompt")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "mode": mode,
            "ai_prompt": aiPrompt,
            "user_prompt": userPrompt
        ]
        if mode == 1 {
            body["component_name"] = componentName
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return UpdateMemoryResponse(from: json)
    }

    // MARK: - User Feedback

    /// 调用 /user_feedback，提交用户反馈并调整评分权重
    func userFeedback(feedback: String) async throws -> UserFeedbackResponse {
        let url = URL(string: "\(baseURL)/user_feedback")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["feedback": feedback]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return UserFeedbackResponse(from: json)
    }

    // MARK: - Generate 3D Model

    /// 调用 /generate_3d_model，从 3d_image/ 中的图片生成 3D 模型
    func generate3DModel(prompt: String, modelName: String? = nil) async throws -> Generate3DModelResponse {
        let url = URL(string: "\(baseURL)/generate_3d_model")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["prompt": prompt]
        if let modelName {
            body["model_name"] = modelName
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return Generate3DModelResponse(from: json)
    }

    // MARK: - Speech Transcription

    /// 发送音频文件到服务器，调用讯飞语音识别，返回文本
    func transcribeAudio(_ audioData: Data, filename: String = "recording.wav") async throws -> String {
        let url = URL(string: "\(baseURL)/speech_transcribe")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let success = json["success"] as? Bool, success,
              let text = json["text"] as? String else {
            throw APIError.invalidResponse
        }
        return text
    }

    // MARK: - Mico Switch

    /// 切换语音模式：0 = 分贝检测，1 = 持续发送
    func switchMico(mode: Int) async throws -> MicoSwitchResponse {
        let url = URL(string: "\(baseURL)/mico_switch")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["mode": mode]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return MicoSwitchResponse(from: json)
    }

    // MARK: - Models List

    /// 获取已处理的部件图片列表及对应的 3D 模型状态
    func fetchModelsList() async throws -> ModelsListResponse {
        let url = URL(string: "\(baseURL)/models_list")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return ModelsListResponse(from: json)
    }

    // MARK: - VLM Analysis

    /// 调用 /vlm_analysis，传入语音文本触发 VLM 分析
    func vlmAnalysis(transcriptText: String, triggerTypes: [String] = ["语音输入触发"]) async throws -> VLMAnalysisResponse {
        let url = URL(string: "\(baseURL)/vlm_analysis")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "transcript_text": transcriptText,
            "trigger_types": triggerTypes
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return VLMAnalysisResponse(from: json)
    }

    // MARK: - AI Feedback

    /// 调用 GET /latest_feedback，获取 AI 主动反馈（轮询用，读后即焚）
    func fetchLatestFeedback() async throws -> LatestFeedbackResponse {
        let url = URL(string: "\(baseURL)/latest_feedback")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return LatestFeedbackResponse(from: json)
    }

    /// 调用 /ai_feedback，获取 AI 主动反馈建议
    func aiFeedback(componentName: String, parsedVLM: [String: Any]) async throws -> AIFeedbackResponse {
        let url = URL(string: "\(baseURL)/ai_feedback")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "component_name": componentName,
            "parsed_vlm": parsedVLM
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return AIFeedbackResponse(from: json)
    }
}

// MARK: - Response Models

/// 部件信息（用于整体生成时展示已完成的部件图）
struct ComponentInfo {
    let name: String
    let imageURL: String
    var image: UIImage? = nil
}

struct MemoryQAResponse {
    let hasQuestions: Bool
    let questions: [QAQuestion]
    let currentIndex: Int
    let updateResult: String?
    let remainingCount: Int
    let error: String?

    var currentQuestion: QAQuestion? {
        guard currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    init(from json: [String: Any]) {
        self.hasQuestions = json["has_questions"] as? Bool ?? false
        self.currentIndex = json["current_index"] as? Int ?? 0
        self.remainingCount = json["remaining_count"] as? Int ?? 0
        self.updateResult = json["update_result"] as? String
        self.error = json["error"] as? String

        if let questionsArray = json["questions"] as? [[String: Any]] {
            self.questions = questionsArray.map { QAQuestion(from: $0) }
        } else {
            self.questions = []
        }
    }
}

struct QAQuestion {
    let target: String
    let descType: String
    let issueType: String
    let issue: String
    let question: String

    init(from json: [String: Any]) {
        self.target = json["target"] as? String ?? ""
        self.descType = json["desc_type"] as? String ?? ""
        self.issueType = json["issue_type"] as? String ?? ""
        self.issue = json["issue"] as? String ?? ""
        self.question = json["question"] as? String ?? ""
    }
}

struct HealthResponse {
    let systemInitialized: Bool
    let speechRunning: Bool
    let memoryLoaded: Bool
    let micoMode: Int

    init(from json: [String: Any]) {
        self.systemInitialized = json["system_initialized"] as? Bool ?? false
        self.speechRunning = json["speech_running"] as? Bool ?? false
        self.memoryLoaded = json["memory_loaded"] as? Bool ?? false
        self.micoMode = json["mico_mode"] as? Int ?? 0
    }
}

struct ComponentsInfoResponse {
    let structureInfo: [String]
    let functionInfo: [String]
    let uncertainInfo: [UncertainItem]

    struct UncertainItem {
        let target: String
        let content: String
        let descType: String

        init(from json: [String: Any]) {
            self.target = json["target"] as? String ?? ""
            self.content = json["content"] as? String ?? ""
            self.descType = json["desc_type"] as? String ?? ""
        }
    }

    init(from json: [String: Any]) {
        self.structureInfo = json["structure_info"] as? [String] ?? []
        self.functionInfo = json["function_info"] as? [String] ?? []

        if let array = json["uncertain_info"] as? [[String: Any]] {
            self.uncertainInfo = array.map { UncertainItem(from: $0) }
        } else {
            self.uncertainInfo = []
        }
    }
}

struct GeneratePromptResponse {
    let success: Bool
    let prompt: String
    let hasReferenceImage: Bool
    let componentCount: Int
    let componentImages: [String]
    let overallImageIndex: Int?

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.prompt = json["prompt"] as? String ?? ""
        self.hasReferenceImage = json["has_reference_image"] as? Bool ?? false
        self.componentCount = json["component_count"] as? Int ?? 0

        if let urls = json["component_images"] as? [String] {
            self.componentImages = urls
        } else {
            self.componentImages = []
        }

        self.overallImageIndex = json["overall_image_index"] as? Int
    }
}

struct UpdateMemoryResponse {
    let success: Bool
    let changesDetected: Bool
    let detectedChanges: DetectedChanges
    let actionsTaken: [String]
    let newComponentCreated: Bool
    let newComponentName: String?

    struct DetectedChanges {
        let appearanceChanges: [String]
        let functionChanges: [String]
        let structureChanges: [String]
        let componentNameChanged: Bool

        init(from json: [String: Any]) {
            self.appearanceChanges = json["appearance_changes"] as? [String] ?? []
            self.functionChanges = json["function_changes"] as? [String] ?? []
            self.structureChanges = json["structure_changes"] as? [String] ?? []
            self.componentNameChanged = json["component_name_changed"] as? Bool ?? false
        }
    }

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.changesDetected = json["changes_detected"] as? Bool ?? false
        if let changes = json["detected_changes"] as? [String: Any] {
            self.detectedChanges = DetectedChanges(from: changes)
        } else {
            self.detectedChanges = DetectedChanges(from: [:])
        }
        self.actionsTaken = json["actions_taken"] as? [String] ?? []
        self.newComponentCreated = json["new_component_created"] as? Bool ?? false
        self.newComponentName = json["new_component_name"] as? String
    }
}

struct UncertainSuggestionsResponse {
    let hasUncertain: Bool
    let uncertainItems: [UncertainItem]
    let count: Int

    struct UncertainItem {
        let target: String
        let type: String
        let content: String
        let suggestion: String

        init(from json: [String: Any]) {
            self.target = json["target"] as? String ?? ""
            self.type = json["type"] as? String ?? ""
            self.content = json["content"] as? String ?? ""
            self.suggestion = json["suggestion"] as? String ?? ""
        }
    }

    init(from json: [String: Any]) {
        self.hasUncertain = json["has_uncertain"] as? Bool ?? false
        self.count = json["count"] as? Int ?? 0

        if let itemsArray = json["uncertain_items"] as? [[String: Any]] {
            self.uncertainItems = itemsArray.map { UncertainItem(from: $0) }
        } else {
            self.uncertainItems = []
        }
    }
}

struct ConfirmSuggestionResponse {
    let success: Bool
    let updatedContent: String
    let message: String

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.updatedContent = json["updated_content"] as? String ?? ""
        self.message = json["message"] as? String ?? ""
    }
}

struct GenerateImageResponse {
    let success: Bool
    let imagePaths: [String]
    let referenceImageUsed: String?

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        if let candidates = json["candidates"] as? [String] {
            self.imagePaths = candidates
        } else {
            self.imagePaths = json["image_paths"] as? [String] ?? []
        }
        self.referenceImageUsed = json["reference_image_used"] as? String
    }
}

struct QAAnswerResponse {
    let success: Bool
    let question: String
    let answer: String

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.question = json["question"] as? String ?? ""
        self.answer = json["answer"] as? String ?? ""
    }
}

struct UserFeedbackResponse {
    let success: Bool
    let analysis: String

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.analysis = json["analysis"] as? String ?? ""
    }
}

struct GenerateFromAnswerResponse {
    let success: Bool
    let aiAnswer: String
    let prompt: String
    let designElements: [String]
    let imagePaths: [String]

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.aiAnswer = json["ai_answer"] as? String ?? ""
        self.prompt = json["prompt"] as? String ?? ""
        self.designElements = json["design_elements"] as? [String] ?? []
        self.imagePaths = json["image_paths"] as? [String] ?? []
    }
}

struct MicoSwitchResponse {
    let success: Bool
    let mode: Int
    let text: String

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.mode = json["mode"] as? Int ?? 0
        self.text = json["text"] as? String ?? ""
    }
}

struct Generate3DModelResponse {
    let success: Bool
    let modelId: String
    let modelURL: String
    let modelPath: String

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.modelId = json["model_id"] as? String ?? ""
        self.modelURL = json["model_url"] as? String ?? ""
        self.modelPath = json["model_path"] as? String ?? ""
    }
}

struct ModelItem: Identifiable {
    let id = UUID()
    let name: String
    let imageURL: String
    let has3DModel: Bool
    let modelURL: String?
}

struct ModelsListResponse {
    let models: [ModelItem]

    init(from json: [String: Any]) {
        if let modelsArray = json["models"] as? [[String: Any]] {
            self.models = modelsArray.map { item in
                ModelItem(
                    name: item["name"] as? String ?? "",
                    imageURL: item["image_url"] as? String ?? "",
                    has3DModel: item["has_3d_model"] as? Bool ?? false,
                    modelURL: item["model_url"] as? String
                )
            }
        } else {
            self.models = []
        }
    }
}

// MARK: - VLM Analysis & AI Feedback Responses

struct VLMAnalysisResponse {
    let success: Bool
    let imageCount: Int
    let nodeType: String
    let repeatCount: Int
    let shouldFeedback: Bool
    let parsedVLM: [String: Any]

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        self.imageCount = json["image_count"] as? Int ?? 0
        self.nodeType = json["node_type"] as? String ?? ""
        self.repeatCount = json["repeat_count"] as? Int ?? 0
        self.shouldFeedback = json["should_feedback"] as? Bool ?? false
        self.parsedVLM = json["parsed_vlm"] as? [String: Any] ?? [:]
    }
}

struct AIFeedbackResponse {
    let success: Bool
    let content: String
    let scores: [String: Int]
    let totalScore: Double

    init(from json: [String: Any]) {
        self.success = json["success"] as? Bool ?? false
        if let feedback = json["feedback"] as? [String: Any] {
            self.content = feedback["content"] as? String ?? ""
            self.totalScore = feedback["total_score"] as? Double ?? 0.0
            if let scoresDict = feedback["scores"] as? [String: Int] {
                self.scores = scoresDict
            } else {
                self.scores = [:]
            }
        } else {
            self.content = ""
            self.scores = [:]
            self.totalScore = 0.0
        }
    }
}

/// GET /latest_feedback 响应（读后即焚）
struct LatestFeedbackResponse {
    let hasFeedback: Bool
    let content: String?
    let scores: [String: Int]?
    let totalScore: Double?
    let componentName: String?
    let triggerType: String?

    init(from json: [String: Any]) {
        self.hasFeedback = json["has_feedback"] as? Bool ?? false

        if self.hasFeedback, let feedback = json["feedback"] as? [String: Any] {
            self.content = feedback["content"] as? String
            self.totalScore = feedback["total_score"] as? Double
            if let scoresDict = feedback["scores"] as? [String: Int] {
                self.scores = scoresDict
            } else {
                self.scores = nil
            }
            self.componentName = json["component_name"] as? String
            self.triggerType = json["trigger_type"] as? String
        } else {
            self.content = nil
            self.scores = nil
            self.totalScore = nil
            self.componentName = nil
            self.triggerType = nil
        }
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器返回无效响应"
        case .httpError(let code):
            return "HTTP 错误 (\(code))"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}
