#include "opaque_underlay.h"

#include <epoxy/gl.h>
#include <gdk/gdkwayland.h>

namespace {

// A texture of one opaque pixel, without an alpha channel, made the first
// time the view is drawn; 0 until then, or if it could not be made.
GLuint texture = 0;
GdkGLContext* context = nullptr;
bool failed = false;

// The view, once the underlay is laid beneath it.
GtkWidget* underlaid = nullptr;

// Tells the desktop that the view hides what lies behind it, which it can
// tell only of what is drawn opaque: without it, the desktop draws the
// windows and the wallpaper behind the window, and blends the window over
// them, at every frame. GTK says so only of a window whose background it
// paints, which it would do at every frame, and says it no longer each
// time it lays the window out, so it is said again then.
void tell_opaque() {
  if (underlaid == nullptr) {
    return;
  }
  GtkWidget* toplevel = gtk_widget_get_toplevel(underlaid);
  GdkWindow* window = gtk_widget_get_window(toplevel);
  if (window == nullptr) {
    return;
  }
  cairo_rectangle_int_t rect = {0, 0,
                                gtk_widget_get_allocated_width(underlaid),
                                gtk_widget_get_allocated_height(underlaid)};
  gtk_widget_translate_coordinates(underlaid, toplevel, 0, 0, &rect.x,
                                   &rect.y);
  cairo_region_t* region = cairo_region_create_rectangle(&rect);
  gdk_window_set_opaque_region(window, region);
  cairo_region_destroy(region);
}

void laid_out_cb(GtkWidget* toplevel, gpointer user_data) {
  tell_opaque();
}

bool make_texture(GdkWindow* window) {
  g_autoptr(GError) error = nullptr;
  // Made from the window, it shares what it makes with the context GTK
  // paints the window with.
  context = gdk_window_create_gl_context(window, &error);
  if (context == nullptr || !gdk_gl_context_realize(context, &error)) {
    g_warning("No opaque underlay: %s",
              error != nullptr ? error->message : "no context");
    g_clear_object(&context);
    return false;
  }
  gdk_gl_context_make_current(context);
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  const GLubyte black[3] = {0, 0, 0};
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB8, 1, 1, 0, GL_RGB, GL_UNSIGNED_BYTE,
               black);
  glFlush();
  gdk_gl_context_clear_current();
  return true;
}

// Before Flutter draws its frame, the pixel over all of it. GTK repeats
// the texture across what it is to cover.
gboolean draw_cb(GtkWidget* area, cairo_t* cr, gpointer user_data) {
  GdkWindow* window = gtk_widget_get_window(area);
  if (failed || window == nullptr) {
    return FALSE;
  }
  if (texture == 0) {
    if (!make_texture(window)) {
      failed = true;
      return FALSE;
    }
    underlaid = gtk_widget_get_ancestor(area, fl_view_get_type());
    GtkWidget* toplevel = gtk_widget_get_toplevel(area);
    g_signal_connect_after(toplevel, "size-allocate", G_CALLBACK(laid_out_cb),
                           nullptr);
    g_signal_connect_after(toplevel, "style-updated", G_CALLBACK(laid_out_cb),
                           nullptr);
    tell_opaque();
  }
  gdk_cairo_draw_from_gl(cr, window, texture, GL_TEXTURE, 1, 0, 0,
                         gtk_widget_get_allocated_width(area),
                         gtk_widget_get_allocated_height(area));
  return FALSE;
}

// The widget Flutter draws its frames in, of those within [widget].
GtkWidget* drawing_area_in(GtkWidget* widget) {
  if (GTK_IS_DRAWING_AREA(widget)) {
    return widget;
  }
  if (!GTK_IS_CONTAINER(widget)) {
    return nullptr;
  }
  GtkWidget* found = nullptr;
  GList* children = gtk_container_get_children(GTK_CONTAINER(widget));
  for (GList* child = children; child != nullptr && found == nullptr;
       child = child->next) {
    found = drawing_area_in(GTK_WIDGET(child->data));
  }
  g_list_free(children);
  return found;
}

}  // namespace

void opaque_underlay_lay(FlView* view) {
  // Elsewhere GTK reads what the graphics card drew back to draw it: there,
  // this would cost what it saves on Wayland.
  if (!GDK_IS_WAYLAND_DISPLAY(gtk_widget_get_display(GTK_WIDGET(view)))) {
    return;
  }
  // In the very widget the frame is drawn in, before it: GTK takes what
  // was drawn beneath a widget for something it must blend the widget's
  // drawing over, and copies it into the graphics card after all.
  GtkWidget* area = drawing_area_in(GTK_WIDGET(view));
  if (area != nullptr) {
    g_signal_connect(area, "draw", G_CALLBACK(draw_cb), nullptr);
  }
}
