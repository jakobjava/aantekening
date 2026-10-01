#include "touchpad_hold.h"

#include <gdk/gdkwayland.h>

#include <cstring>

#include "protocols/pointer-gestures-unstable-v1-client-protocol.h"

namespace {

struct TouchpadHold {
  FlMethodChannel* channel = nullptr;
  zwp_pointer_gestures_v1* gestures = nullptr;
  bool resting = false;
};

void tell(TouchpadHold* self, const char* fingers) {
  g_autoptr(FlValue) argument = fl_value_new_string(fingers);
  fl_method_channel_invoke_method(self->channel, "fingers", argument, nullptr,
                                  nullptr, nullptr);
}

void hold_begin(void* data,
                zwp_pointer_gesture_hold_v1* hold,
                uint32_t serial,
                uint32_t time,
                wl_surface* surface,
                uint32_t fingers) {
  auto* self = static_cast<TouchpadHold*>(data);
  // One finger resting is a hand about to move the pointer.
  self->resting = fingers >= 2;
  if (self->resting) {
    tell(self, "resting");
  }
}

void hold_end(void* data,
              zwp_pointer_gesture_hold_v1* hold,
              uint32_t serial,
              uint32_t time,
              int32_t cancelled) {
  auto* self = static_cast<TouchpadHold*>(data);
  if (self->resting) {
    self->resting = false;
    tell(self, cancelled != 0 ? "moving" : "lifted");
  }
}

const zwp_pointer_gesture_hold_v1_listener hold_listener = {hold_begin,
                                                             hold_end};

void global(void* data,
            wl_registry* registry,
            uint32_t name,
            const char* interface,
            uint32_t version) {
  auto* self = static_cast<TouchpadHold*>(data);
  constexpr uint32_t holds =
      ZWP_POINTER_GESTURES_V1_GET_HOLD_GESTURE_SINCE_VERSION;
  if (strcmp(interface, zwp_pointer_gestures_v1_interface.name) == 0 &&
      version >= holds) {
    self->gestures = static_cast<zwp_pointer_gestures_v1*>(
        wl_registry_bind(registry, name, &zwp_pointer_gestures_v1_interface,
                         holds));
  }
}

void global_remove(void* data, wl_registry* registry, uint32_t name) {}

const wl_registry_listener registry_listener = {global, global_remove};

}  // namespace

void touchpad_hold_listen(FlView* view) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(view));
  if (!GDK_IS_WAYLAND_DISPLAY(display)) {
    return;
  }
  GdkDevice* device =
      gdk_seat_get_pointer(gdk_display_get_default_seat(display));
  wl_pointer* pointer =
      device == nullptr ? nullptr : gdk_wayland_device_get_wl_pointer(device);
  if (pointer == nullptr) {
    return;
  }

  // The desktop's gestures are looked up on a queue of their own, so that
  // waiting for the answer hands none of GDK's own events on early.
  wl_display* wayland = gdk_wayland_display_get_wl_display(display);
  wl_event_queue* queue = wl_display_create_queue(wayland);
  auto* wrapped = static_cast<wl_display*>(wl_proxy_create_wrapper(wayland));
  wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(wrapped), queue);
  wl_registry* registry = wl_display_get_registry(wrapped);
  // Kept for as long as the app runs.
  auto* self = new TouchpadHold();
  wl_registry_add_listener(registry, &registry_listener, self);
  wl_display_roundtrip_queue(wayland, queue);
  wl_registry_destroy(registry);
  wl_proxy_wrapper_destroy(wrapped);
  if (self->gestures == nullptr) {
    wl_event_queue_destroy(queue);
    delete self;
    return;
  }
  // Its gestures are told of with GDK's own events, as they come.
  wl_proxy_set_queue(reinterpret_cast<wl_proxy*>(self->gestures), nullptr);
  wl_event_queue_destroy(queue);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "aantekening/touchpad", FL_METHOD_CODEC(codec));
  zwp_pointer_gesture_hold_v1* hold =
      zwp_pointer_gestures_v1_get_hold_gesture(self->gestures, pointer);
  zwp_pointer_gesture_hold_v1_add_listener(hold, &hold_listener, self);
}
