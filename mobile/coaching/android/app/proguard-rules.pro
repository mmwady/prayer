# MediaPipe uses Protobuf Lite reflective field schemas. R8 must preserve the
# generated field names (e.g. platform_) and their storage, including release APKs.
# Official guidance: https://github.com/protocolbuffers/protobuf/blob/main/java/lite.md
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }

# Flogger discovers its enclosing class from the factory's stack frame. R8
# inlining/removal of that frame breaks MediaPipe Graph initialization.
# https://github.com/google/flogger/blob/master/api/src/main/java/com/google/common/flogger/FluentLogger.java
-keep class com.google.common.flogger.** { *; }

# MediaPipe's packaged JNI looks up Java packet fields by their original names,
# including ProtoUtil.SerializedMessage.typeName. Preserve this JNI boundary.
-keep class com.google.mediapipe.framework.ProtoUtil$SerializedMessage { *; }
-keep class com.google.mediapipe.framework.Packet { *; }

# JNI calls process() on these Java callbacks; ordinary Java callers cannot
# expose that reachability to R8. Keep interface dispatch and its implementations.
-keep interface com.google.mediapipe.framework.PacketListCallback { *; }
-keep class * implements com.google.mediapipe.framework.PacketListCallback { *; }
-keep interface com.google.mediapipe.framework.PacketCallback { *; }
-keep class * implements com.google.mediapipe.framework.PacketCallback { *; }

# ONNX Runtime JNI constructs Java values by name. Official Android R8 rule:
# https://onnxruntime.ai/docs/build/android.html
-keep class ai.onnxruntime.** { *; }
