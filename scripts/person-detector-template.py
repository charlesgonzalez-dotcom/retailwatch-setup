"""
RetailWatch — Store Person Detector
Reads store config from C:\RetailWatch\store-config.json
Pushes detections to Supabase
"""

import os, threading, time, json
from http.server import HTTPServer, BaseHTTPRequestHandler

try:
    import cv2
except ImportError:
    print("ERROR: opencv-python-headless not installed. Run setup script first.")
    input("Press Enter to exit..."); exit(1)

try:
    from ultralytics import YOLO
except ImportError:
    print("ERROR: ultralytics not installed. Run setup script first.")
    input("Press Enter to exit..."); exit(1)

try:
    import requests as req_lib
except ImportError:
    print("ERROR: requests not installed. Run setup script first.")
    input("Press Enter to exit..."); exit(1)

# ── Load store config ─────────────────────────────────────────────────────────
CONFIG_PATH = r'C:\RetailWatch\store-config.json'
try:
    with open(CONFIG_PATH) as f:
        store_cfg = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read {CONFIG_PATH}: {e}")
    print("Run 2-configure-store.ps1 first.")
    input("Press Enter to exit..."); exit(1)

STORE_NAME = store_cfg['store_name']
STORE_SLUG = store_cfg['store_slug']
CAMERAS    = store_cfg['cameras']

# ── Supabase ──────────────────────────────────────────────────────────────────
SUPABASE_URL = 'https://gncyncbgipvajskinpbv.supabase.co'
SUPABASE_KEY = 'sb_publishable_YiU_AByM8uiCSbzwwmjA9A_TUELjXpW'
SB_HEADERS   = {
    'apikey'       : SUPABASE_KEY,
    'Authorization': f'Bearer {SUPABASE_KEY}',
    'Content-Type' : 'application/json',
}

# ── Detection config ──────────────────────────────────────────────────────────
PROCESS_INTERVAL = 1.5
IMGSZ            = 416
CONFIDENCE       = 0.52
KP_MIN_CONF      = 0.50

KP_LEFT_SHOULDER  = 5
KP_RIGHT_SHOULDER = 6
KP_LEFT_WRIST     = 9
KP_RIGHT_WRIST    = 10
KP_LEFT_HIP       = 11
KP_RIGHT_HIP      = 12
KP_LEFT_KNEE      = 13
KP_RIGHT_KNEE     = 14

detections   = {}
lock         = threading.Lock()
model        = None
supabase_ids = {}


def fetch_supabase_ids():
    global supabase_ids
    try:
        r = req_lib.get(f"{SUPABASE_URL}/rest/v1/stores",
                        params={'slug': f"eq.{STORE_SLUG}", 'select': 'id'},
                        headers=SB_HEADERS, timeout=10)
        if not r.ok or not r.json():
            print(f"[WARN] Store '{STORE_SLUG}' not found in Supabase")
            return
        store_id = r.json()[0]['id']
        r2 = req_lib.get(f"{SUPABASE_URL}/rest/v1/cameras",
                         params={'store_id': f"eq.{store_id}", 'select': 'id,channel'},
                         headers=SB_HEADERS, timeout=10)
        cam_map = {c['channel']: c['id'] for c in r2.json()} if r2.ok else {}
        supabase_ids = {'store_id': store_id, 'cameras': cam_map}
        print(f"Supabase: store_id={store_id[:8]}... cameras={list(cam_map.keys())}")
    except Exception as e:
        print(f"[WARN] Supabase fetch failed: {e}")


