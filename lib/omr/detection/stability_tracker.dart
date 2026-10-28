import 'dart:math';
import '../geometry/quadrilateral.dart';
import 'live_document_detector.dart';

/// Lifecycle states of live document detection in the camera feed.
enum LiveTrackingState {
  /// Looking for a document in the camera frame.
  searching,

  /// Document quadrilateral detected, but user/camera is moving.
  detected,

  /// Document has remained stable within the threshold for consecutive frames.
  steady,

  /// Document is reliably stable and ready for automatic capture.
  readyToCapture,

  /// Document is being captured and processed.
  capturing,
}

/// Tracks document boundary stability over time to provide smooth UI tracking
/// and reliable CamScanner-style automatic capture.
class StabilityTracker {
  /// Maximum normalized corner displacement permitted between consecutive frames.
  final double driftThreshold;

  /// Number of consecutive stable frames required to fire auto-capture.
  final int requiredStableFrames;

  /// Exponential Moving Average factor (alpha in [0.0, 1.0]).
  /// Higher values respond faster; lower values provide smoother filtering.
  final double smoothingAlpha;

  Quadrilateral? _smoothedQuad;
  int _stableFrameCount = 0;
  LiveTrackingState _state = LiveTrackingState.searching;
  String _statusMessage = 'Searching for document...';

  StabilityTracker({
    this.driftThreshold = 0.040,
    this.requiredStableFrames = 2,
    this.smoothingAlpha = 0.45,
  });

  /// The currently smoothed quadrilateral in normalized [0.0, 1.0] coordinates.
  Quadrilateral? get smoothedQuad => _smoothedQuad;

  /// Number of consecutive stable frames accumulated so far.
  int get stableFrameCount => _stableFrameCount;

  /// Stability progress from 0.0 to 1.0 for rendering circular countdown rings.
  double get stabilityProgress => min(1.0, _stableFrameCount / max(1, requiredStableFrames));

  /// Current tracking state.
  LiveTrackingState get state => _state;

  /// Current user-facing guidance message.
  String get statusMessage => _statusMessage;

  /// Whether conditions for automatic capture are fully met.
  bool get shouldAutoCapture => _state == LiveTrackingState.readyToCapture;

  /// Updates the tracker with the latest frame detection result.
  void update(LiveDetectionResult result) {
    if (_state == LiveTrackingState.capturing) return;

    final newQuad = result.normalizedQuad;

    // 1. If frame is blurry or no document detected
    if (newQuad == null || !result.isReliable) {
      if (result.isBlurry) {
        _stableFrameCount = max(0, _stableFrameCount - 2);
        _state = _smoothedQuad != null ? LiveTrackingState.detected : LiveTrackingState.searching;
        _statusMessage = 'Camera moving, hold steady...';
      } else {
        _stableFrameCount = max(0, _stableFrameCount - 1);
        if (_stableFrameCount == 0) {
          _smoothedQuad = null;
          _state = LiveTrackingState.searching;
          _statusMessage = result.message.isNotEmpty ? result.message : 'Searching for document...';
        }
      }
      return;
    }

    // 2. If this is the first detection
    if (_smoothedQuad == null) {
      _smoothedQuad = newQuad;
      _stableFrameCount = 1;
      _state = LiveTrackingState.detected;
      _statusMessage = 'Document detected - hold steady';
      return;
    }

    // 3. Compute corner drift between previous smoothed quad and new quad
    final prev = _smoothedQuad!;
    final driftTL = prev.tl.distanceTo(newQuad.tl);
    final driftTR = prev.tr.distanceTo(newQuad.tr);
    final driftBR = prev.br.distanceTo(newQuad.br);
    final driftBL = prev.bl.distanceTo(newQuad.bl);
    final maxDrift = max(max(driftTL, driftTR), max(driftBR, driftBL));

    // 4. Update smoothed coordinates via Exponential Moving Average (EMA)
    _smoothedQuad = Quadrilateral(
      tl: prev.tl * (1.0 - smoothingAlpha) + newQuad.tl * smoothingAlpha,
      tr: prev.tr * (1.0 - smoothingAlpha) + newQuad.tr * smoothingAlpha,
      br: prev.br * (1.0 - smoothingAlpha) + newQuad.br * smoothingAlpha,
      bl: prev.bl * (1.0 - smoothingAlpha) + newQuad.bl * smoothingAlpha,
    );

    // 5. Evaluate stability
    if (maxDrift < driftThreshold && !result.isBlurry) {
      _stableFrameCount++;
      if (_stableFrameCount >= requiredStableFrames) {
        _state = LiveTrackingState.readyToCapture;
        _statusMessage = 'Hold steady! Capturing...';
      } else {
        _state = LiveTrackingState.steady;
        _statusMessage = 'Document detected - hold steady';
      }
    } else {
      // Movement detected, decay stability
      _stableFrameCount = max(1, _stableFrameCount - 2);
      _state = LiveTrackingState.detected;
      _statusMessage = 'Hold steady...';
    }
  }

  /// Locks tracker state during active image capture.
  void lockCapture() {
    _state = LiveTrackingState.capturing;
    _statusMessage = 'Capturing document...';
  }

  /// Resets tracker state to resume searching.
  void reset() {
    _smoothedQuad = null;
    _stableFrameCount = 0;
    _state = LiveTrackingState.searching;
    _statusMessage = 'Searching for document...';
  }
}
