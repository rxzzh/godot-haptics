//
//  haptics.h
//  haptics
//
//  Created by Kyoz on 07/07/2023.
//  Extended with complete iOS Haptic API support
//

#ifndef HAPTICS_H
#define HAPTICS_H

#ifdef VERSION_4_0
#include "core/object/object.h"
#else
#include "core/object.h"
#endif

class Haptics : public Object {

  GDCLASS(Haptics, Object);

  static Haptics *instance;

  // Core Haptics engine instance (stored as void* to avoid Obj-C in header)
  void *haptic_engine;
  bool engine_initialized;

public:
  // === Impact Feedback (UIImpactFeedbackGenerator) ===
  void light();
  void medium();
  void heavy();
  void soft();                  // iOS 13+ - soft, elastic feel
  void rigid();                 // iOS 13+ - rigid, mechanical feel
  void impact(float intensity); // iOS 13+ - custom intensity 0.0-1.0

  // === Notification Feedback (UINotificationFeedbackGenerator) ===
  void success(); // Success notification
  void warning(); // Warning notification
  void error();   // Error notification

  // === Selection Feedback (UISelectionFeedbackGenerator) ===
  void selection(); // Selection changed feedback

  // === Core Haptics (CHHapticEngine, iOS 13+) ===
  void transient(float intensity, float sharpness);
  void continuous(float intensity, float sharpness, float duration);

  // === Preset Patterns ===
  void pattern_heartbeat();
  void pattern_double_tap();
  void pattern_ramp_up();

  // === Utility ===
  bool is_supported();
  bool is_core_haptics_supported();
  void prepare();
  void stop();

  static Haptics *get_singleton();

  Haptics();
  ~Haptics();

protected:
  static void _bind_methods();

private:
  void init_haptic_engine();
  void cleanup_haptic_engine();
};

#endif
