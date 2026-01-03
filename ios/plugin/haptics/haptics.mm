//
//  haptics.mm
//  haptics
//
//  Created by Kyoz on 07/07/2023.
//  Extended with complete iOS Haptic API support
//

#import <AVFoundation/AVFoundation.h>
#import <CoreHaptics/CoreHaptics.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef VERSION_4_0
#include "core/object/class_db.h"
#else
#include "core/class_db.h"
#endif

#include "haptics.h"

Haptics *Haptics::instance = NULL;

Haptics::Haptics() {
  instance = this;
  haptic_engine = NULL;
  engine_initialized = false;
  NSLog(@"[Haptics] Initialize haptics plugin");
}

Haptics::~Haptics() {
  cleanup_haptic_engine();
  if (instance == this) {
    instance = NULL;
  }
  NSLog(@"[Haptics] Deinitialize haptics plugin");
}

Haptics *Haptics::get_singleton() { return instance; }

// =============================================================================
// MARK: - Method Bindings
// =============================================================================

void Haptics::_bind_methods() {
  // Impact Feedback
  ClassDB::bind_method("light", &Haptics::light);
  ClassDB::bind_method("medium", &Haptics::medium);
  ClassDB::bind_method("heavy", &Haptics::heavy);
  ClassDB::bind_method("soft", &Haptics::soft);
  ClassDB::bind_method("rigid", &Haptics::rigid);
  ClassDB::bind_method("impact", &Haptics::impact);

  // Notification Feedback
  ClassDB::bind_method("success", &Haptics::success);
  ClassDB::bind_method("warning", &Haptics::warning);
  ClassDB::bind_method("error", &Haptics::error);

  // Selection Feedback
  ClassDB::bind_method("selection", &Haptics::selection);

  // Core Haptics
  ClassDB::bind_method("transient", &Haptics::transient);
  ClassDB::bind_method("continuous", &Haptics::continuous);

  // Preset Patterns
  ClassDB::bind_method("pattern_heartbeat", &Haptics::pattern_heartbeat);
  ClassDB::bind_method("pattern_double_tap", &Haptics::pattern_double_tap);
  ClassDB::bind_method("pattern_ramp_up", &Haptics::pattern_ramp_up);

  // Utility
  ClassDB::bind_method("is_supported", &Haptics::is_supported);
  ClassDB::bind_method("is_core_haptics_supported",
                       &Haptics::is_core_haptics_supported);
  ClassDB::bind_method("prepare", &Haptics::prepare);
  ClassDB::bind_method("stop", &Haptics::stop);
}

// =============================================================================
// MARK: - Impact Feedback (UIImpactFeedbackGenerator)
// =============================================================================

void Haptics::light() {
  UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc]
      initWithStyle:UIImpactFeedbackStyleLight];
  [generator prepare];
  [generator impactOccurred];
}

void Haptics::medium() {
  UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc]
      initWithStyle:UIImpactFeedbackStyleMedium];
  [generator prepare];
  [generator impactOccurred];
}

void Haptics::heavy() {
  UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc]
      initWithStyle:UIImpactFeedbackStyleHeavy];
  [generator prepare];
  [generator impactOccurred];
}

void Haptics::soft() {
  if (@available(iOS 13.0, *)) {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleSoft];
    [generator prepare];
    [generator impactOccurred];
  } else {
    // Fallback to light for older iOS versions
    light();
  }
}

void Haptics::rigid() {
  if (@available(iOS 13.0, *)) {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleRigid];
    [generator prepare];
    [generator impactOccurred];
  } else {
    // Fallback to heavy for older iOS versions
    heavy();
  }
}

void Haptics::impact(float intensity) {
  if (@available(iOS 13.0, *)) {
    // Clamp intensity to valid range
    CGFloat clampedIntensity = fmax(0.0, fmin(1.0, intensity));
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleMedium];
    [generator prepare];
    [generator impactOccurredWithIntensity:clampedIntensity];
  } else {
    // Fallback: map intensity to light/medium/heavy
    if (intensity < 0.33) {
      light();
    } else if (intensity < 0.66) {
      medium();
    } else {
      heavy();
    }
  }
}

// =============================================================================
// MARK: - Notification Feedback (UINotificationFeedbackGenerator)
// =============================================================================

