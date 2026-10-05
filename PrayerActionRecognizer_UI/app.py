from __future__ import annotations

import threading
import time
from collections import deque
from pathlib import Path

import av
import numpy as np
import streamlit as st
from PIL import Image, ImageOps
from streamlit_webrtc import WebRtcMode, webrtc_streamer


APP_DIR = Path(__file__).resolve().parent
BUNDLE_DIR = APP_DIR / "deployment_bundle"

ACTION_NAMES = {
    "1_Qiyam": ("Qiyam", "القيام"),
    "2_Takbir": ("Takbir", "التكبير"),
    "3_Qiyam_Recitation": ("Qiyam recitation", "القيام والقراءة"),
    "4_Ruku": ("Ruku", "الركوع"),
    "5_Sujud": ("Sujud", "السجود"),
    "6_Jalsa": ("Jalsa", "الجلسة"),
    "7_Salam_Right": ("Salam right", "التسليم يمينًا"),
    "8_Salam_Left": ("Salam left", "التسليم يسارًا"),
}


st.set_page_config(
    page_title="Prayer action recognizer",
    page_icon="🕌",
    layout="wide",
    initial_sidebar_state="collapsed",
)

st.markdown(
    """
    <style>
      .stApp { background: linear-gradient(145deg, #f7f4eb 0%, #edf5ef 100%); }
      .block-container { max-width: 1080px; padding-top: 2.2rem; }
      .hero { text-align: center; margin-bottom: 1.4rem; }
      .hero h1 { color: #173f35; margin-bottom: .25rem; }
      .hero p { color: #587068; font-size: 1.05rem; }
      .result-card {
        background: #ffffff; border: 1px solid #d9e6df; border-radius: 18px;
        padding: 1.4rem 1.6rem; box-shadow: 0 8px 24px rgba(24, 67, 56, .08);
      }
      .result-label { color: #657a73; font-size: .88rem; text-transform: uppercase; }
      .result-main { color: #123f34; font-size: 2rem; font-weight: 750; margin: .25rem 0; }
      .result-ar { color: #9a6b1f; font-size: 1.35rem; direction: rtl; }
      [data-testid="stFileUploader"], [data-testid="stCameraInput"] {
        background: rgba(255,255,255,.72); border-radius: 14px; padding: .5rem;
      }
      div.stButton > button { background: #176b56; color: white; border-radius: 10px; }
    </style>
    """,
    unsafe_allow_html=True,
)


@st.cache_resource(show_spinner="Loading prayer action model…")
def load_predictor():
    from deployment_bundle.imcspd_inference import PrayerActionPredictor

    required = [
        "model_metadata.json",
        "preprocessing.npz",
        "pose_landmarker_heavy.task",
        "main_seed_2026.pt",
        "main_seed_3407.pt",
        "main_seed_8111.pt",
    ]
    missing = [name for name in required if not (BUNDLE_DIR / name).is_file()]
    if missing:
        raise FileNotFoundError("Missing deployment files: " + ", ".join(missing))
    return PrayerActionPredictor(BUNDLE_DIR)


def action_label(code: str) -> tuple[str, str]:
    return ACTION_NAMES.get(code, (code.replace("_", " "), ""))


def show_result(result: dict) -> None:
    if not result.get("pose_detected"):
        st.warning(
            "No usable body pose was detected. Keep the full body visible, improve "
            "the lighting, and reduce background clutter."
        )
        return

    english, arabic = action_label(result["predicted_action"])
    confidence = float(result["confidence"])
    st.markdown(
        f"""
        <div class="result-card">
          <div class="result-label">Predicted prayer action</div>
          <div class="result-main">{english}</div>
          <div class="result-ar">{arabic}</div>
        </div>
        """,
        unsafe_allow_html=True,
    )
    st.metric("Confidence", f"{confidence:.1%}")
    st.progress(confidence)

    st.subheader("Top predictions")
    for item in result.get("top3", []):
        label, _ = action_label(item["action"])
        st.markdown(f"{label} — **{item['probability']:.1%}**")
        st.progress(float(item["probability"]))

    with st.expander("Prediction details"):
        st.markdown(f"Model: `{result.get('model_type', 'unknown')}`")
        st.markdown(f"Pose recovery: `{result.get('recovery_method', 'unknown')}`")
        st.markdown(
            f"Mean landmark visibility: `{result.get('mean_visibility', 0):.3f}`"
        )
        st.markdown(f"Inference time: `{result.get('inference_ms', 0):.0f} ms`")


