#include "clipboard_image.h"

#include <shellapi.h>
#include <wincodec.h>
#include <wrl/client.h>
#include "utils.h"

namespace {
using Microsoft::WRL::ComPtr;
using flutter::EncodableValue;
constexpr ULONG kMaxBytes = 8 * 1024 * 1024;
struct ClipboardCloser { ~ClipboardCloser() { CloseClipboard(); } };

// Convert Windows screenshots to PNG, a format accepted by the image API.
HRESULT EncodePng(HBITMAP handle, std::vector<uint8_t>& bytes) {
  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICBitmap> bitmap;
  ComPtr<IStream> stream;
  ComPtr<IWICBitmapEncoder> encoder;
  ComPtr<IWICBitmapFrameEncode> frame;
  HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(factory.GetAddressOf()));
  if (SUCCEEDED(hr)) hr = factory->CreateBitmapFromHBITMAP(handle, nullptr, WICBitmapIgnoreAlpha, &bitmap);
  if (SUCCEEDED(hr)) hr = CreateStreamOnHGlobal(nullptr, TRUE, &stream);
  if (SUCCEEDED(hr)) hr = factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
  if (SUCCEEDED(hr)) hr = encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache);
  if (SUCCEEDED(hr)) hr = encoder->CreateNewFrame(&frame, nullptr);
  if (SUCCEEDED(hr)) hr = frame->Initialize(nullptr);
  if (SUCCEEDED(hr)) hr = frame->WriteSource(bitmap.Get(), nullptr);
  if (SUCCEEDED(hr)) hr = frame->Commit();
  if (SUCCEEDED(hr)) hr = encoder->Commit();
  STATSTG stat{};
  if (SUCCEEDED(hr)) hr = stream->Stat(&stat, STATFLAG_NONAME);
  if (FAILED(hr)) return hr;
  if (!stat.cbSize.QuadPart || stat.cbSize.QuadPart > kMaxBytes) return HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE);
  bytes.resize(stat.cbSize.LowPart);
  hr = stream->Seek({}, STREAM_SEEK_SET, nullptr);
  ULONG read = 0;
  if (SUCCEEDED(hr)) hr = stream->Read(bytes.data(), stat.cbSize.LowPart, &read);
  return SUCCEEDED(hr) && read != stat.cbSize.LowPart ? E_FAIL : hr;
}
}  // namespace

void ReadClipboardImage(HWND owner, flutter::MethodResult<EncodableValue>& result) {
  if (!OpenClipboard(owner)) { result.Error("busy", "Clipboard is busy"); return; }
  ClipboardCloser closer;
  // Prefer original PNG bytes to preserve transparency.
  if (auto png = GetClipboardData(RegisterClipboardFormatW(L"PNG"))) {
    const auto size = GlobalSize(png);
    if (size > kMaxBytes) { result.Error("size", "Image exceeds 8 MB"); return; }
    if (auto data = static_cast<const uint8_t*>(GlobalLock(png))) {
      std::vector<uint8_t> bytes(data, data + size);
      GlobalUnlock(png);
      if (!bytes.empty()) { result.Success(EncodableValue(std::move(bytes))); return; }
    }
  }
  if (auto bitmap = static_cast<HBITMAP>(GetClipboardData(CF_BITMAP))) {
    BITMAP info{};
    if (!GetObjectW(bitmap, sizeof(info), &info) || info.bmWidth <= 0 || info.bmHeight <= 0 ||
        static_cast<int64_t>(info.bmWidth) * info.bmHeight > 24000000) {
      result.Error("dimensions", "Invalid or oversized bitmap"); return;
    }
    std::vector<uint8_t> bytes;
    const auto hr = EncodePng(bitmap, bytes);
    if (FAILED(hr)) { result.Error(hr == HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE) ? "size" : "image", "Cannot encode image"); return; }
    result.Success(EncodableValue(std::move(bytes))); return;
  }
  // Explorer copies file paths instead of bitmap pixels.
  if (auto files = static_cast<HDROP>(GetClipboardData(CF_HDROP))) {
    flutter::EncodableList paths;
    const UINT count = DragQueryFileW(files, 0xFFFFFFFF, nullptr, 0);
    for (UINT i = 0; i < count && i < 6; ++i) {
      const UINT len = DragQueryFileW(files, i, nullptr, 0);
      std::vector<wchar_t> path(len + 1);
      if (DragQueryFileW(files, i, path.data(), len + 1)) paths.emplace_back(Utf8FromUtf16(path.data()));
    }
    if (!paths.empty()) { result.Success(EncodableValue(std::move(paths))); return; }
  }
  result.Success();
}