void Haptics::success() {
  UINotificationFeedbackGenerator *generator =
      [[UINotificationFeedbackGenerator alloc] init];
  [generator prepare];
  [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
}

void Haptics::warning() {
  UINotificationFeedbackGenerator *generator =
      [[UINotificationFeedbackGenerator alloc] init];
  [generator prepare];
  [generator notificationOccurred:UINotificationFeedbackTypeWarning];
}

void Haptics::error() {
  UINotificationFeedbackGenerator *generator =
      [[UINotificationFeedbackGenerator alloc] init];
  [generator prepare];
  [generator notificationOccurred:UINotificationFeedbackTypeError];
}

// =============================================================================
// MARK: - Selection Feedback (UISelectionFeedbackGenerator)
// =============================================================================

void Haptics::selection() {
  UISelectionFeedbackGenerator *generator =
      [[UISelectionFeedbackGenerator alloc] init];
  [generator prepare];
  [generator selectionChanged];
}

// =============================================================================
// MARK: - Core Haptics Engine Management
// =============================================================================

void Haptics::init_haptic_engine() {
  if (@available(iOS 13.0, *)) {
    if (engine_initialized)
      return;

    NSError *error = nil;
    CHHapticEngine *engine = [[CHHapticEngine alloc] initAndReturnError:&error];

    if (error) {
      NSLog(@"[Haptics] Failed to create haptic engine: %@",
            error.localizedDescription);
      return;
    }

    // Configure engine to auto-restart if it stops
    engine.resetHandler = ^{
      NSError *startError = nil;
      [(__bridge CHHapticEngine *)self->haptic_engine
          startAndReturnError:&startError];
      if (startError) {
        NSLog(@"[Haptics] Failed to restart haptic engine: %@",
              startError.localizedDescription);
      }
    };

    engine.stoppedHandler = ^(CHHapticEngineStoppedReason reason) {
      NSLog(@"[Haptics] Haptic engine stopped, reason: %ld", (long)reason);
    };

    // Start the engine
    [engine startAndReturnError:&error];
    if (error) {
      NSLog(@"[Haptics] Failed to start haptic engine: %@",
            error.localizedDescription);
      return;
    }

    haptic_engine = (__bridge_retained void *)engine;
    engine_initialized = true;
    NSLog(@"[Haptics] Core Haptics engine initialized successfully");
  }
}

void Haptics::cleanup_haptic_engine() {
  if (@available(iOS 13.0, *)) {
    if (haptic_engine) {
      CHHapticEngine *engine =
          (__bridge_transfer CHHapticEngine *)haptic_engine;
      [engine stopWithCompletionHandler:nil];
      haptic_engine = NULL;
      engine_initialized = false;
      NSLog(@"[Haptics] Core Haptics engine cleaned up");
    }
  }
}

// =============================================================================
// MARK: - Core Haptics (CHHapticEngine)
// =============================================================================

void Haptics::transient(float intensity, float sharpness) {
  if (@available(iOS 13.0, *)) {
    if (!engine_initialized) {
      init_haptic_engine();
    }

    if (!haptic_engine) {
      // Fallback to UIKit
      impact(intensity);
      return;
    }

    CHHapticEngine *engine = (__bridge CHHapticEngine *)haptic_engine;

    // Clamp values
    float clampedIntensity = fmax(0.0f, fmin(1.0f, intensity));
    float clampedSharpness = fmax(0.0f, fmin(1.0f, sharpness));

    // Create haptic event
    CHHapticEventParameter *intensityParam = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticIntensity
                      value:clampedIntensity];
    CHHapticEventParameter *sharpnessParam = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticSharpness
                      value:clampedSharpness];

    CHHapticEvent *event = [[CHHapticEvent alloc]
        initWithEventType:CHHapticEventTypeHapticTransient
               parameters:@[ intensityParam, sharpnessParam ]
             relativeTime:0];

    NSError *error = nil;
    CHHapticPattern *pattern =
        [[CHHapticPattern alloc] initWithEvents:@[ event ]
                                     parameters:@[]
                                          error:&error];

    if (error) {
      NSLog(@"[Haptics] Failed to create pattern: %@",
            error.localizedDescription);
      return;
    }

    id<CHHapticPatternPlayer> player = [engine createPlayerWithPattern:pattern
                                                                 error:&error];
    if (error) {
      NSLog(@"[Haptics] Failed to create player: %@",
            error.localizedDescription);
      return;
    }

    [player startAtTime:CHHapticTimeImmediate error:&error];
    if (error) {
      NSLog(@"[Haptics] Failed to play haptic: %@", error.localizedDescription);
    }
  } else {
    // Fallback for older iOS
    impact(intensity);
  }
}

