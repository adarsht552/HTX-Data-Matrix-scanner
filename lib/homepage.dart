import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';  // Added for WriteBuffer and HapticFeedback
import 'package:flutter/foundation.dart'; // Added for compute
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:camera/camera.dart';
import 'package:htxdatamatrix/appconstant.dart';
import 'package:permission_handler/permission_handler.dart';
import 'scan_history_service.dart';
import 'history_page.dart';
// Import for InputImagePlaneMetadata
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'dart:math' as Math;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class ScannerScreen extends StatefulWidget {
  @override
  _ScannerScreenState createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with RouteAware, TickerProviderStateMixin {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  String result = "Scan a QR code";
  int _selectedIndex = 2;
  bool _isScanning = false;
  String? values;
  
  // Debug information
  bool _debugMode = true;
  Barcode? _lastDetectedBarcode;
  DateTime? _lastDetectionTime;
  String? lastScannedValue;
  // History service
  final ScanHistoryService _historyService = ScanHistoryService();

  
  // Camera controller
  CameraController? _cameraController;
  List<CameraDescription> cameras = [];
  
  // ML Kit scanner
  final BarcodeScanner _barcodeScanner = BarcodeScanner(
    formats: [
      BarcodeFormat.dataMatrix, // Make sure DataMatrix is first priority
      BarcodeFormat.qrCode,
      BarcodeFormat.aztec,   
      BarcodeFormat.code128, 
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.itf,
      BarcodeFormat.pdf417,
      BarcodeFormat.unknown,
    ],
  );
  bool _isBusy = false;
  
  // Zoom control
  double _currentZoom = 1.0;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  bool _autoZoomEnabled = false; // Auto-zoom disabled by default
  double _baseScaleFactor = 1.0; // For pinch zoom tracking
  
  // Flash control
  bool _isFlashOn = false;
  
  // Scan area animation controller
  double _scanAreaSize = 200.0;
  bool _isAnimating = false;
  
  // Scanning line animation
  late AnimationController _scanLineAnimationController;
  late Animation<double> _scanLineAnimation;
  
  // Scan success flash effect
  bool _showScanSuccessFlash = false;
  
  // Initial instruction overlay
  bool _showInstructions = true;

  @override
  void initState() {
    super.initState();
    // _requestCameraPermission();
    
    // Initialize scan line animation
    _scanLineAnimationController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scanLineAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Hide instructions after delay
    Future.delayed(Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _showInstructions = false;
        });
      }
    });
    
    // This will initialize the camera
    _initializeCamera();
    
    // Give some time for camera to initialize before starting scan
    Future.delayed(Duration(seconds: 2), () {
      if (mounted && _cameraController != null && _cameraController!.value.isInitialized) {
        _startScanning();
      }
    });
    
    // Add a periodic check to ensure camera scanning is still active
    Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted && _cameraController != null && _cameraController!.value.isInitialized && !_isScanning) {
        print("Periodic check: Restarting scanner because it's not active");
        _isBusy = false;
        _resumeScanning();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-start scanning once camera is ready
    if (_cameraController != null && 
        _cameraController!.value.isInitialized && 
        !_isScanning) {
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted && !_isScanning) {
          _isBusy = false; // Ensure busy flag is reset
          _startScanning();
        }
      });
    }
  }

  @override
  void didPushNext() {
    super.didPushNext();
    _stopScanning();
  }

  @override
  void didPopNext() {
    super.didPopNext();
    _resumeScanning();
  }

  // Future<void> _requestCameraPermission() async {
  //   print("Requesting camera permission...");
    
  //   // First check the current status
  //   var status = await Permission.camera.status;
    
  //   // If permission is not determined, request it
  //   if (status.isDenied) {
  //     print("Camera permission is denied, requesting...");
  //     status = await Permission.camera.request();
  //   }
    
  //   print("Camera permission status: $status");
    
  //   if (status.isGranted) {
  //     print("Camera permission granted, initializing camera...");
  //     // Add a slight delay before initializing camera
  //     if (mounted) {
  //       await Future.delayed(Duration(milliseconds: 500));
  //       await _initializeCamera();
  //     }
  //   } else if (status.isDenied || status.isPermanentlyDenied) {
  //     print("Camera permission denied");
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text("Camera permission is required for scanning."),
  //           duration: Duration(seconds: 5),
  //           action: SnackBarAction(
  //             label: 'SETTINGS',
  //             onPressed: () => openAppSettings(),
  //           ),
  //         ),
  //       );
  //     }
  //   }
  // }

  Future<void> _initializeCamera() async {
    // Make sure to dispose any existing controller before creating a new one
    await _cameraController?.dispose();
    _cameraController = null;
    
    try {
      print("Initializing camera...");
      cameras = await availableCameras();
      print("Available cameras: ${cameras.length}");
      
      if (cameras.isEmpty) {
        print("No cameras available.");
        return;
      }
      
      // Try to use back camera when available (usually has better resolution)
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras[0],
      );
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.yuv420 
            : ImageFormatGroup.bgra8888,
      );
      
      print("Initializing camera controller...");
      
      // Add a timeout to camera initialization to prevent getting stuck
      bool initialized = false;
      
      try {
        await _cameraController!.initialize().timeout(
          Duration(seconds: 10),
          onTimeout: () {
            print("Camera initialization timed out after 10 seconds");
            throw TimeoutException("Camera initialization timed out");
          },
        );
        initialized = true;
        print("Camera controller initialized successfully.");
      } catch (e) {
        print("Error during camera initialization: $e");
        
        // Clean up on error
        await _cameraController?.dispose();
        _cameraController = null;
        
        // Try one more time with a lower resolution
        if (!initialized && mounted) {
          print("Retrying with lower resolution...");
          _retryWithLowerResolution();
          return;
        }
      }
      
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        // Enable auto focus mode for better scanning
        await _setupAutoFocus();
        
        // Get available zoom range
        try {
          _maxAvailableZoom = await _cameraController!.getMaxZoomLevel();
          _minAvailableZoom = await _cameraController!.getMinZoomLevel();
          _currentZoom = _minAvailableZoom;
          print("Zoom range: $_minAvailableZoom to $_maxAvailableZoom");
        } catch (e) {
          print("Error getting zoom levels: $e");
          // Use default values if we can't get zoom levels
          _maxAvailableZoom = 3.0;
          _minAvailableZoom = 1.0;
        }
        
        if (mounted) {
          setState(() {});
          
          // Auto start scanning when camera is ready
          print("Starting scanning...");
          _startScanning();
        }
      }
    } catch (e) {
      print("Camera initialization error: $e");
      
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Camera initialization failed. Please restart the app."),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Add a method to retry with lower resolution if high resolution fails
  Future<void> _retryWithLowerResolution() async {
    try {
      if (cameras.isEmpty) return;
      
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras[0],
      );
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium, // Try with medium resolution instead
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.yuv420 
            : ImageFormatGroup.bgra8888,
      );
      
      print("Retrying camera initialization with medium resolution...");
      
      // Add timeout here too
      await _cameraController!.initialize().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print("Camera initialization timed out on retry");
          throw TimeoutException("Camera initialization timed out on retry");
        },
      );
      
      print("Camera initialized successfully with medium resolution.");
      
      // Continue with the rest of the setup
      await _setupAutoFocus();
      
      try {
        _maxAvailableZoom = await _cameraController!.getMaxZoomLevel();
        _minAvailableZoom = await _cameraController!.getMinZoomLevel();
      } catch (e) {
        _maxAvailableZoom = 3.0;
        _minAvailableZoom = 1.0;
      }
      _currentZoom = _minAvailableZoom;
      
      if (mounted) {
        setState(() {});
        _startScanning();
      }
    } catch (e) {
      print("Error during camera retry: $e");
      
      // Final fallback to lowest resolution
      if (mounted) {
        _retryWithLowestResolution();
      }
    }
  }

  // Final fallback with the lowest resolution
  Future<void> _retryWithLowestResolution() async {
    try {
      if (cameras.isEmpty) return;
      
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras[0],
      );
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.low, // Try with low resolution as last resort
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid 
            ? ImageFormatGroup.yuv420 
            : ImageFormatGroup.bgra8888,
      );
      
      print("Final retry with low resolution...");
      await _cameraController!.initialize();
      
      // Minimal setup
      _maxAvailableZoom = 2.0;
      _minAvailableZoom = 1.0;
      _currentZoom = 1.0;
      
      if (mounted) {
        setState(() {});
        _startScanning();
      }
    } catch (e) {
      print("All camera initialization attempts failed: $e");
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not initialize camera. Please restart the app."),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Set up auto focus to improve scanning
  Future<void> _setupAutoFocus() async {
    if (_cameraController == null) return;
    
    try {
      // Try to set continuous auto-focus mode for better scanning
      await _cameraController!.setFocusMode(FocusMode.auto);
      print("Set focus mode to auto focus");
      
      // Set exposure mode to auto for better image quality
      try {
        await _cameraController!.setExposureMode(ExposureMode.auto);
        print("Set exposure mode to auto exposure");
      } catch (e) {
        print("Error setting exposure mode: $e");
      }
      
      // Add periodic auto-focus to improve detection
      Timer.periodic(Duration(seconds: 3), (timer) {
        if (_cameraController != null && 
            _cameraController!.value.isInitialized &&
            _isScanning && 
            mounted) {
          // Try auto-focus periodically
          try {
            _cameraController!.setFocusPoint(Offset(0.5, 0.5)); // Center of screen
            _cameraController!.setExposurePoint(Offset(0.5, 0.5)); // Center exposure as well
            
            // Toggle focus mode to force refocus
            _cameraController!.setFocusMode(FocusMode.auto);
            Future.delayed(Duration(milliseconds: 300), () {
              if (_cameraController != null && _cameraController!.value.isInitialized) {
                _cameraController!.setFocusMode(FocusMode.auto);
              }
            });
          } catch (e) {
            print("Error during periodic focus: $e");
          }
        }
      });
    } catch (e) {
      print("Error setting auto focus: $e");
      // Try with locked focus instead if auto focus fails
      try {
        await _cameraController!.setFocusMode(FocusMode.locked);
        print("Fallback: Set focus mode to locked");
      } catch (e2) {
        print("Failed to set locked focus mode: $e2");
      }
    }
  }

  String _cleanupScannedData(String data) {
    // Remove any control characters
    data = data.replaceAll(RegExp(r'[\x00-\x1F\x7F-\x9F]'), '');
    // Trim whitespace
    return data.trim();
  }

  // Helper method to convert CameraImage to InputImage
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    try {
      print("Converting camera image to input image...");
      
      if (cameras.isEmpty) {
        print("Camera list is empty!");
        return null;
      }
      
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras[0],
      );
      
      // Handle rotation properly
      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
          InputImageRotation.rotation0deg;
      
      print("Camera sensor orientation: ${camera.sensorOrientation}");
      print("Input image rotation: $rotation");
      
      // Get image format
      final inputFormat = InputImageFormatValue.fromRawValue(image.format.raw);
      if (inputFormat == null) {
        print("Input format is null, using yuv420");
      }
      final format = inputFormat ?? InputImageFormat.yuv420;
      
      print("Image format: ${image.format.raw}, mapped to: $format");
      
      // Get the bytes from the image planes
      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();
      
      // Log for debugging
      print("Created input image - width: ${image.width}, height: ${image.height}, bytes length: ${bytes.length}");
      
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      print("Error creating input image: $e");
      return null;
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isBusy) return;
    _isBusy = true;
    
    try {
      print("Processing camera frame... Size: ${image.width}x${image.height}");
      final InputImage? inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _isBusy = false;
        print("Failed to create input image from camera image");
        return;
      }
      
      print("Sending image to ML Kit for barcode detection...");
      final barcodes = await _barcodeScanner.processImage(inputImage);
      print("ML Kit result: found ${barcodes.length} barcodes");
      
      if (barcodes.isNotEmpty && mounted) {
        print("=============== DETECTED BARCODES ===============");
        
        // First, prioritize DataMatrix format if found
        Barcode? dataMatrixBarcode;
        Barcode? otherBarcode;
        
        for (final barcode in barcodes) {
          // Log detailed barcode info for debugging
          print("Barcode format: ${barcode.format}");
          print("Barcode type: ${barcode.type}");
          print("Barcode value: ${barcode.rawValue}");
          print("Barcode display value: ${barcode.displayValue}");
          if (barcode.cornerPoints != null) {
            print("Barcode corners: ${barcode.cornerPoints}");
          }
          
          // Save for debug display in any case
          setState(() {
            _lastDetectedBarcode = barcode;
            _lastDetectionTime = DateTime.now();
          });
          
          // Check if this is a DataMatrix code
          if (barcode.format == BarcodeFormat.dataMatrix && barcode.rawValue != null) {
            dataMatrixBarcode = barcode;
            // Don't break immediately - we want to log all barcodes for debugging
          } else if (barcode.rawValue != null && otherBarcode == null) {
            // Save the first valid non-DataMatrix barcode as fallback
            otherBarcode = barcode;
          }
        }
        
        // Process the data matrix barcode if found
        if (dataMatrixBarcode != null) {
          print("DataMatrix format found! Processing it with priority");
          _processScannedBarcode(dataMatrixBarcode);
        }
        // If no DataMatrix found, process other barcode types
        else if (otherBarcode != null) {
          print("No DataMatrix detected, using fallback format: ${otherBarcode.format}");
          _processScannedBarcode(otherBarcode);
        } else {
          print("No valid barcodes detected in this frame");
          _isBusy = false; // Reset busy flag when no valid barcode is found
        }
        
        print("===============================================");
      } else {
        // When no barcodes are found
        print("No barcodes found in this frame");
        
        if (_autoZoomEnabled) {
          // Only auto zoom if explicitly enabled
          _tryAutoZoom();
        }
        
        _isBusy = false; // Reset busy flag when no barcodes found
      }
    } catch (e) {
      print("Barcode scanning error: $e");
      print(e.toString());
      _isBusy = false; // Reset busy flag on error
    }
  }

  Future<void> _startScanning() async {
    if (_cameraController == null || !mounted) {
      print("Cannot start scanning: camera controller not ready or widget not mounted");
      return;
    }
    
    if (!_cameraController!.value.isInitialized) {
      print("Cannot start scanning: camera not initialized");
      return;
    }
    
    setState(() {
      _isScanning = true;
    });
    
    print("Starting image stream for scanning");
    try {
      _cameraController!.startImageStream((CameraImage image) {
        _processImage(image);
      });
    } catch (e) {
      print("Error starting image stream: $e");
    }
  }

  void _stopScanning() {
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream();
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _resumeScanning() {
    if (_cameraController != null && !_isScanning) {
      _isBusy = false; // Reset busy flag to ensure new scans will be processed
      print("Resuming scanner...");
      _startScanning();
    }
  }

  // Method to set zoom level
  Future<void> _setZoomLevel(double zoom) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    try {
      await _cameraController!.setZoomLevel(zoom);
      setState(() {
        _currentZoom = zoom;
      });
    } catch (e) {
      print('Error setting zoom: $e');
    }
  }

  // Auto zoom logic
