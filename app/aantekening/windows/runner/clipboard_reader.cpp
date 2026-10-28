#include "clipboard_reader.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <cstring>
#include <string>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

// [wide] as UTF-8.
std::string Utf8(const std::wstring& wide) {
  if (wide.empty()) return std::string();
  const int length =
      WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                          nullptr, 0, nullptr, nullptr);
  std::string out(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      out.data(), length, nullptr, nullptr);
  return out;
}

// What the clipboard holds in [format], as it holds it; nothing if it
// holds nothing in it.
std::vector<uint8_t> BytesIn(UINT format) {
  HANDLE data = GetClipboardData(format);
  if (data == nullptr) return {};
  const SIZE_T size = GlobalSize(data);
  const auto* bytes = static_cast<const uint8_t*>(GlobalLock(data));
  if (bytes == nullptr) return {};
  std::vector<uint8_t> out(bytes, bytes + size);
  GlobalUnlock(data);
  return out;
}

// The files copied, by their paths.
EncodableList CopiedFiles() {
  EncodableList files;
  auto drop = static_cast<HDROP>(GetClipboardData(CF_HDROP));
  if (drop == nullptr) return files;
  const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count; i++) {
    const UINT length = DragQueryFileW(drop, i, nullptr, 0);
    if (length == 0) continue;
    std::wstring path(length + 1, L'\0');
    DragQueryFileW(drop, i, path.data(), length + 1);
    path.resize(length);
    files.push_back(EncodableValue(Utf8(path)));
  }
  return files;
}

// The picture held as a bitmap, as a .bmp file holds it: a file's header,
// then the bitmap. A bitmap of 32 bits a pixel says nothing of its fourth
// byte, which a screenshot leaves at nought: it is made opaque, as it is
// on the screen.
std::vector<uint8_t> BitmapFile() {
  std::vector<uint8_t> bitmap = BytesIn(CF_DIB);
  if (bitmap.size() < sizeof(BITMAPINFOHEADER)) return {};
  BITMAPINFOHEADER info;
  std::memcpy(&info, bitmap.data(), sizeof(info));
  DWORD colours = info.biClrUsed;
  if (colours == 0 && info.biBitCount <= 8) colours = 1u << info.biBitCount;
  const DWORD masks = info.biSize == sizeof(BITMAPINFOHEADER) &&
                              info.biCompression == BI_BITFIELDS
                          ? 3 * sizeof(DWORD)
                          : 0;
  const size_t pixels = info.biSize + masks + colours * sizeof(RGBQUAD);
  if (pixels > bitmap.size()) return {};
  if (info.biBitCount == 32 && info.biCompression == BI_RGB) {
    for (size_t at = pixels + 3; at < bitmap.size(); at += 4) {
      bitmap[at] = 0xFF;
    }
  }
  BITMAPFILEHEADER header = {};
  header.bfType = 0x4D42;  // "BM"
  header.bfSize = static_cast<DWORD>(sizeof(header) + bitmap.size());
  header.bfOffBits = static_cast<DWORD>(sizeof(header) + pixels);
  std::vector<uint8_t> file(sizeof(header) + bitmap.size());
  std::memcpy(file.data(), &header, sizeof(header));
  std::memcpy(file.data() + sizeof(header), bitmap.data(), bitmap.size());
  return file;
}

// What the clipboard holds of files and pictures: files first, as copied
// in Explorer; then a PNG, as the Snipping Tool and browsers copy one;
// then a bitmap, as Print Screen copies the screen.
EncodableValue Read(HWND window) {
  if (!OpenClipboard(window)) return EncodableValue();
  const bool text = IsClipboardFormatAvailable(CF_UNICODETEXT) != 0;
  const UINT png = RegisterClipboardFormatW(L"PNG");
  EncodableMap reply;
  if (IsClipboardFormatAvailable(CF_HDROP)) {
    EncodableList files = CopiedFiles();
    if (!files.empty()) reply[EncodableValue("files")] = EncodableValue(files);
  }
  if (reply.empty() && png != 0 && IsClipboardFormatAvailable(png)) {
    std::vector<uint8_t> bytes = BytesIn(png);
    if (!bytes.empty()) {
      reply[EncodableValue("picture")] = EncodableValue(bytes);
      reply[EncodableValue("type")] = EncodableValue("image/png");
    }
  }
  if (reply.empty() && IsClipboardFormatAvailable(CF_DIB)) {
    std::vector<uint8_t> bytes = BitmapFile();
    if (!bytes.empty()) {
      reply[EncodableValue("picture")] = EncodableValue(bytes);
      reply[EncodableValue("type")] = EncodableValue("image/bmp");
    }
  }
  CloseClipboard();
  if (reply.empty()) return EncodableValue();
  reply[EncodableValue("text")] = EncodableValue(text);
  return EncodableValue(reply);
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>> ListenToClipboardReads(
    flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "aantekening/clipboard",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window](const flutter::MethodCall<EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "read") {
          result->Success(Read(window));
        } else {
          result->NotImplemented();
        }
      });
  return channel;
}
