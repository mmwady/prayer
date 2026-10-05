# Third-party software

MediaPipe Tasks Vision: Copyright Google LLC / The MediaPipe Authors, Apache License 2.0.
The pinned package's normalized-landmark converter is modified at build time to retain
protobuf presence field 5. The graph and model assets are unchanged.
https://github.com/google-ai-edge/mediapipe/blob/master/LICENSE

ONNX Runtime Web: Copyright Microsoft Corporation, MIT License.
https://github.com/microsoft/onnxruntime/blob/main/LICENSE

Pillow reference image algorithms: Copyright Secret Labs AB and Fredrik Lundh and
Pillow contributors. HPND license. JavaScript implementations reproduce Pillow behavior.
https://github.com/python-pillow/Pillow/blob/main/LICENSE

Model weights/task file remain the supplied project artifacts; this implementation
does not assert additional redistribution rights for them.

fast-png and its PNG decompression dependencies: MIT license; used to preserve
unassociated RGB when dropping alpha as Pillow does, and to avoid implicit color
management in PNG decoding. https://github.com/image-js/fast-png/blob/main/LICENSE
