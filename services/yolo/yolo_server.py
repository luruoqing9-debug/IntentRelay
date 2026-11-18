import cv2
import numpy as np
import base64
from flask import Flask, request, jsonify
from ultralytics import YOLO

app = Flask(__name__)

print("[yolo_server] 正在加载模型...")
model = YOLO('yolov8x-seg.pt')
model.to('cuda:3')
print("[yolo_server] 模型加载完成，使用 GPU 3")


@app.route('/yolo_process', methods=['POST'])
def yolo_process():
    data = request.get_json()
    img_base64 = data.get("frame")
    count = data.get("count")
    detection_info = []

    if not img_base64:
        return jsonify({"error": "no frame"}), 400

    frame_bytes = base64.b64decode(img_base64)
    frame_np = cv2.imdecode(
        np.frombuffer(frame_bytes, np.uint8),
        cv2.IMREAD_COLOR
    )

    results = model(frame_np, conf=0.4, iou=0.5, imgsz=640)

    boxes = results[0].boxes

    if boxes is not None and boxes.xyxyn is not None and boxes.cls is not None:
        for box, cls in zip(
            boxes.xyxyn.cpu().numpy(),
            boxes.cls.cpu().numpy()
        ):
            name = model.names[int(cls)]
            detection_info.append({
                "name": name,
                "box": [
                    float(box[0]),
                    float(box[1]),
                    float(box[2]),
                    float(box[3])
                ]
            })

    return jsonify({
        "count": count,
        "detection": detection_info,
        "view_point": None
    })


if __name__ == '__main__':
    print("[yolo_server] 启动: http://0.0.0.0:9002/yolo_process")
    app.run(host='0.0.0.0', port=9002, debug=False, threaded=True)
