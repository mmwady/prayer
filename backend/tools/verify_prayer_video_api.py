"""Run from backend with a consented local video path; no paid services."""
import sys, io, json, base64, time
from pathlib import Path
import cv2
import httpx
from PIL import Image
base="http://127.0.0.1:8000/api/v1/prayer-analyses"
cap=cv2.VideoCapture(sys.argv[1]); fps=cap.get(cv2.CAP_PROP_FPS)
duration=int(cap.get(cv2.CAP_PROP_FRAME_COUNT)/fps*1000)
with httpx.Client(timeout=60) as client:
    config=client.get(base+"/config").json(); rate=config["frame_sample_fps"]
    response=client.post(base,json=dict(prayer="demo",duration_ms=duration,sample_fps=rate,upload_consent=True)); response.raise_for_status()
    data=response.json(); url=base+"/"+data["job_id"]; headers={"Authorization":"Bearer "+data["access_token"]}
    try:
        batch=[]; batch_id=0
        for i in range(int(duration/1000*rate)):
            ms=int(i*1000/rate);cap.set(cv2.CAP_PROP_POS_MSEC,ms);ok,frame=cap.read()
            if not ok: break
            image=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB));image.thumbnail((config["max_dimension"],config["max_dimension"]))
            buf=io.BytesIO();image.save(buf,format="JPEG",quality=80)
            batch.append(dict(frame_id=f"f{i}",timestamp_ms=ms,sequence_index=i,jpeg_base64=base64.b64encode(buf.getvalue()).decode()))
            if len(batch)==config["batch_frames"]:
                client.post(url+"/frames",headers=headers,json=dict(batch_id=str(batch_id),frames=batch)).raise_for_status();batch=[];batch_id+=1
        if batch: client.post(url+"/frames",headers=headers,json=dict(batch_id=str(batch_id),frames=batch)).raise_for_status()
        client.post(url+"/complete",headers=headers).raise_for_status()
        for attempt in range(240):
            status=client.get(url,headers=headers).json()
            if status["status"] in ("FAILED","COMPLETED"): break
            if attempt%20==0: print({"status":status["status"],"progress":status.get("processed_frames")},flush=True)
            time.sleep(.5)
        assert status["status"]=="COMPLETED",status
        response=client.get(url+"/report",headers=headers);response.raise_for_status();report=response.json()
        out=Path("../output/video_diagnosis/api_report.json");out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
        print({"result":report["overall_result"],"observed_rakahs":report["observed_rakahs"],"frames":report["metrics"]["processed_frames"],"stations":[(s["station"],s["status"]) for s in report["rakahs"][0]["stations"]]},flush=True)
    finally:
        cap.release();client.delete(url,headers=headers).raise_for_status()
