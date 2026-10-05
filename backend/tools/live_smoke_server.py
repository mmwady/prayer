"""Isolated synthetic transport QA backend. No .env, provider calls or real media.

Run from backend/: python tools/live_smoke_server.py [--port 8013]
"""
import argparse
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import main
from app.config import Settings
from tools import tunnel_gateway
import uvicorn

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8013)
    parser.add_argument('--prediction-delay', type=float, default=0)
    args = parser.parse_args()
    if args.prediction_delay:
        from app.analysis.inference import InferencePipeline
        predict = InferencePipeline.predict
        def slow_predict(self, *values, **keywords):
            time.sleep(args.prediction_delay)
            return predict(self, *values, **keywords)
        InferencePipeline.predict = slow_predict
    settings = Settings(_env_file=None, analysis_allow_mock=True, inference_provider='mock',
                        prayer_guidance_enabled=False, mosque_demo_enabled=False,
                        analysis_storage_dir='../output/playwright/live-jobs')
    main.get_settings = lambda: settings
    tunnel_gateway.backend_app = main.create_app()
    uvicorn.run(tunnel_gateway.app, host='127.0.0.1', port=args.port,
                ws_max_size=settings.analysis_max_frame_bytes + 1028)