void Haptics::continuous(float intensity, float sharpness, float duration) {
  if (@available(iOS 13.0, *)) {
    if (!engine_initialized) {
      init_haptic_engine();
    }

    if (!haptic_engine) {
      // Fallback to UIKit
      impact(intensity);
      return;
    }

    CHHapticEngine *engine = (__bridge CHHapticEngine *)haptic_engine;

    // Clamp values
    float clampedIntensity = fmax(0.0f, fmin(1.0f, intensity));
    float clampedSharpness = fmax(0.0f, fmin(1.0f, sharpness));
    float clampedDuration =
        fmax(0.01f, fmin(30.0f, duration)); // Max 30 seconds

    // Create continuous haptic event
    CHHapticEventParameter *intensityParam = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticIntensity
                      value:clampedIntensity];
    CHHapticEventParameter *sharpnessParam = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticSharpness
                      value:clampedSharpness];

    CHHapticEvent *event = [[CHHapticEvent alloc]
        initWithEventType:CHHapticEventTypeHapticContinuous
               parameters:@[ intensityParam, sharpnessParam ]
             relativeTime:0
                 duration:clampedDuration];

    NSError *error = nil;
    CHHapticPattern *pattern =
        [[CHHapticPattern alloc] initWithEvents:@[ event ]
                                     parameters:@[]
                                          error:&error];

    if (error) {
      NSLog(@"[Haptics] Failed to create continuous pattern: %@",
            error.localizedDescription);
      return;
    }

    id<CHHapticPatternPlayer> player = [engine createPlayerWithPattern:pattern
                                                                 error:&error];
    if (error) {
      NSLog(@"[Haptics] Failed to create continuous player: %@",
            error.localizedDescription);
      return;
    }

    [player startAtTime:CHHapticTimeImmediate error:&error];
    if (error) {
      NSLog(@"[Haptics] Failed to play continuous haptic: %@",
            error.localizedDescription);
    }
  } else {
    // Fallback for older iOS
    impact(intensity);
  }
}

// =============================================================================
// MARK: - Preset Patterns
// =============================================================================

void Haptics::pattern_heartbeat() {
  if (@available(iOS 13.0, *)) {
    if (!engine_initialized) {
      init_haptic_engine();
    }

    if (!haptic_engine) {
      // Fallback
      heavy();
      return;
    }

    CHHapticEngine *engine = (__bridge CHHapticEngine *)haptic_engine;

    // Heartbeat pattern: strong-weak, pause, strong-weak
    NSMutableArray *events = [NSMutableArray array];

    // First beat (strong)
    CHHapticEventParameter *strongIntensity = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticIntensity
                      value:1.0];
    CHHapticEventParameter *strongSharpness = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticSharpness
                      value:0.5];
    [events
        addObject:[[CHHapticEvent alloc]
                      initWithEventType:CHHapticEventTypeHapticTransient
                             parameters:@[ strongIntensity, strongSharpness ]
                           relativeTime:0]];

    // First beat (weak follow-up)
    CHHapticEventParameter *weakIntensity = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticIntensity
                      value:0.5];
    CHHapticEventParameter *weakSharpness = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticSharpness
                      value:0.3];
    [events addObject:[[CHHapticEvent alloc]
                          initWithEventType:CHHapticEventTypeHapticTransient
                                 parameters:@[ weakIntensity, weakSharpness ]
                               relativeTime:0.15]];

    // Second beat (strong) after pause
    [events
        addObject:[[CHHapticEvent alloc]
                      initWithEventType:CHHapticEventTypeHapticTransient
                             parameters:@[ strongIntensity, strongSharpness ]
                           relativeTime:0.5]];

    // Second beat (weak follow-up)
    [events addObject:[[CHHapticEvent alloc]
                          initWithEventType:CHHapticEventTypeHapticTransient
                                 parameters:@[ weakIntensity, weakSharpness ]
                               relativeTime:0.65]];

    NSError *error = nil;
    CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:events
                                                            parameters:@[]
                                                                 error:&error];

    if (!error) {
      id<CHHapticPatternPlayer> player =
          [engine createPlayerWithPattern:pattern error:&error];
      if (!error) {
        [player startAtTime:CHHapticTimeImmediate error:nil];
      }
    }
  } else {
    heavy();
  }
}

