import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'homepage.dart';
import 'appconstant.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:permission_handler/permission_handler.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  bool _cameraInitialized = false;
  bool _permissionGranted = false;
  bool _showPermissionRequest = false;
  bool _splashCompleted = false;
  late AnimationController _logoController;
  late AnimationController _textController;
  late Animation<double> _logoAnimation;
  late Animation<double> _textAnimation;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startSplashSequence();
  }
  
  void _initializeAnimations() {
    _logoController = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );
    
    _textController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _logoAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    
    _textAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeInOut),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.bounceOut),
    );
    
    // Start animations
    _logoController.forward();
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) {
        _textController.forward();
      }
    });
  }
  
  void _startSplashSequence() async {
    // Show splash screen for at least 3 seconds to let animations complete
    await Future.delayed(Duration(seconds: 3));
    
    if (mounted) {
      setState(() {
        _splashCompleted = true;
      });
      
      // Small delay before checking permission
      await Future.delayed(Duration(milliseconds: 500));
      
      // After splash is complete, check camera permission
      await _checkCameraPermission();
    }
  }
  
  Future<void> _checkCameraPermission() async {
    print("Checking camera permission...");
    
    var status = await Permission.camera.status;
    print("Camera permission status: $status");
    
    if (status.isGranted) {
      print("Camera permission already granted");
      setState(() {
        _permissionGranted = true;
      });
      await _initCamera();
    } else {
      print("Camera permission not granted, showing permission request");
      setState(() {
        _showPermissionRequest = true;
      });
    }
  }
  
  Future<void> _requestCameraPermission() async {
    print("Requesting camera permission...");
    
    var status = await Permission.camera.request();
    print("Camera permission request result: $status");
    
    if (status.isGranted) {
      print("Camera permission granted by user");
      setState(() {
        _permissionGranted = true;
        _showPermissionRequest = false;
      });
      await _initCamera();
    } else if (status.isDenied) {
      print("Camera permission denied by user");
      // Show message and keep asking
      _showPermissionDeniedMessage();
    } else if (status.isPermanentlyDenied) {
      print("Camera permission permanently denied");
      _showPermanentlyDeniedDialog();
    }
  }
  
  void _showPermissionDeniedMessage() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Camera permission is required to use the scanner."),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'RETRY',
            textColor: Colors.white,
            onPressed: _requestCameraPermission,
          ),
        ),
      );
    }
  }
  
  void _showPermanentlyDeniedDialog() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(Icons.camera_alt, color: AppConstants.appbarColor),
                SizedBox(width: 12),
                Text('Camera Permission Required'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Camera permission has been permanently denied. Please enable it in app settings to use the scanner.',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Go to Settings > Apps > DataMatrix Scanner > Permissions > Camera',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Keep showing permission request
                },
                child: Text('CANCEL'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppConstants.appbarColor,
                  foregroundColor: Colors.white,
                ),
                child: Text('OPEN SETTINGS'),
              ),
            ],
          );
        },
      );
    }
  }

  Future<void> _initCamera() async {
    try {
      print("Initializing camera...");
      
      // Initialize camera
      final cameras = await availableCameras();
      
      // Mark as initialized
      setState(() {
        _cameraInitialized = true;
      });
      
      print("Camera initialized successfully, navigating to scanner...");
      
      // Small delay to show the success message
      await Future.delayed(Duration(milliseconds: 1000));
      
      // Navigate to scanner screen
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ScannerScreen(),
          ),
        );
      }
    } catch (e) {
      print('Error initializing camera: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera initialization failed. Please restart the app.'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppConstants.appbarColor,
              AppConstants.appbarColor.withOpacity(0.8),
              AppConstants.appbarColor.withOpacity(0.6),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo
              AnimatedBuilder(
                animation: _logoAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Opacity(
                      opacity: _logoAnimation.value,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/images/HanuTechX.png',
                            width: 100,
                            height: 100,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 30),
              
              // Animated App Name
              AnimatedBuilder(
                animation: _textAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, 30 * (1 - _textAnimation.value)),
                    child: Opacity(
                      opacity: _textAnimation.value,
                      child: AnimatedTextKit(
                        animatedTexts: [
                          TypewriterAnimatedText(
                            'DataMatrix Scanner',
                            textStyle: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            speed: Duration(milliseconds: 100),
                          ),
                        ],
                        totalRepeatCount: 1,
                      ),
                    ),
                  );
                },
              ),
              
              SizedBox(height: 20),
              
              // Subtitle with shimmer effect
              AnimatedBuilder(
                animation: _textAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, 20 * (1 - _textAnimation.value)),
                    child: Opacity(
                      opacity: _textAnimation.value * 0.8,
                      child: const Text(
                        'Scan • Decode • Explore',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              SizedBox(height: 40),
              
              // Show different content based on state
              AnimatedBuilder(
                animation: _textAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textAnimation.value,
                    child: _buildCurrentStateWidget(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildCurrentStateWidget() {
    // If splash is not completed, show loading
    if (!_splashCompleted) {
      return _buildSplashLoadingWidget();
    }
    
    // If permission request should be shown
    if (_showPermissionRequest) {
      return _buildPermissionRequestWidget();
    }
    
    // If permission granted, show initialization
    if (_permissionGranted) {
      return _buildInitializationWidget();
    }
    
    // Default loading state
    return _buildSplashLoadingWidget();
  }
  
  Widget _buildSplashLoadingWidget() {
    return Column(
      children: [
        Container(
          width: 200,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Loading...',
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
  
  Widget _buildPermissionRequestWidget() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(20),
          margin: EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.camera_alt,
                color: Colors.white,
                size: 48,
              ),
              SizedBox(height: 16),
              Text(
                'Camera Permission Required',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'This app needs camera access to scan Data Matrix codes and other barcodes.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        SizedBox(height: 30),
        ElevatedButton.icon(
          onPressed: _requestCameraPermission,
          icon: Icon(Icons.camera_alt, size: 20),
          label: Text(
            'Grant Camera Permission',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppConstants.appbarColor,
            padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            elevation: 5,
          ),
        ),
      ],
    );
  }
  
  Widget _buildInitializationWidget() {
    return Column(
      children: [
        
           Container(
          width: 200,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
          ),
          child: const LinearProgressIndicator(
            backgroundColor: Colors.transparent,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _cameraInitialized 
              ? 'Camera initialized successfully!\nStarting scanner...' 
              : 'Initializing camera...',
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    super.dispose();
  }
}

