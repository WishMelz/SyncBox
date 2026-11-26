#pragma once
#include <windows.h>
#include <flutter/encodable_value.h>
#include <flutter/method_result.h>

void ReadClipboardImage(HWND owner, flutter::MethodResult<flutter::EncodableValue>& result);