void Haptics::pattern_double_tap() {
  if (@available(iOS 13.0, *)) {
    if (!engine_initialized) {
      init_haptic_engine();
    }

    if (!haptic_engine) {
      medium();
      return;
    }

    CHHapticEngine *engine = (__bridge CHHapticEngine *)haptic_engine;

    CHHapticEventParameter *intensity = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticIntensity
                      value:0.8];
    CHHapticEventParameter *sharpness = [[CHHapticEventParameter alloc]
        initWithParameterID:CHHapticEventParameterIDHapticSharpness
                      value:0.7];

    NSArray *events = @[
      [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient
                                    parameters:@[ intensity, sharpness ]
                                  relativeTime:0],
      [[CHHapticEvent alloc] initWithEventType:CHHapticEventTypeHapticTransient
                                    parameters:@[ intensity, sharpness ]
                                  relativeTime:0.12]
    ];

    NSError *error = nil;
    CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:events
                                                            parameters:@[]
                                                                 error:&error];

    if (!error) {
      id<CHHapticPatternPlayer> player =
          [engine createPlayerWithPattern:pattern error:&error];
      if (!error) {
        [player startAtTime:CHHapticTimeImmediate error:nil];
      }
    }
  } else {
    medium();
  }
}

void Haptics::pattern_ramp_up() {
  if (@available(iOS 13.0, *)) {
    if (!engine_initialized) {
      init_haptic_engine();
    }

    if (!haptic_engine) {
      heavy();
      return;
    }

    CHHapticEngine *engine = (__bridge CHHapticEngine *)haptic_engine;

    NSMutableArray *events = [NSMutableArray array];

    // Create ramping transients
    for (int i = 0; i < 5; i++) {
      float intensity = 0.2f + (0.8f * (float)i / 4.0f);
      float sharpness = 0.3f + (0.5f * (float)i / 4.0f);

      CHHapticEventParameter *intensityParam = [[CHHapticEventParameter alloc]
          initWithParameterID:CHHapticEventParameterIDHapticIntensity
                        value:intensity];
      CHHapticEventParameter *sharpnessParam = [[CHHapticEventParameter alloc]
          initWithParameterID:CHHapticEventParameterIDHapticSharpness
                        value:sharpness];

      [events
          addObject:[[CHHapticEvent alloc]
                        initWithEventType:CHHapticEventTypeHapticTransient
                               parameters:@[ intensityParam, sharpnessParam ]
                             relativeTime:(double)i * 0.1]];
    }

    NSError *error = nil;
    CHHapticPattern *pattern = [[CHHapticPattern alloc] initWithEvents:events
                                                            parameters:@[]
                                                                 error:&error];

    if (!error) {
      id<CHHapticPatternPlayer> player =
          [engine createPlayerWithPattern:pattern error:&error];
      if (!error) {
        [player startAtTime:CHHapticTimeImmediate error:nil];
      }
    }
  } else {
    heavy();
  }
}

// =============================================================================
// MARK: - Utility Methods
// =============================================================================

bool Haptics::is_supported() {
  // Check if device supports haptic feedback
  // All iPhones 7 and later support haptics
  return true;
}

bool Haptics::is_core_haptics_supported() {
  if (@available(iOS 13.0, *)) {
    return [CHHapticEngine capabilitiesForHardware].supportsHaptics;
  }
  return false;
}

void Haptics::prepare() {
  if (@available(iOS 13.0, *)) {
    if (!engine_initialized) {
      init_haptic_engine();
    }
  }
}

void Haptics::stop() {
  if (@available(iOS 13.0, *)) {
    if (haptic_engine) {
      CHHapticEngine *engine = (__bridge CHHapticEngine *)haptic_engine;
      [engine stopWithCompletionHandler:nil];
      engine_initialized = false;

      // Restart engine for future use
      NSError *error = nil;
      [engine startAndReturnError:&error];
      if (!error) {
        engine_initialized = true;
      }
    }
  }
}
