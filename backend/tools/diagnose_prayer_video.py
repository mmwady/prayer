import sys, json, io
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import cv2
from PIL import Image, ImageDraw
from app.analysis.prayer_action_predictor import PrayerActionPredictor
from app.analysis.inference import Observation
from app.analysis.domain import DEFAULT_POSE_MAP
from app.analysis.temporal import process
from app.analysis.sequence import analyze
from app.config import get_settings
settings=get_settings()
source=sys.argv[1]
out=Path('../output/video_diagnosis'); out.mkdir(parents=True,exist_ok=True)
cap=cv2.VideoCapture(source)
fps=cap.get(cv2.CAP_PROP_FPS); count=cap.get(cv2.CAP_PROP_FRAME_COUNT)
print({'fps':fps,'duration':count/fps},flush=True)
predictor=PrayerActionPredictor(settings.prayer_model_bundle_dir)
predictor.mirror_sujood_recovery=settings.prayer_mirror_sujood_recovery
predictor.ruku_geometry_gate=settings.prayer_ruku_geometry_gate
rows=[]; thumbs=[]
try:
 for i in range(int(count/fps*4)):
  ms=i*250
  cap.set(cv2.CAP_PROP_POS_MSEC,ms); ok,frame=cap.read()
  if not ok: break
  image=Image.fromarray(cv2.cvtColor(frame,cv2.COLOR_BGR2RGB))
  result=predictor.predict(image)
  prob=result.get('probabilities',{}); seated=sum(prob.get(k,0) for k in ('6_Jalsa','7_Salam_Right','8_Salam_Left'))
  if settings.prayer_seated_probability_projection and result['confidence'] < settings.temporal_confidence and seated >= settings.temporal_confidence:
   result={**result,'predicted_action':'6_Jalsa','confidence':seated}
  rows.append(dict(timestamp_ms=ms,**result))
  if i%8==0:
   image.thumbnail((180,240)); tile=Image.new('RGB',(190,275),'white'); tile.paste(image,(0,0)); ImageDraw.Draw(tile).text((3,242),f'{ms/1000:.1f}s {result.get("predicted_action")} {result["confidence"]:.2f}',fill='black'); thumbs.append(tile)
  if i%40==0: print(f'{ms/1000}s',flush=True)
finally:
 cap.release(); predictor.close()
(out/'predictions.json').write_text(json.dumps(rows,indent=2))
obs=[Observation(f'f{i}',r['timestamp_ms'],i,DEFAULT_POSE_MAP.get(r.get('predicted_action'),'unknown'),r['confidence'],r['pose_detected']) for i,r in enumerate(rows)]
events=process(obs)
report=analyze('diagnostic','demo',events,'real',4,len(obs),'actual',normalize_sequence=settings.prayer_sequence_normalization)
(out/'report.json').write_text(report.model_dump_json(indent=2))
print([(e.pose,e.start_ms/1000,e.end_ms/1000,round(e.confidence,2)) for e in events],flush=True)
canvas=Image.new('RGB',(190*6,275*((len(thumbs)+5)//6)),'white')
for i,t in enumerate(thumbs): canvas.paste(t,((i%6)*190,(i//6)*275))
canvas.save(out/'contact_sheet.jpg')