class PrayerVideoProcessor:
    """Draw pose landmarks and capture stable, confident prayer actions."""

    def __init__(self, predictor, minimum_confidence: float):
        self.predictor = predictor
        self.minimum_confidence = minimum_confidence
        self._lock = threading.Lock()
        self._captures = deque(maxlen=12)
        self._candidate = None
        self._stable_count = 0
        self._last_captured_action = None
        self._last_capture_time = 0.0
        self._last_result = None
        self._last_annotated = None
        self._last_inference_time = 0.0

    def recv(self, frame):
        rgb = frame.to_ndarray(format="rgb24")
        now = time.monotonic()

        # Limit heavy model inference while keeping the returned video smooth.
        if now - self._last_inference_time >= 0.22:
            result, annotated = self.predictor.analyze(rgb)
            self._last_inference_time = now
            self._last_result = result
            self._last_annotated = annotated
            self._update_capture(result, annotated, now)

        output = self._last_annotated
        if output is None:
            output = Image.fromarray(rgb)
        return av.VideoFrame.from_ndarray(
            np.ascontiguousarray(output), format="rgb24"
        )

    def _update_capture(self, result, annotated, now):
        action = result.get("predicted_action") if result.get("pose_detected") else None
        confidence = float(result.get("confidence", 0.0))
        if action is None or confidence < self.minimum_confidence:
            self._candidate = None
            self._stable_count = 0
            return

        if action == self._candidate:
            self._stable_count += 1
        else:
            self._candidate = action
            self._stable_count = 1
            if action != self._last_captured_action:
                self._last_captured_action = None

        stable = self._stable_count >= 3
        cooled_down = now - self._last_capture_time >= 3.0
        is_new_action = action != self._last_captured_action
        if stable and cooled_down and is_new_action:
            capture = {
                "image": annotated.copy(),
                "result": dict(result),
                "captured_at": time.strftime("%H:%M:%S"),
            }
            with self._lock:
                self._captures.appendleft(capture)
            self._last_capture_time = now
            self._last_captured_action = action

    def captures(self):
        with self._lock:
            return list(self._captures)

    def clear(self):
        with self._lock:
            self._captures.clear()


def render_realtime_mode() -> None:
    st.subheader("Real-time camera recognition")
    st.markdown(
        "Start the camera and keep your full body in frame. Green lines and gold points "
        "show the detected pose. A posture is captured after three confident matches."
    )
    confidence_percent = st.slider(
        "Automatic capture confidence",
        min_value=50,
        max_value=95,
        value=70,
        step=5,
        format="%d%%",
        key="live_confidence",
    )
    minimum_confidence = confidence_percent / 100
    predictor = load_predictor()
    context = webrtc_streamer(
        key="prayer-live-camera",
        mode=WebRtcMode.SENDRECV,
        media_stream_constraints={"video": True, "audio": False},
        video_processor_factory=lambda: PrayerVideoProcessor(
            predictor, minimum_confidence
        ),
        async_processing=True,
        video_html_attrs={"autoPlay": True, "controls": False, "muted": True},
    )
    if context.video_processor:
        context.video_processor.minimum_confidence = minimum_confidence

    @st.fragment(run_every=1)
    def captured_actions_gallery():
        processor = context.video_processor
        st.subheader("Captured actions")
        if processor is None:
            st.info("Start the camera to begin automatic recognition.")
            return

        captures = processor.captures()
        if not captures:
            st.info("No stable action has been captured yet.")
            return

        if st.button("Clear captured actions", icon=":material/delete:"):
            processor.clear()
            captures = []
        if not captures:
            st.info("Captured actions cleared.")
            return

        for row_start in range(0, len(captures), 3):
            columns = st.columns(3)
            for column, capture in zip(columns, captures[row_start : row_start + 3]):
                result = capture["result"]
                english, arabic = action_label(result["predicted_action"])
                with column:
                    with st.container(border=True):
                        st.image(
                            capture["image"],
                            caption=f"{english} • {capture['captured_at']}",
                            alt=f"Captured {english} posture with pose landmarks",
                            width="stretch",
                        )
                        st.markdown(f"**{english}** · {arabic}")
                        st.metric("Confidence", f"{result['confidence']:.1%}")
                        st.caption(
                            f"Visibility {result.get('mean_visibility', 0):.2f} · "
                            f"{result.get('inference_ms', 0):.0f} ms"
                        )

    captured_actions_gallery()


def render_image_mode(source: str) -> None:
    if source == "Take a photo":
        image_file = st.camera_input("Take a clear, full-body photo")
    else:
        image_file = st.file_uploader(
            "Choose a full-body image",
            type=["jpg", "jpeg", "png", "webp"],
            help="For best results, keep the entire body visible with good lighting.",
        )

    if image_file is None:
        st.info("Provide an image above to begin.")
        st.caption("Privacy: images are processed locally and are not stored by this app.")
        return

    try:
        image_file.seek(0)
        preview = ImageOps.exif_transpose(Image.open(image_file)).convert("RGB")
    except Exception as exc:
        st.error(f"This image could not be opened: {exc}")
        return

    with st.spinner("Detecting pose and classifying action…"):
        try:
            result, annotated = load_predictor().analyze(preview)
        except Exception as exc:
            st.error("The model could not complete this prediction.")
            st.exception(exc)
            return

    left, right = st.columns([1, 1.05], gap="large")
    with left:
        st.image(
            annotated,
            caption="Detected pose landmarks",
            alt="Selected prayer image with pose landmarks over the body",
            width="stretch",
        )
    with right:
        show_result(result)


st.markdown(
    """
    <div class="hero">
      <h1>🕌 Prayer action recognizer</h1>
      <p>Recognize prayer postures from an image or a landmark-enabled live camera.</p>
    </div>
    """,
    unsafe_allow_html=True,
)

mode = st.segmented_control(
    "Recognition mode",
    options=["Upload image", "Take a photo", "Real-time camera"],
    default="Upload image",
    selection_mode="single",
    key="recognition_mode",
)

if mode == "Real-time camera":
    render_realtime_mode()
else:
    render_image_mode(mode)

st.caption(
    "This classifier is an AI estimate and may be incorrect. Use clear, full-body views for best results."
)
