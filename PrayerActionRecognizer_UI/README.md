# Prayer Action Recognizer UI

## Start

Double-click `start_app.bat`. On the first run it creates a private Python environment
and installs the required packages; later runs start faster. The app opens locally at
`http://localhost:8501`.

The UI supports three modes:

- Upload an image and display the detected body landmarks over it.
- Take a single browser-camera photo and display its landmarks and prediction.
- Run a real-time camera feed with a live pose skeleton. After three confident matches,
  the app automatically captures the action and displays its image, name, confidence,
  visibility, and inference time below the video.

Images are passed to the included `deployment_bundle` model locally. Allow camera access
in the browser when prompted. Real-time camera access works from the local `localhost` URL.

## Tips for prediction

- Keep the full body, including hands and feet, in frame.
- Use even lighting and a simple background.
- Face the camera in the orientation expected for the prayer action.
- If no pose is detected, move farther from the camera and retake the photo.

To stop the app, close its command window or press `Ctrl+C` there.
