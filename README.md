# IntentRelay

IntentRelay is a GenAI-assisted hybrid prototyping system designed to support design intent continuity across physical and virtual prototyping activities. This repository contains the implementation and experimental data associated with the paper *"IntentRelay: Supporting Design Intent Continuity Across Physical–Virtual Transitions in GenAI-Assisted Hybrid Prototyping."*

## Overview

IntentRelay integrates a visionOS application with a Python backend to capture design-related visual and verbal information, maintain evolving design intent in object-centered memory, and reuse stored intent to support subsequent design generation and feedback.

## Deployment

### Prerequisites

- **macOS** with Xcode and the visionOS SDK installed.
- **Apple Vision Pro** for running the mixed reality application.
- **Python environment** with dependencies listed in `backend/requirements.txt`.
- **Gemini API Access** for AI-based intent analysis and memory processing.
- **Supporting Services**: ComfyUI for image generation, iFlytek API for speech transcription, and a Hunyuan3D service for 3D model generation when using the corresponding features.
- **CUDA-enabled GPU** for the current YOLO-based object detection service.

### Configuration

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/luruoqing9-debug/IntentRelay.git
   cd IntentRelay
   ```

2. **Set Up the Backend**:

   ```bash
   cd backend
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

3. **Configure API Keys and Services**:

   Create a `.env` file in the `backend/` directory and configure the required credentials:

   ```env
   GEMINI_API_KEY=YOUR_API_KEY

   # Speech transcription
   XFYUN_ASR_APPID=YOUR_APP_ID
   XFYUN_ASR_API_KEY=YOUR_API_KEY
   XFYUN_ASR_API_SECRET=YOUR_API_SECRET

   # ComfyUI image generation
   COMFYUI_URL=http://127.0.0.1:8188
   COMFY_API_KEY=YOUR_API_KEY
   ```

   Configure the corresponding service endpoints and supporting resources before enabling image and 3D model generation.

4. **Start the Backend**:

   From the `backend/` directory, run:

   ```bash
   python api.py
   ```

   The HTTP API server runs on port `9000` by default.

5. **Build the visionOS Application**:

   - Open `frontend/IntentRelay.xcodeproj` in Xcode.
   - Select the `IntentRelay` target and configure your development team and bundle identifier.
   - Configure signing for the `IntentRelayRecorder` extension.
   - Update the backend URL in `frontend/IntentRelay/Network/BackendAPI.swift` to match your server address.
   - If using first-person screen capture, configure the streaming endpoint in `frontend/IntentRelayRecorder/SampleHandler.swift`.
   - Build and run the application on Apple Vision Pro.

### Supporting Services

The repository also includes supporting components for first-person frame streaming, object detection, and image generation.

- `backend/LiveAPI.py`: Receives and distributes first-person video frames.
- `backend/trigger.py` and `services/yolo/`: Support visual detection and trigger processing.
- `services/comfyui/`: Contains the custom node used for ComfyUI integration.

These services require separate configuration of their endpoints, model weights, and runtime environments. The ComfyUI workflow files and external 3D generation service must also be configured separately.

## Experimental Data

The experimental dataset associated with this research is available in:

`experimental_data/Intentrelay_Data.xlsx`