Future<void> _tryAutoZoom() async {
  if (!_autoZoomEnabled || _cameraController == null) return;
  
  // More gradual auto-zoom logic
  if (_currentZoom < _maxAvailableZoom - 0.2) {
    double newZoom = _currentZoom + 0.05; // Smaller increment for smoother zoom
    if (newZoom > _maxAvailableZoom) {
      newZoom = _maxAvailableZoom;
    }
    await _setZoomLevel(newZoom);
  } else {
    // Instead of jumping to min zoom, gradually decrease
    double newZoom = _currentZoom - 0.1;
    if (newZoom < _minAvailableZoom) {
      newZoom = _minAvailableZoom;
    }
    await _setZoomLevel(newZoom);
  }
}
  
  // Animate success
  void _animateScanSuccess() {
    if (_isAnimating) return;
    
    setState(() {
      _isAnimating = true;
      _showScanSuccessFlash = true;
    });
    
    // Add haptic feedback (vibration)
    HapticFeedback.heavyImpact();
    
    // Flash animation
    for (int i = 0; i < 2; i++) {
      Future.delayed(Duration(milliseconds: i * 300), () {
        if (mounted) {
          setState(() {
            _scanAreaSize = 230.0;
          });
        }
      });
      
      Future.delayed(Duration(milliseconds: i * 300 + 150), () {
        if (mounted) {
          setState(() {
            _scanAreaSize = 200.0;
          });
        }
      });
    }
    
    // Hide flash effect after short delay
    Future.delayed(Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _showScanSuccessFlash = false;
        });
      }
    });
    
    // Reset animation flag
    Future.delayed(Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _isAnimating = false;
        });
      }
    });
  }

  // Toggle flash
  Future<void> _toggleFlash() async {
    try {
      final newFlashMode = _isFlashOn ? FlashMode.off : FlashMode.torch;
      await _cameraController!.setFlashMode(newFlashMode);
      
      setState(() {
        _isFlashOn = !_isFlashOn;
      });
    } catch (e) {
      print('Error toggling flash: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Flash control not available on this device')),
      );
    }
  }

  // Quick zoom presets
