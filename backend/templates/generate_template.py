import cv2
import mediapipe as mp
import json
import os
import argparse

# -----------------------------------------------------------------------------
# Video to JSON Template Generator for Action Recognition
#
# This script processes a PRE-RECORDED VIDEO FILE of an exercise repetition.
# It does NOT open the live web camera. It extracts the skeletal keypoints 
# using MediaPipe frame-by-frame and exports them into a JSON template.
# -----------------------------------------------------------------------------

class TemplateGenerator:
    def __init__(self):
        # Initialize MediaPipe Pose model with high accuracy settings.
        self.mp_pose = mp.solutions.pose
        self.pose = self.mp_pose.Pose(
            static_image_mode=False,
            model_complexity=2, # Highest accuracy model for robust templates
            min_detection_confidence=0.8,
            min_tracking_confidence=0.8
        )
        
        # Mapping MediaPipe landmark indices to our Dart App's KeypointId strings.
        self.landmark_map = {
            0: 'nose', 2: 'leftEye', 5: 'rightEye', 7: 'leftEar', 8: 'rightEar',
            11: 'leftShoulder', 12: 'rightShoulder', 13: 'leftElbow', 14: 'rightElbow',
            15: 'leftWrist', 16: 'rightWrist', 23: 'leftHip', 24: 'rightHip',
            25: 'leftKnee', 26: 'rightKnee', 27: 'leftAnkle', 28: 'rightAnkle'
        }

    def generate(self, video_path: str, output_json_path: str):
        """
        Reads the provided video file frame by frame, extracts normalized keypoints,
        computes the 'spineMid' point, and saves the sequence as a JSON file.
        """
        if not os.path.exists(video_path):
            raise FileNotFoundError(f"Error: The video file '{video_path}' was not found.")

        # Pass the video file path to OpenCV (this reads the file, NOT the webcam)
        cap = cv2.VideoCapture(video_path)
        sequence = []

        print(f"Processing video file: {video_path}...")

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break # Reached the end of the video file

            # Convert BGR (OpenCV format) to RGB (MediaPipe format)
            image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = self.pose.process(image_rgb)

            if results.pose_landmarks:
                frame_keypoints = []
                landmarks = results.pose_landmarks.landmark

                # 1. Extract mapped COCO points
                for idx, name in self.landmark_map.items():
                    lm = landmarks[idx]
                    frame_keypoints.append({
                        "id": name,
                        "x": lm.x,          # Normalized 0.0 to 1.0
                        "y": lm.y,          # Normalized 0.0 to 1.0
                        "confidence": lm.visibility
                    })

                # 2. Compute custom 'spineMid' point for the 'curved_back' rule
                ls = landmarks[11] # Left Shoulder
                rs = landmarks[12] # Right Shoulder
                lh = landmarks[23] # Left Hip
                rh = landmarks[24] # Right Hip

                spine_x = (ls.x + rs.x + lh.x + rh.x) / 4.0
                spine_y = (ls.y + rs.y + lh.y + rh.y) / 4.0
                spine_vis = min(ls.visibility, rs.visibility, lh.visibility, rh.visibility)

                frame_keypoints.append({
                    "id": "spineMid",
                    "x": spine_x,
                    "y": spine_y,
                    "confidence": spine_vis
                })

                sequence.append(frame_keypoints)

        cap.release()

        # 3. Save the extracted sequence to a JSON file
        with open(output_json_path, 'w', encoding='utf-8') as f:
            json.dump(sequence, f, indent=2)
            
        print(f"Success! Generated template with {len(sequence)} frames.")
        print(f"Saved to: {output_json_path}")

# -----------------------------------------------------------------------------
# Command Line Interface (CLI) Setup
# This allows you to run the script directly from the terminal with arguments.
# -----------------------------------------------------------------------------
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert an exercise video file into a JSON template.")
    
    # Required argument: The path to the video file
    parser.add_argument("video_file", help="Path to the input video file (e.g., squat_video.mp4)")
    
    # Optional argument: The path to save the JSON file (defaults to template.json)
    parser.add_argument("--output", default="template.json", help="Path to save the output JSON (default: template.json)")
    
    args = parser.parse_args()
    
    generator = TemplateGenerator()
    try:
        generator.generate(args.video_file, args.output)
    except Exception as e:
        print(str(e))