def push_detection(cam_id, persons, suspicious, behaviors, status):
    if not supabase_ids:
        return
    camera_uuid = supabase_ids.get('cameras', {}).get(cam_id)
    if not camera_uuid:
        return
    def _push():
        try:
            req_lib.post(f"{SUPABASE_URL}/rest/v1/detections",
                         headers={**SB_HEADERS, 'Prefer': 'resolution=merge-duplicates'},
                         json={'camera_id': camera_uuid, 'store_id': supabase_ids['store_id'],
                               'persons': persons, 'suspicious': suspicious,
                               'behaviors': behaviors, 'status': status,
                               'recorded_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())},
                         timeout=5)
        except Exception:
            pass
    threading.Thread(target=_push, daemon=True).start()


def load_model():
    global model
    model_path = r'C:\RetailWatch\yolov8n-pose.pt'
    print("Loading YOLOv8-nano-pose model...")
    model = YOLO(model_path)
    print("Model ready.")


def get_kp(xy, conf, idx):
    return (float(xy[idx][0]), float(xy[idx][1])) if conf[idx] >= KP_MIN_CONF else None


def analyze_pose(xy, conf):
    flags = []
    l_shoulder = get_kp(xy, conf, KP_LEFT_SHOULDER)
    r_shoulder = get_kp(xy, conf, KP_RIGHT_SHOULDER)
    l_hip      = get_kp(xy, conf, KP_LEFT_HIP)
    r_hip      = get_kp(xy, conf, KP_RIGHT_HIP)
    l_knee     = get_kp(xy, conf, KP_LEFT_KNEE)
    r_knee     = get_kp(xy, conf, KP_RIGHT_KNEE)

    hip_y = (l_hip[1] + r_hip[1]) / 2 if l_hip and r_hip else (l_hip[1] if l_hip else (r_hip[1] if r_hip else None))
    shoulder_y = (l_shoulder[1] + r_shoulder[1]) / 2 if l_shoulder and r_shoulder else (l_shoulder[1] if l_shoulder else (r_shoulder[1] if r_shoulder else None))
    knee_y = (l_knee[1] + r_knee[1]) / 2 if l_knee and r_knee else (l_knee[1] if l_knee else (r_knee[1] if r_knee else None))

    if hip_y is None or shoulder_y is None:
        return flags

    body_height = abs(hip_y - shoulder_y)
    if knee_y and shoulder_y >= knee_y:
        flags.append('crouching')
    if knee_y and 'crouching' not in flags:
        mid_thigh_y = (hip_y + knee_y) / 2
        if shoulder_y > mid_thigh_y + body_height * 0.10:
            flags.append('deep_bend')
    return flags


def detect_camera(cam):
    cam_id  = cam['id']
    cam_key = f"{STORE_NAME}_cam{cam_id}"
    print(f"  Starting: {cam_key}")
    cap = None

    while True:
        try:
            if cap is None or not cap.isOpened():
                cap = cv2.VideoCapture(cam['url'])
                cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
                if not cap.isOpened():
                    with lock:
                        detections[cam_key] = {'persons': 0, 'suspicious': 0, 'behaviors': [],
                                               'status': 'offline', 'cam': cam_id,
                                               'timestamp': int(time.time() * 1000)}
                    push_detection(cam_id, 0, 0, [], 'offline')
                    time.sleep(10); cap = None; continue

            for _ in range(4):
                cap.grab()
            ret, frame = cap.retrieve()
            if not ret:
                cap.release(); cap = None; continue

            results = model(frame, imgsz=IMGSZ, conf=CONFIDENCE, verbose=False)
            person_count = sum(len(r.boxes) for r in results)
            suspicious_count = 0
            all_behaviors = []

            if person_count >= 2:
                for r in results:
                    if r.keypoints is not None and len(r.keypoints) > 0:
                        kp_xy   = r.keypoints.xy.cpu().numpy()
                        kp_conf = r.keypoints.conf.cpu().numpy()
                        for i in range(len(r.boxes)):
                            behaviors = analyze_pose(kp_xy[i], kp_conf[i])
                            if behaviors:
                                suspicious_count += 1
                                all_behaviors.extend(behaviors)

            unique_behaviors = list(set(all_behaviors))
            with lock:
                detections[cam_key] = {'persons': person_count, 'suspicious': suspicious_count,
                                       'behaviors': unique_behaviors, 'status': 'online',
                                       'cam': cam_id, 'timestamp': int(time.time() * 1000)}
            push_detection(cam_id, person_count, suspicious_count, unique_behaviors, 'online')

        except Exception as e:
            print(f"  [{cam_key}] Error: {e}")
            if cap:
                try: cap.release()
                except: pass
            cap = None
            with lock:
                detections[cam_key] = {'persons': 0, 'suspicious': 0, 'behaviors': [],
                                       'status': 'error', 'cam': cam_id,
                                       'timestamp': int(time.time() * 1000)}
            push_detection(cam_id, 0, 0, [], 'error')

        time.sleep(PROCESS_INTERVAL)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        if self.path == '/detections':
            with lock:
                self.wfile.write(json.dumps(detections).encode())
        elif self.path == '/health':
            with lock:
                online = sum(1 for d in detections.values() if d.get('status') == 'online')
            self.wfile.write(json.dumps({'status': 'ok', 'store': STORE_NAME,
                                         'cameras': len(detections), 'online': online}).encode())
        else:
            self.wfile.write(b'{}')

    def log_message(self, fmt, *args):
        pass


if __name__ == '__main__':
    print(f"\nRetailWatch Person Detector — {STORE_NAME}")
    print(f"Monitoring {len(CAMERAS)} cameras\n")
    load_model()
    fetch_supabase_ids()
    print("Starting camera threads...")
    for cam in CAMERAS:
        threading.Thread(target=detect_camera, args=(cam,), daemon=True).start()
    print(f"\nDetection API: http://localhost:3002/detections")
    print("Press Ctrl+C to stop.\n")
    try:
        HTTPServer(('', 3002), Handler).serve_forever()
    except KeyboardInterrupt:
        print("Stopped.")