Future<void> _setZoomPreset(double preset) async {
  // Disable auto-zoom when setting presets manually
  setState(() {
    _autoZoomEnabled = false;
  });
  await _setZoomLevel(preset);
  print("Manual zoom preset set to: $preset, auto-zoom disabled");
}

  // Handle scale gesture for pinch zoom
void _handleScaleUpdate(ScaleUpdateDetails details) {
  // Ignore if camera is not initialized
  if (_cameraController == null || !_cameraController!.value.isInitialized) {
    return;
  }
  
  // Calculate new zoom level
  double newZoom = _baseScaleFactor * details.scale;
  
  // Clamp to available zoom range
  newZoom = newZoom.clamp(_minAvailableZoom, _maxAvailableZoom);
  
  // Update zoom if sufficiently changed
  if ((_currentZoom - newZoom).abs() > 0.05) {
    _setZoomLevel(newZoom);
    // Disable auto-zoom when manually zooming
    if (_autoZoomEnabled) {
      setState(() {
        _autoZoomEnabled = false;
      });
      print("Manual pinch zoom detected, auto-zoom disabled");
    }
  }
}
  
  // Set base scale factor for relative pinch zoom
  void _handleScaleStart(ScaleStartDetails details) {
    _baseScaleFactor = _currentZoom;
  }

  @override
  void dispose() {
    _stopScanning();
    _barcodeScanner.close();
    // Make sure camera controller is properly disposed
    _cameraController?.dispose();
    _cameraController = null;
    _scanLineAnimationController.dispose();
    super.dispose();
  }

  // Show scan result in a dialog
  void _showScanResultDialog(String scanValue,String formatName) {
    // Make sure scanning is stopped when showing dialog
    _stopScanning();
    
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        return WillPopScope(
          // Prevent back button from dismissing dialog without explicit user action
          onWillPop: () async => false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            backgroundColor: Colors.white,
            elevation: 10,
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppConstants.appbarColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.appbarColor.withOpacity(0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    color: AppConstants.appbarColor,
                    size: 24,
                  ),
                ),
               const SizedBox(width: 12),
                const Text(
                  'Scan Successful',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppConstants.appbarColor,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '$formatName Code Detected',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                Text(
                  'Scanned Value:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        scanValue,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Length: ${scanValue.length} characters',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Time: ${DateTime.now().toString().split('.').first}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              // Copy button
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: scanValue));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied to clipboard'),
                      backgroundColor: AppConstants.appbarColor,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
                icon: Icon(Icons.copy, size: 18, color: AppConstants.appbarColor),
                label: Text(
                  'COPY',
                  style: TextStyle(
                    color: AppConstants.appbarColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // Open URL button (only show if scanned value is a URL)
              if (_isUrl(scanValue))
                AnimationLimiter(
                  child: AnimationConfiguration.staggeredList(
                    position: 1,
                    duration: const Duration(milliseconds: 375),
                    child: SlideAnimation(
                      verticalOffset: 50.0,
                      child: FadeInAnimation(
                        child: TextButton.icon(
                          onPressed: () {
                            _launchUrl(scanValue);
                          },
                          icon: const Icon(Icons.open_in_browser, size: 18, color: AppConstants.appbarColor),
                          label: const Text(
                            'OPEN URL',
                            style: TextStyle(
                              color:  AppConstants.appbarColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              
              // Continue scanning button
              ElevatedButton.icon(
                onPressed: () {
                   lastScannedValue = null;
                  Navigator.of(context).pop();
                  // Reset busy flag and restart scanning
                 
                  _isBusy = false;
                  _startScanning();
                },
                icon: Icon(Icons.qr_code_scanner, size: 18),
                label: Text('CONTINUE SCANNING'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.appbarColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
            contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 24),
            actionsPadding: EdgeInsets.fromLTRB(16, 8, 16, 16),
          ),
        );
      },
    );
  }

  // Add navigation method
  void _onItemTapped(int index) async {
    if (index == _selectedIndex) return;

    // Stop camera before navigation
    _stopScanning();

    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        // Navigate to Dashboard or Home screen
        break;
      case 1:
        // Navigate to My Assets or similar screen
        break;
      case 2:
        // Already on scanner page
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner, color: Colors.white, size: 24),
            SizedBox(width: 10),
            Text(
              "DataMatrix Scanner",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
            ),
            
          ],
        ), 
        centerTitle: true,
        backgroundColor: AppConstants.appbarColor,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        actions: [
          // // Debug mode toggle
          // IconButton(
          //   icon: Icon(
          //     _debugMode ? Icons.bug_report : Icons.bug_report_outlined,
          //     color: Colors.white, 
          //   ),
          //   onPressed: () {
          //     setState(() {
          //       _debugMode = !_debugMode;
          //     });
          //   },
          //   tooltip: _debugMode ? 'Disable Debug' : 'Enable Debug',
          // ),
          
          // History button
          IconButton(
            icon: Icon(
              Icons.history,
              color: Colors.white,
            ),
            onPressed: () {
              // Temporarily stop scanning while in history
              _stopScanning();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => HistoryPage()),
              ).then((_) {
                // Resume scanning when returning from history
                if (mounted) {
                  _resumeScanning();
                }
              });
            },
            tooltip: 'View Scan History',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.black,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    // Camera preview with pinch-to-zoom
                    _cameraController != null && _cameraController!.value.isInitialized
                        ? GestureDetector(
                            onScaleStart: _handleScaleStart,
                            onScaleUpdate: _handleScaleUpdate,
                            child: CameraPreview(_cameraController!),
                          )
                        : Container(
                            color: Colors.black,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppConstants.appbarColor,
                              ),
                            ),
                          ),
                    
                    // Debug overlay with improved styling
                    if (_debugMode && _lastDetectedBarcode != null)
                      Positioned(
                        top: 20,
                        left: 20,
                        right: 20,
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.green.withOpacity(0.5), width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.bug_report, color: Colors.green, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    "DEBUG INFO",
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Divider(color: Colors.green.withOpacity(0.3)),
                              Text(
                                "Format: ${_lastDetectedBarcode!.format}",
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              Text(
                                "Type: ${_lastDetectedBarcode!.type}",
                                style: TextStyle(color: Colors.white, fontSize: 12),
                              ),
                              Text(
                                "Value: ${_lastDetectedBarcode!.rawValue ?? 'null'}",
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "Detected at: ${_lastDetectionTime.toString().split('.').first}",
                                style: TextStyle(color: Colors.white70, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Modern scanner overlay with crosshair
                    if (_cameraController != null && _cameraController!.value.isInitialized)
                      Center(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Remove the bordered scan area and replace with crosshair lines
                            // Horizontal line
                            Container(
                              width: MediaQuery.of(context).size.width,
                              height: 2,
                              color: _isScanning 
                                ? Colors.green.withOpacity(0.7)
                                : Colors.white.withOpacity(0.5),
                            ),
                            
                            // Vertical line
                            Container(
                              width: 2,
                              height: MediaQuery.of(context).size.height,
                              color: _isScanning 
                                ? Colors.green.withOpacity(0.7) 
                                : Colors.white.withOpacity(0.5),
                            ),
                            
                            // Keep the scanner moving line animation if you want it
                            if (_isScanning)
                              AnimatedBuilder(
                                animation: _scanLineAnimationController,
                                builder: (context, child) {
                                  return Positioned(
                                    top: _scanLineAnimation.value * (MediaQuery.of(context).size.height - 200),
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 2,
                                      width: MediaQuery.of(context).size.width - 100,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            Colors.green.withOpacity(0.5),
                                            Colors.green,
                                            Colors.green,
                                            Colors.green.withOpacity(0.5),
                                            Colors.transparent,
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.green.withOpacity(0.7),
                                            blurRadius: 8,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              
                            // Remove the corner markers since we're not using a bordered area anymore
                            
                            // You may want to add a center dot where the lines intersect
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isScanning 
                                  ? Colors.green.withOpacity(0.5)
                                  : Colors.white.withOpacity(0.5),
                                border: Border.all(
                                  color: _isScanning 
                                    ? Colors.green
                                    : Colors.white,
                                  width: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Top right quick controls with improved styling
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white24,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Flash toggle
                            IconButton(
                              onPressed: _toggleFlash,
                              icon: Icon(
                                _isFlashOn ? Icons.flash_on : Icons.flash_off,
                                color: _isFlashOn ? Colors.amberAccent : Colors.white,
                                size: 24,
                            ),
                            tooltip: _isFlashOn ? 'Turn Off Flash' : 'Turn On Flash',
                            padding: EdgeInsets.all(8),
                            constraints: BoxConstraints(),
                          ),
                          // Image picker button
                          IconButton(
                            onPressed: _pickImageFromGallery,
                            icon: Icon(
                              Icons.photo_library,
                              color: Colors.white,
                              size: 24,
                            ),
                            tooltip: 'Pick Image from Gallery',
                            padding: EdgeInsets.all(8),
                            constraints: BoxConstraints(),
                          ),
                        ],
                        ),
                      ),
                    ),
                    
                    // Bottom zoom controls with improved design
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          // Zoom indicator
                          if (_currentZoom > _minAvailableZoom + 0.1)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              margin: EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '${_currentZoom.toStringAsFixed(1)}x',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          
                          // Zoom slider with improved design
                          Container(
                            margin: EdgeInsets.symmetric(horizontal: 20),
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white10,
                                width: 1,
                              ),
                            ),
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 4,
                                activeTrackColor: AppConstants.appbarColor,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: Colors.white,
                                overlayColor: Colors.green.withOpacity(0.2),
                                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                              ),
                              child: Slider(
                                value: _currentZoom,
                                min: _minAvailableZoom,
                                max: _maxAvailableZoom,
                                divisions: Math.max(1, (_maxAvailableZoom - _minAvailableZoom).round() * 2),
                                onChanged: (value) {
                                  _setZoomLevel(value);
                                  // Disable auto-zoom if user manually adjusts
                                  setState(() {
                                    _autoZoomEnabled = false;
                                  });
                                },
                              ),
                            ),
                          ),
                          
                          // Zoom presets with improved design
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildZoomPresetButton('1×', _minAvailableZoom),
                                const SizedBox(width: 8),
                                _buildZoomPresetButton('2×', _minAvailableZoom + (_maxAvailableZoom - _minAvailableZoom) / 3),
                                const SizedBox(width: 8),
                                _buildZoomPresetButton('Max', _maxAvailableZoom),
                                const SizedBox(width: 16),
                                // Auto zoom toggle with improved design
                             GestureDetector(
  onTap: () {
    setState(() {
      _autoZoomEnabled = !_autoZoomEnabled;
      if (_autoZoomEnabled) {
        // Don't reset zoom immediately, let auto-zoom handle it gradually
        print("Auto-zoom enabled at current zoom level: $_currentZoom");
      } else {
        print("Auto-zoom disabled");
      }
    });
  },
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: _autoZoomEnabled ? AppConstants.appbarColor : Colors.black54,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: _autoZoomEnabled ? Colors.green : Colors.white24,
        width: 1,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _autoZoomEnabled ? Icons.autorenew : Icons.autorenew_outlined,
          color: Colors.white,
          size: 16,
        ),
        SizedBox(width: 4),
        Text(
          'Auto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: _autoZoomEnabled ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    ),
  ),
),
                             
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Scanning indicator with improved design
                   
                    // Help text with improved design
                    if (_isScanning)
                      Positioned(
                        bottom: 120,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white24,
                                width: 1,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  "Position  code inside the frame",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    
                    // Scan success flash effect
                    if (_showScanSuccessFlash)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.check_circle_outline,
                              color: Colors.white,
                              size: 80,
                            ),
                          ),
                        ),
                      ),
                    
                    // Initial instructions overlay with improved design
                    if (_showInstructions && _cameraController != null && _cameraController!.value.isInitialized)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _showInstructions = false;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.qr_code_scanner,
                                  color: Colors.white,
                                  size: 50,
                                ),
                                SizedBox(height: 20),
                                const Text(
                                  "Data Matrix Scanner",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 30),
                                Container(
                                  padding: EdgeInsets.all(20),
                                  margin: EdgeInsets.symmetric(horizontal: 40),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white10,
                                      width: 1,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      _instructionItem(
                                        Icons.center_focus_strong,
                                        "Position the Data Matrix code within the green frame"
                                      ),
                                      SizedBox(height: 15),
                                      _instructionItem(
                                        Icons.pinch,
                                        "Pinch to zoom in or out"
                                      ),
                                      SizedBox(height: 15),
                                      _instructionItem(
                                        Icons.flash_on,
                                        "Toggle flash for low light conditions"
                                      ),
                                      SizedBox(height: 15),
                                      _instructionItem(
                                        Icons.refresh,
                                        "Scanner continuously runs - results appear in popup"
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 30),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _showInstructions = false;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppConstants.appbarColor,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    elevation: 5,
                                    shadowColor: AppConstants.appbarColor.withOpacity(0.5),
                                  ),
                                  child: const Text(
                                    "Start Scanning",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Helper method to build zoom preset buttons
  Widget _buildZoomPresetButton(String label, double zoomLevel) {
    // Don't highlight any preset by default, only when it's explicitly selected
    bool isActive = label != '1×' && (_currentZoom - zoomLevel).abs() < 0.1;
    
    return GestureDetector(
      onTap: () => _setZoomPreset(zoomLevel),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppConstants.appbarColor : Colors.black54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.green : Colors.white24,
            width: 1,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: AppConstants.appbarColor.withOpacity(0.4),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
  
  // Helper widget for instruction items
  Widget _instructionItem(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppConstants.appbarColor.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppConstants.appbarColor.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppConstants.appbarColor.withOpacity(0.2),
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        SizedBox(width: 15),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // Process a scanned barcode
  void _processScannedBarcode(Barcode barcode) async {
    if (barcode.rawValue == null || barcode.rawValue!.isEmpty) {
      print("Ignoring empty barcode");
      _isBusy = false;
      return;
    }
    
    // Clean up scanned value
    final scannedValue = _cleanupScannedData(barcode.rawValue!);
    
    // Format name for display
    String formatName = "Unknown";
    switch (barcode.format) {
      case BarcodeFormat.dataMatrix:
        formatName = "Data Matrix";
        break;
      case BarcodeFormat.qrCode:
        formatName = "QR Code";
        break;
      case BarcodeFormat.aztec:
        formatName = "Aztec";
        break;
      case BarcodeFormat.code128:
        formatName = "Code 128";
        break;
      case BarcodeFormat.code39:
        formatName = "Code 39";
        break;
      case BarcodeFormat.code93:
        formatName = "Code 93";
        break;
      case BarcodeFormat.ean13:
        formatName = "EAN-13";
        break;
      case BarcodeFormat.ean8:
        formatName = "EAN-8";
        break;
      case BarcodeFormat.itf:
        formatName = "ITF";
        break;
      case BarcodeFormat.pdf417:
        formatName = "PDF417";
        break;
      default:
        formatName = "Unknown";
        break;
    }
    
    print("Successfully scanned $formatName: $scannedValue");
    
    if (scannedValue.isEmpty) {
      print("Ignoring empty scanned value after cleanup");
      _isBusy = false;
      return;
    }
    
    // Comment out or modify the duplicate detection logic
    // to allow rescanning the same code after a timeout
    final now = DateTime.now();
    final lastScanTime = _lastDetectionTime ?? DateTime.now().subtract(const Duration(days: 1));
    final timeSinceLastScan = now.difference(lastScanTime).inSeconds;
    
    if (scannedValue == lastScannedValue && timeSinceLastScan < 3) {
      print("Ignoring duplicate scan (scanned $timeSinceLastScan seconds ago): $scannedValue");
      _isBusy = false;
      return;
    }
    
    // Update last scanned value and detection time
    lastScannedValue = scannedValue;
    _lastDetectionTime = now;
    
    // Provide haptic feedback
    HapticFeedback.mediumImpact();
    
    // Show success flash effect
    setState(() {
      _showScanSuccessFlash = true;
      result = "$formatName: $scannedValue";
    });
    
    // Add to scan history
    await _historyService.addScan(scannedValue, formatName);
    
    // Hide flash after a short delay
    Future.delayed(Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showScanSuccessFlash = false;
        });
      }
    });
    
    // Stop scanning and show the dialog
    _stopScanning();
    
    // Show scan result dialog - this will keep scanning paused until user clicks continue
    if (mounted) {
      _showScanResultDialog(scannedValue, formatName);
    }
    
    // Note: We don't restart scanning here anymore.
    // Instead, scanning will resume when user clicks "CONTINUE SCANNING" in the dialog
  }

  // Pick image from gallery and process it
  Future<void> _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      
      if (image != null) {
        // Stop camera scanning while processing gallery image
        _stopScanning();
        
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content:const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppConstants.appbarColor),
                SizedBox(height: 16),
                Text('Processing image...'),
              ],
            ),
          ),
        );
        
        // Process the image
        await _processImageFromGallery(image.path);
        
        // Close loading dialog
        Navigator.of(context).pop();
        
        // Resume scanning after processing
        _resumeScanning();
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Process image from gallery for barcode scanning
  Future<void> _processImageFromGallery(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final barcodes = await _barcodeScanner.processImage(inputImage);
      
      if (barcodes.isNotEmpty) {
        print('Found ${barcodes.length} barcodes in gallery image');
        
        // Find DataMatrix barcode first, then fallback to other formats
        Barcode? dataMatrixBarcode;
        Barcode? otherBarcode;
        
        for (final barcode in barcodes) {
          print('Gallery barcode - Format: ${barcode.format}, Value: ${barcode.rawValue}');
          
          if (barcode.format == BarcodeFormat.dataMatrix && barcode.rawValue != null) {
            dataMatrixBarcode = barcode;
          } else if (barcode.rawValue != null && otherBarcode == null) {
            otherBarcode = barcode;
          }
        }
        
        // Process the best barcode found
        if (dataMatrixBarcode != null) {
          print('Processing DataMatrix from gallery image');
          _processScannedBarcode(dataMatrixBarcode);
        } else if (otherBarcode != null) {
          print('Processing other barcode format from gallery image');
          _processScannedBarcode(otherBarcode);
        } else {
          _showNoBarcodesFoundDialog();
        }
      } else {
        _showNoBarcodesFoundDialog();
      }
    } catch (e) {
      print('Error processing gallery image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Show dialog when no barcodes found in gallery image
  void _showNoBarcodesFoundDialog() {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.orange),
              SizedBox(width: 12),
              Text('No Barcodes Found'),
            ],
          ),
          content: Text(
            'No Data Matrix codes or other supported barcodes were found in the selected image. Please try with a different image or use the camera scanner.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK', style: TextStyle(color: AppConstants.appbarColor)),
            ),
          ],
        ),
      );
    }
  }

  // URL detection and launching methods
  bool _isUrl(String text) {
    text = text.trim();
    
    // More comprehensive URL detection
    final urlPatterns = [
      // Full URL with protocol
      RegExp(r'^https?://[\w\-]+(\.[\w\-]+)+([\w\-\.,@?^=%&:/~\+#]*[\w\-\@?^=%&/~\+#])?$', caseSensitive: false),
      // URL without protocol
      RegExp(r'^www\.[\w\-]+(\.[\w\-]+)+([\w\-\.,@?^=%&:/~\+#]*[\w\-\@?^=%&/~\+#])?$', caseSensitive: false),
      // Simple domain patterns
      RegExp(r'^[\w\-]+(\.[\w\-]+)*\.(com|org|net|edu|gov|io|co|uk|de|fr|jp|cn|au|ca|in|br|mx|ru|it|es|nl|pl|se|no|dk|fi|be|ch|at|cz|hu|gr|pt|ie|sk|si|hr|bg|ro|lt|lv|ee|lu|mt|cy)([\w\-\.,@?^=%&:/~\+#]*[\w\-\@?^=%&/~\+#])?$', caseSensitive: false),
    ];
    
    return urlPatterns.any((pattern) => pattern.hasMatch(text));
  }
  
  Future<void> _launchUrl(String url) async {
    try {
      String originalUrl = url.trim();
      print('Attempting to launch URL: $originalUrl');
      
      // Clean and prepare URL
      if (!originalUrl.startsWith('http://') && !originalUrl.startsWith('https://')) {
        // Add https:// if it's a www link or domain
        if (originalUrl.startsWith('www.') || _isUrl(originalUrl)) {
          originalUrl = 'https://' + originalUrl;
        } else {
          throw 'Invalid URL format';
        }
      }
      
      print('Processed URL: $originalUrl');
      
      final Uri uri = Uri.parse(originalUrl);
      print('Parsed URI: $uri');
      
      // Try different launch modes
      bool launched = false;
      
      // Try external application first
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          launched = true;
          print('Launched with external application');
        }
      } catch (e) {
        print('External application launch failed: $e');
      }
      
      // If external app failed, try platform default
      if (!launched) {
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(
              uri,
              mode: LaunchMode.platformDefault,
            );
            launched = true;
            print('Launched with platform default');
          }
        } catch (e) {
          print('Platform default launch failed: $e');
        }
      }
      
      // If still not launched, try in-app web view
      if (!launched) {
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(
              uri,
              mode: LaunchMode.inAppWebView,
            );
            launched = true;
            print('Launched with in-app web view');
          }
        } catch (e) {
          print('In-app web view launch failed: $e');
        }
      }
      
      if (launched) {
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Opening URL in browser...'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        throw 'Could not launch URL with any method';
      }
      
    } catch (e) {
      print('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open URL. Please copy and paste in browser.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            action: SnackBarAction(
              label: 'COPY',
              textColor: Colors.white,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
              },
            ),
          ),
        );
      }
    }
  }
  IconData _getBarcodeIcon(String formatName) {
  switch (formatName.toLowerCase()) {
    case 'data matrix':
      return Icons.grid_on;
    case 'qr code':
      return Icons.qr_code;
    case 'aztec':
      return Icons.crop_square;
    case 'code 128':
    case 'code 39':
    case 'code 93':
      return Icons.view_stream;
    case 'ean-13':
    case 'ean-8':
      return Icons.receipt_long;
    case 'pdf417':
      return Icons.picture_as_pdf;
    default:
      return Icons.qr_code_scanner;
  }
}

}

// Static method to calculate image brightness
// Must be a top-level function for compute
