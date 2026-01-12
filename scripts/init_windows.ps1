# Create and enter download directory
New-Item -ItemType Directory -Force -Path "download" | Out-Null
Set-Location "download"

# Download OpenCV archives
Invoke-WebRequest `
  -Uri "https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-android-sdk.zip" `
  -OutFile "opencv-4.12.0-android-sdk.zip"

Invoke-WebRequest `
  -Uri "https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-ios-framework.zip" `
  -OutFile "opencv-4.12.0-ios-framework.zip"

# Extract archives
Expand-Archive -Force "opencv-4.12.0-android-sdk.zip" .
Expand-Archive -Force "opencv-4.12.0-ios-framework.zip" .

# Copy iOS framework
Copy-Item `
  -Recurse -Force `
  "opencv2.framework" `
  "..\..\native_opencv\ios"

# Copy Android headers
Copy-Item `
  -Recurse -Force `
  "OpenCV-android-sdk\sdk\native\jni\include" `
  "..\..\native_opencv"

# Create Android jniLibs directory
New-Item `
  -ItemType Directory `
  -Force `
  "..\..\native_opencv\android\src\main\jniLibs" | Out-Null

# Copy Android native libraries
Copy-Item `
  -Recurse -Force `
  "OpenCV-android-sdk\sdk\native\libs\*" `
  "..\..\native_opencv\android\src\main\jniLibs"

# Copy Android JNI includes (mirrors your sh script, even if redundant)
Copy-Item `
  -Recurse -Force `
  "OpenCV-android-sdk\sdk\native\jni\include" `
  "..\..\native_opencv\android\src\main\jniLibs"

Write-Host "dun :)"
