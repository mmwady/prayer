import json,time
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps,ImageEnhance
import torch,mediapipe as mp

class PrayerActionPredictor:
 def __init__(self,bundle_dir):
  self.root=Path(bundle_dir); self.meta=json.loads((self.root/'model_metadata.json').read_text()); z=np.load(self.root/'preprocessing.npz')
  self.mean=z['mean']; self.std=z['std']; self.models={k:[torch.jit.load(str(self.root/p)).eval() for p in v] for k,v in self.meta['components'].items()}
  Base=mp.tasks.BaseOptions; Opt=mp.tasks.vision.PoseLandmarkerOptions; Mode=mp.tasks.vision.RunningMode
  self.detector=mp.tasks.vision.PoseLandmarker.create_from_options(Opt(base_options=Base(model_asset_path=str(self.root/'pose_landmarker_heavy.task')),running_mode=Mode.IMAGE,min_pose_detection_confidence=.2,min_pose_presence_confidence=.2,min_tracking_confidence=.2,num_poses=1))
 def _prepare(self,path):
  im=ImageOps.exif_transpose(Image.open(path)).convert('RGB'); canvas=Image.new('RGB',(384,512),(0,0,0)); im.thumbnail((384,512),Image.Resampling.LANCZOS); canvas.paste(im,((384-im.width)//2,(512-im.height)//2)); return canvas
 def _feature(self,path):
  image=self._prepare(path); candidates=[('standard',image),('autocontrast',ImageOps.autocontrast(image,cutoff=1)),('contrast_1.15',ImageEnhance.Contrast(image).enhance(1.15)),('rotate_minus_5',image.rotate(-5,Image.Resampling.BICUBIC)),('rotate_plus_5',image.rotate(5,Image.Resampling.BICUBIC))]
  for method,im in candidates:
   result=self.detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB,data=np.asarray(im)))
   if not result.pose_landmarks: continue
   lm=result.pose_landmarks[0]; xyz=np.array([[p.x,p.y,p.z] for p in lm],np.float32); vis=np.array([getattr(p,'visibility',0.) or 0. for p in lm],np.float32); pres=np.array([getattr(p,'presence',0.) or 0. for p in lm],np.float32)
   hip=xyz[[23,24]].mean(0); scale=max(np.linalg.norm(xyz[[11,12],:2].mean(0)-hip[:2]),np.linalg.norm(xyz[11,:2]-xyz[12,:2]))
   if np.isfinite(xyz).all() and scale>1e-4:
    feat=np.r_[((xyz-hip)/scale).ravel(),vis,pres,1.].astype(np.float32); return np.r_[(feat[:-1]-self.mean)/self.std,feat[-1]].astype(np.float32),method,float(vis.mean())
  return None,'failed',None
 def _avg(self,name,x):
  with torch.inference_mode(): return np.mean([torch.softmax(m(x),1).numpy()[0] for m in self.models[name]],axis=0)
 def predict(self,image_path):
  started=time.perf_counter(); feat,method,visibility=self._feature(image_path)
  if feat is None: return {'predicted_action':None,'confidence':0.0,'pose_detected':False,'normalization_valid':False,'recovery_method':'failed','warning':'Pose detection and recovery failed.'}
  x=torch.tensor(feat[None],dtype=torch.float32); winner=self.meta['winner']
  if winner=='exp4_probability_fusion':
   w=self.meta['fusion_weights']; p=w['full_weight']*self._avg('full',x)+w['head_weight']*self._avg('head',x)+w['arm_weight']*self._avg('arm',x)
  elif winner in ('exp5_hierarchy_hard','exp6_hierarchy_soft'):
   pg,pq,ps=self._avg('general',x),self._avg('qiyam',x),self._avg('sitting',x); p=np.zeros(8); p[[0,2]]=pg[0]*pq; p[1]=pg[1]; p[3]=pg[2]; p[4]=pg[3]; p[5:8]=pg[4]*ps
   if self.meta['hard_hierarchy']:
    r=pg.argmax(); q=p.copy()*0
    if r==0:q[[0,2]]=pq
    elif r==1:q[1]=1
    elif r==2:q[3]=1
    elif r==3:q[4]=1
    else:q[5:8]=ps
    p=q
  else: p=self._avg('main',x)
  p=p/p.sum(); order=np.argsort(p)[::-1]; classes=self.meta['classes']; result={'predicted_action':classes[int(order[0])],'class_index':int(order[0]),'confidence':float(p[order[0]]),'probabilities':{classes[i]:float(p[i]) for i in range(8)},'top3':[{'action':classes[int(i)],'probability':float(p[i])} for i in order[:3]],'pose_detected':True,'normalization_valid':True,'recovery_method':method,'mean_visibility':visibility,'model_type':winner,'inference_ms':(time.perf_counter()-started)*1000,'warning':None}; return result
 def predict_json(self,image_path): return json.dumps(self.predict(image_path),ensure_ascii=False,indent=2)
 def close(self): self.detector.close()
