#include "clipboard_reader.h"

#include <gtk/gtk.h>
#include <string.h>

namespace {

// The kinds of picture a copied one is asked for in, the best first: PNG,
// which screenshots are copied as and which keeps every pixel.
const char* const kPictureTypes[] = {"image/png", "image/jpeg", "image/gif",
                                     "image/webp", "image/bmp"};

// What GNOME's file manager copies files as, beside or instead of a list
// of URIs: "copy" or "cut", then a URI to a line.
const char kGnomeFiles[] = "x-special/gnome-copied-files";

// A read of the clipboard under way, answered once GTK has what it asked
// for.
struct Read {
  FlMethodCall* call;
  GtkClipboard* clipboard;
  // Whether the clipboard holds text, and the picture it holds, if any.
  gboolean text = FALSE;
  GdkAtom picture = GDK_NONE;
};

void respond(Read* read, FlValue* reply) {
  g_autoptr(FlValue) owned = reply;
  fl_method_call_respond_success(read->call, owned, nullptr);
  g_object_unref(read->call);
  delete read;
}

FlValue* reply_with(Read* read, const char* key, FlValue* value) {
  FlValue* reply = fl_value_new_map();
  fl_value_set_string_take(reply, key, value);
  fl_value_set_string_take(reply, "text", fl_value_new_bool(read->text));
  return reply;
}

void got_picture(GtkClipboard*, GtkSelectionData* data, gpointer user_data) {
  auto* read = static_cast<Read*>(user_data);
  gint length = 0;
  const guchar* bytes =
      data == nullptr ? nullptr
                      : gtk_selection_data_get_data_with_length(data, &length);
  if (bytes == nullptr || length <= 0) {
    respond(read, fl_value_new_null());
    return;
  }
  g_autofree gchar* type = gdk_atom_name(read->picture);
  FlValue* reply = reply_with(read, "picture",
                              fl_value_new_uint8_list(bytes, length));
  fl_value_set_string_take(reply, "type", fl_value_new_string(type));
  respond(read, reply);
}

// Asks for the picture on the clipboard, or answers that there is none.
void ask_for_picture(Read* read) {
  if (read->picture == GDK_NONE) {
    respond(read, fl_value_new_null());
    return;
  }
  gtk_clipboard_request_contents(read->clipboard, read->picture, got_picture,
                                 read);
}

// Answers with [uris] as files: each file's path, and a web address as it
// is. Addresses on the web alone are not files copied but a picture
// copied in a browser, given with its address: the picture, if it is
// there, is what is pasted.
void answer_uris(Read* read, gchar** uris) {
  FlValue* files = fl_value_new_list();
  gboolean local = FALSE;
  for (gchar** uri = uris; uri != nullptr && *uri != nullptr; uri++) {
    if (**uri == '\0') continue;
    g_autofree gchar* path = g_filename_from_uri(*uri, nullptr, nullptr);
    if (path != nullptr) {
      local = TRUE;
      fl_value_append_take(files, fl_value_new_string(path));
    } else if (g_str_has_prefix(*uri, "http://") ||
               g_str_has_prefix(*uri, "https://")) {
      fl_value_append_take(files, fl_value_new_string(*uri));
    }
  }
  if (!local && read->picture != GDK_NONE) {
    fl_value_unref(files);
    ask_for_picture(read);
    return;
  }
  if (fl_value_get_length(files) == 0) {
    fl_value_unref(files);
    ask_for_picture(read);
    return;
  }
  respond(read, reply_with(read, "files", files));
}

void got_uris(GtkClipboard*, gchar** uris, gpointer user_data) {
  answer_uris(static_cast<Read*>(user_data), uris);
}

void got_gnome_files(GtkClipboard*, GtkSelectionData* data,
                     gpointer user_data) {
  auto* read = static_cast<Read*>(user_data);
  gint length = 0;
  const guchar* bytes =
      data == nullptr ? nullptr
                      : gtk_selection_data_get_data_with_length(data, &length);
  if (bytes == nullptr || length <= 0) {
    ask_for_picture(read);
    return;
  }
  g_autofree gchar* text =
      g_strndup(reinterpret_cast<const gchar*>(bytes), length);
  g_auto(GStrv) lines = g_strsplit(text, "\n", -1);
  // The first line says whether they were copied or cut.
  answer_uris(read, lines[0] == nullptr ? lines : lines + 1);
}

void got_targets(GtkClipboard*, GdkAtom* atoms, gint count,
                 gpointer user_data) {
  auto* read = static_cast<Read*>(user_data);
  if (atoms == nullptr || count <= 0) {
    respond(read, fl_value_new_null());
    return;
  }
  read->text = gtk_targets_include_text(atoms, count);
  gboolean gnome = FALSE;
  for (const char* type : kPictureTypes) {
    for (gint i = 0; i < count && read->picture == GDK_NONE; i++) {
      g_autofree gchar* name = gdk_atom_name(atoms[i]);
      if (strcmp(name, type) == 0) read->picture = atoms[i];
    }
  }
  for (gint i = 0; i < count; i++) {
    g_autofree gchar* name = gdk_atom_name(atoms[i]);
    if (strcmp(name, kGnomeFiles) == 0) gnome = TRUE;
  }
  if (gtk_targets_include_uri(atoms, count)) {
    gtk_clipboard_request_uris(read->clipboard, got_uris, read);
  } else if (gnome) {
    gtk_clipboard_request_contents(read->clipboard,
                                   gdk_atom_intern_static_string(kGnomeFiles),
                                   got_gnome_files, read);
  } else {
    ask_for_picture(read);
  }
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (strcmp(fl_method_call_get_name(call), "read") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  auto* read = new Read();
  read->call = FL_METHOD_CALL(g_object_ref(call));
  read->clipboard = gtk_clipboard_get_for_display(gdk_display_get_default(),
                                                  GDK_SELECTION_CLIPBOARD);
  gtk_clipboard_request_targets(read->clipboard, got_targets, read);
}

}  // namespace

void clipboard_reader_listen(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Kept for as long as the app runs.
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "aantekening/clipboard", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call, nullptr,
                                            nullptr);
}
