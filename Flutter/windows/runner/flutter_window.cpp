#include "flutter_window.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <cwctype>
#include <fstream>
#include <flutter/encodable_value.h>
#include <map>
#include <memory>
#include <optional>
#include <shellapi.h>
#include <shlobj.h>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
#include <windows.h>
#include <gdiplus.h>
#include <commctrl.h>
#include <commdlg.h>
#include <mfapi.h>
#include <mfplay.h>
#include <ole2.h>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace {

constexpr int kCompactMessengerWidth = 460;
constexpr int kCompactMessengerHeight = 720;
constexpr int kExpandedMessengerWidth = 960;
constexpr int kQuickAvaAiWidth = 430;
constexpr int kQuickAvaAiHeight = 680;
constexpr int kAzoomMessengerWidth = 1344;
constexpr int kAzoomMessengerHeight = 722;
constexpr wchar_t kNotificationClassName[] = L"AVA_CHAT_NOTIFICATION";
constexpr wchar_t kChatFloatingClassName[] = L"AVA_CHAT_FLOATING";
constexpr wchar_t kProfilePopupClassName[] = L"AVA_PROFILE_POPUP";
constexpr wchar_t kProfileEditClassName[] = L"AVA_PROFILE_EDIT_POPUP";
constexpr wchar_t kFolderCreateClassName[] = L"AVA_FOLDER_CREATE_POPUP";
constexpr wchar_t kNewChatClassName[] = L"AVA_NEW_CHAT_POPUP";
constexpr wchar_t kEmployeeAddClassName[] = L"AVA_EMPLOYEE_ADD_POPUP";
constexpr wchar_t kFolderManageClassName[] = L"AVA_FOLDER_MANAGE_POPUP";
constexpr wchar_t kFolderSubmenuClassName[] = L"AVA_FOLDER_SUBMENU_POPUP";
constexpr wchar_t kQuietRoomsClassName[] = L"AVA_QUIET_ROOMS_POPUP";
constexpr wchar_t kMultiLeaveRoomsClassName[] = L"AVA_MULTI_LEAVE_ROOMS_POPUP";
constexpr wchar_t kImageViewerClassName[] = L"AVA_IMAGE_VIEWER_POPUP";
constexpr wchar_t kVideoViewerClassName[] = L"AVA_VIDEO_VIEWER_POPUP";
constexpr wchar_t kQuietToastClassName[] = L"AVA_QUIET_TOAST";
constexpr int kNotificationWidth = 310;
constexpr int kNotificationHeight = 132;
constexpr int kNotificationMargin = 18;

WINDOWPLACEMENT g_pre_azoom_window_placement{};
bool g_has_pre_azoom_window_placement = false;
WINDOWPLACEMENT g_pre_azoom_fullscreen_placement{};
DWORD g_pre_azoom_fullscreen_style = 0;
bool g_azoom_fullscreen = false;
constexpr int kChatFloatingExpandedWidth = 200;
constexpr int kChatFloatingCollapsedWidth = 48;
constexpr int kChatFloatingHeight = 38;
constexpr int kChatFloatingMargin = 8;
constexpr int kProfilePopupNativeWidth = 338;
constexpr int kProfilePopupNativeHeight = 500;
constexpr int kProfileEditNativeWidth = 338;
constexpr int kProfileEditNativeHeight = 508;
constexpr int kFolderCreateNativeWidth = 370;
constexpr int kFolderCreateNativeHeight = 600;
constexpr int kNewChatNativeWidth = 370;
constexpr int kNewChatNativeHeight = 600;
constexpr int kEmployeeAddNativeWidth = 300;
constexpr int kEmployeeAddNativeHeight = 452;
constexpr int kFolderManageNativeWidth = 370;
constexpr int kFolderManageNativeHeight = 600;
constexpr int kFolderSubmenuWidth = 112;
constexpr int kFolderSubmenuRowHeight = 28;
constexpr int kQuietRoomsNativeWidth = 370;
constexpr int kQuietRoomsNativeHeight = 600;
constexpr int kQuietRoomsRowHeight = 70;
constexpr int kMultiLeaveNativeWidth = 340;
constexpr int kMultiLeaveNativeHeight = 508;
constexpr int kMultiLeaveRowHeight = 68;
constexpr int kImageViewerDefaultWidth = 1268;
constexpr int kImageViewerDefaultHeight = 706;
constexpr int kImageViewerToolbarHeight = 48;
constexpr int kVideoViewerDefaultWidth = 1268;
constexpr int kVideoViewerDefaultHeight = 706;
constexpr int kVideoViewerControlBarHeight = 34;
constexpr int kVideoViewerToolbarHeight = 48;
constexpr int kQuietToastWidth = 250;
constexpr int kQuietToastHeight = 42;
constexpr int kProfilePopupFooterHeight = 140;
constexpr int kProfileWindowCornerRadius = 18;
constexpr UINT_PTR kNotificationAutoCloseTimer = 1001;
constexpr UINT_PTR kFolderSubmenuCloseTimer = 1002;
constexpr UINT_PTR kQuietToastTimer = 1003;
constexpr UINT_PTR kVideoViewerTimer = 1004;
constexpr UINT kVideoViewerPlayerEventMessage = WM_APP + 190;
constexpr int kNotificationEditId = 2000;
constexpr int kProfileNicknameEditId = 3001;
constexpr int kProfileStatusEditId = 3002;
constexpr int kFolderNameEditId = 3201;
constexpr int kNewChatSearchEditId = 3251;
constexpr int kNewChatNameEditId = 3252;
constexpr int kEmployeeNameEditId = 3301;
constexpr int kEmployeePhoneEditId = 3302;
constexpr int kEmployeeCountryEditId = 3303;
constexpr int kEmployeeEmailEditId = 3304;
constexpr UINT kFloatingMenuToggleFold = 4101;
constexpr UINT kFloatingMenuToggleAvatar = 4102;
constexpr UINT kFloatingMenuOpenRoom = 4103;
constexpr UINT kFloatingMenuClose = 4104;
constexpr UINT kFloatingMenuCloseAll = 4105;
constexpr UINT kQuietMenuOpenRoom = 6101;
constexpr UINT kQuietMenuRead = 6103;
constexpr UINT kQuietMenuFloating = 6104;
constexpr UINT kQuietMenuUnquiet = 6105;
constexpr UINT kQuietMenuLeave = 6106;
constexpr UINT kTrayIconId = 7001;
constexpr UINT kTrayIconMessage = WM_APP + 701;
constexpr UINT kTrayMenuOpen = 7101;
constexpr UINT kTrayMenuLock = 7102;
constexpr UINT kTrayMenuLogout = 7103;
constexpr UINT kTrayMenuExit = 7104;
constexpr int kQuickAvaAiHotkeyId = 7201;
constexpr wchar_t kAvaShowMainWindowMessageName[] =
    L"ABBA-S.AVA.ShowMainWindow";

HWND g_active_notification = nullptr;
HWND g_active_profile_popup = nullptr;
HWND g_active_profile_edit_popup = nullptr;
HWND g_active_folder_create_popup = nullptr;
HWND g_active_new_chat_popup = nullptr;
HWND g_active_employee_add_popup = nullptr;
HWND g_active_folder_manage_popup = nullptr;
HWND g_active_folder_submenu_popup = nullptr;
HWND g_active_quiet_rooms_popup = nullptr;
HWND g_active_multi_leave_rooms_popup = nullptr;
HWND g_active_image_viewer = nullptr;
HWND g_active_video_viewer = nullptr;
HWND g_active_quiet_toast = nullptr;
std::map<std::string, HWND> g_chat_floatings;
ULONG_PTR g_gdiplus_token = 0;
bool g_media_foundation_started = false;
bool g_media_foundation_attempted = false;
bool g_ole_initialized = false;

UINT AvaShowMainWindowMessage() {
  static UINT message = ::RegisterWindowMessageW(kAvaShowMainWindowMessageName);
  return message;
}

struct NotificationState {
  std::string room_id;
  std::wstring room_title;
  std::wstring sender_name;
  std::wstring sender_nickname;
  std::wstring body;
  COLORREF avatar_color = RGB(122, 160, 106);
  flutter::MethodChannel<flutter::EncodableValue>* channel;
  HWND edit = nullptr;
  HFONT input_font = nullptr;
};

struct ChatFloatingState {
  std::string room_id;
  std::wstring title;
  COLORREF avatar_color = RGB(122, 160, 106);
  bool is_group = false;
  bool is_muted = false;
  int unread_count = 0;
  bool collapsed = false;
  bool hide_avatar = false;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
};

struct ProfilePopupState {
  bool is_self = false;
  std::string id;
  std::string email;
  std::string avatar_image_url;
  std::string background_image_url;
  std::wstring name;
  std::wstring nickname;
  std::wstring status_message;
  COLORREF avatar_color = RGB(122, 160, 106);
  COLORREF background_color = RGB(122, 160, 106);
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
};

struct ProfileEditState {
  std::string id;
  std::string email;
  std::string avatar_image_url;
  std::wstring name;
  std::wstring nickname;
  std::wstring status_message;
  COLORREF avatar_color = RGB(122, 160, 106);
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  HWND nickname_edit = nullptr;
  HWND status_edit = nullptr;
  HFONT edit_font = nullptr;
};

struct RoomAvatarPartState {
  COLORREF color = RGB(166, 198, 238);
  std::string image_url;
};

struct FolderRoomState {
  std::string id;
  std::wstring title;
  std::wstring preview;
  std::string avatar_image_url;
  COLORREF avatar_color = RGB(166, 198, 238);
  bool is_group = false;
  int participant_count = 1;
  int unread_count = 0;
  std::vector<RoomAvatarPartState> avatar_parts;
};

struct FolderCreateState {
  std::vector<FolderRoomState> rooms;
  std::vector<std::string> selected_room_ids;
  std::wstring initial_name;
  std::wstring selected_icon = L"\x2298";
  bool selecting_rooms = false;
  bool is_edit = false;
  bool submitted = false;
  int room_scroll_offset = 0;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  HWND name_edit = nullptr;
  HFONT edit_font = nullptr;
};

struct NewChatUserState {
  std::string id;
  std::string email;
  std::string avatar_image_url;
  std::wstring name;
  std::wstring nickname;
  COLORREF avatar_color = RGB(166, 198, 238);
};

struct NewChatState {
  std::vector<NewChatUserState> users;
  std::vector<std::string> selected_user_ids;
  int step = 0;
  int scroll_offset = 0;
  bool room_name_editing = false;
  bool submitted = false;
  std::string avatar_image_url;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  HWND search_edit = nullptr;
  HWND name_edit = nullptr;
  HFONT edit_font = nullptr;
};

struct EmployeeResultState {
  bool has_result = false;
  bool is_already_added = false;
  bool blocked = false;
  std::string id;
  std::string email;
  std::wstring name;
  std::wstring nickname;
  COLORREF avatar_color = RGB(166, 198, 238);
  std::string avatar_image_url;
};

struct EmployeeAddState {
  int tab_index = 0;
  bool submitted = false;
  bool formatting_phone = false;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
  HWND name_edit = nullptr;
  HWND phone_edit = nullptr;
  HWND country_edit = nullptr;
  HWND email_edit = nullptr;
  HFONT edit_font = nullptr;
  EmployeeResultState contact_result;
  EmployeeResultState email_result;
};

WNDPROC g_employee_country_edit_original_proc = nullptr;

struct FolderManageItemState {
  std::string id;
  std::wstring name;
  std::wstring icon;
  int count = 0;
  bool is_favorite = false;
  bool is_system = false;
};

struct FolderManageState {
  std::vector<FolderManageItemState> folders;
  int unread_count = 0;
  bool has_favorite = false;
  bool submitted = false;
  bool dragging = false;
  int dragging_index = -1;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
};

struct FolderSubmenuState {
  std::vector<FolderManageItemState> folders;
  RECT parent_rect{};
  int hovered_index = -1;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
};

struct QuietRoomState {
  std::string id;
  std::wstring title;
  std::wstring preview;
  std::wstring time;
  COLORREF avatar_color = RGB(166, 198, 238);
  bool is_group = false;
  bool is_muted = false;
  int unread_count = 0;
  int participant_count = 1;
  std::string avatar_image_url;
  std::vector<RoomAvatarPartState> avatar_parts;
};

struct QuietRoomsState {
  std::vector<QuietRoomState> rooms;
  int hovered_index = -1;
  bool submitted = false;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
};

struct MultiLeaveRoomsState {
  std::vector<QuietRoomState> rooms;
  std::vector<std::string> selected_room_ids;
  int hovered_index = -1;
  int room_scroll_offset = 0;
  bool submitted = false;
  flutter::MethodChannel<flutter::EncodableValue>* channel = nullptr;
};

struct QuietToastState {
  std::wstring message;
};

struct NativeMenuItemState {
  std::string value;
  std::wstring label;
  std::string icon;
  bool separator = false;
  bool enabled = true;
  bool checked = false;
  std::vector<NativeMenuItemState> children;
};

struct ImageViewerItemState {
  std::wstring path;
  std::wstring name;
};

struct ImageViewerState {
  std::vector<ImageViewerItemState> items;
  int index = 0;
  double zoom = 1.0;
  bool fit = true;
  int rotation = 0;
  std::wstring sender;
  std::wstring date;
  std::unique_ptr<Gdiplus::Image> image;
};

class VideoViewerCallback;

struct VideoViewerState {
  std::wstring path;
  std::wstring name;
  std::wstring sender;
  std::wstring date;
  HWND video_host = nullptr;
  IMFPMediaPlayer* player = nullptr;
  VideoViewerCallback* callback = nullptr;
  bool playing = true;
  bool ready = false;
  bool ended = false;
  bool dragging_progress = false;
  bool dragging_volume = false;
  bool has_error = false;
  HRESULT last_error = S_OK;
  double volume = 0.82;
  LONGLONG duration_100ns = 0;
  LONGLONG position_100ns = 0;
};

std::wstring Utf16FromUtf8(const std::string& utf8_string) {
  if (utf8_string.empty()) {
    return std::wstring();
  }
  int target_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
      static_cast<int>(utf8_string.size()), nullptr, 0);
  if (target_length == 0) {
    return std::wstring();
  }
  std::wstring utf16_string(target_length, L'\0');
  int converted_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8_string.data(),
      static_cast<int>(utf8_string.size()), utf16_string.data(),
      target_length);
  if (converted_length == 0) {
    return std::wstring();
  }
  return utf16_string;
}

std::string StringArgument(
    const flutter::EncodableMap& arguments,
    const char* key) {
  auto iterator = arguments.find(flutter::EncodableValue(std::string(key)));
  if (iterator == arguments.end()) {
    return std::string();
  }
  if (const auto* value = std::get_if<std::string>(&iterator->second)) {
    return *value;
  }
  return std::string();
}

COLORREF ColorArgument(
    const flutter::EncodableMap& arguments,
    const char* key,
    COLORREF fallback) {
  std::string value = StringArgument(arguments, key);
  if (value.size() != 7 || value[0] != '#') {
    return fallback;
  }

  int red = 0;
  int green = 0;
  int blue = 0;
  if (sscanf_s(value.c_str() + 1, "%02x%02x%02x", &red, &green, &blue) != 3) {
    return fallback;
  }
  return RGB(red, green, blue);
}

bool BoolArgument(
    const flutter::EncodableMap& arguments,
    const char* key,
    bool fallback) {
  auto iterator = arguments.find(flutter::EncodableValue(std::string(key)));
  if (iterator == arguments.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<bool>(&iterator->second)) {
    return *value;
  }
  return fallback;
}

int IntArgument(
    const flutter::EncodableMap& arguments,
    const char* key,
    int fallback) {
  auto iterator = arguments.find(flutter::EncodableValue(std::string(key)));
  if (iterator == arguments.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return static_cast<int>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<int>(*value);
  }
  if (const auto* value = std::get_if<double>(&iterator->second)) {
    return static_cast<int>(*value);
  }
  return fallback;
}

double DoubleArgument(
    const flutter::EncodableMap& arguments,
    const char* key,
    double fallback) {
  auto iterator = arguments.find(flutter::EncodableValue(std::string(key)));
  if (iterator == arguments.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<double>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return static_cast<double>(*value);
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<double>(*value);
  }
  return fallback;
}

std::vector<std::string> StringListArgument(
    const flutter::EncodableMap& arguments,
    const char* key) {
  std::vector<std::string> values;
  auto iterator = arguments.find(flutter::EncodableValue(std::string(key)));
  if (iterator == arguments.end()) {
    return values;
  }
  if (const auto* list = std::get_if<flutter::EncodableList>(&iterator->second)) {
    for (const auto& item : *list) {
      if (const auto* value = std::get_if<std::string>(&item)) {
        values.push_back(*value);
      }
    }
  }
  return values;
}

std::vector<RoomAvatarPartState> AvatarPartsArgument(
    const flutter::EncodableMap& arguments) {
  std::vector<RoomAvatarPartState> avatars;
  auto iterator =
      arguments.find(flutter::EncodableValue(std::string("avatarParts")));
  if (iterator == arguments.end()) {
    return avatars;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&iterator->second);
  if (!list) {
    return avatars;
  }
  for (const auto& item : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&item);
    if (!map) {
      continue;
    }
    RoomAvatarPartState avatar;
    avatar.color = ColorArgument(*map, "color", RGB(166, 198, 238));
    avatar.image_url = StringArgument(*map, "imageUrl");
    avatars.push_back(avatar);
    if (avatars.size() >= 4) {
      break;
    }
  }
  return avatars;
}

std::string HexFromColor(COLORREF color) {
  char buffer[8];
  sprintf_s(buffer, "#%02X%02X%02X", GetRValue(color), GetGValue(color),
            GetBValue(color));
  return std::string(buffer);
}

void EnsureGdiplus() {
  if (g_gdiplus_token != 0) {
    return;
  }
  Gdiplus::GdiplusStartupInput input;
  if (Gdiplus::GdiplusStartup(&g_gdiplus_token, &input, nullptr) !=
      Gdiplus::Ok) {
    g_gdiplus_token = 0;
  }
}

void ShutdownGdiplus() {
  if (g_gdiplus_token == 0) {
    return;
  }
  Gdiplus::GdiplusShutdown(g_gdiplus_token);
  g_gdiplus_token = 0;
}

bool EnsureMediaFoundation() {
  if (g_media_foundation_attempted) {
    return g_media_foundation_started;
  }
  g_media_foundation_attempted = true;
  HRESULT co_result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(co_result) && co_result != RPC_E_CHANGED_MODE) {
    return false;
  }
  g_media_foundation_started = SUCCEEDED(MFStartup(MF_VERSION));
  return g_media_foundation_started;
}

void ShutdownMediaFoundation() {
  if (!g_media_foundation_started) {
    return;
  }
  MFShutdown();
  g_media_foundation_started = false;
}

bool EnsureOleInitialized() {
  if (g_ole_initialized) {
    return true;
  }
  HRESULT result = OleInitialize(nullptr);
  if (SUCCEEDED(result)) {
    g_ole_initialized = true;
    return true;
  }
  return false;
}

void ShutdownOle() {
  if (!g_ole_initialized) {
    return;
  }
  OleUninitialize();
  g_ole_initialized = false;
}

std::vector<std::string> FilePathsFromDataObject(IDataObject* data_object) {
  std::vector<std::string> paths;
  if (!data_object) {
    return paths;
  }
  FORMATETC format{};
  format.cfFormat = CF_HDROP;
  format.dwAspect = DVASPECT_CONTENT;
  format.lindex = -1;
  format.tymed = TYMED_HGLOBAL;
  if (FAILED(data_object->QueryGetData(&format))) {
    return paths;
  }

  STGMEDIUM medium{};
  if (FAILED(data_object->GetData(&format, &medium))) {
    return paths;
  }
  HDROP drop = reinterpret_cast<HDROP>(medium.hGlobal);
  UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT index = 0; index < count; ++index) {
    UINT length = DragQueryFileW(drop, index, nullptr, 0);
    if (length == 0) {
      continue;
    }
    std::wstring path(length + 1, L'\0');
    DragQueryFileW(drop, index, path.data(), length + 1);
    path.resize(length);
    std::string utf8 = Utf8FromUtf16(path.c_str());
    if (!utf8.empty()) {
      paths.push_back(utf8);
    }
  }
  ReleaseStgMedium(&medium);
  return paths;
}

void InvokeFileDragState(
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    bool active) {
  if (!channel) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("active")] =
      flutter::EncodableValue(active);
  channel->InvokeMethod("fileDragState",
                        std::make_unique<flutter::EncodableValue>(arguments));
}

void InvokeDroppedFiles(
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const std::vector<std::string>& paths) {
  if (!channel || paths.empty()) {
    return;
  }
  flutter::EncodableList list;
  for (const auto& path : paths) {
    list.push_back(flutter::EncodableValue(path));
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("paths")] = flutter::EncodableValue(list);
  channel->InvokeMethod("fileDrop",
                        std::make_unique<flutter::EncodableValue>(arguments));
}

class FileDropTarget final : public IDropTarget {
 public:
  explicit FileDropTarget(
      flutter::MethodChannel<flutter::EncodableValue>* channel)
      : channel_(channel) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (!object) {
      return E_POINTER;
    }
    if (iid == IID_IUnknown || iid == IID_IDropTarget) {
      *object = static_cast<IDropTarget*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override { return ++ref_count_; }

  ULONG STDMETHODCALLTYPE Release() override {
    ULONG count = --ref_count_;
    if (count == 0) {
      delete this;
    }
    return count;
  }

  HRESULT STDMETHODCALLTYPE DragEnter(IDataObject* data_object,
                                      DWORD,
                                      POINTL,
                                      DWORD* effect) override {
    active_ = !FilePathsFromDataObject(data_object).empty();
    if (effect) {
      *effect = active_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    }
    if (active_) {
      InvokeFileDragState(channel_, true);
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragOver(DWORD, POINTL, DWORD* effect) override {
    if (effect) {
      *effect = active_ ? DROPEFFECT_COPY : DROPEFFECT_NONE;
    }
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE DragLeave() override {
    if (active_) {
      InvokeFileDragState(channel_, false);
    }
    active_ = false;
    return S_OK;
  }

  HRESULT STDMETHODCALLTYPE Drop(IDataObject* data_object,
                                 DWORD,
                                 POINTL,
                                 DWORD* effect) override {
    std::vector<std::string> paths = FilePathsFromDataObject(data_object);
    if (effect) {
      *effect = paths.empty() ? DROPEFFECT_NONE : DROPEFFECT_COPY;
    }
    if (active_) {
      InvokeFileDragState(channel_, false);
    }
    active_ = false;
    InvokeDroppedFiles(channel_, paths);
    return S_OK;
  }

 private:
  std::atomic<ULONG> ref_count_{1};
  flutter::MethodChannel<flutter::EncodableValue>* channel_ = nullptr;
  bool active_ = false;
};

bool RegisterFileDropTarget(
    HWND window,
    flutter::MethodChannel<flutter::EncodableValue>* channel) {
  if (!window || !channel || !EnsureOleInitialized()) {
    return false;
  }
  auto* target = new FileDropTarget(channel);
  HRESULT result = RegisterDragDrop(window, target);
  target->Release();
  return SUCCEEDED(result);
}

HFONT CreateUiFont(int point_size, int weight) {
  HDC screen = GetDC(nullptr);
  int height = -MulDiv(point_size, GetDeviceCaps(screen, LOGPIXELSY), 72);
  ReleaseDC(nullptr, screen);
  return CreateFontW(height, 0, 0, 0, weight, FALSE, FALSE, FALSE,
                     DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                     CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
}

void DrawTextBlock(HDC hdc,
                   const std::wstring& text,
                   RECT rect,
                   HFONT font,
                   COLORREF color,
                   UINT format) {
  HGDIOBJ old_font = SelectObject(hdc, font);
  SetBkMode(hdc, TRANSPARENT);
  SetTextColor(hdc, color);
  DrawTextW(hdc, text.c_str(), -1, &rect, format);
  SelectObject(hdc, old_font);
}

void DrawBellIcon(HDC hdc, int x, int y) {
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(182, 182, 182));
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  HGDIOBJ old_brush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
  Arc(hdc, x, y + 3, x + 10, y + 15, x + 2, y + 12, x + 8, y + 12);
  MoveToEx(hdc, x + 2, y + 12, nullptr);
  LineTo(hdc, x + 8, y + 12);
  MoveToEx(hdc, x + 5, y + 15, nullptr);
  LineTo(hdc, x + 5, y + 16);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(pen);
}

RECT SendButtonRect() {
  return RECT{kNotificationWidth - 88, 98, kNotificationWidth - 16, 130};
}

bool HasReplyContent(NotificationState* state) {
  if (!state || !state->edit) {
    return false;
  }
  int length = GetWindowTextLengthW(state->edit);
  if (length <= 0) {
    return false;
  }

  std::wstring text(length + 1, L'\0');
  GetWindowTextW(state->edit, text.data(), length + 1);
  for (wchar_t character : text) {
    if (character != L'\0' && character != L' ' && character != L'\t' &&
        character != L'\r' && character != L'\n') {
      return true;
    }
  }
  return false;
}

void DrawSendButton(HDC hdc, NotificationState* state, HFONT font) {
  RECT button_rect = SendButtonRect();
  bool enabled = HasReplyContent(state);
  COLORREF fill = enabled ? RGB(255, 223, 0) : RGB(244, 244, 244);
  COLORREF text = enabled ? RGB(0, 0, 0) : RGB(184, 184, 184);

  HBRUSH brush = CreateSolidBrush(fill);
  HPEN pen = CreatePen(PS_SOLID, 1, fill);
  HGDIOBJ old_brush = SelectObject(hdc, brush);
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  RoundRect(hdc, button_rect.left, button_rect.top, button_rect.right,
            button_rect.bottom, 8, 8);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(brush);
  DeleteObject(pen);

  RECT text_rect{button_rect.left + 11, button_rect.top, button_rect.right - 23,
                 button_rect.bottom};
  DrawTextBlock(hdc, L"\xC804\xC1A1", text_rect, font, text,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);

  HPEN arrow_pen = CreatePen(PS_SOLID, 1, text);
  old_pen = SelectObject(hdc, arrow_pen);
  int middle_y = button_rect.top + ((button_rect.bottom - button_rect.top) / 2);
  int arrow_x = button_rect.right - 16;
  MoveToEx(hdc, arrow_x - 4, middle_y - 2, nullptr);
  LineTo(hdc, arrow_x, middle_y + 2);
  LineTo(hdc, arrow_x + 4, middle_y - 2);
  SelectObject(hdc, old_pen);
  DeleteObject(arrow_pen);
}

void DrawNotification(NotificationState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);

  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  HPEN border_pen = CreatePen(PS_SOLID, 1, RGB(214, 214, 214));
  HGDIOBJ old_pen = SelectObject(hdc, border_pen);
  HGDIOBJ old_brush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
  Rectangle(hdc, 0, 0, kNotificationWidth, kNotificationHeight);

  HPEN line_pen = CreatePen(PS_SOLID, 1, RGB(238, 238, 238));
  SelectObject(hdc, line_pen);
  MoveToEx(hdc, 0, 94, nullptr);
  LineTo(hdc, kNotificationWidth, 94);
  DeleteObject(border_pen);

  HFONT app_font = CreateUiFont(9, FW_NORMAL);
  HFONT name_font = CreateUiFont(10, FW_NORMAL);
  HFONT body_font = CreateUiFont(9, FW_NORMAL);
  HFONT avatar_font = CreateUiFont(10, FW_BOLD);
  HFONT button_font = CreateUiFont(9, FW_NORMAL);

  RECT app_rect{16, 8, kNotificationWidth - 72, 25};
  std::wstring title = state->room_title.empty()
      ? L"\xC571"
      : state->room_title;
  DrawTextBlock(hdc, title, app_rect, app_font, RGB(0, 0, 0),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  DrawBellIcon(hdc, kNotificationWidth - 42, 8);

  HPEN close_pen = CreatePen(PS_SOLID, 1, RGB(172, 172, 172));
  SelectObject(hdc, close_pen);
  MoveToEx(hdc, kNotificationWidth - 20, 9, nullptr);
  LineTo(hdc, kNotificationWidth - 12, 17);
  MoveToEx(hdc, kNotificationWidth - 12, 9, nullptr);
  LineTo(hdc, kNotificationWidth - 20, 17);
  DeleteObject(close_pen);

  EnsureGdiplus();
  if (g_gdiplus_token != 0) {
    Gdiplus::Graphics graphics(hdc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);
    Gdiplus::SolidBrush avatar_fill(Gdiplus::Color(
        255, GetRValue(state->avatar_color), GetGValue(state->avatar_color),
        GetBValue(state->avatar_color)));
    graphics.FillEllipse(&avatar_fill, 18.0f, 32.0f, 36.0f, 36.0f);
  } else {
    HBRUSH avatar_brush = CreateSolidBrush(state->avatar_color);
    HPEN avatar_pen = CreatePen(PS_SOLID, 1, state->avatar_color);
    HGDIOBJ avatar_old_brush = SelectObject(hdc, avatar_brush);
    HGDIOBJ avatar_old_pen = SelectObject(hdc, avatar_pen);
    Ellipse(hdc, 18, 32, 54, 68);
    SelectObject(hdc, avatar_old_brush);
    SelectObject(hdc, avatar_old_pen);
    DeleteObject(avatar_brush);
    DeleteObject(avatar_pen);
  }

  std::wstring initial = state->sender_nickname.empty()
      ? L"?"
      : state->sender_nickname.substr(0, 1);
  RECT initial_rect{18, 32, 54, 68};
  DrawTextBlock(hdc, initial, initial_rect, avatar_font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  RECT name_rect{64, 33, kNotificationWidth - 55, 51};
  DrawTextBlock(hdc, state->sender_nickname, name_rect, name_font,
                RGB(0, 0, 0), DT_LEFT | DT_VCENTER | DT_SINGLELINE |
                                  DT_END_ELLIPSIS);
  RECT body_rect{64, 53, kNotificationWidth - 20, 76};
  DrawTextBlock(hdc, state->body, body_rect, body_font, RGB(118, 118, 118),
                DT_LEFT | DT_TOP | DT_SINGLELINE | DT_END_ELLIPSIS);
  DrawSendButton(hdc, state, button_font);

  DeleteObject(app_font);
  DeleteObject(name_font);
  DeleteObject(body_font);
  DeleteObject(avatar_font);
  DeleteObject(button_font);

  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(line_pen);
  EndPaint(hwnd, &paint);
}

void ResizeWindowToLogicalWidth(HWND window, int logical_width) {
  if (IsZoomed(window)) {
    ShowWindow(window, SW_RESTORE);
  }

  RECT rect;
  GetWindowRect(window, &rect);
  UINT dpi = GetDpiForWindow(window);
  int width = MulDiv(logical_width, dpi, 96);
  int height = rect.bottom - rect.top;

  SetWindowPos(window, nullptr, rect.left, rect.top, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void ResizeWindowToLogicalSize(HWND window, int logical_width, int logical_height) {
  if (IsZoomed(window)) {
    ShowWindow(window, SW_RESTORE);
  }

  RECT rect;
  GetWindowRect(window, &rect);
  UINT dpi = GetDpiForWindow(window);
  int width = MulDiv(logical_width, dpi, 96);
  int height = MulDiv(logical_height, dpi, 96);

  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (GetMonitorInfo(monitor, &monitor_info)) {
    const RECT work = monitor_info.rcWork;
    const int work_width = work.right - work.left;
    const int work_height = work.bottom - work.top;
    width = std::min(width, work_width);
    height = std::min(height, work_height);
    rect.left = std::clamp(rect.left, work.left, work.right - width);
    rect.top = std::clamp(rect.top, work.top, work.bottom - height);
  }

  SetWindowPos(window, nullptr, rect.left, rect.top, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE);
}

void PositionQuickAvaAiWindow(HWND window) {
  if (!window) {
    return;
  }
  if (IsZoomed(window)) {
    ShowWindow(window, SW_RESTORE);
  }

  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return;
  }

  const UINT dpi = GetDpiForWindow(window);
  const int margin = MulDiv(16, dpi, 96);
  int width = MulDiv(kQuickAvaAiWidth, dpi, 96);
  int height = MulDiv(kQuickAvaAiHeight, dpi, 96);
  const RECT work = monitor_info.rcWork;
  const int work_width = work.right - work.left;
  const int work_height = work.bottom - work.top;
  width = std::min(width, std::max(320, work_width - (margin * 2)));
  height = std::min(height, std::max(420, work_height - (margin * 2)));
  const int x = work.right - width - margin;
  const int y = work.bottom - height - margin;

  SetWindowPos(window, HWND_TOPMOST, x, y, width, height,
               SWP_NOACTIVATE | SWP_HIDEWINDOW);
}

void StorePreAzoomWindowPlacement(HWND window) {
  if (!window || g_has_pre_azoom_window_placement) {
    return;
  }

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(window, &placement)) {
    return;
  }

  g_pre_azoom_window_placement = placement;
  g_has_pre_azoom_window_placement = true;
}

void RestorePreAzoomWindowPlacement(HWND window) {
  if (!window) {
    return;
  }

  if (g_azoom_fullscreen) {
    SetWindowLongPtr(window, GWL_STYLE, g_pre_azoom_fullscreen_style);
    SetWindowPlacement(window, &g_pre_azoom_fullscreen_placement);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
    g_azoom_fullscreen = false;
  }

  if (!g_has_pre_azoom_window_placement) {
    ResizeWindowToLogicalSize(window, kCompactMessengerWidth,
                              kCompactMessengerHeight);
    return;
  }

  WINDOWPLACEMENT placement = g_pre_azoom_window_placement;
  placement.length = sizeof(WINDOWPLACEMENT);
  SetWindowPlacement(window, &placement);
  g_has_pre_azoom_window_placement = false;
}

void SetAzoomFullscreen(HWND window, bool fullscreen) {
  if (!window || g_azoom_fullscreen == fullscreen) {
    return;
  }

  if (fullscreen) {
    g_pre_azoom_fullscreen_style =
        static_cast<DWORD>(GetWindowLongPtr(window, GWL_STYLE));
    g_pre_azoom_fullscreen_placement.length = sizeof(WINDOWPLACEMENT);
    GetWindowPlacement(window, &g_pre_azoom_fullscreen_placement);

    HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    if (!GetMonitorInfo(monitor, &monitor_info)) {
      return;
    }

    SetWindowLongPtr(window, GWL_STYLE, WS_POPUP | WS_VISIBLE);
    const RECT rect = monitor_info.rcMonitor;
    SetWindowPos(window, HWND_TOP, rect.left, rect.top,
                 rect.right - rect.left, rect.bottom - rect.top,
                 SWP_NOACTIVATE | SWP_FRAMECHANGED);
    g_azoom_fullscreen = true;
    return;
  }

  SetWindowLongPtr(window, GWL_STYLE, g_pre_azoom_fullscreen_style);
  SetWindowPlacement(window, &g_pre_azoom_fullscreen_placement);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
  g_azoom_fullscreen = false;
}

void SendNotificationReply(NotificationState* state) {
  if (!state || !state->edit || !state->channel) {
    return;
  }

  int length = GetWindowTextLengthW(state->edit);
  if (length <= 0) {
    return;
  }
  std::wstring text(length + 1, L'\0');
  GetWindowTextW(state->edit, text.data(), length + 1);
  std::string content = Utf8FromUtf16(text.c_str());
  if (content.empty()) {
    return;
  }

  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("roomId")] =
      flutter::EncodableValue(state->room_id);
  arguments[flutter::EncodableValue("content")] =
      flutter::EncodableValue(content);
  state->channel->InvokeMethod(
      "notificationReply",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void OpenNotificationRoom(NotificationState* state) {
  if (!state || !state->channel || state->room_id.empty()) {
    return;
  }

  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue("openRoom");
  arguments[flutter::EncodableValue("roomId")] =
      flutter::EncodableValue(state->room_id);
  state->channel->InvokeMethod(
      "floatingAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

LRESULT CALLBACK NotificationWndProc(HWND hwnd,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam) {
  auto* state =
      reinterpret_cast<NotificationState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<NotificationState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_CREATE:
      SetTimer(hwnd, kNotificationAutoCloseTimer, 3000, nullptr);
      return 0;
    case WM_MOUSEMOVE:
    case WM_SETFOCUS:
      KillTimer(hwnd, kNotificationAutoCloseTimer);
      return 0;
    case WM_LBUTTONDOWN: {
      KillTimer(hwnd, kNotificationAutoCloseTimer);
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (x >= kNotificationWidth - 30 && y <= 28) {
        AnimateWindow(hwnd, 140, AW_HIDE | AW_SLIDE | AW_VER_POSITIVE);
        DestroyWindow(hwnd);
        return 0;
      }
      RECT send_button = SendButtonRect();
      POINT point{x, y};
      if (PtInRect(&send_button, point)) {
        if (HasReplyContent(state)) {
          SendNotificationReply(state);
          AnimateWindow(hwnd, 140, AW_HIDE | AW_SLIDE | AW_VER_POSITIVE);
          DestroyWindow(hwnd);
        } else if (state && state->edit) {
          SetFocus(state->edit);
        }
        return 0;
      }
      RECT content_rect{0, 0, kNotificationWidth, 94};
      if (PtInRect(&content_rect, point)) {
        OpenNotificationRoom(state);
        AnimateWindow(hwnd, 140, AW_HIDE | AW_SLIDE | AW_VER_POSITIVE);
        DestroyWindow(hwnd);
        return 0;
      }
      return 0;
    }
    case WM_PAINT:
      if (state) {
        DrawNotification(state, hwnd);
        return 0;
      }
      break;
    case WM_COMMAND:
      if (LOWORD(wparam) == kNotificationEditId) {
        KillTimer(hwnd, kNotificationAutoCloseTimer);
        RECT send_button = SendButtonRect();
        InvalidateRect(hwnd, &send_button, TRUE);
        return 0;
      }
      break;
    case WM_TIMER:
      if (wparam == kNotificationAutoCloseTimer) {
        AnimateWindow(hwnd, 160, AW_HIDE | AW_SLIDE | AW_VER_POSITIVE);
        DestroyWindow(hwnd);
        return 0;
      }
      break;
    case WM_DESTROY:
      if (g_active_notification == hwnd) {
        g_active_notification = nullptr;
      }
      if (state && state->input_font) {
        DeleteObject(state->input_font);
      }
      delete state;
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

int FloatingWidth(const ChatFloatingState* state) {
  return state && state->collapsed ? kChatFloatingCollapsedWidth
                                   : kChatFloatingExpandedWidth;
}

void DrawSmallMutedIcon(HDC hdc, int x, int y) {
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(112, 112, 112));
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  HGDIOBJ old_brush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
  Arc(hdc, x, y + 2, x + 10, y + 14, x + 2, y + 11, x + 8, y + 11);
  MoveToEx(hdc, x + 2, y + 11, nullptr);
  LineTo(hdc, x + 8, y + 11);
  MoveToEx(hdc, x + 1, y + 15, nullptr);
  LineTo(hdc, x + 11, y + 1);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(pen);
}

void DrawFloatingAvatar(HDC hdc, ChatFloatingState* state, int x, int y) {
  if (!state) {
    return;
  }
  if (state->hide_avatar) {
    HBRUSH brush = CreateSolidBrush(RGB(64, 33, 37));
    HGDIOBJ old_brush = SelectObject(hdc, brush);
    HPEN pen = CreatePen(PS_SOLID, 1, RGB(64, 33, 37));
    HGDIOBJ old_pen = SelectObject(hdc, pen);
    RoundRect(hdc, x, y + 4, x + 17, y + 16, 5, 5);
    POINT tail[3] = {{x + 5, y + 15}, {x + 3, y + 20}, {x + 10, y + 15}};
    Polygon(hdc, tail, 3);
    SelectObject(hdc, old_pen);
    SelectObject(hdc, old_brush);
    DeleteObject(pen);
    DeleteObject(brush);
    return;
  }

  if (state->is_group) {
    COLORREF colors[4] = {
        state->avatar_color,
        RGB(139, 190, 204),
        RGB(166, 198, 238),
        RGB(221, 232, 165),
    };
    for (int i = 0; i < 4; i++) {
      HBRUSH brush = CreateSolidBrush(colors[i]);
      HPEN pen = CreatePen(PS_SOLID, 1, RGB(235, 235, 235));
      HGDIOBJ old_brush = SelectObject(hdc, brush);
      HGDIOBJ old_pen = SelectObject(hdc, pen);
      int left = x + ((i % 2) * 10);
      int top = y + ((i / 2) * 10);
      Ellipse(hdc, left, top, left + 9, top + 9);
      SelectObject(hdc, old_pen);
      SelectObject(hdc, old_brush);
      DeleteObject(pen);
      DeleteObject(brush);
    }
    return;
  }

  HBRUSH brush = CreateSolidBrush(state->avatar_color);
  HGDIOBJ old_brush = SelectObject(hdc, brush);
  HPEN pen = CreatePen(PS_SOLID, 1, state->avatar_color);
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  Ellipse(hdc, x, y, x + 22, y + 22);
  SelectObject(hdc, old_pen);
  SelectObject(hdc, old_brush);
  DeleteObject(pen);
  DeleteObject(brush);

  HFONT font = CreateUiFont(9, FW_BOLD);
  RECT rect{x, y, x + 22, y + 22};
  DrawTextBlock(hdc, L"\x25CF", rect, font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DeleteObject(font);
}

void DrawFloatingUnreadBadge(HDC hdc, int right, int top, int count) {
  if (count <= 0) {
    return;
  }
  std::wstring label = count > 99 ? L"99+" : std::to_wstring(count);
  int width = count > 9 ? 24 : 18;
  RECT rect{right - width, top, right, top + 18};
  HBRUSH brush = CreateSolidBrush(RGB(255, 76, 47));
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(255, 76, 47));
  HGDIOBJ old_brush = SelectObject(hdc, brush);
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, 18, 18);
  SelectObject(hdc, old_pen);
  SelectObject(hdc, old_brush);
  DeleteObject(pen);
  DeleteObject(brush);

  HFONT font = CreateUiFont(8, FW_BOLD);
  DrawTextBlock(hdc, label, rect, font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DeleteObject(font);
}

void DrawChatFloating(ChatFloatingState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  int width = client.right - client.left;

  HBRUSH background = CreateSolidBrush(RGB(214, 214, 214));
  FillRect(hdc, &client, background);
  DeleteObject(background);

  HPEN border = CreatePen(PS_SOLID, 1, RGB(156, 156, 156));
  HGDIOBJ old_pen = SelectObject(hdc, border);
  HGDIOBJ old_brush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
  Rectangle(hdc, 0, 0, width, kChatFloatingHeight);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(border);

  DrawFloatingAvatar(hdc, state, 10, 9);
  if (state->collapsed) {
    DrawFloatingUnreadBadge(hdc, width - 3, 3, state->unread_count);
    EndPaint(hwnd, &paint);
    return;
  }

  int text_left = state->hide_avatar ? 40 : 38;
  int text_right = width - (state->unread_count > 0 ? 34 : 12);
  if (state->is_muted) {
    text_right -= 18;
  }

  HFONT title_font = CreateUiFont(9, FW_NORMAL);
  RECT title_rect{text_left, 0, text_right, kChatFloatingHeight};
  DrawTextBlock(hdc, state->title, title_rect, title_font, RGB(0, 0, 0),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  DeleteObject(title_font);

  if (state->is_muted) {
    DrawSmallMutedIcon(hdc, text_right + 5, 12);
  }
  DrawFloatingUnreadBadge(hdc, width - 7, 10, state->unread_count);
  EndPaint(hwnd, &paint);
}

void InvokeFloatingAction(ChatFloatingState* state, const std::string& action) {
  if (!state || !state->channel) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(action);
  arguments[flutter::EncodableValue("roomId")] =
      flutter::EncodableValue(state->room_id);
  state->channel->InvokeMethod(
      "floatingAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void ResizeFloating(HWND hwnd, ChatFloatingState* state) {
  RECT rect{};
  GetWindowRect(hwnd, &rect);
  SetWindowPos(hwnd, HWND_TOPMOST, rect.left, rect.top, FloatingWidth(state),
               kChatFloatingHeight, SWP_NOACTIVATE);
  InvalidateRect(hwnd, nullptr, TRUE);
}

void CloseAllChatFloatings() {
  std::vector<HWND> windows;
  for (const auto& item : g_chat_floatings) {
    if (item.second) {
      windows.push_back(item.second);
    }
  }
  for (HWND hwnd : windows) {
    DestroyWindow(hwnd);
  }
  g_chat_floatings.clear();
}

void ShowFloatingMenu(HWND hwnd, ChatFloatingState* state) {
  if (!state) {
    return;
  }

  HMENU menu = CreatePopupMenu();
  if (state->collapsed) {
    AppendMenuW(menu, MF_STRING, kFloatingMenuToggleFold,
                L"\xD50C\xB85C\xD305 \xD3BC\xCE58\xAE30");
  } else if (!state->hide_avatar) {
    AppendMenuW(menu, MF_STRING, kFloatingMenuToggleFold,
                L"\xD50C\xB85C\xD305 \xC811\xAE30");
  }

  if (!state->collapsed) {
    AppendMenuW(menu, MF_STRING, kFloatingMenuToggleAvatar,
                state->hide_avatar
                    ? L"\xD504\xB85C\xD544 \xC0AC\xC9C4 \xBCF4\xAE30"
                    : L"\xD504\xB85C\xD544 \xC0AC\xC9C4 \xC228\xAE30\xAE30");
  }

  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kFloatingMenuOpenRoom,
              L"\xCC44\xD305\xBC29 \xC5F4\xAE30");
  AppendMenuW(menu, MF_STRING, kFloatingMenuClose,
              L"\xC774 \xD50C\xB85C\xD305 \xB2EB\xAE30");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kFloatingMenuCloseAll,
              L"\xBAA8\xB4E0 \xD50C\xB85C\xD305 \xC228\xAE30\xAE30");

  POINT point{};
  GetCursorPos(&point);
  UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
      point.x, point.y, 0, hwnd, nullptr);
  DestroyMenu(menu);

  switch (command) {
    case kFloatingMenuToggleFold:
      state->collapsed = !state->collapsed;
      if (state->collapsed) {
        state->hide_avatar = false;
      }
      ResizeFloating(hwnd, state);
      break;
    case kFloatingMenuToggleAvatar:
      state->hide_avatar = !state->hide_avatar;
      if (state->hide_avatar) {
        state->collapsed = false;
      }
      ResizeFloating(hwnd, state);
      break;
    case kFloatingMenuOpenRoom:
      InvokeFloatingAction(state, "openRoom");
      break;
    case kFloatingMenuClose:
      DestroyWindow(hwnd);
      break;
    case kFloatingMenuCloseAll:
      CloseAllChatFloatings();
      break;
  }
}

LRESULT CALLBACK ChatFloatingWndProc(HWND hwnd,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam) {
  auto* state = reinterpret_cast<ChatFloatingState*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state =
          reinterpret_cast<ChatFloatingState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_LBUTTONDOWN:
      ReleaseCapture();
      SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      return 0;
    case WM_CONTEXTMENU:
      ShowFloatingMenu(hwnd, state);
      return 0;
    case WM_PAINT:
      if (state) {
        DrawChatFloating(state, hwnd);
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (state) {
        g_chat_floatings.erase(state->room_id);
        delete state;
      }
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

void RegisterChatFloatingClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kChatFloatingClassName;
  window_class.lpfnWndProc = ChatFloatingWndProc;
  RegisterClass(&window_class);
  registered = true;
}

POINT FloatingOriginForNew(int width) {
  RECT work_area{};
  SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  int index = static_cast<int>(g_chat_floatings.size());
  int x = work_area.left + 12 + index * (width + kChatFloatingMargin);
  if (x + width > work_area.right - 8) {
    x = work_area.left + 12;
  }
  int y = work_area.bottom - kChatFloatingHeight - 8;
  return POINT{x, y};
}

void FillFloatingState(ChatFloatingState* state,
                       flutter::MethodChannel<flutter::EncodableValue>* channel,
                       const flutter::EncodableMap& arguments) {
  state->room_id = StringArgument(arguments, "roomId");
  state->title = Utf16FromUtf8(StringArgument(arguments, "title"));
  state->avatar_color =
      ColorArgument(arguments, "avatarColor", RGB(122, 160, 106));
  state->is_group = BoolArgument(arguments, "isGroup", false);
  state->is_muted = BoolArgument(arguments, "isMuted", false);
  state->unread_count = std::max(0, IntArgument(arguments, "unreadCount", 0));
  state->channel = channel;
}

void ShowOrUpdateChatFloating(
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments,
    bool create_if_missing) {
  RegisterChatFloatingClass();
  std::string room_id = StringArgument(arguments, "roomId");
  if (room_id.empty()) {
    return;
  }

  auto iterator = g_chat_floatings.find(room_id);
  if (iterator != g_chat_floatings.end() && IsWindow(iterator->second)) {
    HWND hwnd = iterator->second;
    auto* state = reinterpret_cast<ChatFloatingState*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
    if (state) {
      FillFloatingState(state, channel, arguments);
      ResizeFloating(hwnd, state);
    }
    return;
  }

  if (!create_if_missing) {
    return;
  }

  auto* state = new ChatFloatingState();
  FillFloatingState(state, channel, arguments);
  int width = FloatingWidth(state);
  POINT origin = FloatingOriginForNew(width);
  HWND hwnd = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
      kChatFloatingClassName,
      L"AVA Chat Floating",
      WS_POPUP,
      origin.x,
      origin.y,
      width,
      kChatFloatingHeight,
      nullptr,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!hwnd) {
    delete state;
    return;
  }
  g_chat_floatings[room_id] = hwnd;
  ShowWindow(hwnd, SW_SHOWNOACTIVATE);
  SetWindowPos(hwnd, HWND_TOPMOST, origin.x, origin.y, width,
               kChatFloatingHeight, SWP_NOACTIVATE | SWP_SHOWWINDOW);
}

void CloseChatFloating(const std::string& room_id) {
  auto iterator = g_chat_floatings.find(room_id);
  if (iterator == g_chat_floatings.end()) {
    return;
  }
  HWND hwnd = iterator->second;
  if (hwnd && IsWindow(hwnd)) {
    DestroyWindow(hwnd);
  } else {
    g_chat_floatings.erase(iterator);
  }
}

void RegisterNotificationClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kNotificationClassName;
  window_class.lpfnWndProc = NotificationWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void ShowNativeChatNotification(
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const std::string& room_id,
    const std::string& room_title,
    const std::string& sender_name,
    const std::string& sender_nickname,
    COLORREF avatar_color,
    const std::string& body) {
  RegisterNotificationClass();
  if (g_active_notification) {
    DestroyWindow(g_active_notification);
    g_active_notification = nullptr;
  }

  RECT work_area{};
  SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  int x = work_area.right - kNotificationWidth;
  int y = work_area.bottom - kNotificationHeight;

  auto* state = new NotificationState();
  state->room_id = room_id;
  state->room_title = Utf16FromUtf8(room_title.empty() ? "AVA" : room_title);
  state->sender_name = Utf16FromUtf8(sender_name);
  state->sender_nickname = Utf16FromUtf8(
      sender_nickname.empty() ? sender_name : sender_nickname);
  state->body = Utf16FromUtf8(body);
  state->avatar_color = avatar_color;
  state->channel = channel;

  HWND window = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
      kNotificationClassName,
      L"AVA",
      WS_POPUP,
      x,
      y,
      kNotificationWidth,
      kNotificationHeight,
      nullptr,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }

  state->input_font = CreateUiFont(9, FW_NORMAL);
  state->edit = CreateWindowExW(
      0,
      L"EDIT",
      L"",
      WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
      16,
      104,
      kNotificationWidth - 104,
      22,
      window,
      reinterpret_cast<HMENU>(static_cast<INT_PTR>(kNotificationEditId)),
      GetModuleHandle(nullptr),
      nullptr);
  SendMessage(state->edit, WM_SETFONT,
              reinterpret_cast<WPARAM>(state->input_font), TRUE);
  SendMessageW(state->edit, EM_SETCUEBANNER, FALSE,
               reinterpret_cast<LPARAM>(L"\xBA54\xC2DC\xC9C0 \xC785\xB825"));

  g_active_notification = window;
  ShowWindow(window, SW_SHOWNOACTIVATE);
  AnimateWindow(window, 180, AW_SLIDE | AW_VER_NEGATIVE);
}

bool PointInRect(const RECT& rect, int x, int y) {
  POINT point{x, y};
  return PtInRect(&rect, point) == TRUE;
}

RECT CloseButtonRect(int width) {
  return RECT{width - 34, 10, width - 10, 34};
}

RECT ProfileBackgroundButtonRect() {
  return RECT{18, 18, 48, 48};
}

RECT ProfileBackgroundRect() {
  return RECT{0, 0, kProfilePopupNativeWidth,
              kProfilePopupNativeHeight - kProfilePopupFooterHeight};
}

void ApplyRoundedWindowRegion(HWND hwnd, int width, int height) {
  HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1,
                                   kProfileWindowCornerRadius,
                                   kProfileWindowCornerRadius);
  if (region && SetWindowRgn(hwnd, region, TRUE) == 0) {
    DeleteObject(region);
  }
}

RECT ProfileActionRect(int index) {
  const int left = 24;
  const int top = kProfilePopupNativeHeight - 56;
  const int half_width = (kProfilePopupNativeWidth - 48) / 2;
  return RECT{left + (half_width * index), top,
              left + (half_width * (index + 1)), top + 40};
}

RECT ProfileEditConfirmRect() {
  return RECT{148, kProfileEditNativeHeight - 56, 228,
              kProfileEditNativeHeight - 20};
}

RECT ProfileEditCancelRect() {
  return RECT{236, kProfileEditNativeHeight - 56, 316,
              kProfileEditNativeHeight - 20};
}

RECT ProfileEditCameraRect() {
  return RECT{196, 151, 222, 177};
}

void DrawCloseButton(HDC hdc, int width, COLORREF color = RGB(150, 150, 150)) {
  HPEN pen = CreatePen(PS_SOLID, 1, color);
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  MoveToEx(hdc, width - 27, 17, nullptr);
  LineTo(hdc, width - 17, 27);
  MoveToEx(hdc, width - 17, 17, nullptr);
  LineTo(hdc, width - 27, 27);
  SelectObject(hdc, old_pen);
  DeleteObject(pen);
}

void DrawFilledRoundRect(HDC hdc,
                         RECT rect,
                         int radius,
                         COLORREF fill,
                         COLORREF stroke) {
  HBRUSH brush = CreateSolidBrush(fill);
  HPEN pen = CreatePen(PS_SOLID, 1, stroke);
  HGDIOBJ old_brush = SelectObject(hdc, brush);
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, radius, radius);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(brush);
  DeleteObject(pen);
}

std::wstring DisplayName(const std::wstring& nickname,
                         const std::wstring& name) {
  return nickname.empty() ? name : nickname;
}

bool DrawImageAvatar(HDC hdc,
                     int x,
                     int y,
                     int size,
                     const std::string& avatar_image_url,
                     bool draw_border = true);

void DrawCircleAvatar(HDC hdc,
                      int x,
                      int y,
                      int size,
                      COLORREF avatar_color,
                      const std::wstring& nickname,
                      const std::wstring& name,
                      const std::string& avatar_image_url,
                      int font_size) {
  if (DrawImageAvatar(hdc, x, y, size, avatar_image_url)) {
    return;
  }

  EnsureGdiplus();
  if (g_gdiplus_token != 0) {
    Gdiplus::Graphics graphics(hdc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::SolidBrush fill(Gdiplus::Color(
        255, GetRValue(avatar_color), GetGValue(avatar_color),
        GetBValue(avatar_color)));
    graphics.FillEllipse(&fill, x, y, size, size);
  } else {
    HBRUSH brush = CreateSolidBrush(avatar_color);
    HPEN pen = CreatePen(PS_SOLID, 1, avatar_color);
    HGDIOBJ old_brush = SelectObject(hdc, brush);
    HGDIOBJ old_pen = SelectObject(hdc, pen);
    Ellipse(hdc, x, y, x + size, y + size);
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    DeleteObject(brush);
    DeleteObject(pen);
  }

  HFONT font = CreateUiFont(font_size, FW_BOLD);
  std::wstring initial = DisplayName(nickname, name);
  initial = initial.empty() ? L"?" : initial.substr(0, 1);
  RECT text_rect{x, y, x + size, y + size};
  DrawTextBlock(hdc, initial, text_rect, font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DeleteObject(font);
}

COLORREF NextProfileBackground(COLORREF color) {
  const COLORREF palette[] = {
      RGB(92, 128, 182), RGB(122, 160, 106), RGB(168, 136, 118),
      RGB(120, 146, 166), RGB(154, 126, 171), RGB(95, 95, 95),
  };
  const int count = static_cast<int>(sizeof(palette) / sizeof(palette[0]));
  for (int index = 0; index < count; ++index) {
    if (palette[index] == color) {
      return palette[(index + 1) % count];
    }
  }
  return palette[0];
}

std::string Base64Encode(const std::vector<unsigned char>& bytes) {
  static constexpr char table[] =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string output;
  output.reserve(((bytes.size() + 2) / 3) * 4);
  for (size_t index = 0; index < bytes.size(); index += 3) {
    unsigned int value = bytes[index] << 16;
    if (index + 1 < bytes.size()) {
      value |= bytes[index + 1] << 8;
    }
    if (index + 2 < bytes.size()) {
      value |= bytes[index + 2];
    }
    output.push_back(table[(value >> 18) & 0x3F]);
    output.push_back(table[(value >> 12) & 0x3F]);
    output.push_back(index + 1 < bytes.size() ? table[(value >> 6) & 0x3F]
                                               : '=');
    output.push_back(index + 2 < bytes.size() ? table[value & 0x3F] : '=');
  }
  return output;
}

int Base64Value(char character) {
  if (character >= 'A' && character <= 'Z') {
    return character - 'A';
  }
  if (character >= 'a' && character <= 'z') {
    return character - 'a' + 26;
  }
  if (character >= '0' && character <= '9') {
    return character - '0' + 52;
  }
  if (character == '+') {
    return 62;
  }
  if (character == '/') {
    return 63;
  }
  return -1;
}

std::vector<unsigned char> Base64Decode(const std::string& encoded) {
  std::vector<unsigned char> bytes;
  int value = 0;
  int bits = -8;
  for (char character : encoded) {
    if (character == '=') {
      break;
    }
    int decoded = Base64Value(character);
    if (decoded < 0) {
      continue;
    }
    value = (value << 6) | decoded;
    bits += 6;
    if (bits >= 0) {
      bytes.push_back(static_cast<unsigned char>((value >> bits) & 0xFF));
      bits -= 8;
    }
  }
  return bytes;
}

std::vector<unsigned char> ImageBytesFromDataUri(const std::string& data_uri) {
  if (data_uri.rfind("data:image/", 0) != 0) {
    return {};
  }
  size_t comma_index = data_uri.find(',');
  if (comma_index == std::string::npos) {
    return {};
  }
  return Base64Decode(data_uri.substr(comma_index + 1));
}

bool DrawDataUriImageCover(HDC hdc,
                           int x,
                           int y,
                           int width,
                           int height,
                           const std::string& image_url) {
  std::vector<unsigned char> bytes = ImageBytesFromDataUri(image_url);
  if (bytes.empty()) {
    return false;
  }

  EnsureGdiplus();
  if (g_gdiplus_token == 0) {
    return false;
  }

  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (!memory) {
    return false;
  }
  void* memory_data = GlobalLock(memory);
  if (!memory_data) {
    GlobalFree(memory);
    return false;
  }
  std::memcpy(memory_data, bytes.data(), bytes.size());
  GlobalUnlock(memory);

  IStream* stream = nullptr;
  if (CreateStreamOnHGlobal(memory, TRUE, &stream) != S_OK || !stream) {
    GlobalFree(memory);
    return false;
  }

  bool drawn = false;
  {
    Gdiplus::Image image(stream);
    if (image.GetLastStatus() == Gdiplus::Ok &&
        image.GetWidth() > 0 &&
        image.GetHeight() > 0) {
      double scale = std::max(
          static_cast<double>(width) / static_cast<double>(image.GetWidth()),
          static_cast<double>(height) / static_cast<double>(image.GetHeight()));
      int draw_width = static_cast<int>(image.GetWidth() * scale);
      int draw_height = static_cast<int>(image.GetHeight() * scale);
      int draw_x = x + ((width - draw_width) / 2);
      int draw_y = y + ((height - draw_height) / 2);

      Gdiplus::Graphics graphics(hdc);
      graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
      graphics.SetSmoothingMode(Gdiplus::SmoothingModeHighQuality);
      graphics.DrawImage(&image, draw_x, draw_y, draw_width, draw_height);
      drawn = true;
    }
  }

  stream->Release();
  return drawn;
}

bool DrawImageAvatar(HDC hdc,
                     int x,
                     int y,
                     int size,
                     const std::string& avatar_image_url,
                     bool draw_border) {
  std::vector<unsigned char> bytes = ImageBytesFromDataUri(avatar_image_url);
  if (bytes.empty()) {
    return false;
  }

  EnsureGdiplus();
  if (g_gdiplus_token == 0) {
    return false;
  }

  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
  if (!memory) {
    return false;
  }
  void* memory_data = GlobalLock(memory);
  if (!memory_data) {
    GlobalFree(memory);
    return false;
  }
  std::memcpy(memory_data, bytes.data(), bytes.size());
  GlobalUnlock(memory);

  IStream* stream = nullptr;
  if (CreateStreamOnHGlobal(memory, TRUE, &stream) != S_OK || !stream) {
    GlobalFree(memory);
    return false;
  }

  bool drawn = false;
  {
    Gdiplus::Image image(stream);
    if (image.GetLastStatus() == Gdiplus::Ok &&
        image.GetWidth() > 0 &&
        image.GetHeight() > 0) {
      double scale = std::max(
          static_cast<double>(size) / static_cast<double>(image.GetWidth()),
          static_cast<double>(size) / static_cast<double>(image.GetHeight()));
      int draw_width = static_cast<int>(image.GetWidth() * scale);
      int draw_height = static_cast<int>(image.GetHeight() * scale);
      int draw_x = x + ((size - draw_width) / 2);
      int draw_y = y + ((size - draw_height) / 2);
      Gdiplus::Graphics graphics(hdc);
      graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
      graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
      Gdiplus::GraphicsPath path;
      path.AddEllipse(x, y, size, size);
      graphics.SetClip(&path);
      graphics.DrawImage(&image, draw_x, draw_y, draw_width, draw_height);
      graphics.ResetClip();
      if (draw_border) {
        Gdiplus::Pen border(Gdiplus::Color(255, 255, 255, 255), 2);
        graphics.DrawEllipse(&border, x + 1, y + 1, size - 2, size - 2);
      }
      drawn = true;
    }
  }

  stream->Release();
  return drawn;
}

std::string MimeTypeForPath(const std::wstring& path) {
  size_t dot_index = path.find_last_of(L'.');
  if (dot_index == std::wstring::npos) {
    return "image/png";
  }
  std::wstring extension = path.substr(dot_index + 1);
  std::transform(extension.begin(), extension.end(), extension.begin(),
                 [](wchar_t character) {
                   return static_cast<wchar_t>(std::towlower(character));
                 });
  if (extension == L"jpg" || extension == L"jpeg") {
    return "image/jpeg";
  }
  if (extension == L"webp") {
    return "image/webp";
  }
  if (extension == L"bmp") {
    return "image/bmp";
  }
  return "image/png";
}

std::string DataUriForImagePath(const std::wstring& path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    return std::string();
  }
  file.seekg(0, std::ios::end);
  std::streamoff size = file.tellg();
  if (size <= 0 || size > 1024 * 1024) {
    return std::string();
  }
  file.seekg(0, std::ios::beg);
  std::vector<unsigned char> bytes(static_cast<size_t>(size));
  file.read(reinterpret_cast<char*>(bytes.data()),
            static_cast<std::streamsize>(size));
  if (!file) {
    return std::string();
  }
  return "data:" + MimeTypeForPath(path) + ";base64," + Base64Encode(bytes);
}

std::wstring OpenProfileImageFile(HWND owner) {
  wchar_t file_name[MAX_PATH] = {};
  OPENFILENAMEW open_file_name{};
  open_file_name.lStructSize = sizeof(open_file_name);
  open_file_name.hwndOwner = owner;
  open_file_name.lpstrFilter =
      L"Image Files\0*.png;*.jpg;*.jpeg;*.webp;*.bmp\0All Files\0*.*\0\0";
  open_file_name.lpstrFile = file_name;
  open_file_name.nMaxFile = MAX_PATH;
  open_file_name.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST |
                         OFN_NOCHANGEDIR | OFN_EXPLORER;
  if (GetOpenFileNameW(&open_file_name)) {
    return std::wstring(file_name);
  }
  return std::wstring();
}

void InvokeProfileAction(
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const std::string& action,
    const std::string& id,
    const std::string& email,
    flutter::EncodableMap extra = flutter::EncodableMap()) {
  if (!channel) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] = flutter::EncodableValue(action);
  arguments[flutter::EncodableValue("id")] = flutter::EncodableValue(id);
  arguments[flutter::EncodableValue("email")] = flutter::EncodableValue(email);
  for (const auto& entry : extra) {
    arguments[entry.first] = entry.second;
  }
  channel->InvokeMethod(
      "profilePopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void DrawProfilePopup(ProfilePopupState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);

  RECT client{};
  GetClientRect(hwnd, &client);
  if (!DrawDataUriImageCover(hdc, 0, 0, kProfilePopupNativeWidth,
                             kProfilePopupNativeHeight,
                             state->background_image_url)) {
    HBRUSH background = CreateSolidBrush(state->background_color);
    FillRect(hdc, &client, background);
    DeleteObject(background);
  }

  HBRUSH shadow = CreateSolidBrush(RGB(62, 62, 62));
  RECT footer{0, kProfilePopupNativeHeight - kProfilePopupFooterHeight,
              kProfilePopupNativeWidth, kProfilePopupNativeHeight};
  FillRect(hdc, &footer, shadow);
  DeleteObject(shadow);

  DrawCloseButton(hdc, kProfilePopupNativeWidth, RGB(245, 245, 245));

  if (state->is_self) {
    RECT background_button = ProfileBackgroundButtonRect();
    DrawFilledRoundRect(hdc, background_button, 30, RGB(255, 255, 255),
                        RGB(235, 235, 235));
    HFONT small_font = CreateUiFont(10, FW_BOLD);
    DrawTextBlock(hdc, L"\x25CB", background_button, small_font,
                  RGB(82, 82, 82), DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DeleteObject(small_font);
  }

  DrawCircleAvatar(hdc, 24, 335, 66, state->avatar_color, state->nickname,
                   state->name, state->avatar_image_url, 18);

  HFONT name_font = CreateUiFont(18, FW_BOLD);
  HFONT status_font = CreateUiFont(10, FW_NORMAL);
  RECT name_rect{24, 407, kProfilePopupNativeWidth - 24, 434};
  DrawTextBlock(hdc, DisplayName(state->nickname, state->name), name_rect,
                name_font, RGB(255, 255, 255),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  if (!state->is_self && !state->status_message.empty()) {
    RECT status_rect{24, 430, kProfilePopupNativeWidth - 42, 452};
    DrawTextBlock(hdc, state->status_message, status_rect, status_font,
                  RGB(245, 245, 245),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  }

  RECT button_frame{24, kProfilePopupNativeHeight - 56,
                    kProfilePopupNativeWidth - 24,
                    kProfilePopupNativeHeight - 16};
  DrawFilledRoundRect(hdc, button_frame, 10, RGB(92, 92, 92),
                      RGB(160, 160, 160));
  HPEN divider_pen = CreatePen(PS_SOLID, 1, RGB(148, 148, 148));
  HGDIOBJ old_pen = SelectObject(hdc, divider_pen);
  int middle = button_frame.left + ((button_frame.right - button_frame.left) / 2);
  MoveToEx(hdc, middle, button_frame.top + 8, nullptr);
  LineTo(hdc, middle, button_frame.bottom - 8);
  SelectObject(hdc, old_pen);
  DeleteObject(divider_pen);

  HFONT button_font = CreateUiFont(10, FW_BOLD);
  RECT first = ProfileActionRect(0);
  RECT second = ProfileActionRect(1);
  DrawTextBlock(hdc, state->is_self ? L"\xB098\xC640\xC758 \xCC44\xD305"
                                    : L"1:1 \xCC44\xD305",
                first, button_font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DrawTextBlock(hdc, state->is_self ? L"\xD504\xB85C\xD544 \xD3B8\xC9D1"
                                    : L"\xD1B5\xD654",
                second, button_font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  DeleteObject(name_font);
  DeleteObject(status_font);
  DeleteObject(button_font);
  EndPaint(hwnd, &paint);
}

void DrawProfileEdit(ProfileEditState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);

  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  DrawCloseButton(hdc, kProfileEditNativeWidth);

  HFONT title_font = CreateUiFont(13, FW_NORMAL);
  HFONT count_font = CreateUiFont(9, FW_NORMAL);
  HFONT button_font = CreateUiFont(10, FW_NORMAL);
  RECT title_rect{18, 32, kProfileEditNativeWidth - 40, 62};
  DrawTextBlock(hdc, L"\xAE30\xBCF8\xD504\xB85C\xD544 \xD3B8\xC9D1",
                title_rect, title_font, RGB(0, 0, 0),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);

  DrawCircleAvatar(hdc, 124, 92, 90, state->avatar_color, state->nickname,
                   state->name, state->avatar_image_url, 20);
  RECT camera = ProfileEditCameraRect();
  DrawFilledRoundRect(hdc, camera, 18, RGB(92, 92, 92), RGB(255, 255, 255));
  DrawTextBlock(hdc, L"\x25CF", camera, count_font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  HPEN line_pen = CreatePen(PS_SOLID, 1, RGB(224, 224, 224));
  HGDIOBJ old_pen = SelectObject(hdc, line_pen);
  MoveToEx(hdc, 18, 248, nullptr);
  LineTo(hdc, kProfileEditNativeWidth - 22, 248);
  MoveToEx(hdc, 18, 290, nullptr);
  LineTo(hdc, kProfileEditNativeWidth - 22, 290);
  SelectObject(hdc, old_pen);
  DeleteObject(line_pen);

  int nickname_length = state->nickname_edit
                            ? GetWindowTextLengthW(state->nickname_edit)
                            : static_cast<int>(state->nickname.size());
  int status_length = state->status_edit
                          ? GetWindowTextLengthW(state->status_edit)
                          : static_cast<int>(state->status_message.size());
  RECT nickname_count{kProfileEditNativeWidth - 72, 222,
                      kProfileEditNativeWidth - 22, 244};
  RECT status_count{kProfileEditNativeWidth - 72, 264,
                    kProfileEditNativeWidth - 22, 286};
  DrawTextBlock(hdc, std::to_wstring(nickname_length) + L"/20",
                nickname_count, count_font, RGB(88, 88, 88),
                DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
  DrawTextBlock(hdc, std::to_wstring(status_length) + L"/60", status_count,
                count_font, RGB(88, 88, 88),
                DT_RIGHT | DT_VCENTER | DT_SINGLELINE);

  bool can_confirm = nickname_length > 0;
  RECT confirm = ProfileEditConfirmRect();
  RECT cancel = ProfileEditCancelRect();
  DrawFilledRoundRect(hdc, confirm, 4,
                      can_confirm ? RGB(255, 223, 0) : RGB(244, 244, 244),
                      can_confirm ? RGB(255, 223, 0) : RGB(244, 244, 244));
  DrawFilledRoundRect(hdc, cancel, 4, RGB(255, 255, 255), RGB(220, 220, 220));
  DrawTextBlock(hdc, L"\xD655\xC778", confirm, button_font,
                can_confirm ? RGB(0, 0, 0) : RGB(180, 180, 180),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DrawTextBlock(hdc, L"\xCDE8\xC18C", cancel, button_font, RGB(0, 0, 0),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  DeleteObject(title_font);
  DeleteObject(count_font);
  DeleteObject(button_font);
  EndPaint(hwnd, &paint);
}

bool ProfileEditCanConfirm(ProfileEditState* state) {
  if (!state || !state->nickname_edit) {
    return false;
  }
  int length = GetWindowTextLengthW(state->nickname_edit);
  if (length <= 0) {
    return false;
  }
  std::wstring text(length + 1, L'\0');
  GetWindowTextW(state->nickname_edit, text.data(), length + 1);
  for (wchar_t character : text) {
    if (character != L'\0' && !std::iswspace(character)) {
      return true;
    }
  }
  return false;
}

std::string TextFromEdit(HWND edit) {
  if (!edit) {
    return std::string();
  }
  int length = GetWindowTextLengthW(edit);
  if (length <= 0) {
    return std::string();
  }
  std::wstring text(length + 1, L'\0');
  GetWindowTextW(edit, text.data(), length + 1);
  return Utf8FromUtf16(text.c_str());
}

void SubmitProfileEdit(ProfileEditState* state) {
  if (!state || !ProfileEditCanConfirm(state)) {
    return;
  }
  flutter::EncodableMap extra;
  extra[flutter::EncodableValue("nickname")] =
      flutter::EncodableValue(TextFromEdit(state->nickname_edit));
  extra[flutter::EncodableValue("statusMessage")] =
      flutter::EncodableValue(TextFromEdit(state->status_edit));
  if (!state->avatar_image_url.empty()) {
    extra[flutter::EncodableValue("avatarImageUrl")] =
        flutter::EncodableValue(state->avatar_image_url);
  }
  InvokeProfileAction(state->channel, "profileEditSubmitted", state->id,
                      state->email, extra);
}

void PickProfileBackgroundImage(ProfilePopupState* state, HWND hwnd) {
  if (!state || !state->is_self) {
    return;
  }
  std::wstring path = OpenProfileImageFile(hwnd);
  if (path.empty()) {
    return;
  }
  std::string data_uri = DataUriForImagePath(path);
  if (data_uri.empty()) {
    return;
  }

  state->background_image_url = data_uri;
  flutter::EncodableMap extra;
  extra[flutter::EncodableValue("backgroundImageUrl")] =
      flutter::EncodableValue(data_uri);
  InvokeProfileAction(state->channel, "backgroundChanged", state->id,
                      state->email, extra);
  InvalidateRect(hwnd, nullptr, TRUE);
}

LRESULT CALLBACK ProfilePopupWndProc(HWND hwnd,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam) {
  auto* state =
      reinterpret_cast<ProfilePopupState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<ProfilePopupState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_LBUTTONDOWN: {
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (PointInRect(CloseButtonRect(kProfilePopupNativeWidth), x, y)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (state && state->is_self &&
          PointInRect(ProfileBackgroundButtonRect(), x, y)) {
        PickProfileBackgroundImage(state, hwnd);
        return 0;
      }
      if (state && state->is_self &&
          PointInRect(ProfileBackgroundRect(), x, y)) {
        PickProfileBackgroundImage(state, hwnd);
        return 0;
      }
      if (state && PointInRect(ProfileActionRect(0), x, y)) {
        InvokeProfileAction(state->channel,
                            state->is_self ? "selfChat" : "directChat",
                            state->id, state->email);
        DestroyWindow(hwnd);
        return 0;
      }
      if (state && PointInRect(ProfileActionRect(1), x, y)) {
        if (state->is_self) {
          InvokeProfileAction(state->channel, "editProfile", state->id,
                              state->email);
          DestroyWindow(hwnd);
        }
        return 0;
      }
      ReleaseCapture();
      SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      return 0;
    }
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) {
        DestroyWindow(hwnd);
        return 0;
      }
      break;
    case WM_PAINT:
      if (state) {
        DrawProfilePopup(state, hwnd);
        return 0;
      }
      break;
    case WM_DESTROY:
      if (g_active_profile_popup == hwnd) {
        g_active_profile_popup = nullptr;
      }
      delete state;
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT CALLBACK ProfileEditWndProc(HWND hwnd,
                                     UINT message,
                                     WPARAM wparam,
                                     LPARAM lparam) {
  auto* state =
      reinterpret_cast<ProfileEditState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<ProfileEditState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_CREATE:
      if (state) {
        state->edit_font = CreateUiFont(11, FW_NORMAL);
        state->nickname_edit = CreateWindowExW(
            0, L"EDIT", state->nickname.c_str(),
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            18, 220, kProfileEditNativeWidth - 92, 25, hwnd,
            reinterpret_cast<HMENU>(
                static_cast<INT_PTR>(kProfileNicknameEditId)),
            GetModuleHandle(nullptr), nullptr);
        state->status_edit = CreateWindowExW(
            0, L"EDIT", state->status_message.c_str(),
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            18, 262, kProfileEditNativeWidth - 92, 25, hwnd,
            reinterpret_cast<HMENU>(
                static_cast<INT_PTR>(kProfileStatusEditId)),
            GetModuleHandle(nullptr), nullptr);
        SendMessage(state->nickname_edit, WM_SETFONT,
                    reinterpret_cast<WPARAM>(state->edit_font), TRUE);
        SendMessage(state->status_edit, WM_SETFONT,
                    reinterpret_cast<WPARAM>(state->edit_font), TRUE);
        SendMessage(state->nickname_edit, EM_SETLIMITTEXT, 20, 0);
        SendMessage(state->status_edit, EM_SETLIMITTEXT, 60, 0);
        SendMessageW(state->status_edit, EM_SETCUEBANNER, FALSE,
                     reinterpret_cast<LPARAM>(
                         L"\xC0C1\xD0DC\xBA54\xC2DC\xC9C0"));
      }
      return 0;
    case WM_COMMAND:
      if (LOWORD(wparam) == kProfileNicknameEditId ||
          LOWORD(wparam) == kProfileStatusEditId) {
        RECT update{0, 216, kProfileEditNativeWidth,
                    kProfileEditNativeHeight};
        InvalidateRect(hwnd, &update, TRUE);
        return 0;
      }
      break;
    case WM_LBUTTONDOWN: {
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (PointInRect(CloseButtonRect(kProfileEditNativeWidth), x, y) ||
          PointInRect(ProfileEditCancelRect(), x, y)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (state && PointInRect(ProfileEditCameraRect(), x, y)) {
        std::wstring path = OpenProfileImageFile(hwnd);
        if (!path.empty()) {
          std::string data_uri = DataUriForImagePath(path);
          if (!data_uri.empty()) {
            state->avatar_image_url = data_uri;
            InvalidateRect(hwnd, nullptr, TRUE);
          }
        }
        return 0;
      }
      if (state && PointInRect(ProfileEditConfirmRect(), x, y)) {
        SubmitProfileEdit(state);
        if (ProfileEditCanConfirm(state)) {
          DestroyWindow(hwnd);
        }
        return 0;
      }

      RECT nickname_rect{18, 220, kProfileEditNativeWidth - 72, 246};
      RECT status_rect{18, 262, kProfileEditNativeWidth - 72, 288};
      if (!PointInRect(nickname_rect, x, y) && !PointInRect(status_rect, x, y)) {
        ReleaseCapture();
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      }
      return 0;
    }
    case WM_KEYDOWN:
      if (wparam == VK_ESCAPE) {
        DestroyWindow(hwnd);
        return 0;
      }
      break;
    case WM_CTLCOLOREDIT: {
      HDC edit_dc = reinterpret_cast<HDC>(wparam);
      SetBkColor(edit_dc, RGB(255, 255, 255));
      SetTextColor(edit_dc, RGB(0, 0, 0));
      return reinterpret_cast<LRESULT>(GetStockObject(WHITE_BRUSH));
    }
    case WM_PAINT:
      if (state) {
        DrawProfileEdit(state, hwnd);
        return 0;
      }
      break;
    case WM_DESTROY:
      if (g_active_profile_edit_popup == hwnd) {
        g_active_profile_edit_popup = nullptr;
      }
      if (state && state->edit_font) {
        DeleteObject(state->edit_font);
      }
      delete state;
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }

  return DefWindowProc(hwnd, message, wparam, lparam);
}

RECT FolderConfirmRect() {
  return RECT{188, kFolderCreateNativeHeight - 56, 264,
              kFolderCreateNativeHeight - 19};
}

RECT FolderCancelRect() {
  return RECT{272, kFolderCreateNativeHeight - 56, 352,
              kFolderCreateNativeHeight - 19};
}

std::wstring FolderName(FolderCreateState* state) {
  if (!state || !state->name_edit) {
    return std::wstring();
  }
  int length = GetWindowTextLengthW(state->name_edit);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring text(length + 1, L'\0');
  GetWindowTextW(state->name_edit, text.data(), length + 1);
  text.resize(length);
  return text;
}

bool FolderCanConfirm(FolderCreateState* state) {
  std::wstring name = FolderName(state);
  return !name.empty() && name.size() <= 10;
}

bool FolderRoomSelected(FolderCreateState* state, const std::string& room_id) {
  if (!state) {
    return false;
  }
  return std::find(state->selected_room_ids.begin(),
                   state->selected_room_ids.end(),
                   room_id) != state->selected_room_ids.end();
}

bool StringListContains(const std::vector<std::string>& values,
                        const std::string& value) {
  return std::find(values.begin(), values.end(), value) != values.end();
}

Gdiplus::Color GdiColorFromColorRef(COLORREF color, BYTE alpha = 255) {
  return Gdiplus::Color(alpha, GetRValue(color), GetGValue(color),
                        GetBValue(color));
}

void DrawSmoothCircleFill(HDC hdc,
                          int x,
                          int y,
                          int size,
                          COLORREF fill,
                          std::optional<COLORREF> stroke = std::nullopt,
                          float stroke_width = 1.0f) {
  EnsureGdiplus();
  if (g_gdiplus_token == 0) {
    HBRUSH brush = CreateSolidBrush(fill);
    HPEN pen = CreatePen(PS_SOLID, 1, stroke.value_or(fill));
    HGDIOBJ old_brush = SelectObject(hdc, brush);
    HGDIOBJ old_pen = SelectObject(hdc, pen);
    Ellipse(hdc, x, y, x + size, y + size);
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    DeleteObject(brush);
    DeleteObject(pen);
    return;
  }
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  Gdiplus::SolidBrush brush(GdiColorFromColorRef(fill));
  graphics.FillEllipse(&brush, x, y, size, size);
  if (stroke.has_value()) {
    Gdiplus::Pen pen(GdiColorFromColorRef(*stroke), stroke_width);
    float inset = stroke_width / 2.0f;
    graphics.DrawEllipse(&pen, x + inset, y + inset, size - stroke_width,
                         size - stroke_width);
  }
}

void DrawSmoothRoundedRect(HDC hdc,
                           RECT rect,
                           int radius,
                           COLORREF fill,
                           std::optional<COLORREF> stroke = std::nullopt,
                           float stroke_width = 1.0f) {
  if (radius <= 0) {
    HBRUSH brush = CreateSolidBrush(fill);
    FillRect(hdc, &rect, brush);
    DeleteObject(brush);
    if (stroke.has_value()) {
      HPEN pen = CreatePen(PS_SOLID, static_cast<int>(stroke_width), *stroke);
      HGDIOBJ old_brush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
      HGDIOBJ old_pen = SelectObject(hdc, pen);
      Rectangle(hdc, rect.left, rect.top, rect.right, rect.bottom);
      SelectObject(hdc, old_brush);
      SelectObject(hdc, old_pen);
      DeleteObject(pen);
    }
    return;
  }
  EnsureGdiplus();
  if (g_gdiplus_token == 0) {
    DrawFilledRoundRect(hdc, rect, radius * 2, fill, stroke.value_or(fill));
    return;
  }
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  Gdiplus::GraphicsPath path;
  const int diameter = std::max(1, radius * 2);
  path.AddArc(rect.left, rect.top, diameter, diameter, 180, 90);
  path.AddArc(rect.right - diameter, rect.top, diameter, diameter, 270, 90);
  path.AddArc(rect.right - diameter, rect.bottom - diameter, diameter,
              diameter, 0, 90);
  path.AddArc(rect.left, rect.bottom - diameter, diameter, diameter, 90, 90);
  path.CloseFigure();
  Gdiplus::SolidBrush brush(GdiColorFromColorRef(fill));
  graphics.FillPath(&brush, &path);
  if (stroke.has_value()) {
    Gdiplus::Pen pen(GdiColorFromColorRef(*stroke), stroke_width);
    graphics.DrawPath(&pen, &path);
  }
}

void DrawCameraButton(HDC hdc, RECT rect) {
  int width = rect.right - rect.left;
  int height = rect.bottom - rect.top;
  int size = std::min(width, height);
  int x = rect.left + (width - size) / 2;
  int y = rect.top + (height - size) / 2;
  DrawSmoothCircleFill(hdc, x, y, size, RGB(84, 84, 84),
                       RGB(255, 255, 255), 1.6f);

  EnsureGdiplus();
  if (g_gdiplus_token == 0) {
    HFONT font = CreateUiFont(9, FW_BOLD);
    DrawTextBlock(hdc, L"\x25C9", rect, font, RGB(255, 255, 255),
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DeleteObject(font);
    return;
  }

  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  Gdiplus::SolidBrush white(Gdiplus::Color(255, 255, 255, 255));
  const float body_w = size * 0.58f;
  const float body_h = size * 0.38f;
  const float body_x = x + (size - body_w) / 2.0f;
  const float body_y = y + size * 0.36f;
  Gdiplus::GraphicsPath body;
  const float radius = 3.2f;
  body.AddArc(body_x, body_y, radius * 2, radius * 2, 180, 90);
  body.AddArc(body_x + body_w - radius * 2, body_y, radius * 2, radius * 2,
              270, 90);
  body.AddArc(body_x + body_w - radius * 2, body_y + body_h - radius * 2,
              radius * 2, radius * 2, 0, 90);
  body.AddArc(body_x, body_y + body_h - radius * 2, radius * 2, radius * 2,
              90, 90);
  body.CloseFigure();
  graphics.FillPath(&white, &body);
  graphics.FillRectangle(&white, body_x + body_w * 0.22f,
                         y + size * 0.27f, body_w * 0.26f, size * 0.11f);
  Gdiplus::SolidBrush dark(Gdiplus::Color(255, 84, 84, 84));
  const float lens = size * 0.22f;
  graphics.FillEllipse(&dark, x + (size - lens) / 2.0f,
                       body_y + (body_h - lens) / 2.0f, lens, lens);
}

void DrawMagnifierIcon(HDC hdc, int x, int y, int size, COLORREF color) {
  EnsureGdiplus();
  if (g_gdiplus_token == 0) {
    HFONT font = CreateUiFont(std::max(8, size / 2), FW_NORMAL);
    DrawTextBlock(hdc, L"\x2315", RECT{x, y, x + size, y + size}, font,
                  color, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DeleteObject(font);
    return;
  }
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  Gdiplus::Pen pen(GdiColorFromColorRef(color), 1.5f);
  pen.SetStartCap(Gdiplus::LineCapRound);
  pen.SetEndCap(Gdiplus::LineCapRound);
  graphics.DrawEllipse(&pen, x + size * 0.18f, y + size * 0.18f,
                       size * 0.48f, size * 0.48f);
  graphics.DrawLine(&pen, x + size * 0.61f, y + size * 0.61f,
                    x + size * 0.82f, y + size * 0.82f);
}

void DrawSmoothPersonGlyph(HDC hdc, int x, int y, int size) {
  EnsureGdiplus();
  if (g_gdiplus_token == 0) {
    HFONT font = CreateUiFont(std::max(9, size / 3), FW_BOLD);
    RECT rect{x, y, x + size, y + size};
    DrawTextBlock(hdc, L"\x25CF", rect, font, RGB(255, 255, 255),
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DeleteObject(font);
    return;
  }
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  Gdiplus::SolidBrush brush(Gdiplus::Color(220, 255, 255, 255));
  float head = size * 0.22f;
  float head_x = x + (size - head) / 2.0f;
  float head_y = y + size * 0.26f;
  graphics.FillEllipse(&brush, head_x, head_y, head, head);
  float body_w = size * 0.48f;
  float body_h = size * 0.28f;
  float body_x = x + (size - body_w) / 2.0f;
  float body_y = y + size * 0.52f;
  graphics.FillPie(&brush, body_x, body_y, body_w, body_h * 1.55f, 180, 180);
}

void DrawSmoothAvatar(HDC hdc,
                      int x,
                      int y,
                      int size,
                      COLORREF color,
                      const std::string& image_url = std::string()) {
  if (DrawImageAvatar(hdc, x, y, size, image_url, false)) {
    return;
  }
  DrawSmoothCircleFill(hdc, x, y, size, color);
  DrawSmoothPersonGlyph(hdc, x, y, size);
}

std::wstring NormalizeFolderIconToken(const std::wstring& icon) {
  std::wstring normalized;
  normalized.reserve(icon.size());
  for (wchar_t value : icon) {
    if (value != L'\xFE0F') {
      normalized.push_back(value);
    }
  }
  return normalized;
}

enum class FolderIconKind {
  block,
  chat,
  home,
  work,
  heart,
  pencil,
  basket,
  card,
  flight,
  plus,
  smile,
  star,
  circle,
};

FolderIconKind FolderIconKindFor(const std::wstring& icon) {
  const std::wstring normalized = NormalizeFolderIconToken(icon);
  if (normalized == L"\x2298") {
    return FolderIconKind::block;
  }
  if (normalized == L"\xD83D\xDCAC") {
    return FolderIconKind::chat;
  }
  if (normalized == L"\x2302" || normalized == L"\xD83C\xDFE0") {
    return FolderIconKind::home;
  }
  if (normalized == L"\x25A0" || normalized == L"\xD83D\xDCBC") {
    return FolderIconKind::work;
  }
  if (normalized == L"\x2665" || normalized == L"\xD83D\xDC97") {
    return FolderIconKind::heart;
  }
  if (normalized == L"\x270E" || normalized == L"\x270F") {
    return FolderIconKind::pencil;
  }
  if (normalized == L"\x25A3" || normalized == L"\xD83E\xDDFA") {
    return FolderIconKind::basket;
  }
  if (normalized == L"\x25AC" || normalized == L"\xD83D\xDCB3") {
    return FolderIconKind::card;
  }
  if (normalized == L"\x2708") {
    return FolderIconKind::flight;
  }
  if (normalized == L"\x271A" || normalized == L"\x2795") {
    return FolderIconKind::plus;
  }
  if (normalized == L"\x263A") {
    return FolderIconKind::smile;
  }
  if (normalized == L"\x2605" || normalized == L"\x2B50") {
    return FolderIconKind::star;
  }
  if (normalized == L"\x25CB") {
    return FolderIconKind::circle;
  }
  return FolderIconKind::chat;
}

COLORREF FolderManageIconColor(const std::wstring& icon);

void AddFolderRoundedRectPath(Gdiplus::GraphicsPath& path,
                              float x,
                              float y,
                              float width,
                              float height,
                              float radius) {
  const float diameter = std::max(1.0f, radius * 2.0f);
  path.AddArc(x, y, diameter, diameter, 180, 90);
  path.AddArc(x + width - diameter, y, diameter, diameter, 270, 90);
  path.AddArc(x + width - diameter, y + height - diameter, diameter, diameter,
              0, 90);
  path.AddArc(x, y + height - diameter, diameter, diameter, 90, 90);
  path.CloseFigure();
}

void DrawFolderFallbackGlyph(HDC hdc,
                             RECT rect,
                             const std::wstring& icon,
                             int size) {
  const std::wstring normalized = NormalizeFolderIconToken(icon);
  std::wstring fallback = normalized.empty() ? L"\xD83D\xDCAC" : normalized;
  HFONT font = CreateUiFont(std::max(8, size - 3), FW_NORMAL);
  DrawTextBlock(hdc, fallback, rect, font, FolderManageIconColor(icon),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DeleteObject(font);
}

void DrawFolderIconGlyph(HDC hdc,
                         RECT rect,
                         const std::wstring& icon,
                         int target_size = 15) {
  int width = rect.right - rect.left;
  int height = rect.bottom - rect.top;
  int size = std::min({target_size, width, height});
  int x = rect.left + ((width - size) / 2);
  int y = rect.top + ((height - size) / 2);
  COLORREF color_ref = FolderManageIconColor(icon);

  EnsureGdiplus();
  if (g_gdiplus_token == 0) {
    DrawFolderFallbackGlyph(hdc, RECT{x, y, x + size, y + size}, icon, size);
    return;
  }

  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  Gdiplus::SolidBrush brush(GdiColorFromColorRef(color_ref));
  Gdiplus::Pen pen(GdiColorFromColorRef(color_ref),
                   std::max(1.2f, size * 0.13f));
  pen.SetStartCap(Gdiplus::LineCapRound);
  pen.SetEndCap(Gdiplus::LineCapRound);
  pen.SetLineJoin(Gdiplus::LineJoinRound);

  const float fx = static_cast<float>(x);
  const float fy = static_cast<float>(y);
  const float fs = static_cast<float>(size);

  switch (FolderIconKindFor(icon)) {
    case FolderIconKind::block: {
      graphics.DrawEllipse(&pen, fx + fs * 0.18f, fy + fs * 0.18f,
                           fs * 0.64f, fs * 0.64f);
      graphics.DrawLine(&pen, fx + fs * 0.30f, fy + fs * 0.70f,
                        fx + fs * 0.70f, fy + fs * 0.30f);
      break;
    }
    case FolderIconKind::chat: {
      Gdiplus::GraphicsPath bubble;
      AddFolderRoundedRectPath(bubble, fx + fs * 0.10f, fy + fs * 0.18f,
                               fs * 0.76f, fs * 0.58f, fs * 0.16f);
      graphics.FillPath(&brush, &bubble);
      Gdiplus::PointF tail[] = {
          {fx + fs * 0.34f, fy + fs * 0.72f},
          {fx + fs * 0.26f, fy + fs * 0.92f},
          {fx + fs * 0.52f, fy + fs * 0.72f},
      };
      graphics.FillPolygon(&brush, tail, 3);
      break;
    }
    case FolderIconKind::home: {
      Gdiplus::PointF roof[] = {
          {fx + fs * 0.12f, fy + fs * 0.48f},
          {fx + fs * 0.50f, fy + fs * 0.14f},
          {fx + fs * 0.88f, fy + fs * 0.48f},
      };
      graphics.FillPolygon(&brush, roof, 3);
      Gdiplus::GraphicsPath body;
      AddFolderRoundedRectPath(body, fx + fs * 0.24f, fy + fs * 0.45f,
                               fs * 0.52f, fs * 0.40f, fs * 0.06f);
      graphics.FillPath(&brush, &body);
      break;
    }
    case FolderIconKind::work: {
      Gdiplus::GraphicsPath body;
      AddFolderRoundedRectPath(body, fx + fs * 0.12f, fy + fs * 0.34f,
                               fs * 0.76f, fs * 0.50f, fs * 0.08f);
      graphics.FillPath(&brush, &body);
      Gdiplus::Pen handle_pen(GdiColorFromColorRef(color_ref),
                              std::max(1.1f, fs * 0.10f));
      handle_pen.SetStartCap(Gdiplus::LineCapRound);
      handle_pen.SetEndCap(Gdiplus::LineCapRound);
      graphics.DrawLine(&handle_pen, fx + fs * 0.36f, fy + fs * 0.32f,
                        fx + fs * 0.36f, fy + fs * 0.22f);
      graphics.DrawLine(&handle_pen, fx + fs * 0.36f, fy + fs * 0.22f,
                        fx + fs * 0.64f, fy + fs * 0.22f);
      graphics.DrawLine(&handle_pen, fx + fs * 0.64f, fy + fs * 0.22f,
                        fx + fs * 0.64f, fy + fs * 0.32f);
      Gdiplus::Pen seam(Gdiplus::Color(85, 255, 255, 255), 1.0f);
      graphics.DrawLine(&seam, fx + fs * 0.16f, fy + fs * 0.52f,
                        fx + fs * 0.84f, fy + fs * 0.52f);
      break;
    }
    case FolderIconKind::heart: {
      DrawFolderFallbackGlyph(hdc, RECT{x, y - 1, x + size, y + size}, L"\x2665",
                              size + 2);
      break;
    }
    case FolderIconKind::pencil: {
      graphics.DrawLine(&pen, fx + fs * 0.30f, fy + fs * 0.76f,
                        fx + fs * 0.74f, fy + fs * 0.32f);
      Gdiplus::PointF nib[] = {
          {fx + fs * 0.74f, fy + fs * 0.32f},
          {fx + fs * 0.86f, fy + fs * 0.24f},
          {fx + fs * 0.78f, fy + fs * 0.42f},
      };
      graphics.FillPolygon(&brush, nib, 3);
      break;
    }
    case FolderIconKind::basket: {
      Gdiplus::Pen basket_pen(GdiColorFromColorRef(color_ref),
                              std::max(1.2f, fs * 0.11f));
      basket_pen.SetLineJoin(Gdiplus::LineJoinRound);
      graphics.DrawRectangle(&basket_pen, fx + fs * 0.24f, fy + fs * 0.28f,
                             fs * 0.52f, fs * 0.52f);
      graphics.DrawLine(&basket_pen, fx + fs * 0.34f, fy + fs * 0.28f,
                        fx + fs * 0.42f, fy + fs * 0.18f);
      graphics.DrawLine(&basket_pen, fx + fs * 0.58f, fy + fs * 0.18f,
                        fx + fs * 0.66f, fy + fs * 0.28f);
      break;
    }
    case FolderIconKind::card: {
      Gdiplus::GraphicsPath card;
      AddFolderRoundedRectPath(card, fx + fs * 0.14f, fy + fs * 0.26f,
                               fs * 0.72f, fs * 0.48f, fs * 0.06f);
      graphics.FillPath(&brush, &card);
      Gdiplus::Pen white_pen(Gdiplus::Color(155, 255, 255, 255), 1.0f);
      graphics.DrawLine(&white_pen, fx + fs * 0.22f, fy + fs * 0.42f,
                        fx + fs * 0.78f, fy + fs * 0.42f);
      break;
    }
    case FolderIconKind::flight: {
      DrawFolderFallbackGlyph(hdc, RECT{x, y - 1, x + size, y + size + 1},
                              L"\x2708", size + 1);
      break;
    }
    case FolderIconKind::plus: {
      Gdiplus::Pen plus_pen(GdiColorFromColorRef(color_ref),
                            std::max(2.0f, fs * 0.18f));
      plus_pen.SetStartCap(Gdiplus::LineCapRound);
      plus_pen.SetEndCap(Gdiplus::LineCapRound);
      graphics.DrawLine(&plus_pen, fx + fs * 0.24f, fy + fs * 0.50f,
                        fx + fs * 0.76f, fy + fs * 0.50f);
      graphics.DrawLine(&plus_pen, fx + fs * 0.50f, fy + fs * 0.24f,
                        fx + fs * 0.50f, fy + fs * 0.76f);
      break;
    }
    case FolderIconKind::smile: {
      graphics.DrawEllipse(&pen, fx + fs * 0.16f, fy + fs * 0.16f,
                           fs * 0.68f, fs * 0.68f);
      Gdiplus::SolidBrush dot(GdiColorFromColorRef(color_ref));
      graphics.FillEllipse(&dot, fx + fs * 0.36f, fy + fs * 0.38f,
                           fs * 0.08f, fs * 0.08f);
      graphics.FillEllipse(&dot, fx + fs * 0.58f, fy + fs * 0.38f,
                           fs * 0.08f, fs * 0.08f);
      graphics.DrawArc(&pen, fx + fs * 0.34f, fy + fs * 0.43f, fs * 0.32f,
                       fs * 0.28f, 20, 140);
      break;
    }
    case FolderIconKind::star: {
      std::vector<Gdiplus::PointF> points;
      for (int i = 0; i < 10; i++) {
        double angle = -3.14159265358979323846 / 2.0 +
                       i * 3.14159265358979323846 / 5.0;
        float radius = (i % 2 == 0) ? fs * 0.42f : fs * 0.18f;
        float point_x =
            fx + fs * 0.50f + static_cast<float>(std::cos(angle)) * radius;
        float point_y =
            fy + fs * 0.52f + static_cast<float>(std::sin(angle)) * radius;
        points.push_back(Gdiplus::PointF(point_x, point_y));
      }
      graphics.FillPolygon(&brush, points.data(),
                           static_cast<INT>(points.size()));
      break;
    }
    case FolderIconKind::circle: {
      graphics.DrawEllipse(&pen, fx + fs * 0.20f, fy + fs * 0.20f,
                           fs * 0.60f, fs * 0.60f);
      break;
    }
  }
}

void DrawSmoothFolderIconCircle(HDC hdc,
                                RECT rect,
                                const std::wstring& icon,
                                bool selected,
                                HFONT /*font*/) {
  int size = std::min(rect.right - rect.left, rect.bottom - rect.top);
  int x = rect.left + ((rect.right - rect.left - size) / 2);
  int y = rect.top + ((rect.bottom - rect.top - size) / 2);
  DrawSmoothCircleFill(hdc, x, y, size, RGB(246, 246, 246),
                       selected ? std::optional<COLORREF>(RGB(20, 20, 20))
                                : std::nullopt,
                       1.0f);
  DrawFolderIconGlyph(hdc, rect, icon, 15);
}

void ToggleFolderRoom(FolderCreateState* state, const std::string& room_id) {
  if (!state) {
    return;
  }
  auto iterator = std::find(state->selected_room_ids.begin(),
                            state->selected_room_ids.end(), room_id);
  if (iterator == state->selected_room_ids.end()) {
    state->selected_room_ids.push_back(room_id);
  } else {
    state->selected_room_ids.erase(iterator);
  }
}

void DrawCheckCircle(HDC hdc, RECT circle, bool selected) {
  EnsureGdiplus();
  if (g_gdiplus_token != 0) {
    int width = circle.right - circle.left;
    int height = circle.bottom - circle.top;
    int size = std::min(width, height);
    int x = circle.left + ((width - size) / 2);
    int y = circle.top + ((height - size) / 2);
    Gdiplus::Graphics graphics(hdc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    if (selected) {
      Gdiplus::SolidBrush fill(Gdiplus::Color(255, 255, 223, 0));
      graphics.FillEllipse(&fill, x, y, size, size);
      Gdiplus::Pen check(Gdiplus::Color(255, 0, 0, 0), 2.2f);
      check.SetStartCap(Gdiplus::LineCapRound);
      check.SetEndCap(Gdiplus::LineCapRound);
      Gdiplus::PointF points[3] = {
          Gdiplus::PointF(x + size * 0.28f, y + size * 0.50f),
          Gdiplus::PointF(x + size * 0.45f, y + size * 0.67f),
          Gdiplus::PointF(x + size * 0.74f, y + size * 0.34f),
      };
      graphics.DrawLines(&check, points, 3);
      return;
    }
    Gdiplus::SolidBrush fill(Gdiplus::Color(255, 255, 255, 255));
    Gdiplus::Pen stroke(Gdiplus::Color(255, 160, 160, 160), 1.0f);
    graphics.FillEllipse(&fill, x + 0.5f, y + 0.5f, size - 1.0f,
                         size - 1.0f);
    graphics.DrawEllipse(&stroke, x + 0.5f, y + 0.5f, size - 1.0f,
                         size - 1.0f);
    return;
  }
  if (selected) {
    HBRUSH brush = CreateSolidBrush(RGB(255, 223, 0));
    HPEN pen = CreatePen(PS_SOLID, 1, RGB(255, 223, 0));
    HGDIOBJ old_brush = SelectObject(hdc, brush);
    HGDIOBJ old_pen = SelectObject(hdc, pen);
    Ellipse(hdc, circle.left, circle.top, circle.right, circle.bottom);
    SelectObject(hdc, old_brush);
    SelectObject(hdc, old_pen);
    DeleteObject(brush);
    DeleteObject(pen);

    HPEN check_pen = CreatePen(PS_SOLID, 2, RGB(0, 0, 0));
    old_pen = SelectObject(hdc, check_pen);
    int width = circle.right - circle.left;
    int height = circle.bottom - circle.top;
    MoveToEx(hdc, circle.left + width / 4, circle.top + height / 2, nullptr);
    LineTo(hdc, circle.left + width / 2 - 1, circle.top + (height * 3) / 4);
    LineTo(hdc, circle.right - width / 4, circle.top + height / 3);
    SelectObject(hdc, old_pen);
    DeleteObject(check_pen);
    return;
  }

  HGDIOBJ old_brush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(160, 160, 160));
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  Ellipse(hdc, circle.left, circle.top, circle.right, circle.bottom);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(pen);
}

void DrawRedUnreadBadge(HDC hdc, int center_x, int center_y, int count) {
  if (count <= 0) {
    return;
  }
  std::wstring label = count > 99 ? L"99+" : std::to_wstring(count);
  int width = count > 9 ? 24 : 18;
  RECT rect{center_x - width / 2, center_y - 9, center_x + width / 2,
            center_y + 9};
  EnsureGdiplus();
  if (g_gdiplus_token != 0) {
    Gdiplus::Graphics graphics(hdc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
    Gdiplus::SolidBrush brush(Gdiplus::Color(255, 239, 75, 45));
    Gdiplus::GraphicsPath path;
    int radius = 18;
    path.AddArc(rect.left, rect.top, radius, radius, 180, 90);
    path.AddArc(rect.right - radius, rect.top, radius, radius, 270, 90);
    path.AddArc(rect.right - radius, rect.bottom - radius, radius, radius, 0,
                90);
    path.AddArc(rect.left, rect.bottom - radius, radius, radius, 90, 90);
    path.CloseFigure();
    graphics.FillPath(&brush, &path);
    HFONT font = CreateUiFont(8, FW_BOLD);
    DrawTextBlock(hdc, label, rect, font, RGB(255, 255, 255),
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DeleteObject(font);
    return;
  }
  HBRUSH brush = CreateSolidBrush(RGB(239, 75, 45));
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(239, 75, 45));
  HGDIOBJ old_brush = SelectObject(hdc, brush);
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  RoundRect(hdc, rect.left, rect.top, rect.right, rect.bottom, 18, 18);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(brush);
  DeleteObject(pen);

  HFONT font = CreateUiFont(8, FW_BOLD);
  DrawTextBlock(hdc, label, rect, font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DeleteObject(font);
}

void DrawFolderAvatar(HDC hdc, const FolderRoomState& room, int x, int y,
                      int size) {
  if (room.is_group) {
    COLORREF colors[4] = {room.avatar_color, RGB(139, 190, 204),
                          RGB(166, 198, 238), RGB(221, 232, 165)};
    int dot = size / 2;
    for (int index = 0; index < 4; index++) {
      int left = x + (index % 2) * dot;
      int top = y + (index / 2) * dot;
      COLORREF color = colors[index];
      std::string image_url;
      if (index < static_cast<int>(room.avatar_parts.size())) {
        color = room.avatar_parts[index].color;
        image_url = room.avatar_parts[index].image_url;
      }
      DrawSmoothAvatar(hdc, left, top, dot, color, image_url);
    }
    return;
  }

  DrawSmoothAvatar(hdc, x, y, size, room.avatar_color, room.avatar_image_url);
}

RECT EmployeePrimaryRect() {
  return RECT{114, kEmployeeAddNativeHeight - 52, 194,
              kEmployeeAddNativeHeight - 15};
}

RECT EmployeeSecondaryRect() {
  return RECT{202, kEmployeeAddNativeHeight - 52, 282,
              kEmployeeAddNativeHeight - 15};
}

std::wstring WindowText(HWND hwnd) {
  if (!hwnd) {
    return std::wstring();
  }
  int length = GetWindowTextLengthW(hwnd);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring text(length + 1, L'\0');
  GetWindowTextW(hwnd, text.data(), length + 1);
  text.resize(length);
  return text;
}

std::wstring EmployeeName(EmployeeAddState* state) {
  return state ? WindowText(state->name_edit) : std::wstring();
}

std::wstring EmployeePhone(EmployeeAddState* state) {
  return state ? WindowText(state->phone_edit) : std::wstring();
}

std::wstring EmployeeCountry(EmployeeAddState* state) {
  std::wstring country = state ? WindowText(state->country_edit) : std::wstring();
  return country.empty() ? L"+82" : country;
}

std::wstring EmployeeFullPhone(EmployeeAddState* state) {
  std::wstring phone = EmployeePhone(state);
  if (phone.empty() || phone.front() == L'+') {
    return phone;
  }
  return EmployeeCountry(state) + L" " + phone;
}

std::wstring EmployeeEmail(EmployeeAddState* state) {
  return state ? WindowText(state->email_edit) : std::wstring();
}

std::wstring DigitsOnly(const std::wstring& value) {
  std::wstring digits;
  for (wchar_t ch : value) {
    if (ch >= L'0' && ch <= L'9') {
      digits.push_back(ch);
    }
  }
  return digits;
}

std::wstring FormatPhoneNumber(const std::wstring& value) {
  std::wstring digits = DigitsOnly(value);
  if (digits.size() == 11 && digits.rfind(L"010", 0) == 0) {
    return digits.substr(0, 3) + L"-" + digits.substr(3, 4) + L"-" +
           digits.substr(7, 4);
  }
  if (digits.size() == 10 && digits.rfind(L"010", 0) == 0) {
    return digits.substr(0, 3) + L"-" + digits.substr(3, 3) + L"-" +
           digits.substr(6, 4);
  }
  if (digits.size() == 10) {
    return digits.substr(0, 3) + L"-" + digits.substr(3, 3) + L"-" +
           digits.substr(6, 4);
  }
  if (digits.size() > 11) {
    digits.resize(11);
    return FormatPhoneNumber(digits);
  }
  return value;
}

bool EmployeeContactReady(EmployeeAddState* state) {
  return state && !EmployeeName(state).empty() && !EmployeeFullPhone(state).empty();
}

bool EmployeeEmailReady(EmployeeAddState* state) {
  return state && !EmployeeEmail(state).empty();
}

void InvokeEmployeeAction(EmployeeAddState* state,
                          const std::string& action,
                          const std::wstring& name,
                          const std::wstring& phone,
                          const std::wstring& email);

LRESULT CALLBACK EmployeeCountryEditProc(HWND hwnd,
                                         UINT message,
                                         WPARAM wparam,
                                         LPARAM lparam);

const std::vector<std::pair<std::wstring, std::wstring>>& EmployeeCountryCodes() {
  static const std::vector<std::pair<std::wstring, std::wstring>> codes = {
      {L"Afghanistan", L"+93"},
      {L"Albania", L"+355"},
      {L"Algeria", L"+213"},
      {L"American Samoa", L"+1 684"},
      {L"Andorra", L"+376"},
      {L"Angola", L"+244"},
      {L"Argentina", L"+54"},
      {L"Australia", L"+61"},
      {L"Brazil", L"+55"},
      {L"Canada", L"+1"},
      {L"China", L"+86"},
      {L"France", L"+33"},
      {L"Germany", L"+49"},
      {L"India", L"+91"},
      {L"Indonesia", L"+62"},
      {L"Japan", L"+81"},
      {L"Korea", L"+82"},
      {L"Singapore", L"+65"},
      {L"United Kingdom", L"+44"},
      {L"United States", L"+1"},
  };
  return codes;
}

void ShowEmployeeCountryMenu(HWND hwnd, EmployeeAddState* state) {
  if (!state || !state->country_edit) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  const auto& codes = EmployeeCountryCodes();
  for (int index = 0; index < static_cast<int>(codes.size()); index++) {
    std::wstring label = codes[index].first + L" " + codes[index].second;
    AppendMenuW(menu, MF_STRING, 7100 + index, label.c_str());
  }
  POINT point{20, 216};
  ClientToScreen(hwnd, &point);
  UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_LEFTALIGN | TPM_TOPALIGN,
                                point.x, point.y, 0, hwnd, nullptr);
  DestroyMenu(menu);
  int index = static_cast<int>(command) - 7100;
  if (index >= 0 && index < static_cast<int>(codes.size())) {
    SetWindowTextW(state->country_edit, codes[index].second.c_str());
    state->contact_result = EmployeeResultState();
    if (EmployeeContactReady(state)) {
      InvokeEmployeeAction(state, "contactChanged", EmployeeName(state),
                           EmployeeFullPhone(state), std::wstring());
    }
    InvalidateRect(hwnd, nullptr, TRUE);
  }
}

LRESULT CALLBACK EmployeeCountryEditProc(HWND hwnd,
                                         UINT message,
                                         WPARAM wparam,
                                         LPARAM lparam) {
  if (message == WM_LBUTTONDOWN || message == WM_LBUTTONDBLCLK) {
    HWND parent = GetParent(hwnd);
    auto* state = reinterpret_cast<EmployeeAddState*>(
        GetWindowLongPtr(parent, GWLP_USERDATA));
    ShowEmployeeCountryMenu(parent, state);
    return 0;
  }
  if (g_employee_country_edit_original_proc) {
    return CallWindowProc(g_employee_country_edit_original_proc, hwnd, message,
                          wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void ShowEmployeeTabControls(EmployeeAddState* state) {
  if (!state) {
    return;
  }
  bool contact = state->tab_index == 0;
  ShowWindow(state->name_edit, contact ? SW_SHOW : SW_HIDE);
  ShowWindow(state->phone_edit, contact ? SW_SHOW : SW_HIDE);
  ShowWindow(state->country_edit, SW_HIDE);
  ShowWindow(state->email_edit, contact ? SW_HIDE : SW_SHOW);
}

void InvokeEmployeeAction(EmployeeAddState* state,
                          const std::string& action,
                          const std::wstring& name = std::wstring(),
                          const std::wstring& phone = std::wstring(),
                          const std::wstring& email = std::wstring()) {
  if (!state || !state->channel) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(action);
  arguments[flutter::EncodableValue("name")] =
      flutter::EncodableValue(Utf8FromUtf16(name.c_str()));
  arguments[flutter::EncodableValue("phone")] =
      flutter::EncodableValue(Utf8FromUtf16(phone.c_str()));
  arguments[flutter::EncodableValue("email")] =
      flutter::EncodableValue(Utf8FromUtf16(email.c_str()));
  state->channel->InvokeMethod(
      "employeePopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void DrawEmployeeButton(HDC hdc,
                        RECT rect,
                        const std::wstring& label,
                        bool enabled,
                        bool primary,
                        HFONT font) {
  COLORREF fill = primary && enabled ? RGB(255, 223, 0)
                                     : primary ? RGB(240, 240, 240)
                                               : RGB(255, 255, 255);
  COLORREF border = primary && enabled ? RGB(255, 223, 0)
                                       : RGB(225, 225, 225);
  DrawFilledRoundRect(hdc, rect, 4, fill, border);
  DrawTextBlock(hdc, label, rect, font,
                enabled ? RGB(0, 0, 0) : RGB(115, 115, 115),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

void DrawEmployeeTabs(HDC hdc, EmployeeAddState* state, HFONT font) {
  RECT contact{20, 88, 108, 118};
  RECT id{124, 88, 196, 118};
  DrawTextBlock(hdc, L"\xC5F0\xB77D\xCC98\xB85C \xCD94\xAC00", contact, font,
                state->tab_index == 0 ? RGB(0, 0, 0) : RGB(115, 115, 115),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  DrawTextBlock(hdc, L"ID\xB85C \xCD94\xAC00", id, font,
                state->tab_index == 1 ? RGB(0, 0, 0) : RGB(115, 115, 115),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(225, 225, 225));
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  MoveToEx(hdc, 0, 124, nullptr);
  LineTo(hdc, kEmployeeAddNativeWidth, 124);
  SelectObject(hdc, old_pen);
  DeleteObject(pen);
  HPEN active = CreatePen(PS_SOLID, 2, RGB(0, 0, 0));
  old_pen = SelectObject(hdc, active);
  if (state->tab_index == 0) {
    MoveToEx(hdc, 20, 113, nullptr);
    LineTo(hdc, 104, 113);
  } else {
    MoveToEx(hdc, 124, 113, nullptr);
    LineTo(hdc, 180, 113);
  }
  SelectObject(hdc, old_pen);
  DeleteObject(active);
}

void DrawEmployeeAdd(EmployeeAddState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  DrawCloseButton(hdc, kEmployeeAddNativeWidth);
  HFONT title_font = CreateUiFont(13, FW_NORMAL);
  HFONT label_font = CreateUiFont(10, FW_NORMAL);
  HFONT small_font = CreateUiFont(9, FW_NORMAL);
  HFONT button_font = CreateUiFont(10, FW_NORMAL);

  DrawTextBlock(hdc, L"\xC9C1\xC6D0 \xCD94\xAC00", RECT{20, 42, 160, 64},
                title_font, RGB(0, 0, 0),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  DrawEmployeeTabs(hdc, state, label_font);

  if (state->tab_index == 0) {
    std::wstring name = EmployeeName(state);
    DrawTextBlock(hdc, std::to_wstring(name.size()) + L"/20",
                  RECT{236, 154, 282, 176}, small_font, RGB(100, 100, 100),
                  DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
    HWND focus = GetFocus();
    COLORREF inactive_line = RGB(218, 218, 218);
    HPEN name_line = CreatePen(
        PS_SOLID, 1, focus == state->name_edit ? RGB(0, 0, 0) : inactive_line);
    HGDIOBJ old_pen = SelectObject(hdc, name_line);
    MoveToEx(hdc, 20, 178, nullptr);
    LineTo(hdc, 282, 178);
    SelectObject(hdc, old_pen);
    DeleteObject(name_line);
    HPEN phone_line = CreatePen(
        PS_SOLID, 1, focus == state->phone_edit ? RGB(0, 0, 0) : inactive_line);
    old_pen = SelectObject(hdc, phone_line);
    MoveToEx(hdc, 20, 214, nullptr);
    LineTo(hdc, 78, 214);
    MoveToEx(hdc, 88, 214, nullptr);
    LineTo(hdc, 282, 214);
    SelectObject(hdc, old_pen);
    DeleteObject(phone_line);
    std::wstring country = WindowText(state->country_edit);
    if (country.empty()) {
      country = L"+82";
    }
    DrawTextBlock(hdc, country, RECT{20, 188, 58, 212}, label_font,
                  RGB(0, 0, 0), DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    DrawTextBlock(hdc, L"\x2304", RECT{62, 188, 80, 212}, label_font,
                  RGB(120, 120, 120), DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DrawTextBlock(hdc,
                  L"\xC9C1\xC6D0\xC758 \xC774\xB984\xACFC \xC804\xD654\xBC88\xD638\xB97C \xC785\xB825\xD574\xC8FC\xC138\xC694.",
                  RECT{20, 226, 282, 252}, small_font, RGB(125, 125, 125),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  } else {
    std::wstring email = EmployeeEmail(state);
    DrawTextBlock(hdc, std::to_wstring(email.size()) + L"/80",
                  RECT{236, 154, 282, 176}, small_font, RGB(100, 100, 100),
                  DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
    HPEN line = CreatePen(PS_SOLID, 1,
                          GetFocus() == state->email_edit ? RGB(0, 0, 0)
                                                           : RGB(218, 218, 218));
    HGDIOBJ old_pen = SelectObject(hdc, line);
    MoveToEx(hdc, 20, 178, nullptr);
    LineTo(hdc, 282, 178);
    SelectObject(hdc, old_pen);
    DeleteObject(line);
    DrawTextBlock(hdc,
                  L"AVA \xC774\xBA54\xC77C\xB85C \xC9C1\xC6D0\xC744 \xCC3E\xC744\xC218 \xC788\xC2B5\xB2C8\xB2E4.",
                  RECT{20, 194, 282, 222}, small_font, RGB(125, 125, 125),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    const EmployeeResultState& result = state->email_result;
    if (result.has_result) {
      DrawSmoothAvatar(hdc, 114, 248, 72, result.avatar_color,
                       result.avatar_image_url);
      std::wstring label = result.nickname.empty() ? result.name : result.nickname;
      DrawTextBlock(hdc, label, RECT{38, 326, 262, 350}, label_font,
                    RGB(0, 0, 0),
                    DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    }
  }

  bool contact_ready = EmployeeContactReady(state);
  bool email_ready = state->email_result.has_result;
  bool ready = state->tab_index == 0 ? contact_ready : email_ready;
  bool already = state->tab_index == 0
                     ? state->contact_result.is_already_added
                     : state->email_result.is_already_added;
  std::wstring primary_label =
      already ? L"1:1 \xCC44\xD305" : L"\xC9C1\xC6D0 \xCD94\xAC00";
  if (state->tab_index == 0 || state->email_result.has_result) {
    DrawEmployeeButton(hdc, EmployeePrimaryRect(), primary_label, ready, true,
                       button_font);
  }
  if (state->tab_index == 1 && state->email_result.has_result) {
    const EmployeeResultState& result = state->email_result;
    std::wstring secondary =
        result.blocked ? L"\xCC28\xB2E8 \xD574\xC81C" : L"\xCC28\xB2E8";
    DrawEmployeeButton(hdc, EmployeeSecondaryRect(), secondary,
                       result.has_result, false, button_font);
  }

  DeleteObject(title_font);
  DeleteObject(label_font);
  DeleteObject(small_font);
  DeleteObject(button_font);
  EndPaint(hwnd, &paint);
}

void UpdateEmployeeResult(EmployeeAddState* state,
                          const flutter::EncodableMap& arguments) {
  if (!state) {
    return;
  }
  std::string scope = StringArgument(arguments, "scope");
  EmployeeResultState* result =
      scope == "contact" ? &state->contact_result : &state->email_result;
  result->has_result = BoolArgument(arguments, "hasResult", false);
  result->is_already_added =
      BoolArgument(arguments, "isAlreadyAdded", false);
  result->blocked = BoolArgument(arguments, "blocked", false);
  result->id = StringArgument(arguments, "id");
  result->email = StringArgument(arguments, "email");
  result->name = Utf16FromUtf8(StringArgument(arguments, "name"));
  result->nickname = Utf16FromUtf8(StringArgument(arguments, "nickname"));
  result->avatar_color =
      ColorArgument(arguments, "avatarColor", RGB(166, 198, 238));
  result->avatar_image_url = StringArgument(arguments, "avatarImageUrl");
}

LRESULT CALLBACK EmployeeAddWndProc(HWND hwnd,
                                    UINT message,
                                    WPARAM wparam,
                                    LPARAM lparam) {
  auto* state = reinterpret_cast<EmployeeAddState*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<EmployeeAddState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_CREATE:
      if (state) {
        state->edit_font = CreateUiFont(10, FW_NORMAL);
        state->name_edit = CreateWindowExW(
            0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            20, 148, 214, 26, hwnd,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEmployeeNameEditId)),
            GetModuleHandle(nullptr), nullptr);
        state->country_edit = CreateWindowExW(
            0, L"EDIT", L"+82", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            20, 188, 40, 24, hwnd,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEmployeeCountryEditId)),
            GetModuleHandle(nullptr), nullptr);
        state->phone_edit = CreateWindowExW(
            0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            88, 188, 194, 24, hwnd,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEmployeePhoneEditId)),
            GetModuleHandle(nullptr), nullptr);
        state->email_edit = CreateWindowExW(
            0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            20, 148, 214, 26, hwnd,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kEmployeeEmailEditId)),
            GetModuleHandle(nullptr), nullptr);
        for (HWND edit : {state->name_edit, state->country_edit,
                          state->phone_edit, state->email_edit}) {
          SendMessage(edit, WM_SETFONT,
                      reinterpret_cast<WPARAM>(state->edit_font), TRUE);
        }
        g_employee_country_edit_original_proc =
            reinterpret_cast<WNDPROC>(SetWindowLongPtr(
                state->country_edit, GWLP_WNDPROC,
                reinterpret_cast<LONG_PTR>(EmployeeCountryEditProc)));
        SendMessageW(state->name_edit, EM_SETCUEBANNER, TRUE,
                     reinterpret_cast<LPARAM>(L"\xC9C1\xC6D0 \xC774\xB984"));
        SendMessageW(state->phone_edit, EM_SETCUEBANNER, TRUE,
                     reinterpret_cast<LPARAM>(L"\xC804\xD654\xBC88\xD638"));
        SendMessageW(state->email_edit, EM_SETCUEBANNER, TRUE,
                     reinterpret_cast<LPARAM>(L"\xC9C1\xC6D0 AVA ID"));
        ShowEmployeeTabControls(state);
      }
      return 0;
    case WM_COMMAND: {
      UINT id = LOWORD(wparam);
      UINT code = HIWORD(wparam);
      if (code == EN_CHANGE && state) {
        if (id == kEmployeeNameEditId || id == kEmployeePhoneEditId) {
          if (id == kEmployeePhoneEditId && !state->formatting_phone) {
            std::wstring before = EmployeePhone(state);
            std::wstring formatted = FormatPhoneNumber(before);
            if (formatted != before) {
              state->formatting_phone = true;
              SetWindowTextW(state->phone_edit, formatted.c_str());
              SendMessageW(state->phone_edit, EM_SETSEL,
                           static_cast<WPARAM>(formatted.size()),
                           static_cast<LPARAM>(formatted.size()));
              state->formatting_phone = false;
            }
          }
          state->contact_result = EmployeeResultState();
          if (EmployeeContactReady(state)) {
            InvokeEmployeeAction(state, "contactChanged",
                                 EmployeeName(state), EmployeeFullPhone(state));
          }
        } else if (id == kEmployeeEmailEditId) {
          state->email_result = EmployeeResultState();
          if (EmployeeEmailReady(state)) {
            InvokeEmployeeAction(state, "emailChanged", std::wstring(),
                                 std::wstring(), EmployeeEmail(state));
          }
        }
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      if ((code == EN_SETFOCUS || code == EN_KILLFOCUS) && state) {
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      break;
    }
    case WM_LBUTTONDOWN: {
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (PointInRect(CloseButtonRect(kEmployeeAddNativeWidth), x, y)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (!state) {
        return 0;
      }
      if (y >= 84 && y <= 120) {
        if (x >= 18 && x <= 112) {
          state->tab_index = 0;
          ShowEmployeeTabControls(state);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
        if (x >= 120 && x <= 200) {
          state->tab_index = 1;
          ShowEmployeeTabControls(state);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
      }
      if (state->tab_index == 0 && x >= 18 && x <= 82 && y >= 184 &&
          y <= 218) {
        ShowEmployeeCountryMenu(hwnd, state);
        return 0;
      }
      if (PointInRect(EmployeePrimaryRect(), x, y)) {
        if (state->tab_index == 0 && EmployeeContactReady(state)) {
          InvokeEmployeeAction(state, "primaryContact", EmployeeName(state),
                               EmployeeFullPhone(state));
        } else if (state->tab_index == 1 && state->email_result.has_result) {
          InvokeEmployeeAction(state, "primaryEmail", std::wstring(),
                               std::wstring(), EmployeeEmail(state));
        }
        return 0;
      }
      if (state->tab_index == 1 &&
          PointInRect(EmployeeSecondaryRect(), x, y) &&
          state->email_result.has_result) {
        InvokeEmployeeAction(
            state, state->email_result.blocked ? "unblockEmail" : "blockEmail",
            std::wstring(), std::wstring(), EmployeeEmail(state));
        return 0;
      }
      if (y < 34) {
        ReleaseCapture();
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      }
      return 0;
    }
    case WM_PAINT:
      if (state) {
        DrawEmployeeAdd(state, hwnd);
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (g_active_employee_add_popup == hwnd) {
        g_active_employee_add_popup = nullptr;
      }
      if (state) {
        if (!state->submitted) {
          InvokeEmployeeAction(state, "closed");
        }
        if (state->edit_font) {
          DeleteObject(state->edit_font);
        }
        delete state;
      }
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

const std::vector<std::wstring>& FolderIconChoices() {
  static const std::vector<std::wstring> icons = {
      L"\x2298", L"\x2302", L"\x25A0", L"\x2665", L"\x270E", L"\x25A3",
      L"\x25AC", L"\x2708", L"\x271A", L"\x263A", L"\x2605", L"\x25CB",
  };
  return icons;
}

COLORREF FolderManageIconColor(const std::wstring& icon);

RECT FolderIconRect(int index) {
  int column = index % 7;
  int row = index / 7;
  int left = 20 + column * 48;
  int top = 176 + row * 42;
  return RECT{left, top, left + 34, top + 34};
}

void DrawFolderButtons(HDC hdc, FolderCreateState* state, HFONT font) {
  RECT confirm = FolderConfirmRect();
  RECT cancel = FolderCancelRect();
  bool enabled = state->selecting_rooms
                     ? !state->selected_room_ids.empty()
                     : FolderCanConfirm(state);
  DrawFilledRoundRect(hdc, confirm, 4,
                      enabled ? RGB(255, 223, 0) : RGB(241, 241, 241),
                      enabled ? RGB(255, 223, 0) : RGB(241, 241, 241));
  std::wstring confirm_label =
      state->selecting_rooms
          ? (state->selected_room_ids.empty()
                 ? L"\xC120\xD0DD"
                 : L"\xC120\xD0DD " +
                       std::to_wstring(state->selected_room_ids.size()))
          : L"\xD655\xC778";
  DrawTextBlock(hdc, confirm_label, confirm,
                font, enabled ? RGB(0, 0, 0) : RGB(176, 176, 176),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DrawFilledRoundRect(hdc, cancel, 4, RGB(255, 255, 255), RGB(225, 225, 225));
  DrawTextBlock(hdc, L"\xCDE8\xC18C", cancel, font, RGB(0, 0, 0),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

void DrawFolderCreate(FolderCreateState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  DrawCloseButton(hdc, kFolderCreateNativeWidth);
  HFONT title_font = CreateUiFont(13, FW_NORMAL);
  HFONT label_font = CreateUiFont(10, FW_NORMAL);
  HFONT small_font = CreateUiFont(9, FW_NORMAL);
  HFONT button_font = CreateUiFont(10, FW_NORMAL);

  if (state->selecting_rooms) {
    RECT title{20, 36, 260, 60};
    DrawTextBlock(hdc, L"\xCC44\xD305\xBC29 \xC120\xD0DD", title, title_font, RGB(0, 0, 0),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    RECT search{20, 78, kFolderCreateNativeWidth - 18, 114};
    DrawFilledRoundRect(hdc, search, 18, RGB(245, 245, 245),
                        RGB(245, 245, 245));
    DrawTextBlock(hdc, L"\x2315", RECT{34, 82, 58, 112}, label_font,
                  RGB(130, 130, 130), DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    DrawTextBlock(hdc,
                  L"\xCC44\xD305\xBC29, \xCC38\xC5EC\xC790 \xAC80\xC0C9",
                  RECT{58, 82, 260, 112}, label_font, RGB(130, 130, 130),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);

    const int list_top = 126;
    const int row_height = 68;
    const int visible_count = 6;
    int max_offset = std::max(0, static_cast<int>(state->rooms.size()) -
                                     visible_count);
    state->room_scroll_offset =
        std::max(0, std::min(state->room_scroll_offset, max_offset));
    for (int visible = 0; visible < visible_count; visible++) {
      int index = state->room_scroll_offset + visible;
      if (index >= static_cast<int>(state->rooms.size())) {
        break;
      }
      const FolderRoomState& room = state->rooms[index];
      int y = list_top + visible * row_height;
      if (FolderRoomSelected(state, room.id)) {
        RECT selected{14, y - 2, kFolderCreateNativeWidth - 16,
                      y + row_height - 4};
        HBRUSH brush = CreateSolidBrush(RGB(239, 239, 239));
        FillRect(hdc, &selected, brush);
        DeleteObject(brush);
      }
      DrawFolderAvatar(hdc, room, 18, y + 5, 42);
      RECT title_rect{76, y + 7, 300, y + 27};
      DrawTextBlock(hdc, room.title, title_rect, label_font, RGB(0, 0, 0),
                    DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
      RECT preview_rect{76, y + 28, 300, y + 55};
      DrawTextBlock(hdc, room.preview, preview_rect, small_font,
                    RGB(110, 110, 110),
                    DT_LEFT | DT_TOP | DT_WORDBREAK | DT_END_ELLIPSIS);
      RECT circle{kFolderCreateNativeWidth - 42, y + 18,
                  kFolderCreateNativeWidth - 18, y + 42};
      if (room.unread_count > 0) {
        DrawRedUnreadBadge(hdc, kFolderCreateNativeWidth - 66, y + 30,
                           room.unread_count);
      }
      DrawCheckCircle(hdc, circle, FolderRoomSelected(state, room.id));
    }
    if (state->rooms.size() > visible_count) {
      RECT bar{kFolderCreateNativeWidth - 8, list_top, kFolderCreateNativeWidth - 4,
               list_top + visible_count * row_height};
      HBRUSH track = CreateSolidBrush(RGB(238, 238, 238));
      FillRect(hdc, &bar, track);
      DeleteObject(track);
      int thumb_height = std::max(28, (visible_count * row_height * visible_count) /
                                          static_cast<int>(state->rooms.size()));
      int thumb_top = list_top +
                      ((visible_count * row_height - thumb_height) *
                       state->room_scroll_offset) /
                          std::max(1, max_offset);
      RECT thumb{kFolderCreateNativeWidth - 9, thumb_top,
                 kFolderCreateNativeWidth - 3, thumb_top + thumb_height};
      HBRUSH thumb_brush = CreateSolidBrush(RGB(190, 190, 190));
      FillRect(hdc, &thumb, thumb_brush);
      DeleteObject(thumb_brush);
    }
    DrawFolderButtons(hdc, state, button_font);
  } else {
    RECT title{20, 36, 260, 60};
    DrawTextBlock(hdc,
                  state->is_edit ? L"\xD3F4\xB354 \xD3B8\xC9D1"
                                 : L"\xD3F4\xB354 \xB9CC\xB4E4\xAE30",
                  title, title_font, RGB(0, 0, 0),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    std::wstring name = FolderName(state);
    RECT count{kFolderCreateNativeWidth - 58, 90, kFolderCreateNativeWidth - 18,
               112};
    DrawTextBlock(hdc, std::to_wstring(name.size()) + L"/10", count,
                  small_font, RGB(100, 100, 100),
                  DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
    HPEN line = CreatePen(PS_SOLID, 1, RGB(229, 229, 229));
    HGDIOBJ old_pen = SelectObject(hdc, line);
    MoveToEx(hdc, 20, 112, nullptr);
    LineTo(hdc, kFolderCreateNativeWidth - 18, 112);
    SelectObject(hdc, old_pen);
    DeleteObject(line);

    DrawTextBlock(hdc, L"\xD3F4\xB354 \xC544\xC774\xCF58", RECT{20, 138, 180, 160},
                  label_font, RGB(80, 80, 80),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    const auto& icons = FolderIconChoices();
    for (int index = 0; index < static_cast<int>(icons.size()); index++) {
      RECT icon_rect = FolderIconRect(index);
      bool selected = icons[index] == state->selected_icon;
      DrawSmoothFolderIconCircle(hdc, icon_rect, icons[index], selected,
                                 title_font);
    }

    DrawTextBlock(hdc, L"\xB4F1\xB85D\xD55C \xCC44\xD305\xBC29", RECT{20, 262, 180, 284},
                  label_font, RGB(80, 80, 80),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    RECT add_rect{20, 298, 160, 338};
    DrawFilledRoundRect(hdc, RECT{20, 298, 60, 338}, 12, RGB(248, 248, 248),
                        RGB(229, 229, 229));
    DrawTextBlock(hdc, L"+", RECT{20, 298, 60, 338}, title_font,
                  RGB(80, 80, 80), DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DrawTextBlock(hdc, L"\xCC44\xD305\xBC29 \xCD94\xAC00", RECT{72, 298, 180, 338}, label_font,
                  RGB(0, 0, 0), DT_LEFT | DT_VCENTER | DT_SINGLELINE);

    int y = 354;
    for (const auto& id : state->selected_room_ids) {
      auto iterator = std::find_if(state->rooms.begin(), state->rooms.end(),
                                   [&](const FolderRoomState& room) {
                                     return room.id == id;
                                   });
      if (iterator == state->rooms.end()) {
        continue;
      }
      DrawFolderAvatar(hdc, *iterator, 20, y, 34);
      std::wstring row_title =
          iterator->title + L" " + std::to_wstring(iterator->participant_count);
      DrawTextBlock(hdc, row_title, RECT{70, y + 3, 280, y + 31},
                    label_font, RGB(0, 0, 0),
                    DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
      RECT remove{kFolderCreateNativeWidth - 64, y + 2,
                  kFolderCreateNativeWidth - 18, y + 32};
      DrawFilledRoundRect(hdc, remove, 4, RGB(255, 255, 255),
                          RGB(225, 225, 225));
      DrawTextBlock(hdc, L"\xD574\xC81C", remove, small_font, RGB(0, 0, 0),
                    DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      y += 44;
      if (y > kFolderCreateNativeHeight - 88) {
        break;
      }
    }
    DrawFolderButtons(hdc, state, button_font);
  }

  DeleteObject(title_font);
  DeleteObject(label_font);
  DeleteObject(small_font);
  DeleteObject(button_font);
  EndPaint(hwnd, &paint);
}

void InvokeFolderClosed(FolderCreateState* state) {
  if (!state || !state->channel || state->submitted) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(std::string("closed"));
  state->channel->InvokeMethod(
      "folderPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void SubmitFolderCreate(FolderCreateState* state, HWND hwnd) {
  if (!state || !state->channel || !FolderCanConfirm(state)) {
    return;
  }
  flutter::EncodableList room_ids;
  for (const auto& room_id : state->selected_room_ids) {
    room_ids.push_back(flutter::EncodableValue(room_id));
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(std::string("created"));
  arguments[flutter::EncodableValue("name")] =
      flutter::EncodableValue(Utf8FromUtf16(FolderName(state).c_str()));
  arguments[flutter::EncodableValue("icon")] =
      flutter::EncodableValue(Utf8FromUtf16(state->selected_icon.c_str()));
  arguments[flutter::EncodableValue("roomIds")] =
      flutter::EncodableValue(room_ids);
  state->submitted = true;
  state->channel->InvokeMethod(
      "folderPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
  DestroyWindow(hwnd);
}

LRESULT CALLBACK FolderCreateWndProc(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  auto* state = reinterpret_cast<FolderCreateState*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<FolderCreateState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_CREATE:
      if (state) {
        state->edit_font = CreateUiFont(11, FW_NORMAL);
        state->name_edit = CreateWindowExW(
            0, L"EDIT", state->initial_name.c_str(),
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            20, 82, kFolderCreateNativeWidth - 86, 26, hwnd,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kFolderNameEditId)),
            GetModuleHandle(nullptr), nullptr);
        SendMessage(state->name_edit, WM_SETFONT,
                    reinterpret_cast<WPARAM>(state->edit_font), TRUE);
        SendMessageW(
            state->name_edit, EM_SETCUEBANNER, FALSE,
            reinterpret_cast<LPARAM>(L"\xD3F4\xB354 \xC774\xB984\xC744 \xC785\xB825\xD574 \xC8FC\xC138\xC694."));
      }
      return 0;
    case WM_COMMAND:
      if (LOWORD(wparam) == kFolderNameEditId) {
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      break;
    case WM_MOUSEWHEEL:
      if (state && state->selecting_rooms) {
        int delta = GET_WHEEL_DELTA_WPARAM(wparam);
        state->room_scroll_offset += delta < 0 ? 1 : -1;
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      break;
    case WM_LBUTTONDOWN: {
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (PointInRect(CloseButtonRect(kFolderCreateNativeWidth), x, y)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (!state) {
        return 0;
      }
      if (state->selecting_rooms) {
        if (PointInRect(FolderConfirmRect(), x, y)) {
          if (state->selected_room_ids.empty()) {
            return 0;
          }
          state->selecting_rooms = false;
          ShowWindow(state->name_edit, SW_SHOW);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
        if (PointInRect(FolderCancelRect(), x, y)) {
          state->selecting_rooms = false;
          ShowWindow(state->name_edit, SW_SHOW);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
        const int list_top = 126;
        const int row_height = 68;
        if (y >= list_top && y < list_top + row_height * 6) {
          int index = state->room_scroll_offset + ((y - list_top) / row_height);
          if (index >= 0 && index < static_cast<int>(state->rooms.size())) {
            ToggleFolderRoom(state, state->rooms[index].id);
            InvalidateRect(hwnd, nullptr, TRUE);
          }
          return 0;
        }
      } else {
        if (PointInRect(FolderCancelRect(), x, y)) {
          DestroyWindow(hwnd);
          return 0;
        }
        if (PointInRect(FolderConfirmRect(), x, y)) {
          SubmitFolderCreate(state, hwnd);
          return 0;
        }
        const auto& icons = FolderIconChoices();
        for (int index = 0; index < static_cast<int>(icons.size()); index++) {
          if (PointInRect(FolderIconRect(index), x, y)) {
            state->selected_icon = icons[index];
            InvalidateRect(hwnd, nullptr, TRUE);
            return 0;
          }
        }
        RECT add_rect{20, 298, 180, 338};
        if (PointInRect(add_rect, x, y)) {
          state->selecting_rooms = true;
          ShowWindow(state->name_edit, SW_HIDE);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
        int row_y = 354;
        for (const auto& id : state->selected_room_ids) {
          RECT remove{kFolderCreateNativeWidth - 64, row_y + 2,
                      kFolderCreateNativeWidth - 18, row_y + 32};
          if (PointInRect(remove, x, y)) {
            ToggleFolderRoom(state, id);
            InvalidateRect(hwnd, nullptr, TRUE);
            return 0;
          }
          row_y += 44;
        }
      }
      if (y < 34) {
        ReleaseCapture();
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      }
      return 0;
    }
    case WM_PAINT:
      if (state) {
        DrawFolderCreate(state, hwnd);
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (g_active_folder_create_popup == hwnd) {
        g_active_folder_create_popup = nullptr;
      }
      if (state) {
        InvokeFolderClosed(state);
        if (state->edit_font) {
          DeleteObject(state->edit_font);
        }
        delete state;
      }
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

RECT NewChatConfirmRect() {
  return RECT{180, kNewChatNativeHeight - 61, 260,
              kNewChatNativeHeight - 23};
}

RECT NewChatCancelRect() {
  return RECT{270, kNewChatNativeHeight - 61, 350,
              kNewChatNativeHeight - 23};
}

RECT NewChatNameInputRect() {
  return RECT{24, 224, kNewChatNativeWidth - 78, 250};
}

std::wstring NewChatSearchText(NewChatState* state) {
  return state ? WindowText(state->search_edit) : std::wstring();
}

std::wstring NewChatRoomName(NewChatState* state) {
  return state ? WindowText(state->name_edit) : std::wstring();
}

std::wstring LowercaseCopy(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t character) {
                   return static_cast<wchar_t>(std::towlower(character));
                 });
  return value;
}

bool ContainsFolded(const std::wstring& value, const std::wstring& query) {
  if (query.empty()) {
    return true;
  }
  return LowercaseCopy(value).find(LowercaseCopy(query)) != std::wstring::npos;
}

bool NewChatUserSelected(NewChatState* state, const std::string& user_id) {
  if (!state) {
    return false;
  }
  return StringListContains(state->selected_user_ids, user_id);
}

void ToggleNewChatUser(NewChatState* state, const std::string& user_id) {
  if (!state) {
    return;
  }
  auto iterator = std::find(state->selected_user_ids.begin(),
                            state->selected_user_ids.end(), user_id);
  if (iterator == state->selected_user_ids.end()) {
    state->selected_user_ids.push_back(user_id);
  } else {
    state->selected_user_ids.erase(iterator);
  }
}

const NewChatUserState* NewChatUserById(NewChatState* state,
                                        const std::string& user_id) {
  if (!state) {
    return nullptr;
  }
  auto iterator = std::find_if(
      state->users.begin(), state->users.end(),
      [&](const NewChatUserState& user) { return user.id == user_id; });
  return iterator == state->users.end() ? nullptr : &(*iterator);
}

std::wstring NewChatUserDisplayName(const NewChatUserState& user) {
  return user.nickname.empty() ? user.name : user.nickname;
}

std::wstring NewChatDefaultTitle(NewChatState* state) {
  if (!state) {
    return std::wstring();
  }
  std::wstring title;
  int count = 0;
  for (const auto& user_id : state->selected_user_ids) {
    const NewChatUserState* user = NewChatUserById(state, user_id);
    if (!user) {
      continue;
    }
    if (!title.empty()) {
      title += L", ";
    }
    title += NewChatUserDisplayName(*user);
    count++;
    if (count >= 8) {
      break;
    }
  }
  if (title.size() > 50) {
    title = title.substr(0, 47) + L"...";
  }
  return title;
}

std::vector<int> NewChatFilteredIndices(NewChatState* state) {
  std::vector<int> indices;
  if (!state) {
    return indices;
  }
  std::wstring query = NewChatSearchText(state);
  for (int index = 0; index < static_cast<int>(state->users.size()); index++) {
    const NewChatUserState& user = state->users[index];
    std::wstring searchable = user.name + L" " + user.nickname + L" " +
                              Utf16FromUtf8(user.email);
    if (ContainsFolded(searchable, query)) {
      indices.push_back(index);
    }
  }
  return indices;
}

RECT NewChatChipRect(int index, int x, int y, const std::wstring& label) {
  int width = std::max(48, std::min(116, 34 + static_cast<int>(label.size()) * 12));
  return RECT{x, y, x + width, y + 31};
}

void DrawNewChatButtons(HDC hdc, bool enabled, HFONT font) {
  RECT confirm = NewChatConfirmRect();
  RECT cancel = NewChatCancelRect();
  DrawSmoothRoundedRect(
      hdc, confirm, 4,
      enabled ? RGB(255, 223, 0) : RGB(245, 245, 245),
      enabled ? RGB(255, 223, 0) : RGB(245, 245, 245));
  DrawTextBlock(hdc, L"\xD655\xC778", confirm, font,
                enabled ? RGB(0, 0, 0) : RGB(170, 170, 170),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DrawSmoothRoundedRect(hdc, cancel, 4, RGB(255, 255, 255),
                        RGB(225, 225, 225));
  DrawTextBlock(hdc, L"\xCDE8\xC18C", cancel, font, RGB(0, 0, 0),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

void DrawNewChatSelectedChips(HDC hdc,
                              NewChatState* state,
                              HFONT font) {
  if (!state || state->selected_user_ids.empty()) {
    return;
  }
  int x = 22;
  int y = 86;
  for (int index = 0; index < static_cast<int>(state->selected_user_ids.size());
       index++) {
    const NewChatUserState* user =
        NewChatUserById(state, state->selected_user_ids[index]);
    if (!user) {
      continue;
    }
    std::wstring label = NewChatUserDisplayName(*user);
    RECT chip = NewChatChipRect(index, x, y, label);
    DrawSmoothRoundedRect(hdc, chip, 15, RGB(255, 255, 255),
                          RGB(130, 130, 130));
    RECT text{chip.left + 12, chip.top, chip.right - 22, chip.bottom};
    DrawTextBlock(hdc, label, text, font, RGB(0, 0, 0),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    RECT close{chip.right - 22, chip.top, chip.right - 6, chip.bottom};
    DrawTextBlock(hdc, L"\x00D7", close, font, RGB(0, 0, 0),
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    x = chip.right + 8;
    if (x > kNewChatNativeWidth - 70) {
      break;
    }
  }
}

void DrawNewChatGroupAvatar(HDC hdc, NewChatState* state, int x, int y) {
  if (!state) {
    return;
  }
  if (!state->avatar_image_url.empty()) {
    DrawSmoothAvatar(hdc, x, y, 96, RGB(166, 198, 238),
                     state->avatar_image_url);
  } else {
    int size = 48;
    for (int index = 0; index < 4; index++) {
      COLORREF color = RGB(166, 198, 238);
      std::string image_url;
      if (index < static_cast<int>(state->selected_user_ids.size())) {
        const NewChatUserState* user =
            NewChatUserById(state, state->selected_user_ids[index]);
        if (user) {
          color = user->avatar_color;
          image_url = user->avatar_image_url;
        }
      }
      DrawSmoothAvatar(hdc, x + (index % 2) * size, y + (index / 2) * size,
                       size, color, image_url);
    }
  }

  RECT camera{x + 66, y + 66, x + 98, y + 98};
  DrawCameraButton(hdc, camera);
}

void DrawNewChatPopup(NewChatState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  DrawCloseButton(hdc, kNewChatNativeWidth);
  HFONT title_font = CreateUiFont(13, FW_NORMAL);
  HFONT label_font = CreateUiFont(10, FW_NORMAL);
  HFONT small_font = CreateUiFont(9, FW_NORMAL);
  HFONT button_font = CreateUiFont(10, FW_NORMAL);

  if (state->step == 0) {
    std::wstring title = L"\xB300\xD654\xC0C1\xB300 \xC120\xD0DD";
    if (!state->selected_user_ids.empty()) {
      title += L" " + std::to_wstring(state->selected_user_ids.size());
    }
    DrawTextBlock(hdc, title, RECT{20, 36, 260, 60}, title_font,
                  RGB(0, 0, 0), DT_LEFT | DT_VCENTER | DT_SINGLELINE);

    bool has_selection = !state->selected_user_ids.empty();
    DrawNewChatSelectedChips(hdc, state, label_font);

    int search_top = has_selection ? 140 : 86;
    RECT search{20, search_top, kNewChatNativeWidth - 18, search_top + 36};
    DrawSmoothRoundedRect(hdc, search, 18, RGB(245, 245, 245),
                          RGB(245, 245, 245));
    DrawMagnifierIcon(hdc, 34, search_top + 10, 16, RGB(150, 150, 150));
    std::wstring query = NewChatSearchText(state);
    if (!query.empty()) {
      RECT clear{kNewChatNativeWidth - 48, search_top + 8,
                 kNewChatNativeWidth - 28, search_top + 28};
      DrawSmoothCircleFill(hdc, clear.left, clear.top, 18, RGB(160, 160, 160));
      DrawTextBlock(hdc, L"\x00D7", clear, small_font, RGB(255, 255, 255),
                    DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    }
    if (state->search_edit) {
      MoveWindow(state->search_edit, 58, search_top + 8,
                 kNewChatNativeWidth - 114, 22, TRUE);
      ShowWindow(state->search_edit, SW_SHOW);
    }
    if (state->name_edit) {
      ShowWindow(state->name_edit, SW_HIDE);
    }

    int label_top = search_top + 48;
    if (state->selected_user_ids.size() > 1) {
      int group_y = label_top;
      for (int index = 0;
           index < std::min(4, static_cast<int>(state->selected_user_ids.size()));
           index++) {
        const NewChatUserState* user =
            NewChatUserById(state, state->selected_user_ids[index]);
        if (!user) {
          continue;
        }
        DrawSmoothAvatar(hdc, 22 + (index % 2) * 18,
                         group_y + 7 + (index / 2) * 18, 20,
                         user->avatar_color, user->avatar_image_url);
      }
      DrawTextBlock(
          hdc,
          L"\xC120\xD0DD\xD55C \xCE5C\xAD6C\xB4E4\xC774 \xCC38\xC5EC \xC911\xC778 \xCC44\xD305\xBC29 1",
          RECT{74, group_y + 10, kNewChatNativeWidth - 24, group_y + 42},
          label_font, RGB(0, 0, 0),
          DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
      HPEN separator = CreatePen(PS_SOLID, 1, RGB(235, 235, 235));
      HGDIOBJ old_pen = SelectObject(hdc, separator);
      MoveToEx(hdc, 22, group_y + 58, nullptr);
      LineTo(hdc, kNewChatNativeWidth - 20, group_y + 58);
      SelectObject(hdc, old_pen);
      DeleteObject(separator);
      label_top += 74;
    }
    auto indices = NewChatFilteredIndices(state);
    DrawTextBlock(hdc,
                  L"\xCE5C\xAD6C " + std::to_wstring(indices.size()),
                  RECT{20, label_top, 130, label_top + 22}, small_font,
                  RGB(110, 110, 110), DT_LEFT | DT_VCENTER | DT_SINGLELINE);

    int list_top = label_top + 28;
    int list_bottom = kNewChatNativeHeight - 82;
    int row_height = 56;
    int visible_count = std::max(1, (list_bottom - list_top) / row_height);
    int max_offset =
        std::max(0, static_cast<int>(indices.size()) - visible_count);
    state->scroll_offset = std::max(0, std::min(state->scroll_offset, max_offset));

    for (int visible = 0; visible < visible_count; visible++) {
      int filtered_index = state->scroll_offset + visible;
      if (filtered_index >= static_cast<int>(indices.size())) {
        break;
      }
      const NewChatUserState& user = state->users[indices[filtered_index]];
      int y = list_top + visible * row_height;
      bool selected = NewChatUserSelected(state, user.id);
      if (selected) {
        RECT selected_rect{14, y - 2, kNewChatNativeWidth - 14,
                           y + row_height - 2};
        DrawSmoothRoundedRect(hdc, selected_rect, 0, RGB(239, 239, 239),
                              RGB(239, 239, 239));
      }
      DrawSmoothAvatar(hdc, 20, y + 8, 40, user.avatar_color,
                       user.avatar_image_url);
      DrawTextBlock(hdc, NewChatUserDisplayName(user),
                    RECT{74, y + 9, kNewChatNativeWidth - 58, y + 47},
                    label_font, RGB(0, 0, 0),
                    DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
      RECT circle{kNewChatNativeWidth - 46, y + 16, kNewChatNativeWidth - 22,
                  y + 40};
      DrawCheckCircle(hdc, circle, selected);
    }

    if (indices.size() > static_cast<size_t>(visible_count)) {
      RECT bar{kNewChatNativeWidth - 8, list_top, kNewChatNativeWidth - 4,
               list_top + visible_count * row_height};
      HBRUSH track = CreateSolidBrush(RGB(238, 238, 238));
      FillRect(hdc, &bar, track);
      DeleteObject(track);
      int thumb_height = std::max(
          28, (visible_count * row_height * visible_count) /
                  static_cast<int>(indices.size()));
      int thumb_top =
          list_top + ((visible_count * row_height - thumb_height) *
                      state->scroll_offset) /
                         std::max(1, max_offset);
      RECT thumb{kNewChatNativeWidth - 9, thumb_top, kNewChatNativeWidth - 3,
                 thumb_top + thumb_height};
      HBRUSH thumb_brush = CreateSolidBrush(RGB(190, 190, 190));
      FillRect(hdc, &thumb, thumb_brush);
      DeleteObject(thumb_brush);
    }

    DrawNewChatButtons(hdc, !state->selected_user_ids.empty(), button_font);
  } else {
    if (state->search_edit) {
      ShowWindow(state->search_edit, SW_HIDE);
    }
    std::wstring name = NewChatRoomName(state);
    bool show_name_edit = state->room_name_editing || !name.empty();
    if (state->name_edit) {
      ShowWindow(state->name_edit, show_name_edit ? SW_SHOW : SW_HIDE);
      RECT input = NewChatNameInputRect();
      MoveWindow(state->name_edit, input.left, input.top,
                 input.right - input.left, input.bottom - input.top, TRUE);
    }

    DrawTextBlock(hdc, L"\xADF8\xB8F9\xCC44\xD305\xBC29 \xC815\xBCF4 \xC124\xC815",
                  RECT{20, 36, 300, 60}, title_font, RGB(0, 0, 0),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    DrawNewChatGroupAvatar(hdc, state, 136, 86);

    if (!show_name_edit) {
      RECT placeholder = NewChatNameInputRect();
      placeholder.right = kNewChatNativeWidth - 74;
      DrawTextBlock(hdc, NewChatDefaultTitle(state), placeholder, label_font,
                    RGB(130, 130, 130),
                    DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    }
    RECT count{kNewChatNativeWidth - 62, 224, kNewChatNativeWidth - 20, 250};
    DrawTextBlock(hdc, std::to_wstring(name.size()) + L"/50", count,
                  small_font, RGB(110, 110, 110),
                  DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
    HPEN line = CreatePen(PS_SOLID, 1, RGB(224, 224, 224));
    HGDIOBJ old_pen = SelectObject(hdc, line);
    MoveToEx(hdc, 24, 254, nullptr);
    LineTo(hdc, kNewChatNativeWidth - 22, 254);
    SelectObject(hdc, old_pen);
    DeleteObject(line);

    DrawTextBlock(
        hdc,
        L"\xCC44\xD305\xC2DC\xC791 \xC804 \xC124\xC815\xD55C \xADF8\xB8F9\xCC44\xD305\xBC29\xC758 \xC0AC\xC9C4\xACFC \xC774\xB984\xC740 \xB2E4\xB978 \xBAA8\xB4E0",
        RECT{24, 278, kNewChatNativeWidth - 24, 300}, small_font,
        RGB(90, 90, 90), DT_LEFT | DT_TOP | DT_SINGLELINE);
    DrawTextBlock(
        hdc,
        L"\xB300\xD654\xC0C1\xB300\xC5D0\xAC8C\xB3C4 \xB3D9\xC77C\xD558\xAC8C \xBCF4\xC785\xB2C8\xB2E4.",
        RECT{24, 300, kNewChatNativeWidth - 24, 322}, small_font,
        RGB(90, 90, 90), DT_LEFT | DT_TOP | DT_SINGLELINE);
    DrawTextBlock(
        hdc,
        L"\xCD94\xAC00\xC218\xC815\xC740 \"\xBA54\xB274 > \xCC44\xD305\xBC29 \xC124\xC815\"\xC744 \xC774\xC6A9\xD574 \xC8FC\xC138\xC694.",
        RECT{24, 322, kNewChatNativeWidth - 24, 344}, small_font,
        RGB(90, 90, 90), DT_LEFT | DT_TOP | DT_SINGLELINE);

    DrawNewChatButtons(hdc, true, button_font);
  }

  DeleteObject(title_font);
  DeleteObject(label_font);
  DeleteObject(small_font);
  DeleteObject(button_font);
  EndPaint(hwnd, &paint);
}

void InvokeNewChatClosed(NewChatState* state) {
  if (!state || !state->channel || state->submitted) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(std::string("closed"));
  state->channel->InvokeMethod(
      "newChatPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void SubmitNewChat(NewChatState* state, HWND hwnd) {
  if (!state || !state->channel || state->selected_user_ids.empty()) {
    return;
  }
  flutter::EncodableList user_ids;
  for (const auto& user_id : state->selected_user_ids) {
    user_ids.push_back(flutter::EncodableValue(user_id));
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(std::string("create"));
  arguments[flutter::EncodableValue("userIds")] =
      flutter::EncodableValue(user_ids);
  arguments[flutter::EncodableValue("title")] =
      flutter::EncodableValue(Utf8FromUtf16(NewChatRoomName(state).c_str()));
  arguments[flutter::EncodableValue("avatarImageUrl")] =
      flutter::EncodableValue(state->avatar_image_url);
  state->submitted = true;
  state->channel->InvokeMethod(
      "newChatPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

LRESULT CALLBACK NewChatWndProc(HWND hwnd,
                                UINT message,
                                WPARAM wparam,
                                LPARAM lparam) {
  auto* state =
      reinterpret_cast<NewChatState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<NewChatState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_CREATE:
      if (state) {
        state->edit_font = CreateUiFont(11, FW_NORMAL);
        state->search_edit = CreateWindowExW(
            0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 58, 94,
            kNewChatNativeWidth - 114, 22, hwnd,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kNewChatSearchEditId)),
            GetModuleHandle(nullptr), nullptr);
        SendMessage(state->search_edit, WM_SETFONT,
                    reinterpret_cast<WPARAM>(state->edit_font), TRUE);
        SendMessageW(state->search_edit, EM_SETCUEBANNER, FALSE,
                     reinterpret_cast<LPARAM>(L"\xC774\xB984 \xAC80\xC0C9"));

        state->name_edit = CreateWindowExW(
            0, L"EDIT", L"", WS_CHILD | ES_AUTOHSCROLL, 24, 224,
            kNewChatNativeWidth - 78, 26, hwnd,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(kNewChatNameEditId)),
            GetModuleHandle(nullptr), nullptr);
        SendMessage(state->name_edit, WM_SETFONT,
                    reinterpret_cast<WPARAM>(state->edit_font), TRUE);
        std::wstring cue = NewChatDefaultTitle(state);
        SendMessageW(state->name_edit, EM_SETCUEBANNER, TRUE,
                     reinterpret_cast<LPARAM>(cue.c_str()));
      }
      return 0;
    case WM_CTLCOLOREDIT: {
      if (state && (reinterpret_cast<HWND>(lparam) == state->search_edit ||
                    reinterpret_cast<HWND>(lparam) == state->name_edit)) {
        HDC edit_dc = reinterpret_cast<HDC>(wparam);
        SetTextColor(edit_dc, RGB(0, 0, 0));
        HWND edit = reinterpret_cast<HWND>(lparam);
        COLORREF background =
            edit == state->search_edit ? RGB(245, 245, 245) : RGB(255, 255, 255);
        SetBkColor(edit_dc, background);
        SetBkMode(edit_dc, OPAQUE);
        static HBRUSH search_brush = CreateSolidBrush(RGB(245, 245, 245));
        static HBRUSH white_brush = CreateSolidBrush(RGB(255, 255, 255));
        return reinterpret_cast<INT_PTR>(
            edit == state->search_edit ? search_brush : white_brush);
      }
      break;
    }
    case WM_COMMAND:
      if (LOWORD(wparam) == kNewChatSearchEditId ||
          LOWORD(wparam) == kNewChatNameEditId) {
        if (state) {
          if (LOWORD(wparam) == kNewChatSearchEditId) {
            state->scroll_offset = 0;
          }
          if (LOWORD(wparam) == kNewChatNameEditId) {
            if (HIWORD(wparam) == EN_SETFOCUS) {
              state->room_name_editing = true;
            } else if (HIWORD(wparam) == EN_KILLFOCUS &&
                       NewChatRoomName(state).empty()) {
              state->room_name_editing = false;
            }
          }
        }
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      break;
    case WM_MOUSEWHEEL:
      if (state && state->step == 0) {
        int delta = GET_WHEEL_DELTA_WPARAM(wparam);
        state->scroll_offset += delta < 0 ? 1 : -1;
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      break;
    case WM_LBUTTONDOWN: {
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (PointInRect(CloseButtonRect(kNewChatNativeWidth), x, y)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (!state) {
        return 0;
      }
      if (PointInRect(NewChatCancelRect(), x, y)) {
        if (state->step == 1) {
          state->step = 0;
          state->room_name_editing = false;
          ShowWindow(state->name_edit, SW_HIDE);
          ShowWindow(state->search_edit, SW_SHOW);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
        DestroyWindow(hwnd);
        return 0;
      }
      if (PointInRect(NewChatConfirmRect(), x, y)) {
        if (state->selected_user_ids.empty()) {
          return 0;
        }
        if (state->step == 0) {
          state->step = 1;
          state->room_name_editing = false;
          SetWindowTextW(state->name_edit, L"");
          std::wstring cue = NewChatDefaultTitle(state);
          SendMessageW(state->name_edit, EM_SETCUEBANNER, TRUE,
                       reinterpret_cast<LPARAM>(cue.c_str()));
          ShowWindow(state->search_edit, SW_HIDE);
          ShowWindow(state->name_edit, SW_HIDE);
          SetFocus(hwnd);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
        SubmitNewChat(state, hwnd);
        return 0;
      }

      if (state->step == 0) {
        bool has_selection = !state->selected_user_ids.empty();
        if (has_selection) {
          int chip_x = 22;
          int chip_y = 86;
          for (const auto& user_id : state->selected_user_ids) {
            const NewChatUserState* user = NewChatUserById(state, user_id);
            if (!user) {
              continue;
            }
            RECT chip =
                NewChatChipRect(0, chip_x, chip_y, NewChatUserDisplayName(*user));
            if (PointInRect(chip, x, y)) {
              ToggleNewChatUser(state, user_id);
              InvalidateRect(hwnd, nullptr, TRUE);
              return 0;
            }
            chip_x = chip.right + 8;
            if (chip_x > kNewChatNativeWidth - 70) {
              break;
            }
          }
        }
        int search_top = has_selection ? 140 : 86;
        RECT clear{kNewChatNativeWidth - 48, search_top + 8,
                   kNewChatNativeWidth - 28, search_top + 28};
        if (!NewChatSearchText(state).empty() && PointInRect(clear, x, y)) {
          SetWindowTextW(state->search_edit, L"");
          state->scroll_offset = 0;
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }

        int label_top = search_top + 48;
        if (state->selected_user_ids.size() > 1) {
          label_top += 74;
        }
        int list_top = label_top + 28;
        int list_bottom = kNewChatNativeHeight - 82;
        int row_height = 56;
        auto indices = NewChatFilteredIndices(state);
        int visible_count = std::max(1, (list_bottom - list_top) / row_height);
        if (y >= list_top && y < list_top + row_height * visible_count) {
          int filtered_index = state->scroll_offset + ((y - list_top) / row_height);
          if (filtered_index >= 0 &&
              filtered_index < static_cast<int>(indices.size())) {
            ToggleNewChatUser(state, state->users[indices[filtered_index]].id);
            InvalidateRect(hwnd, nullptr, TRUE);
          }
          return 0;
        }
      } else {
        RECT input = NewChatNameInputRect();
        RECT input_hit{input.left, input.top - 4, kNewChatNativeWidth - 20,
                       input.bottom + 8};
        if (PointInRect(input_hit, x, y)) {
          state->room_name_editing = true;
          ShowWindow(state->name_edit, SW_SHOW);
          SetFocus(state->name_edit);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
        if (NewChatRoomName(state).empty()) {
          state->room_name_editing = false;
          ShowWindow(state->name_edit, SW_HIDE);
        }
        RECT camera{202, 152, 234, 184};
        if (PointInRect(camera, x, y)) {
          std::wstring path = OpenProfileImageFile(hwnd);
          if (!path.empty()) {
            std::string data_uri = DataUriForImagePath(path);
            if (!data_uri.empty()) {
              state->avatar_image_url = data_uri;
              InvalidateRect(hwnd, nullptr, TRUE);
            }
          }
          return 0;
        }
      }

      if (y < 34) {
        ReleaseCapture();
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      }
      return 0;
    }
    case WM_PAINT:
      if (state) {
        DrawNewChatPopup(state, hwnd);
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (g_active_new_chat_popup == hwnd) {
        g_active_new_chat_popup = nullptr;
      }
      if (state) {
        InvokeNewChatClosed(state);
        if (state->edit_font) {
          DeleteObject(state->edit_font);
        }
        delete state;
      }
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

RECT FolderManageBottomRect() {
  return RECT{0, kFolderManageNativeHeight - 46, kFolderManageNativeWidth,
              kFolderManageNativeHeight};
}

RECT FolderManageRecommendedRect(int top) {
  return RECT{22, top, kFolderManageNativeWidth - 18, top + 52};
}

void InvokeFolderManageAction(FolderManageState* state,
                              const std::string& action,
                              const std::string& folder_id = std::string()) {
  if (!state || !state->channel) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(action);
  if (!folder_id.empty()) {
    arguments[flutter::EncodableValue("folderId")] =
        flutter::EncodableValue(folder_id);
  }
  state->submitted = true;
  state->channel->InvokeMethod(
      "folderPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void InvokeFolderManageReorder(FolderManageState* state) {
  if (!state || !state->channel) {
    return;
  }
  flutter::EncodableList folder_ids;
  for (const auto& folder : state->folders) {
    folder_ids.push_back(flutter::EncodableValue(folder.id));
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(std::string("reorderFolders"));
  arguments[flutter::EncodableValue("folderIds")] =
      flutter::EncodableValue(folder_ids);
  state->channel->InvokeMethod(
      "folderPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void InvokeFolderManageClosed(FolderManageState* state) {
  if (!state || !state->channel || state->submitted) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(std::string("closed"));
  state->channel->InvokeMethod(
      "folderPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

COLORREF FolderManageIconColor(const std::wstring& icon) {
  const std::wstring normalized = NormalizeFolderIconToken(icon);
  if (normalized == L"\x2605" || normalized == L"\x2B50") {
    return RGB(255, 160, 0);
  }
  if (normalized == L"\x2302" || normalized == L"\xD83C\xDFE0") {
    return RGB(255, 111, 60);
  }
  if (normalized == L"\x25A0" || normalized == L"\xD83D\xDCBC") {
    return RGB(138, 90, 40);
  }
  if (normalized == L"\x2665" || normalized == L"\xD83D\xDC97") {
    return RGB(255, 91, 158);
  }
  if (normalized == L"\x270E" || normalized == L"\x270F") {
    return RGB(255, 122, 26);
  }
  if (normalized == L"\x25A3" || normalized == L"\xD83E\xDDFA") {
    return RGB(232, 77, 91);
  }
  if (normalized == L"\x25AC" || normalized == L"\xD83D\xDCB3") {
    return RGB(61, 139, 255);
  }
  if (normalized == L"\x2708") {
    return RGB(74, 144, 226);
  }
  if (normalized == L"\x271A" || normalized == L"\x2795") {
    return RGB(0, 168, 107);
  }
  if (normalized == L"\xD83D\xDCAC") {
    return RGB(82, 167, 244);
  }
  return RGB(82, 167, 244);
}

void InvokeFolderSubmenuAction(FolderSubmenuState* state,
                               const std::string& result) {
  if (!state || !state->channel || result.empty()) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("result")] =
      flutter::EncodableValue(result);
  state->channel->InvokeMethod(
      "folderSubmenuAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void DrawFolderSubmenu(FolderSubmenuState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);

  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  HPEN border = CreatePen(PS_SOLID, 1, RGB(199, 199, 199));
  HGDIOBJ old_pen = SelectObject(hdc, border);
  HGDIOBJ old_brush = SelectObject(hdc, GetStockObject(NULL_BRUSH));
  Rectangle(hdc, 0, 0, client.right, client.bottom);
  SelectObject(hdc, old_brush);
  SelectObject(hdc, old_pen);
  DeleteObject(border);

  HFONT font = CreateUiFont(9, FW_NORMAL);
  for (int index = 0; index < static_cast<int>(state->folders.size());
       index++) {
    int top = index * kFolderSubmenuRowHeight;
    RECT row{1, top + 1, client.right - 1, top + kFolderSubmenuRowHeight};
    if (state->hovered_index == index) {
      HBRUSH hover = CreateSolidBrush(RGB(239, 239, 239));
      FillRect(hdc, &row, hover);
      DeleteObject(hover);
    }
    const auto& folder = state->folders[index];
    DrawFolderIconGlyph(
        hdc, RECT{10, top, 31, top + kFolderSubmenuRowHeight}, folder.icon, 15);
    DrawTextBlock(hdc, folder.name,
                  RECT{36, top, client.right - 8,
                       top + kFolderSubmenuRowHeight},
                  font, RGB(0, 0, 0),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  }
  DeleteObject(font);
  EndPaint(hwnd, &paint);
}

LRESULT CALLBACK FolderSubmenuWndProc(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  auto* state = reinterpret_cast<FolderSubmenuState*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state =
          reinterpret_cast<FolderSubmenuState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_CREATE:
      SetTimer(hwnd, kFolderSubmenuCloseTimer, 80, nullptr);
      return 0;
    case WM_MOUSEMOVE: {
      if (!state) {
        return 0;
      }
      int y = GET_Y_LPARAM(lparam);
      int hovered = y / kFolderSubmenuRowHeight;
      if (hovered < 0 || hovered >= static_cast<int>(state->folders.size())) {
        hovered = -1;
      }
      if (hovered != state->hovered_index) {
        state->hovered_index = hovered;
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    }
    case WM_LBUTTONDOWN: {
      if (!state) {
        return 0;
      }
      int y = GET_Y_LPARAM(lparam);
      int index = y / kFolderSubmenuRowHeight;
      if (index >= 0 && index < static_cast<int>(state->folders.size())) {
        InvokeFolderSubmenuAction(state,
                                  "folder:" + state->folders[index].id);
        DestroyWindow(hwnd);
      }
      return 0;
    }
    case WM_TIMER:
      if (wparam == kFolderSubmenuCloseTimer && state) {
        POINT cursor{};
        GetCursorPos(&cursor);
        RECT window_rect{};
        GetWindowRect(hwnd, &window_rect);
        if (!PtInRect(&state->parent_rect, cursor) &&
            !PtInRect(&window_rect, cursor)) {
          DestroyWindow(hwnd);
        }
        return 0;
      }
      break;
    case WM_PAINT:
      if (state) {
        DrawFolderSubmenu(state, hwnd);
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (g_active_folder_submenu_popup == hwnd) {
        g_active_folder_submenu_popup = nullptr;
      }
      KillTimer(hwnd, kFolderSubmenuCloseTimer);
      delete state;
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void DrawManageEditIcon(HDC hdc, RECT rect) {
  HFONT icon_font = CreateUiFont(13, FW_NORMAL);
  DrawTextBlock(hdc, L"\x270E", rect, icon_font, RGB(50, 50, 50),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DeleteObject(icon_font);
}

void DrawManageTrashIcon(HDC hdc, RECT rect) {
  HPEN pen = CreatePen(PS_SOLID, 1, RGB(50, 50, 50));
  HGDIOBJ old_pen = SelectObject(hdc, pen);
  Rectangle(hdc, rect.left + 10, rect.top + 15, rect.right - 10,
            rect.bottom - 8);
  MoveToEx(hdc, rect.left + 8, rect.top + 12, nullptr);
  LineTo(hdc, rect.right - 8, rect.top + 12);
  MoveToEx(hdc, rect.left + 13, rect.top + 9, nullptr);
  LineTo(hdc, rect.right - 13, rect.top + 9);
  MoveToEx(hdc, rect.left + 15, rect.top + 18, nullptr);
  LineTo(hdc, rect.left + 15, rect.bottom - 11);
  MoveToEx(hdc, rect.right - 15, rect.top + 18, nullptr);
  LineTo(hdc, rect.right - 15, rect.bottom - 11);
  SelectObject(hdc, old_pen);
  DeleteObject(pen);
}

void DrawFolderManageRow(HDC hdc,
                         RECT rect,
                         const std::wstring& icon,
                         const std::wstring& title,
                         int count,
                         bool can_edit,
                         bool can_delete,
                         bool is_dragging,
                         HFONT font,
                         HFONT small_font) {
  DrawFilledRoundRect(hdc, rect, 3,
                      is_dragging ? RGB(250, 250, 250) : RGB(255, 255, 255),
                      RGB(225, 225, 225));
  DrawTextBlock(hdc, L"\x2630", RECT{rect.left + 14, rect.top,
                                      rect.left + 36, rect.bottom},
                small_font, RGB(0, 0, 0),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DrawFolderIconGlyph(hdc,
                      RECT{rect.left + 42, rect.top, rect.left + 76,
                           rect.bottom},
                      icon, 15);
  std::wstring label = title;
  if (count > 0) {
    label += L" " + std::to_wstring(count);
  }
  DrawTextBlock(hdc, label, RECT{rect.left + 82, rect.top,
                                 rect.right - 82, rect.bottom},
                font, RGB(0, 0, 0), DT_LEFT | DT_VCENTER | DT_SINGLELINE |
                                      DT_END_ELLIPSIS);
  if (can_edit) {
    DrawManageEditIcon(hdc, RECT{rect.right - 78, rect.top + 8,
                                 rect.right - 48, rect.bottom - 8});
  }
  if (can_delete) {
    DrawManageTrashIcon(hdc, RECT{rect.right - 42, rect.top + 8,
                                  rect.right - 12, rect.bottom - 8});
  }
  if (is_dragging) {
    HPEN blue_pen = CreatePen(PS_SOLID, 2, RGB(73, 137, 255));
    HGDIOBJ old_pen = SelectObject(hdc, blue_pen);
    MoveToEx(hdc, rect.left, rect.bottom - 1, nullptr);
    LineTo(hdc, rect.right, rect.bottom - 1);
    SelectObject(hdc, old_pen);
    DeleteObject(blue_pen);
  }
}

void DrawFolderManage(FolderManageState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  DrawCloseButton(hdc, kFolderManageNativeWidth);
  HFONT title_font = CreateUiFont(13, FW_NORMAL);
  HFONT label_font = CreateUiFont(10, FW_NORMAL);
  HFONT small_font = CreateUiFont(10, FW_NORMAL);

  DrawTextBlock(hdc, L"\xCC44\xD305\xBC29 \xD3F4\xB354 \xAD00\xB9AC",
                RECT{20, 36, 260, 62}, title_font, RGB(0, 0, 0),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);

  int y = 72;
  for (int index = 0; index < static_cast<int>(state->folders.size());
       index++) {
    const auto& folder = state->folders[index];
    DrawFolderManageRow(hdc, RECT{22, y, kFolderManageNativeWidth - 18, y + 52},
                        folder.icon, folder.name, folder.count,
                        !folder.is_system && !folder.is_favorite,
                        !folder.is_system,
                        state->dragging && state->dragging_index == index,
                        label_font, small_font);
    y += 60;
    if (y > 390) {
      break;
    }
  }

  if (!state->has_favorite) {
    y += 10;
    DrawTextBlock(hdc, L"\xCD94\xCC9C \xD3F4\xB354",
                  RECT{22, y, 160, y + 22}, small_font, RGB(110, 110, 110),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    y += 30;
    RECT recommended = FolderManageRecommendedRect(y);
    DrawFilledRoundRect(hdc, recommended, 3, RGB(255, 255, 255),
                        RGB(225, 225, 225));
    DrawFolderIconGlyph(
        hdc,
        RECT{recommended.left + 16, recommended.top, recommended.left + 46,
             recommended.bottom},
        L"\x2605", 15);
    DrawTextBlock(hdc, L"\xC990\xACA8\xCC3E\xAE30",
                  RECT{recommended.left + 56, recommended.top,
                       recommended.right - 48, recommended.bottom},
                  label_font, RGB(0, 0, 0),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE);
    DrawTextBlock(hdc, L"+",
                  RECT{recommended.right - 44, recommended.top,
                       recommended.right - 16, recommended.bottom},
                  label_font, RGB(0, 0, 0),
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  }

  RECT line{0, kFolderManageNativeHeight - 47, kFolderManageNativeWidth,
            kFolderManageNativeHeight - 46};
  HBRUSH line_brush = CreateSolidBrush(RGB(229, 229, 229));
  FillRect(hdc, &line, line_brush);
  DeleteObject(line_brush);
  DrawTextBlock(hdc, L"+ \xD3F4\xB354 \xB9CC\xB4E4\xAE30",
                FolderManageBottomRect(), label_font, RGB(0, 0, 0),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  DeleteObject(title_font);
  DeleteObject(label_font);
  DeleteObject(small_font);
  EndPaint(hwnd, &paint);
}

LRESULT CALLBACK FolderManageWndProc(HWND hwnd,
                                      UINT message,
                                      WPARAM wparam,
                                      LPARAM lparam) {
  auto* state = reinterpret_cast<FolderManageState*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<FolderManageState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_LBUTTONDOWN: {
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (PointInRect(CloseButtonRect(kFolderManageNativeWidth), x, y)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (!state) {
        return 0;
      }
      if (PointInRect(FolderManageBottomRect(), x, y)) {
        InvokeFolderManageAction(state, "createFolder");
        DestroyWindow(hwnd);
        return 0;
      }

      int row_y = 72;
      for (int index = 0; index < static_cast<int>(state->folders.size());
           index++) {
        const auto& folder = state->folders[index];
        RECT row{22, row_y, kFolderManageNativeWidth - 18, row_y + 52};
        RECT drag_rect{row.left, row.top, row.left + 42, row.bottom};
        RECT edit_rect{row.right - 82, row.top, row.right - 46, row.bottom};
        RECT delete_rect{row.right - 46, row.top, row.right, row.bottom};
        if (PointInRect(drag_rect, x, y)) {
          state->dragging = true;
          state->dragging_index = index;
          SetCapture(hwnd);
          InvalidateRect(hwnd, nullptr, TRUE);
          return 0;
        }
        if (!folder.is_system && !folder.is_favorite &&
            PointInRect(edit_rect, x, y)) {
          InvokeFolderManageAction(state, "editFolder", folder.id);
          DestroyWindow(hwnd);
          return 0;
        }
        if (!folder.is_system && PointInRect(delete_rect, x, y)) {
          InvokeFolderManageAction(state, "deleteFolder", folder.id);
          DestroyWindow(hwnd);
          return 0;
        }
        row_y += 60;
        if (row_y > 390) {
          break;
        }
      }

      if (!state->has_favorite) {
        int recommended_top = 72 + static_cast<int>(
            std::min<size_t>(state->folders.size(), 5)) * 60 + 40;
        RECT recommended = FolderManageRecommendedRect(recommended_top);
        if (PointInRect(recommended, x, y)) {
          InvokeFolderManageAction(state, "addFavorite");
          DestroyWindow(hwnd);
          return 0;
        }
      }

      if (y < 34) {
        ReleaseCapture();
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      }
      return 0;
    }
    case WM_MOUSEMOVE:
      if (state && state->dragging && state->dragging_index >= 0) {
        int y = GET_Y_LPARAM(lparam);
        int target = (y - 72) / 60;
        int max_index = static_cast<int>(state->folders.size()) - 1;
        target = std::max(0, std::min(target, max_index));
        if (target != state->dragging_index) {
          auto item = state->folders[state->dragging_index];
          state->folders.erase(state->folders.begin() + state->dragging_index);
          state->folders.insert(state->folders.begin() + target, item);
          state->dragging_index = target;
          InvokeFolderManageReorder(state);
          InvalidateRect(hwnd, nullptr, TRUE);
        }
        return 0;
      }
      break;
    case WM_LBUTTONUP:
      if (state && state->dragging) {
        state->dragging = false;
        state->dragging_index = -1;
        ReleaseCapture();
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      break;
    case WM_PAINT:
      if (state) {
        DrawFolderManage(state, hwnd);
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (g_active_folder_manage_popup == hwnd) {
        g_active_folder_manage_popup = nullptr;
      }
      if (state) {
        InvokeFolderManageClosed(state);
        delete state;
      }
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void InvokeQuietRoomsAction(QuietRoomsState* state,
                            const std::string& action,
                            const std::string& room_id = std::string()) {
  if (!state || !state->channel) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(action);
  if (!room_id.empty()) {
    arguments[flutter::EncodableValue("roomId")] =
        flutter::EncodableValue(room_id);
  }
  state->channel->InvokeMethod(
      "quietRoomsPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void DrawQuietToast(QuietToastState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH black = CreateSolidBrush(RGB(0, 0, 0));
  FillRect(hdc, &client, black);
  DeleteObject(black);
  HFONT font = CreateUiFont(10, FW_SEMIBOLD);
  DrawTextBlock(hdc,
                state && !state->message.empty()
                    ? state->message
                    : L"\xC870\xC6A9\xD55C \xCC44\xD305\xBC29\xC5D0\xC11C \xD574\xC81C\xB418\xC5C8\xC2B5\xB2C8\xB2E4.",
                client, font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  DeleteObject(font);
  EndPaint(hwnd, &paint);
}

LRESULT CALLBACK QuietToastWndProc(HWND hwnd,
                                   UINT message,
                                   WPARAM wparam,
                                   LPARAM lparam) {
  auto* state =
      reinterpret_cast<QuietToastState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<QuietToastState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_CREATE:
      SetTimer(hwnd, kQuietToastTimer, 1000, nullptr);
      return 0;
    case WM_TIMER:
      if (wparam == kQuietToastTimer) {
        DestroyWindow(hwnd);
        return 0;
      }
      break;
    case WM_PAINT:
      DrawQuietToast(state, hwnd);
      return 0;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (g_active_quiet_toast == hwnd) {
        g_active_quiet_toast = nullptr;
      }
      KillTimer(hwnd, kQuietToastTimer);
      delete state;
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void RegisterQuietToastClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kQuietToastClassName;
  window_class.lpfnWndProc = QuietToastWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void ShowNativeQuietToast(HWND owner) {
  RegisterQuietToastClass();
  if (g_active_quiet_toast) {
    DestroyWindow(g_active_quiet_toast);
    g_active_quiet_toast = nullptr;
  }
  HWND root_owner = GetWindow(owner, GW_OWNER);
  if (root_owner) {
    owner = root_owner;
  }
  RECT owner_rect{};
  GetWindowRect(owner, &owner_rect);
  int x = owner_rect.left + ((owner_rect.right - owner_rect.left -
                              kQuietToastWidth) /
                             2);
  int y = owner_rect.top + ((owner_rect.bottom - owner_rect.top) / 2);
  auto* state = new QuietToastState();
  state->message =
      L"\xC870\xC6A9\xD55C \xCC44\xD305\xBC29\xC5D0\xC11C \xD574\xC81C\xB418\xC5C8\xC2B5\xB2C8\xB2E4.";
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED,
      kQuietToastClassName,
      L"AVA Quiet Toast",
      WS_POPUP,
      x,
      y,
      kQuietToastWidth,
      kQuietToastHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kQuietToastWidth, kQuietToastHeight);
  SetLayeredWindowAttributes(window, 0, 189, LWA_ALPHA);
  g_active_quiet_toast = window;
  ShowWindow(window, SW_SHOWNOACTIVATE);
}

void DrawQuietRooms(QuietRoomsState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  DrawCloseButton(hdc, kQuietRoomsNativeWidth);
  HFONT title_font = CreateUiFont(13, FW_NORMAL);
  HFONT small_font = CreateUiFont(9, FW_NORMAL);
  HFONT room_font = CreateUiFont(10, FW_BOLD);
  HFONT preview_font = CreateUiFont(10, FW_NORMAL);

  DrawTextBlock(hdc, L"\xC870\xC6A9\xD55C \xCC44\xD305\xBC29",
                RECT{20, 34, 220, 58}, title_font, RGB(0, 0, 0),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  DrawTextBlock(hdc,
                L"\xD65C\xB3D9\xD558\xC9C0 \xC54A\xB294 \xCC44\xD305\xBC29\xC744 \xBCF4\xAD00\xD569\xB2C8\xB2E4. \xCC44\xD305\xBC29 \xC54C\xB9BC\xC774 \xBE44\xD65C\xC131\xD654 \xB418\xBA70",
                RECT{20, 68, kQuietRoomsNativeWidth - 20, 86}, small_font,
                RGB(80, 80, 80), DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  DrawTextBlock(hdc,
                L"\xC548 \xC77D\xC740 \xBA54\xC2DC\xC9C0 \xC218\xC5D0 \xD3EC\xD568\xB418\xC9C0 \xC54A\xC2B5\xB2C8\xB2E4.",
                RECT{20, 86, kQuietRoomsNativeWidth - 20, 104}, small_font,
                RGB(80, 80, 80), DT_LEFT | DT_VCENTER | DT_SINGLELINE);

  int y = 114;
  for (int index = 0; index < static_cast<int>(state->rooms.size());
       index++) {
    const auto& room = state->rooms[index];
    RECT row{14, y, kQuietRoomsNativeWidth - 14, y + kQuietRoomsRowHeight};
    if (state->hovered_index == index) {
      HBRUSH hover = CreateSolidBrush(RGB(239, 239, 239));
      FillRect(hdc, &row, hover);
      DeleteObject(hover);
    }

    FolderRoomState avatar;
    avatar.avatar_color = room.avatar_color;
    avatar.is_group = room.is_group;
    avatar.avatar_image_url = room.avatar_image_url;
    avatar.avatar_parts = room.avatar_parts;
    DrawFolderAvatar(hdc, avatar, 20, y + 12, 44);

    RECT title_rect{76, y + 10, kQuietRoomsNativeWidth - 82, y + 31};
    DrawTextBlock(hdc, room.title, title_rect, room_font, RGB(0, 0, 0),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    if (room.is_muted) {
      DrawSmallMutedIcon(hdc, title_rect.right + 4, y + 14);
    }
    DrawTextBlock(hdc, room.time,
                  RECT{kQuietRoomsNativeWidth - 72, y + 12,
                       kQuietRoomsNativeWidth - 20, y + 30},
                  small_font, RGB(92, 92, 92),
                  DT_RIGHT | DT_VCENTER | DT_SINGLELINE);
    DrawTextBlock(hdc, room.preview,
                  RECT{76, y + 35, kQuietRoomsNativeWidth - 28, y + 58},
                  preview_font, RGB(80, 80, 80),
                  DT_LEFT | DT_TOP | DT_SINGLELINE | DT_END_ELLIPSIS);
    y += kQuietRoomsRowHeight;
    if (y > kQuietRoomsNativeHeight - 40) {
      break;
    }
  }

  DeleteObject(title_font);
  DeleteObject(small_font);
  DeleteObject(room_font);
  DeleteObject(preview_font);
  EndPaint(hwnd, &paint);
}

int QuietRoomIndexAt(QuietRoomsState* state, int y) {
  if (!state) {
    return -1;
  }
  int index = (y - 114) / kQuietRoomsRowHeight;
  if (y < 114 || index < 0 || index >= static_cast<int>(state->rooms.size())) {
    return -1;
  }
  return index;
}

void RemoveQuietRoomAt(HWND hwnd, QuietRoomsState* state, int index) {
  if (!state || index < 0 || index >= static_cast<int>(state->rooms.size())) {
    return;
  }
  state->rooms.erase(state->rooms.begin() + index);
  state->hovered_index = -1;
  ShowNativeQuietToast(hwnd);
  if (state->rooms.empty()) {
    DestroyWindow(hwnd);
    return;
  }
  InvalidateRect(hwnd, nullptr, TRUE);
}

void ShowQuietRoomMenu(HWND hwnd, QuietRoomsState* state, int index) {
  if (!state || index < 0 || index >= static_cast<int>(state->rooms.size())) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kQuietMenuOpenRoom,
              L"\xCC44\xD305\xBC29 \xC5F4\xAE30");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kQuietMenuRead,
              L"\xC77D\xC74C \xCC98\xB9AC        R");
  AppendMenuW(menu, MF_STRING, kQuietMenuFloating,
              L"\xD50C\xB85C\xD305 \xB760\xC6B0\xAE30");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kQuietMenuUnquiet,
              L"\xC870\xC6A9\xD55C \xCC44\xD305\xBC29\xC5D0\xC11C \xD574\xC81C");
  AppendMenuW(menu, MF_STRING, kQuietMenuLeave,
              L"\xCC44\xD305\xBC29 \xB098\xAC00\xAE30");

  POINT point{};
  GetCursorPos(&point);
  UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
      point.x, point.y, 0, hwnd, nullptr);
  DestroyMenu(menu);
  PostMessage(hwnd, WM_NULL, 0, 0);

  if (index < 0 || index >= static_cast<int>(state->rooms.size())) {
    return;
  }
  std::string room_id = state->rooms[index].id;
  switch (command) {
    case kQuietMenuOpenRoom:
      InvokeQuietRoomsAction(state, "openRoom", room_id);
      break;
    case kQuietMenuRead:
      state->rooms[index].unread_count = 0;
      InvokeQuietRoomsAction(state, "read", room_id);
      InvalidateRect(hwnd, nullptr, TRUE);
      break;
    case kQuietMenuFloating:
      InvokeQuietRoomsAction(state, "floating", room_id);
      break;
    case kQuietMenuUnquiet:
      InvokeQuietRoomsAction(state, "unquiet", room_id);
      RemoveQuietRoomAt(hwnd, state, index);
      break;
    case kQuietMenuLeave:
      InvokeQuietRoomsAction(state, "leave", room_id);
      RemoveQuietRoomAt(hwnd, state, index);
      break;
    default:
      break;
  }
}

LRESULT CALLBACK QuietRoomsWndProc(HWND hwnd,
                                   UINT message,
                                   WPARAM wparam,
                                   LPARAM lparam) {
  auto* state =
      reinterpret_cast<QuietRoomsState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<QuietRoomsState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_LBUTTONDOWN: {
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (PointInRect(CloseButtonRect(kQuietRoomsNativeWidth), x, y)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (y < 34) {
        ReleaseCapture();
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      }
      return 0;
    }
    case WM_LBUTTONDBLCLK: {
      int index = QuietRoomIndexAt(state, GET_Y_LPARAM(lparam));
      if (state && index >= 0) {
        InvokeQuietRoomsAction(state, "openRoom", state->rooms[index].id);
      }
      return 0;
    }
    case WM_MOUSEMOVE: {
      int index = QuietRoomIndexAt(state, GET_Y_LPARAM(lparam));
      if (state && index != state->hovered_index) {
        state->hovered_index = index;
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    }
    case WM_CONTEXTMENU: {
      if (!state) {
        return 0;
      }
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &point);
      int index = QuietRoomIndexAt(state, point.y);
      ShowQuietRoomMenu(hwnd, state, index);
      return 0;
    }
    case WM_PAINT:
      if (state) {
        DrawQuietRooms(state, hwnd);
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (g_active_quiet_rooms_popup == hwnd) {
        g_active_quiet_rooms_popup = nullptr;
      }
      if (state) {
        InvokeQuietRoomsAction(state, "closed");
        delete state;
      }
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void RegisterQuietRoomsClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.style = CS_DBLCLKS;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kQuietRoomsClassName;
  window_class.lpfnWndProc = QuietRoomsWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void InvokeMultiLeaveRoomsAction(
    MultiLeaveRoomsState* state,
    const std::string& action,
    const std::vector<std::string>& room_ids = std::vector<std::string>()) {
  if (!state || !state->channel) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(action);
  if (!room_ids.empty()) {
    flutter::EncodableList ids;
    for (const auto& room_id : room_ids) {
      ids.push_back(flutter::EncodableValue(room_id));
    }
    arguments[flutter::EncodableValue("roomIds")] =
        flutter::EncodableValue(ids);
  }
  state->submitted = true;
  state->channel->InvokeMethod(
      "multiLeaveRoomsPopupAction",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void ToggleMultiLeaveRoom(MultiLeaveRoomsState* state,
                          const std::string& room_id) {
  if (!state) {
    return;
  }
  auto iterator = std::find(state->selected_room_ids.begin(),
                            state->selected_room_ids.end(), room_id);
  if (iterator == state->selected_room_ids.end()) {
    state->selected_room_ids.push_back(room_id);
  } else {
    state->selected_room_ids.erase(iterator);
  }
}

RECT MultiLeaveLeaveButtonRect() {
  return RECT{90, kMultiLeaveNativeHeight - 58, 194,
              kMultiLeaveNativeHeight - 20};
}

RECT MultiLeaveCancelButtonRect() {
  return RECT{202, kMultiLeaveNativeHeight - 58, 306,
              kMultiLeaveNativeHeight - 20};
}

void DrawMultiLeaveButton(HDC hdc,
                          RECT rect,
                          const std::wstring& label,
                          bool enabled,
                          HFONT font,
                          bool primary) {
  COLORREF fill = primary
                      ? (enabled ? RGB(255, 223, 0) : RGB(244, 244, 244))
                      : RGB(255, 255, 255);
  COLORREF border = primary
                        ? fill
                        : RGB(225, 225, 225);
  COLORREF text = enabled ? RGB(0, 0, 0) : RGB(176, 176, 176);
  DrawFilledRoundRect(hdc, rect, 4, fill, border);
  DrawTextBlock(hdc, label, rect, font, text,
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
}

void DrawMultiLeaveRooms(MultiLeaveRoomsState* state, HWND hwnd) {
  PAINTSTRUCT paint;
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HBRUSH white = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(hdc, &client, white);
  DeleteObject(white);

  DrawCloseButton(hdc, kMultiLeaveNativeWidth);
  HFONT title_font = CreateUiFont(13, FW_NORMAL);
  HFONT label_font = CreateUiFont(10, FW_BOLD);
  HFONT small_font = CreateUiFont(9, FW_NORMAL);
  HFONT button_font = CreateUiFont(10, FW_NORMAL);

  DrawTextBlock(hdc, L"\xC5EC\xB7EC \xCC44\xD305\xBC29 \xB098\xAC00\xAE30",
                RECT{20, 34, 240, 62}, title_font, RGB(0, 0, 0),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);

  const int list_top = 76;
  const int visible_count = 5;
  int max_offset = std::max(0, static_cast<int>(state->rooms.size()) -
                                   visible_count);
  state->room_scroll_offset =
      std::max(0, std::min(state->room_scroll_offset, max_offset));

  for (int visible = 0; visible < visible_count; visible++) {
    int index = state->room_scroll_offset + visible;
    if (index >= static_cast<int>(state->rooms.size())) {
      break;
    }
    const auto& room = state->rooms[index];
    bool selected = StringListContains(state->selected_room_ids, room.id);
    int y = list_top + visible * kMultiLeaveRowHeight;
    RECT row{12, y, kMultiLeaveNativeWidth - 12,
             y + kMultiLeaveRowHeight};
    if (state->hovered_index == index || selected) {
      HBRUSH hover = CreateSolidBrush(RGB(239, 239, 239));
      FillRect(hdc, &row, hover);
      DeleteObject(hover);
    }

    FolderRoomState avatar;
    avatar.avatar_color = room.avatar_color;
    avatar.is_group = room.is_group;
    avatar.avatar_image_url = room.avatar_image_url;
    avatar.avatar_parts = room.avatar_parts;
    DrawFolderAvatar(hdc, avatar, 20, y + 10, 44);

    std::wstring title = room.title;
    if (room.participant_count > 1) {
      title += L" " + std::to_wstring(room.participant_count);
    }
    RECT title_rect{76, y + 8, kMultiLeaveNativeWidth - 86, y + 29};
    DrawTextBlock(hdc, title, title_rect, label_font, RGB(0, 0, 0),
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
    DrawTextBlock(hdc, room.preview,
                  RECT{76, y + 31, kMultiLeaveNativeWidth - 72, y + 58},
                  small_font, RGB(90, 90, 90),
                  DT_LEFT | DT_TOP | DT_WORDBREAK | DT_END_ELLIPSIS);
    if (room.unread_count > 0) {
      DrawRedUnreadBadge(hdc, kMultiLeaveNativeWidth - 62, y + 24,
                         room.unread_count);
    }
    RECT circle{kMultiLeaveNativeWidth - 38, y + 22,
                kMultiLeaveNativeWidth - 16, y + 44};
    DrawCheckCircle(hdc, circle, selected);
  }

  if (state->rooms.size() > visible_count) {
    RECT track{kMultiLeaveNativeWidth - 8, list_top, kMultiLeaveNativeWidth - 4,
               list_top + visible_count * kMultiLeaveRowHeight};
    HBRUSH track_brush = CreateSolidBrush(RGB(238, 238, 238));
    FillRect(hdc, &track, track_brush);
    DeleteObject(track_brush);
    int thumb_height = std::max(
        28,
        (visible_count * kMultiLeaveRowHeight * visible_count) /
            static_cast<int>(state->rooms.size()));
    int thumb_top =
        list_top + ((visible_count * kMultiLeaveRowHeight - thumb_height) *
                    state->room_scroll_offset) /
                       std::max(1, max_offset);
    RECT thumb{kMultiLeaveNativeWidth - 9, thumb_top,
               kMultiLeaveNativeWidth - 3, thumb_top + thumb_height};
    HBRUSH thumb_brush = CreateSolidBrush(RGB(190, 190, 190));
    FillRect(hdc, &thumb, thumb_brush);
    DeleteObject(thumb_brush);
  }

  RECT line{0, kMultiLeaveNativeHeight - 80, kMultiLeaveNativeWidth,
            kMultiLeaveNativeHeight - 79};
  HBRUSH line_brush = CreateSolidBrush(RGB(235, 235, 235));
  FillRect(hdc, &line, line_brush);
  DeleteObject(line_brush);

  bool can_leave = !state->selected_room_ids.empty();
  std::wstring leave_label = can_leave
                                 ? L"\xB098\xAC00\xAE30 " +
                                       std::to_wstring(
                                           state->selected_room_ids.size())
                                 : L"\xB098\xAC00\xAE30";
  DrawMultiLeaveButton(hdc, MultiLeaveLeaveButtonRect(), leave_label,
                       can_leave, button_font, true);
  DrawMultiLeaveButton(hdc, MultiLeaveCancelButtonRect(), L"\xCDE8\xC18C",
                       true, button_font, false);

  DeleteObject(title_font);
  DeleteObject(label_font);
  DeleteObject(small_font);
  DeleteObject(button_font);
  EndPaint(hwnd, &paint);
}

int MultiLeaveRoomIndexAt(MultiLeaveRoomsState* state, int y) {
  if (!state || y < 76) {
    return -1;
  }
  int visible = (y - 76) / kMultiLeaveRowHeight;
  if (visible < 0 || visible >= 5) {
    return -1;
  }
  int index = state->room_scroll_offset + visible;
  if (index < 0 || index >= static_cast<int>(state->rooms.size())) {
    return -1;
  }
  return index;
}

LRESULT CALLBACK MultiLeaveRoomsWndProc(HWND hwnd,
                                        UINT message,
                                        WPARAM wparam,
                                        LPARAM lparam) {
  auto* state = reinterpret_cast<MultiLeaveRoomsState*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state =
          reinterpret_cast<MultiLeaveRoomsState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_MOUSEWHEEL:
      if (state) {
        int delta = GET_WHEEL_DELTA_WPARAM(wparam);
        state->room_scroll_offset += delta < 0 ? 1 : -1;
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      break;
    case WM_MOUSEMOVE: {
      int index = MultiLeaveRoomIndexAt(state, GET_Y_LPARAM(lparam));
      if (state && index != state->hovered_index) {
        state->hovered_index = index;
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    }
    case WM_LBUTTONDOWN: {
      int x = GET_X_LPARAM(lparam);
      int y = GET_Y_LPARAM(lparam);
      if (PointInRect(CloseButtonRect(kMultiLeaveNativeWidth), x, y) ||
          PointInRect(MultiLeaveCancelButtonRect(), x, y)) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (!state) {
        return 0;
      }
      if (PointInRect(MultiLeaveLeaveButtonRect(), x, y)) {
        if (!state->selected_room_ids.empty()) {
          InvokeMultiLeaveRoomsAction(state, "leaveRooms",
                                      state->selected_room_ids);
          DestroyWindow(hwnd);
        }
        return 0;
      }
      int index = MultiLeaveRoomIndexAt(state, y);
      if (index >= 0) {
        ToggleMultiLeaveRoom(state, state->rooms[index].id);
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      if (y < 34) {
        ReleaseCapture();
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      }
      return 0;
    }
    case WM_PAINT:
      if (state) {
        DrawMultiLeaveRooms(state, hwnd);
        return 0;
      }
      break;
    case WM_NCACTIVATE:
      return TRUE;
    case WM_NCPAINT:
      return 0;
    case WM_DESTROY:
      if (g_active_multi_leave_rooms_popup == hwnd) {
        g_active_multi_leave_rooms_popup = nullptr;
      }
      if (state) {
        if (!state->submitted) {
          InvokeMultiLeaveRoomsAction(state, "closed");
        }
        delete state;
      }
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

std::wstring ImageViewerFileNameOnly(const std::wstring& path) {
  size_t slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos || slash + 1 >= path.size()) {
    return path.empty() ? L"image.png" : path;
  }
  return path.substr(slash + 1);
}

std::wstring ImageViewerDownloadsDirectory() {
  PWSTR known_path = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(
          FOLDERID_Downloads, KF_FLAG_DEFAULT, nullptr, &known_path)) &&
      known_path) {
    std::wstring path(known_path);
    CoTaskMemFree(known_path);
    CreateDirectoryW(path.c_str(), nullptr);
    return path;
  }

  wchar_t profile[MAX_PATH] = {};
  DWORD length = GetEnvironmentVariableW(L"USERPROFILE", profile, MAX_PATH);
  if (length > 0 && length < MAX_PATH) {
    std::wstring path(profile);
    path += L"\\Downloads";
    CreateDirectoryW(path.c_str(), nullptr);
    return path;
  }
  return L".";
}

bool ImageViewerFileExists(const std::wstring& path) {
  DWORD attributes = GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

std::wstring ImageViewerUniqueDownloadPath(const std::wstring& file_name) {
  std::wstring safe_name = ImageViewerFileNameOnly(file_name);
  if (safe_name.empty()) {
    safe_name = L"image.png";
  }
  std::wstring directory = ImageViewerDownloadsDirectory();
  std::wstring base = safe_name;
  std::wstring extension;
  size_t dot = safe_name.find_last_of(L'.');
  if (dot != std::wstring::npos && dot > 0) {
    base = safe_name.substr(0, dot);
    extension = safe_name.substr(dot);
  }

  std::wstring candidate = directory + L"\\" + safe_name;
  int suffix = 1;
  while (ImageViewerFileExists(candidate)) {
    candidate = directory + L"\\" + base + L" (" +
                std::to_wstring(suffix++) + L")" + extension;
  }
  return candidate;
}

std::wstring ImageViewerCurrentPath(const ImageViewerState* state) {
  if (!state || state->items.empty() || state->index < 0 ||
      state->index >= static_cast<int>(state->items.size())) {
    return std::wstring();
  }
  return state->items[state->index].path;
}

void ImageViewerLoadCurrent(ImageViewerState* state) {
  if (!state) {
    return;
  }
  state->image.reset();
  std::wstring path = ImageViewerCurrentPath(state);
  if (path.empty()) {
    return;
  }
  EnsureGdiplus();
  auto image = std::make_unique<Gdiplus::Image>(path.c_str());
  if (image->GetLastStatus() == Gdiplus::Ok && image->GetWidth() > 0 &&
      image->GetHeight() > 0) {
    state->image = std::move(image);
  }
}

struct ImageViewerLayout {
  RECT image_rect;
  double scale = 1.0;
  int main_height = 1;
};

ImageViewerLayout ImageViewerLayoutFor(const ImageViewerState* state,
                                       RECT client) {
  ImageViewerLayout layout{};
  layout.main_height =
      std::max<int>(1, static_cast<int>(client.bottom - client.top) -
                           kImageViewerToolbarHeight);
  layout.image_rect = RECT{client.left, client.top, client.right,
                           client.top + layout.main_height};
  if (!state || !state->image) {
    return layout;
  }

  const double image_width = static_cast<double>(state->image->GetWidth());
  const double image_height = static_cast<double>(state->image->GetHeight());
  const bool rotated = std::abs(state->rotation % 180) == 90;
  const double natural_width = rotated ? image_height : image_width;
  const double natural_height = rotated ? image_width : image_height;
  const double content_width = static_cast<double>(client.right - client.left);
  const double side_margin = std::max(92.0, content_width * 0.174);
  const double available_width = std::max(220.0, content_width - side_margin * 2);
  const double available_height = std::max(220.0, static_cast<double>(layout.main_height));
  layout.scale = state->fit
                     ? std::min(available_width / natural_width,
                                available_height / natural_height)
                     : std::clamp(state->zoom, 0.25, 5.0);
  if (!std::isfinite(layout.scale) || layout.scale <= 0.0) {
    layout.scale = 1.0;
  }

  int draw_width = std::max(80, static_cast<int>(std::round(natural_width * layout.scale)));
  int draw_height =
      std::max(80, static_cast<int>(std::round(natural_height * layout.scale)));
  int center_x = (client.right - client.left) / 2;
  int center_y = layout.main_height / 2;
  layout.image_rect = RECT{center_x - draw_width / 2,
                           center_y - draw_height / 2,
                           center_x + (draw_width + 1) / 2,
                           center_y + (draw_height + 1) / 2};
  return layout;
}

struct ImageViewerThumbnailRect {
  int index = 0;
  RECT rect{};
};

std::vector<ImageViewerThumbnailRect> ImageViewerThumbnailRects(
    const ImageViewerState* state,
    RECT client,
    const ImageViewerLayout& layout) {
  std::vector<ImageViewerThumbnailRect> rects;
  if (!state || state->items.size() <= 1) {
    return rects;
  }
  const int thumb_size = 48;
  const int gap = 6;
  const int visible = std::min<int>(11, static_cast<int>(state->items.size()));
  int start = 0;
  if (static_cast<int>(state->items.size()) > visible) {
    start = std::clamp(state->index - visible / 2, 0,
                       static_cast<int>(state->items.size()) - visible);
  }
  const int total_width = visible * thumb_size + (visible - 1) * gap;
  const int left = (client.right - client.left - total_width) / 2;
  const int top = std::min<int>(
      layout.main_height - 58,
      std::max<int>(8, static_cast<int>(layout.image_rect.bottom) - 58));
  for (int i = 0; i < visible; ++i) {
    ImageViewerThumbnailRect item;
    item.index = start + i;
    item.rect = RECT{left + i * (thumb_size + gap), top,
                     left + i * (thumb_size + gap) + thumb_size,
                     top + thumb_size};
    rects.push_back(item);
  }
  return rects;
}

RECT ImageViewerPrevRect(RECT client, const ImageViewerLayout& layout) {
  return RECT{15, layout.main_height / 2 - 19, 53, layout.main_height / 2 + 19};
}

RECT ImageViewerNextRect(RECT client, const ImageViewerLayout& layout) {
  return RECT{client.right - 53, layout.main_height / 2 - 19,
              client.right - 15, layout.main_height / 2 + 19};
}

struct ImageViewerToolbarButton {
  int command = 0;
  RECT rect{};
  std::wstring label;
};

std::vector<ImageViewerToolbarButton> ImageViewerToolbarButtons(RECT client,
                                                                int main_height) {
  std::vector<ImageViewerToolbarButton> buttons;
  const int y = main_height + 7;
  const int size = 34;
  const std::vector<std::wstring> left_labels = {
      L"▦", L"−", L"+", L"↗", L"↻"};
  for (int i = 0; i < static_cast<int>(left_labels.size()); ++i) {
    int x = 17 + i * 36;
    buttons.push_back(ImageViewerToolbarButton{
        i + 1, RECT{x, y, x + size, y + size}, left_labels[i]});
  }
  buttons.push_back(ImageViewerToolbarButton{
      6, RECT{client.right - 82, y, client.right - 48, y + size}, L"⇩"});
  buttons.push_back(ImageViewerToolbarButton{
      7, RECT{client.right - 46, y, client.right - 12, y + size}, L"⋯"});
  return buttons;
}

void ImageViewerDrawImageCover(Gdiplus::Graphics& graphics,
                               Gdiplus::Image& image,
                               RECT rect) {
  const double target_width = static_cast<double>(rect.right - rect.left);
  const double target_height = static_cast<double>(rect.bottom - rect.top);
  if (target_width <= 0 || target_height <= 0 || image.GetWidth() == 0 ||
      image.GetHeight() == 0) {
    return;
  }
  const double scale = std::max(target_width / image.GetWidth(),
                                target_height / image.GetHeight());
  const double source_width = target_width / scale;
  const double source_height = target_height / scale;
  const double source_x = (image.GetWidth() - source_width) / 2.0;
  const double source_y = (image.GetHeight() - source_height) / 2.0;
  graphics.DrawImage(
      &image,
      Gdiplus::RectF(static_cast<Gdiplus::REAL>(rect.left),
                    static_cast<Gdiplus::REAL>(rect.top),
                    static_cast<Gdiplus::REAL>(target_width),
                    static_cast<Gdiplus::REAL>(target_height)),
      static_cast<Gdiplus::REAL>(source_x),
      static_cast<Gdiplus::REAL>(source_y),
      static_cast<Gdiplus::REAL>(source_width),
      static_cast<Gdiplus::REAL>(source_height), Gdiplus::UnitPixel);
}

void ImageViewerPaint(ImageViewerState* state, HWND hwnd) {
  PAINTSTRUCT paint{};
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HDC memory_dc = CreateCompatibleDC(hdc);
  HBITMAP bitmap = CreateCompatibleBitmap(
      hdc, std::max<int>(1, static_cast<int>(client.right - client.left)),
      std::max<int>(1, static_cast<int>(client.bottom - client.top)));
  HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);

  RECT main_rect = client;
  main_rect.bottom = std::max<LONG>(
      main_rect.top, client.bottom - kImageViewerToolbarHeight);
  HBRUSH main_brush = CreateSolidBrush(RGB(245, 245, 245));
  FillRect(memory_dc, &main_rect, main_brush);
  DeleteObject(main_brush);

  RECT toolbar_rect = client;
  toolbar_rect.top = main_rect.bottom;
  HBRUSH toolbar_brush = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(memory_dc, &toolbar_rect, toolbar_brush);
  DeleteObject(toolbar_brush);

  ImageViewerLayout layout = ImageViewerLayoutFor(state, client);
  EnsureGdiplus();
  Gdiplus::Graphics graphics(memory_dc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeHighQuality);
  graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);

  if (state && state->image) {
    const double image_width = static_cast<double>(state->image->GetWidth());
    const double image_height = static_cast<double>(state->image->GetHeight());
    const double center_x =
        (layout.image_rect.left + layout.image_rect.right) / 2.0;
    const double center_y =
        (layout.image_rect.top + layout.image_rect.bottom) / 2.0;
    graphics.TranslateTransform(static_cast<Gdiplus::REAL>(center_x),
                                static_cast<Gdiplus::REAL>(center_y));
    graphics.RotateTransform(static_cast<Gdiplus::REAL>(state->rotation));
    graphics.DrawImage(
        state->image.get(),
        Gdiplus::RectF(
            static_cast<Gdiplus::REAL>(-image_width * layout.scale / 2.0),
            static_cast<Gdiplus::REAL>(-image_height * layout.scale / 2.0),
            static_cast<Gdiplus::REAL>(image_width * layout.scale),
            static_cast<Gdiplus::REAL>(image_height * layout.scale)));
    graphics.ResetTransform();
  }

  if (state && state->items.size() > 1) {
    RECT prev = ImageViewerPrevRect(client, layout);
    RECT next = ImageViewerNextRect(client, layout);
    Gdiplus::SolidBrush white(Gdiplus::Color(255, 255, 255, 255));
    Gdiplus::Pen border(Gdiplus::Color(255, 220, 220, 220), 1.0f);
    graphics.FillEllipse(&white, static_cast<Gdiplus::REAL>(prev.left),
                         static_cast<Gdiplus::REAL>(prev.top), 38.0f, 38.0f);
    graphics.DrawEllipse(&border, static_cast<Gdiplus::REAL>(prev.left),
                         static_cast<Gdiplus::REAL>(prev.top), 38.0f, 38.0f);
    graphics.FillEllipse(&white, static_cast<Gdiplus::REAL>(next.left),
                         static_cast<Gdiplus::REAL>(next.top), 38.0f, 38.0f);
    graphics.DrawEllipse(&border, static_cast<Gdiplus::REAL>(next.left),
                         static_cast<Gdiplus::REAL>(next.top), 38.0f, 38.0f);

    HFONT arrow_font = CreateUiFont(18, FW_NORMAL);
    DrawTextBlock(memory_dc, L"‹", prev, arrow_font, RGB(70, 70, 70),
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DrawTextBlock(memory_dc, L"›", next, arrow_font, RGB(70, 70, 70),
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DeleteObject(arrow_font);

    std::vector<ImageViewerThumbnailRect> thumbs =
        ImageViewerThumbnailRects(state, client, layout);
    for (const auto& thumb : thumbs) {
      Gdiplus::SolidBrush thumb_background(Gdiplus::Color(255, 238, 238, 238));
      graphics.FillRectangle(
          &thumb_background, static_cast<Gdiplus::REAL>(thumb.rect.left),
          static_cast<Gdiplus::REAL>(thumb.rect.top),
          static_cast<Gdiplus::REAL>(thumb.rect.right - thumb.rect.left),
          static_cast<Gdiplus::REAL>(thumb.rect.bottom - thumb.rect.top));
      Gdiplus::Image image(state->items[thumb.index].path.c_str());
      if (image.GetLastStatus() == Gdiplus::Ok) {
        ImageViewerDrawImageCover(graphics, image, thumb.rect);
      }
      if (thumb.index == state->index) {
        Gdiplus::Pen selected(Gdiplus::Color(255, 255, 223, 0), 2.0f);
        graphics.DrawRectangle(
            &selected, static_cast<Gdiplus::REAL>(thumb.rect.left + 1),
            static_cast<Gdiplus::REAL>(thumb.rect.top + 1),
            static_cast<Gdiplus::REAL>(thumb.rect.right - thumb.rect.left - 2),
            static_cast<Gdiplus::REAL>(thumb.rect.bottom - thumb.rect.top - 2));
      }
    }

    if (!thumbs.empty()) {
      RECT count_rect{
          (client.right - client.left) / 2 - 36, thumbs.front().rect.top - 30,
          (client.right - client.left) / 2 + 36, thumbs.front().rect.top - 6};
      DrawFilledRoundRect(memory_dc, count_rect, 14, RGB(70, 70, 70),
                          RGB(70, 70, 70));
      std::wstring count = L"▧ " + std::to_wstring(state->index + 1) + L"/" +
                           std::to_wstring(state->items.size());
      HFONT count_font = CreateUiFont(8, FW_NORMAL);
      DrawTextBlock(memory_dc, count, count_rect, count_font, RGB(255, 255, 255),
                    DT_CENTER | DT_VCENTER | DT_SINGLELINE);
      DeleteObject(count_font);
    }
  }

  HFONT toolbar_font = CreateUiFont(13, FW_NORMAL);
  for (const auto& button : ImageViewerToolbarButtons(client, layout.main_height)) {
    DrawTextBlock(memory_dc, button.label, button.rect, toolbar_font,
                  RGB(45, 45, 45), DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  }
  DeleteObject(toolbar_font);

  BitBlt(hdc, 0, 0, client.right - client.left, client.bottom - client.top,
         memory_dc, 0, 0, SRCCOPY);
  SelectObject(memory_dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  EndPaint(hwnd, &paint);
}

void ImageViewerOpenCurrentFile(HWND hwnd, const ImageViewerState* state) {
  std::wstring path = ImageViewerCurrentPath(state);
  if (!path.empty()) {
    ShellExecuteW(hwnd, L"open", path.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
  }
}

void ImageViewerOpenCurrentFolder(HWND hwnd, const ImageViewerState* state) {
  std::wstring path = ImageViewerCurrentPath(state);
  if (path.empty()) {
    return;
  }
  std::wstring parameters = L"/select,\"" + path + L"\"";
  ShellExecuteW(hwnd, L"open", L"explorer.exe", parameters.c_str(), nullptr,
                SW_SHOWNORMAL);
}

void ImageViewerCopyCurrentToDownloads(const ImageViewerState* state) {
  if (!state || state->items.empty()) {
    return;
  }
  const ImageViewerItemState& item = state->items[state->index];
  std::wstring target = ImageViewerUniqueDownloadPath(
      item.name.empty() ? ImageViewerFileNameOnly(item.path) : item.name);
  CopyFileW(item.path.c_str(), target.c_str(), FALSE);
}

void ImageViewerSetIndex(ImageViewerState* state, HWND hwnd, int index) {
  if (!state || state->items.empty()) {
    return;
  }
  int next = std::clamp(index, 0, static_cast<int>(state->items.size()) - 1);
  if (next == state->index && state->image) {
    return;
  }
  state->index = next;
  state->rotation = 0;
  ImageViewerLoadCurrent(state);
  InvalidateRect(hwnd, nullptr, TRUE);
}

void ImageViewerShowMoreMenu(HWND hwnd,
                             ImageViewerState* state,
                             RECT anchor) {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, 1, L"열기");
  AppendMenuW(menu, MF_STRING, 2, L"폴더 열기");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 3, L"다운로드");
  POINT point{anchor.left, anchor.top};
  ClientToScreen(hwnd, &point);
  UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_LEFTALIGN | TPM_BOTTOMALIGN, point.x, point.y,
      0, hwnd, nullptr);
  DestroyMenu(menu);
  if (command == 1) {
    ImageViewerOpenCurrentFile(hwnd, state);
  } else if (command == 2) {
    ImageViewerOpenCurrentFolder(hwnd, state);
  } else if (command == 3) {
    ImageViewerCopyCurrentToDownloads(state);
  }
}

LRESULT CALLBACK ImageViewerWndProc(HWND hwnd,
                                    UINT message,
                                    WPARAM wparam,
                                    LPARAM lparam) {
  auto* state =
      reinterpret_cast<ImageViewerState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<ImageViewerState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      ImageViewerLoadCurrent(state);
      return TRUE;
    }
    case WM_ERASEBKGND:
      return 1;
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = 760;
      info->ptMinTrackSize.y = 500;
      return 0;
    }
    case WM_SIZE:
      InvalidateRect(hwnd, nullptr, TRUE);
      return 0;
    case WM_KEYDOWN:
      if (!state) {
        break;
      }
      if (wparam == VK_ESCAPE) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (wparam == VK_LEFT) {
        ImageViewerSetIndex(state, hwnd, state->index - 1);
        return 0;
      }
      if (wparam == VK_RIGHT) {
        ImageViewerSetIndex(state, hwnd, state->index + 1);
        return 0;
      }
      if (wparam == VK_OEM_PLUS || wparam == VK_ADD) {
        state->fit = false;
        state->zoom = std::min(5.0, state->zoom + 0.25);
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      if (wparam == VK_OEM_MINUS || wparam == VK_SUBTRACT) {
        state->fit = false;
        state->zoom = std::max(0.25, state->zoom - 0.25);
        InvalidateRect(hwnd, nullptr, TRUE);
        return 0;
      }
      break;
    case WM_LBUTTONDOWN: {
      if (!state) {
        break;
      }
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      RECT client{};
      GetClientRect(hwnd, &client);
      ImageViewerLayout layout = ImageViewerLayoutFor(state, client);

      if (state->items.size() > 1) {
        RECT prev = ImageViewerPrevRect(client, layout);
        RECT next = ImageViewerNextRect(client, layout);
        if (PtInRect(&prev, point)) {
          ImageViewerSetIndex(state, hwnd, state->index - 1);
          return 0;
        }
        if (PtInRect(&next, point)) {
          ImageViewerSetIndex(state, hwnd, state->index + 1);
          return 0;
        }
        for (const auto& thumb : ImageViewerThumbnailRects(state, client, layout)) {
          if (PtInRect(&thumb.rect, point)) {
            ImageViewerSetIndex(state, hwnd, thumb.index);
            return 0;
          }
        }
      }

      for (const auto& button : ImageViewerToolbarButtons(client, layout.main_height)) {
        if (!PtInRect(&button.rect, point)) {
          continue;
        }
        switch (button.command) {
          case 1:
          case 4:
            state->fit = true;
            InvalidateRect(hwnd, nullptr, TRUE);
            break;
          case 2:
            state->fit = false;
            state->zoom = std::max(0.25, state->zoom - 0.25);
            InvalidateRect(hwnd, nullptr, TRUE);
            break;
          case 3:
            state->fit = false;
            state->zoom = std::min(5.0, state->zoom + 0.25);
            InvalidateRect(hwnd, nullptr, TRUE);
            break;
          case 5:
            state->rotation = (state->rotation + 90) % 360;
            InvalidateRect(hwnd, nullptr, TRUE);
            break;
          case 6:
            ImageViewerCopyCurrentToDownloads(state);
            break;
          case 7:
            ImageViewerShowMoreMenu(hwnd, state, button.rect);
            break;
          default:
            break;
        }
        return 0;
      }
      return 0;
    }
    case WM_PAINT:
      ImageViewerPaint(state, hwnd);
      return 0;
    case WM_DESTROY:
      if (g_active_image_viewer == hwnd) {
        g_active_image_viewer = nullptr;
      }
      delete state;
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void RegisterImageViewerClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kImageViewerClassName;
  window_class.lpfnWndProc = ImageViewerWndProc;
  RegisterClass(&window_class);
  registered = true;
}

class VideoViewerCallback final : public IMFPMediaPlayerCallback {
 public:
  explicit VideoViewerCallback(HWND hwnd) : hwnd_(hwnd) {}

  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** object) override {
    if (!object) {
      return E_POINTER;
    }
    if (iid == IID_IUnknown || iid == __uuidof(IMFPMediaPlayerCallback)) {
      *object = static_cast<IMFPMediaPlayerCallback*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }

  ULONG STDMETHODCALLTYPE AddRef() override {
    return ++ref_count_;
  }

  ULONG STDMETHODCALLTYPE Release() override {
    ULONG count = --ref_count_;
    if (count == 0) {
      delete this;
    }
    return count;
  }

  void STDMETHODCALLTYPE OnMediaPlayerEvent(MFP_EVENT_HEADER* event) override {
    if (!event || !hwnd_) {
      return;
    }
    PostMessageW(hwnd_, kVideoViewerPlayerEventMessage,
                 static_cast<WPARAM>(event->eEventType),
                 static_cast<LPARAM>(event->hrEvent));
  }

 private:
  std::atomic<ULONG> ref_count_{1};
  HWND hwnd_ = nullptr;
};

struct VideoViewerLayout {
  RECT main{};
  RECT control{};
  RECT toolbar{};
  RECT play{};
  RECT current{};
  RECT progress{};
  RECT duration{};
  RECT speaker{};
  RECT volume{};
};

struct VideoViewerToolbarButton {
  int command = 0;
  RECT rect{};
  std::wstring label;
  COLORREF color = RGB(50, 50, 50);
};

VideoViewerLayout VideoViewerLayoutFor(RECT client) {
  VideoViewerLayout layout{};
  const int width = std::max<int>(1, client.right - client.left);
  const int controls_height =
      kVideoViewerControlBarHeight + kVideoViewerToolbarHeight;
  const int main_bottom =
      std::max<int>(client.top, client.bottom - controls_height);
  layout.main = RECT{client.left, client.top, client.right, main_bottom};
  layout.control =
      RECT{client.left, main_bottom, client.right,
           main_bottom + kVideoViewerControlBarHeight};
  layout.toolbar =
      RECT{client.left, layout.control.bottom, client.right, client.bottom};

  const int control_mid =
      layout.control.top + kVideoViewerControlBarHeight / 2;
  layout.play = RECT{client.left, layout.control.top, client.left + 36,
                     layout.control.bottom};
  layout.current = RECT{client.left + 44, layout.control.top,
                        client.left + 84, layout.control.bottom};
  const int progress_left = client.left + 90;
  const int progress_right =
      std::max<int>(progress_left + 80, static_cast<int>(client.right) - 220);
  layout.progress =
      RECT{progress_left, control_mid - 5, progress_right, control_mid + 5};
  layout.duration = RECT{progress_right + 12, layout.control.top,
                         progress_right + 75, layout.control.bottom};
  layout.speaker = RECT{progress_right + 78, layout.control.top,
                        progress_right + 112, layout.control.bottom};
  layout.volume = RECT{progress_right + 118, control_mid - 5,
                       std::max<int>(progress_right + 160,
                                     static_cast<int>(client.right) - 14),
                       control_mid + 5};
  if (width < 760) {
    layout.volume.right = client.right - 10;
  }
  return layout;
}

std::vector<VideoViewerToolbarButton> VideoViewerToolbarButtons(RECT client) {
  std::vector<VideoViewerToolbarButton> buttons;
  VideoViewerLayout layout = VideoViewerLayoutFor(client);
  const int y = layout.toolbar.top + 7;
  const int size = 34;
  const std::vector<std::wstring> left_labels = {
      L"\x25A6", L"\x2212", L"+", L"\x2197", L"\x21BB"};
  for (int i = 0; i < static_cast<int>(left_labels.size()); ++i) {
    int x = 17 + i * 36;
    buttons.push_back(VideoViewerToolbarButton{
        i + 1, RECT{x, y, x + size, y + size}, left_labels[i],
        i == 0 ? RGB(85, 85, 85) : RGB(160, 160, 160)});
  }
  buttons.push_back(VideoViewerToolbarButton{
      6, RECT{client.right - 82, y, client.right - 48, y + size}, L"\x21E9",
      RGB(45, 45, 45)});
  buttons.push_back(VideoViewerToolbarButton{
      7, RECT{client.right - 46, y, client.right - 12, y + size}, L"\x22EF",
      RGB(45, 45, 45)});
  return buttons;
}

std::wstring VideoViewerFormatTime(LONGLONG value_100ns) {
  LONGLONG total_seconds =
      std::max<LONGLONG>(0, value_100ns / 10000000LL);
  LONGLONG hours = total_seconds / 3600;
  LONGLONG minutes = (total_seconds % 3600) / 60;
  LONGLONG seconds = total_seconds % 60;
  wchar_t buffer[32] = {};
  if (hours > 0) {
    swprintf_s(buffer, L"%lld:%02lld:%02lld", hours, minutes, seconds);
  } else {
    swprintf_s(buffer, L"%02lld:%02lld", minutes, seconds);
  }
  return std::wstring(buffer);
}

LONGLONG VideoViewerReadPosition(IMFPMediaPlayer* player, bool duration) {
  if (!player) {
    return 0;
  }
  PROPVARIANT value{};
  PropVariantInit(&value);
  HRESULT result = duration
                       ? player->GetDuration(MFP_POSITIONTYPE_100NS, &value)
                       : player->GetPosition(MFP_POSITIONTYPE_100NS, &value);
  LONGLONG output = 0;
  if (SUCCEEDED(result)) {
    if (value.vt == VT_I8) {
      output = value.hVal.QuadPart;
    } else if (value.vt == VT_UI8) {
      output = static_cast<LONGLONG>(value.uhVal.QuadPart);
    }
  }
  PropVariantClear(&value);
  return std::max<LONGLONG>(0, output);
}

void VideoViewerRefreshPosition(VideoViewerState* state) {
  if (!state || !state->player) {
    return;
  }
  LONGLONG duration = VideoViewerReadPosition(state->player, true);
  if (duration > 0) {
    state->duration_100ns = duration;
  }
  LONGLONG position = VideoViewerReadPosition(state->player, false);
  if (position >= 0) {
    state->position_100ns = position;
  }
}

double VideoViewerProgressRatio(const VideoViewerState* state) {
  if (!state || state->duration_100ns <= 0) {
    return 0.0;
  }
  return std::clamp(static_cast<double>(state->position_100ns) /
                        static_cast<double>(state->duration_100ns),
                    0.0, 1.0);
}

void VideoViewerSetVolume(VideoViewerState* state, double value) {
  if (!state) {
    return;
  }
  state->volume = std::clamp(value, 0.0, 1.0);
  if (state->player) {
    state->player->SetVolume(static_cast<float>(state->volume));
  }
}

void VideoViewerSeek(VideoViewerState* state, double ratio) {
  if (!state || !state->player) {
    return;
  }
  if (state->duration_100ns <= 0) {
    VideoViewerRefreshPosition(state);
  }
  if (state->duration_100ns <= 0) {
    return;
  }
  LONGLONG target = static_cast<LONGLONG>(
      std::round(state->duration_100ns * std::clamp(ratio, 0.0, 1.0)));
  PROPVARIANT value{};
  PropVariantInit(&value);
  value.vt = VT_I8;
  value.hVal.QuadPart = target;
  if (SUCCEEDED(state->player->SetPosition(MFP_POSITIONTYPE_100NS, &value))) {
    state->position_100ns = target;
    state->ended = false;
  }
  PropVariantClear(&value);
}

void VideoViewerTogglePlay(VideoViewerState* state) {
  if (!state || !state->player) {
    return;
  }
  if (state->playing) {
    if (SUCCEEDED(state->player->Pause())) {
      state->playing = false;
    }
    return;
  }
  if (state->ended) {
    VideoViewerSeek(state, 0.0);
  }
  if (SUCCEEDED(state->player->Play())) {
    state->playing = true;
    state->ended = false;
  }
}

void VideoViewerPositionVideoHost(HWND hwnd, VideoViewerState* state) {
  if (!state || !state->video_host) {
    return;
  }
  RECT client{};
  GetClientRect(hwnd, &client);
  VideoViewerLayout layout = VideoViewerLayoutFor(client);
  MoveWindow(state->video_host, layout.main.left, layout.main.top,
             layout.main.right - layout.main.left,
             layout.main.bottom - layout.main.top, TRUE);
  if (state->player) {
    state->player->UpdateVideo();
  }
}

void VideoViewerDrawLine(HDC hdc,
                         int left,
                         int top,
                         int right,
                         int bottom,
                         COLORREF color) {
  RECT rect{left, top, right, bottom};
  HBRUSH brush = CreateSolidBrush(color);
  FillRect(hdc, &rect, brush);
  DeleteObject(brush);
}

void VideoViewerDrawTrack(HDC hdc,
                          RECT rect,
                          double ratio,
                          COLORREF track,
                          COLORREF fill) {
  const int center = rect.top + (rect.bottom - rect.top) / 2;
  VideoViewerDrawLine(hdc, rect.left, center - 1, rect.right, center + 1,
                      track);
  int filled = rect.left + static_cast<int>(
                               std::round((rect.right - rect.left) *
                                          std::clamp(ratio, 0.0, 1.0)));
  VideoViewerDrawLine(hdc, rect.left, center - 1, filled, center + 1, fill);
}

void VideoViewerDrawSpeaker(HDC hdc, RECT rect) {
  EnsureGdiplus();
  Gdiplus::Graphics graphics(hdc);
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);

  Gdiplus::SolidBrush fill(Gdiplus::Color(255, 255, 255, 255));
  Gdiplus::Pen wave(Gdiplus::Color(255, 255, 255, 255), 1.8f);
  wave.SetStartCap(Gdiplus::LineCapRound);
  wave.SetEndCap(Gdiplus::LineCapRound);

  const Gdiplus::REAL center_y =
      static_cast<Gdiplus::REAL>(rect.top + (rect.bottom - rect.top) / 2.0);
  const Gdiplus::REAL left = static_cast<Gdiplus::REAL>(rect.left + 7);
  Gdiplus::PointF body[] = {
      {left, center_y - 4.0f},
      {left + 5.0f, center_y - 4.0f},
      {left + 12.0f, center_y - 10.0f},
      {left + 12.0f, center_y + 10.0f},
      {left + 5.0f, center_y + 4.0f},
      {left, center_y + 4.0f},
  };
  graphics.FillPolygon(&fill, body, 6);
  graphics.DrawArc(&wave, left + 10.0f, center_y - 7.0f, 10.0f, 14.0f,
                   -45.0f, 90.0f);
  graphics.DrawArc(&wave, left + 13.0f, center_y - 10.0f, 14.0f, 20.0f,
                   -45.0f, 90.0f);
}

void VideoViewerPaint(VideoViewerState* state, HWND hwnd) {
  PAINTSTRUCT paint{};
  HDC hdc = BeginPaint(hwnd, &paint);
  RECT client{};
  GetClientRect(hwnd, &client);
  HDC memory_dc = CreateCompatibleDC(hdc);
  HBITMAP bitmap = CreateCompatibleBitmap(
      hdc, std::max<int>(1, client.right - client.left),
      std::max<int>(1, client.bottom - client.top));
  HGDIOBJ old_bitmap = SelectObject(memory_dc, bitmap);

  VideoViewerLayout layout = VideoViewerLayoutFor(client);
  HBRUSH main_brush = CreateSolidBrush(RGB(245, 245, 245));
  FillRect(memory_dc, &layout.main, main_brush);
  DeleteObject(main_brush);

  HBRUSH control_brush = CreateSolidBrush(RGB(98, 98, 98));
  FillRect(memory_dc, &layout.control, control_brush);
  DeleteObject(control_brush);

  HBRUSH toolbar_brush = CreateSolidBrush(RGB(255, 255, 255));
  FillRect(memory_dc, &layout.toolbar, toolbar_brush);
  DeleteObject(toolbar_brush);

  if (state && state->has_error) {
    HFONT error_font = CreateUiFont(11, FW_NORMAL);
    DrawTextBlock(memory_dc, L"Cannot play this video.", layout.main,
                  error_font, RGB(80, 80, 80),
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    DeleteObject(error_font);
  }

  HFONT control_font = CreateUiFont(8, FW_BOLD);
  HFONT icon_font = CreateUiFont(13, FW_NORMAL);
  DrawTextBlock(memory_dc,
                state && state->playing ? L"\x23F8" : L"\x25B6",
                layout.play, icon_font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  DrawTextBlock(memory_dc,
                VideoViewerFormatTime(state ? state->position_100ns : 0),
                layout.current, control_font, RGB(255, 255, 255),
                DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  VideoViewerDrawTrack(memory_dc, layout.progress,
                       VideoViewerProgressRatio(state), RGB(146, 146, 146),
                       RGB(255, 255, 255));
  DrawTextBlock(memory_dc,
                VideoViewerFormatTime(state ? state->duration_100ns : 0),
                layout.duration, control_font, RGB(255, 255, 255),
                DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  VideoViewerDrawSpeaker(memory_dc, layout.speaker);
  VideoViewerDrawTrack(memory_dc, layout.volume, state ? state->volume : 0.82,
                       RGB(146, 146, 146), RGB(255, 255, 255));
  DeleteObject(control_font);
  DeleteObject(icon_font);

  HFONT toolbar_font = CreateUiFont(13, FW_NORMAL);
  for (const auto& button : VideoViewerToolbarButtons(client)) {
    DrawTextBlock(memory_dc, button.label, button.rect, toolbar_font,
                  button.color, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  }
  DeleteObject(toolbar_font);

  BitBlt(hdc, 0, 0, client.right - client.left, client.bottom - client.top,
         memory_dc, 0, 0, SRCCOPY);
  SelectObject(memory_dc, old_bitmap);
  DeleteObject(bitmap);
  DeleteDC(memory_dc);
  EndPaint(hwnd, &paint);
  if (state && state->player) {
    state->player->UpdateVideo();
  }
}

void VideoViewerOpenFile(HWND hwnd, const VideoViewerState* state) {
  if (state && !state->path.empty()) {
    ShellExecuteW(hwnd, L"open", state->path.c_str(), nullptr, nullptr,
                  SW_SHOWNORMAL);
  }
}

void VideoViewerOpenFolder(HWND hwnd, const VideoViewerState* state) {
  if (!state || state->path.empty()) {
    return;
  }
  std::wstring parameters = L"/select,\"" + state->path + L"\"";
  ShellExecuteW(hwnd, L"open", L"explorer.exe", parameters.c_str(), nullptr,
                SW_SHOWNORMAL);
}

void VideoViewerCopyToDownloads(const VideoViewerState* state) {
  if (!state || state->path.empty()) {
    return;
  }
  std::wstring target = ImageViewerUniqueDownloadPath(
      state->name.empty() ? ImageViewerFileNameOnly(state->path) : state->name);
  CopyFileW(state->path.c_str(), target.c_str(), FALSE);
}

void VideoViewerShowMoreMenu(HWND hwnd,
                             VideoViewerState* state,
                             RECT anchor) {
  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, 1, L"\xC5F4\xAE30");
  AppendMenuW(menu, MF_STRING, 2, L"\xD3F4\xB354 \xC5F4\xAE30");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, 3, L"\xB2E4\xC6B4\xB85C\xB4DC");
  POINT point{anchor.left, anchor.top};
  ClientToScreen(hwnd, &point);
  UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_LEFTALIGN | TPM_BOTTOMALIGN, point.x, point.y,
      0, hwnd, nullptr);
  DestroyMenu(menu);
  if (command == 1) {
    VideoViewerOpenFile(hwnd, state);
  } else if (command == 2) {
    VideoViewerOpenFolder(hwnd, state);
  } else if (command == 3) {
    VideoViewerCopyToDownloads(state);
  }
}

void VideoViewerInitialize(HWND hwnd, VideoViewerState* state) {
  if (!state) {
    return;
  }
  if (!EnsureMediaFoundation()) {
    state->has_error = true;
    state->playing = false;
    state->last_error = E_FAIL;
    return;
  }
  RECT client{};
  GetClientRect(hwnd, &client);
  VideoViewerLayout layout = VideoViewerLayoutFor(client);
  state->video_host = CreateWindowExW(
      0, L"STATIC", nullptr,
      WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS | WS_CLIPCHILDREN,
      layout.main.left, layout.main.top, layout.main.right - layout.main.left,
      layout.main.bottom - layout.main.top, hwnd, nullptr,
      GetModuleHandle(nullptr), nullptr);
  if (!state->video_host) {
    state->has_error = true;
    state->playing = false;
    state->last_error = E_FAIL;
    return;
  }
  state->callback = new VideoViewerCallback(hwnd);
  HRESULT result = MFPCreateMediaPlayer(
      state->path.c_str(), TRUE, MFP_OPTION_NONE, state->callback,
      state->video_host, &state->player);
  if (FAILED(result) || !state->player) {
    state->has_error = true;
    state->playing = false;
    state->last_error = result;
    DestroyWindow(state->video_host);
    state->video_host = nullptr;
    if (state->callback) {
      state->callback->Release();
      state->callback = nullptr;
    }
    return;
  }
  state->player->SetBorderColor(RGB(245, 245, 245));
  state->player->SetAspectRatioMode(0x1);
  state->player->SetVolume(static_cast<float>(state->volume));
  SetTimer(hwnd, kVideoViewerTimer, 180, nullptr);
}

void VideoViewerShutdown(HWND hwnd, VideoViewerState* state) {
  KillTimer(hwnd, kVideoViewerTimer);
  if (!state) {
    return;
  }
  if (state->player) {
    state->player->Stop();
    state->player->Shutdown();
    state->player->Release();
    state->player = nullptr;
  }
  if (state->callback) {
    state->callback->Release();
    state->callback = nullptr;
  }
}

void VideoViewerApplyTrackClick(HWND hwnd,
                                VideoViewerState* state,
                                RECT track,
                                int x,
                                bool volume) {
  if (!state || track.right <= track.left) {
    return;
  }
  double ratio = static_cast<double>(x - track.left) /
                 static_cast<double>(track.right - track.left);
  if (volume) {
    VideoViewerSetVolume(state, ratio);
  } else {
    VideoViewerSeek(state, ratio);
  }
  InvalidateRect(hwnd, nullptr, FALSE);
}

void VideoViewerHandlePlayerEvent(HWND hwnd,
                                  VideoViewerState* state,
                                  WPARAM wparam,
                                  LPARAM lparam) {
  if (!state) {
    return;
  }
  HRESULT event_result = static_cast<HRESULT>(lparam);
  if (FAILED(event_result)) {
    state->has_error = true;
    state->last_error = event_result;
  }
  switch (static_cast<MFP_EVENT_TYPE>(wparam)) {
    case MFP_EVENT_TYPE_PLAY:
      state->playing = true;
      state->ended = false;
      break;
    case MFP_EVENT_TYPE_PAUSE:
    case MFP_EVENT_TYPE_STOP:
      state->playing = false;
      break;
    case MFP_EVENT_TYPE_MEDIAITEM_SET:
      state->ready = true;
      VideoViewerRefreshPosition(state);
      break;
    case MFP_EVENT_TYPE_PLAYBACK_ENDED:
      state->playing = false;
      state->ended = true;
      VideoViewerRefreshPosition(state);
      break;
    case MFP_EVENT_TYPE_ERROR:
      state->has_error = true;
      state->playing = false;
      break;
    default:
      break;
  }
  InvalidateRect(hwnd, nullptr, FALSE);
}

LRESULT CALLBACK VideoViewerWndProc(HWND hwnd,
                                    UINT message,
                                    WPARAM wparam,
                                    LPARAM lparam) {
  auto* state =
      reinterpret_cast<VideoViewerState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));

  switch (message) {
    case WM_NCCREATE: {
      auto* create_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
      state = reinterpret_cast<VideoViewerState*>(create_struct->lpCreateParams);
      SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
      return TRUE;
    }
    case WM_CREATE:
      VideoViewerInitialize(hwnd, state);
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      info->ptMinTrackSize.x = 760;
      info->ptMinTrackSize.y = 500;
      return 0;
    }
    case WM_SIZE:
      VideoViewerPositionVideoHost(hwnd, state);
      InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    case WM_TIMER:
      if (wparam == kVideoViewerTimer && state) {
        VideoViewerRefreshPosition(state);
        RECT client{};
        GetClientRect(hwnd, &client);
        VideoViewerLayout layout = VideoViewerLayoutFor(client);
        RECT dirty = RECT{layout.control.left, layout.control.top,
                          layout.control.right, layout.toolbar.bottom};
        InvalidateRect(hwnd, &dirty, FALSE);
        return 0;
      }
      break;
    case kVideoViewerPlayerEventMessage:
      VideoViewerHandlePlayerEvent(hwnd, state, wparam, lparam);
      return 0;
    case WM_KEYDOWN:
      if (!state) {
        break;
      }
      if (wparam == VK_ESCAPE) {
        DestroyWindow(hwnd);
        return 0;
      }
      if (wparam == VK_SPACE) {
        VideoViewerTogglePlay(state);
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      if (wparam == VK_LEFT || wparam == VK_RIGHT) {
        VideoViewerRefreshPosition(state);
        LONGLONG delta = (wparam == VK_RIGHT ? 5 : -5) * 10000000LL;
        LONGLONG target =
            std::clamp(state->position_100ns + delta, 0LL,
                       std::max<LONGLONG>(state->duration_100ns, 0));
        if (state->duration_100ns > 0) {
          VideoViewerSeek(state, static_cast<double>(target) /
                                     static_cast<double>(state->duration_100ns));
        }
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      break;
    case WM_LBUTTONDOWN: {
      if (!state) {
        break;
      }
      POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      RECT client{};
      GetClientRect(hwnd, &client);
      VideoViewerLayout layout = VideoViewerLayoutFor(client);
      if (PtInRect(&layout.play, point)) {
        VideoViewerTogglePlay(state);
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
      }
      if (PtInRect(&layout.progress, point)) {
        state->dragging_progress = true;
        SetCapture(hwnd);
        VideoViewerApplyTrackClick(hwnd, state, layout.progress, point.x,
                                   false);
        return 0;
      }
      if (PtInRect(&layout.volume, point)) {
        state->dragging_volume = true;
        SetCapture(hwnd);
        VideoViewerApplyTrackClick(hwnd, state, layout.volume, point.x, true);
        return 0;
      }
      for (const auto& button : VideoViewerToolbarButtons(client)) {
        if (!PtInRect(&button.rect, point)) {
          continue;
        }
        if (button.command == 6) {
          VideoViewerCopyToDownloads(state);
        } else if (button.command == 7) {
          VideoViewerShowMoreMenu(hwnd, state, button.rect);
        }
        return 0;
      }
      return 0;
    }
    case WM_MOUSEMOVE:
      if (state && (state->dragging_progress || state->dragging_volume)) {
        RECT client{};
        GetClientRect(hwnd, &client);
        VideoViewerLayout layout = VideoViewerLayoutFor(client);
        VideoViewerApplyTrackClick(hwnd, state,
                                   state->dragging_volume ? layout.volume
                                                          : layout.progress,
                                   GET_X_LPARAM(lparam),
                                   state->dragging_volume);
        return 0;
      }
      break;
    case WM_LBUTTONUP:
      if (state && (state->dragging_progress || state->dragging_volume)) {
        state->dragging_progress = false;
        state->dragging_volume = false;
        ReleaseCapture();
        return 0;
      }
      break;
    case WM_PAINT:
      VideoViewerPaint(state, hwnd);
      return 0;
    case WM_DESTROY:
      if (g_active_video_viewer == hwnd) {
        g_active_video_viewer = nullptr;
      }
      VideoViewerShutdown(hwnd, state);
      delete state;
      SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void RegisterVideoViewerClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kVideoViewerClassName;
  window_class.lpfnWndProc = VideoViewerWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void RegisterMultiLeaveRoomsClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kMultiLeaveRoomsClassName;
  window_class.lpfnWndProc = MultiLeaveRoomsWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void RegisterProfilePopupClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kProfilePopupClassName;
  window_class.lpfnWndProc = ProfilePopupWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void RegisterProfileEditClass() {
  static bool registered = false;
  if (registered) {
    return;
  }
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kProfileEditClassName;
  window_class.lpfnWndProc = ProfileEditWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void RegisterFolderCreateClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kFolderCreateClassName;
  window_class.lpfnWndProc = FolderCreateWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void RegisterNewChatClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kNewChatClassName;
  window_class.lpfnWndProc = NewChatWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void RegisterEmployeeAddClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kEmployeeAddClassName;
  window_class.lpfnWndProc = EmployeeAddWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void RegisterFolderManageClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kFolderManageClassName;
  window_class.lpfnWndProc = FolderManageWndProc;
  RegisterClass(&window_class);
  registered = true;
}

void RegisterFolderSubmenuClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kFolderSubmenuClassName;
  window_class.lpfnWndProc = FolderSubmenuWndProc;
  RegisterClass(&window_class);
  registered = true;
}

std::vector<FolderRoomState> FolderRoomsArgument(
    const flutter::EncodableMap& arguments) {
  std::vector<FolderRoomState> rooms;
  auto iterator = arguments.find(flutter::EncodableValue(std::string("rooms")));
  if (iterator == arguments.end()) {
    return rooms;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&iterator->second);
  if (!list) {
    return rooms;
  }
  for (const auto& item : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&item);
    if (!map) {
      continue;
    }
    FolderRoomState room;
    room.id = StringArgument(*map, "id");
    room.title = Utf16FromUtf8(StringArgument(*map, "title"));
    room.preview = Utf16FromUtf8(StringArgument(*map, "preview"));
    room.avatar_image_url = StringArgument(*map, "avatarImageUrl");
    room.avatar_color =
        ColorArgument(*map, "avatarColor", RGB(166, 198, 238));
    room.is_group = BoolArgument(*map, "isGroup", false);
    room.participant_count = IntArgument(*map, "participantCount", 1);
    room.unread_count = std::max(0, IntArgument(*map, "unreadCount", 0));
    room.avatar_parts = AvatarPartsArgument(*map);
    if (!room.id.empty()) {
      rooms.push_back(room);
    }
  }
  return rooms;
}

std::vector<NewChatUserState> NewChatUsersArgument(
    const flutter::EncodableMap& arguments) {
  std::vector<NewChatUserState> users;
  auto iterator = arguments.find(flutter::EncodableValue(std::string("users")));
  if (iterator == arguments.end()) {
    return users;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&iterator->second);
  if (!list) {
    return users;
  }
  for (const auto& item : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&item);
    if (!map) {
      continue;
    }
    NewChatUserState user;
    user.id = StringArgument(*map, "id");
    user.email = StringArgument(*map, "email");
    user.name = Utf16FromUtf8(StringArgument(*map, "name"));
    user.nickname = Utf16FromUtf8(StringArgument(*map, "nickname"));
    user.avatar_image_url = StringArgument(*map, "avatarImageUrl");
    user.avatar_color =
        ColorArgument(*map, "avatarColor", RGB(166, 198, 238));
    if (!user.id.empty()) {
      users.push_back(user);
    }
  }
  return users;
}

std::vector<FolderManageItemState> FolderManageItemsArgument(
    const flutter::EncodableMap& arguments) {
  std::vector<FolderManageItemState> folders;
  auto iterator =
      arguments.find(flutter::EncodableValue(std::string("folders")));
  if (iterator == arguments.end()) {
    return folders;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&iterator->second);
  if (!list) {
    return folders;
  }
  for (const auto& item : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&item);
    if (!map) {
      continue;
    }
    FolderManageItemState folder;
    folder.id = StringArgument(*map, "id");
    folder.name = Utf16FromUtf8(StringArgument(*map, "name"));
    folder.icon = Utf16FromUtf8(StringArgument(*map, "icon"));
    folder.count = IntArgument(*map, "count", 0);
    folder.is_favorite = BoolArgument(*map, "isFavorite", false);
    folder.is_system = BoolArgument(*map, "isSystem", false);
    if (!folder.id.empty()) {
      folders.push_back(folder);
    }
  }
  return folders;
}

std::vector<QuietRoomState> QuietRoomsArgument(
    const flutter::EncodableMap& arguments) {
  std::vector<QuietRoomState> rooms;
  auto iterator = arguments.find(flutter::EncodableValue(std::string("rooms")));
  if (iterator == arguments.end()) {
    return rooms;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&iterator->second);
  if (!list) {
    return rooms;
  }
  for (const auto& item : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&item);
    if (!map) {
      continue;
    }
    QuietRoomState room;
    room.id = StringArgument(*map, "id");
    room.title = Utf16FromUtf8(StringArgument(*map, "title"));
    room.preview = Utf16FromUtf8(StringArgument(*map, "preview"));
    room.time = Utf16FromUtf8(StringArgument(*map, "time"));
    room.avatar_color =
        ColorArgument(*map, "avatarColor", RGB(166, 198, 238));
    room.is_group = BoolArgument(*map, "isGroup", false);
    room.is_muted = BoolArgument(*map, "isMuted", false);
    room.unread_count = std::max(0, IntArgument(*map, "unreadCount", 0));
    room.participant_count = IntArgument(*map, "participantCount", 1);
    room.avatar_image_url = StringArgument(*map, "avatarImageUrl");
    room.avatar_parts = AvatarPartsArgument(*map);
    if (!room.id.empty()) {
      rooms.push_back(room);
    }
  }
  return rooms;
}

std::vector<NativeMenuItemState> NativeMenuItemsFromList(
    const flutter::EncodableList& list) {
  std::vector<NativeMenuItemState> items;
  for (const auto& item : list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&item);
    if (!map) {
      continue;
    }
    NativeMenuItemState menu_item;
    menu_item.value = StringArgument(*map, "value");
    menu_item.label = Utf16FromUtf8(StringArgument(*map, "label"));
    menu_item.icon = StringArgument(*map, "icon");
    menu_item.separator = BoolArgument(*map, "separator", false);
    menu_item.enabled = BoolArgument(*map, "enabled", true);
    menu_item.checked = BoolArgument(*map, "checked", false);
    auto children_iterator =
        map->find(flutter::EncodableValue(std::string("children")));
    if (children_iterator != map->end()) {
      if (const auto* children =
              std::get_if<flutter::EncodableList>(&children_iterator->second)) {
        menu_item.children = NativeMenuItemsFromList(*children);
      }
    }
    if (menu_item.separator || !menu_item.label.empty() ||
        !menu_item.value.empty() || !menu_item.children.empty()) {
      items.push_back(menu_item);
    }
  }
  return items;
}

std::vector<NativeMenuItemState> NativeMenuItemsArgument(
    const flutter::EncodableMap& arguments) {
  auto iterator = arguments.find(flutter::EncodableValue(std::string("items")));
  if (iterator == arguments.end()) {
    return {};
  }
  const auto* list = std::get_if<flutter::EncodableList>(&iterator->second);
  if (!list) {
    return {};
  }
  return NativeMenuItemsFromList(*list);
}

std::wstring NativeMenuDisplayLabel(const NativeMenuItemState& item) {
  if (item.icon == "quiet") {
    return L"\x2298  " + item.label;
  }
  if (item.icon == "spoiler") {
    return L"\x25CC  " + item.label;
  }
  if (!item.icon.empty()) {
    return Utf16FromUtf8(item.icon) + L"  " + item.label;
  }
  return item.label;
}

void AppendNativeMenuItems(HMENU menu,
                           const std::vector<NativeMenuItemState>& items,
                           UINT& next_command,
                           std::map<UINT, std::string>& commands) {
  for (const auto& item : items) {
    if (item.separator) {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      continue;
    }
    if (!item.children.empty()) {
      HMENU submenu = CreatePopupMenu();
      AppendNativeMenuItems(submenu, item.children, next_command, commands);
      UINT flags = MF_POPUP | (item.enabled ? MF_ENABLED : MF_GRAYED);
      std::wstring label = NativeMenuDisplayLabel(item);
      AppendMenuW(menu, flags, reinterpret_cast<UINT_PTR>(submenu),
                  label.c_str());
      continue;
    }
    UINT command = next_command++;
    commands[command] = item.value;
    UINT flags = MF_STRING | (item.enabled ? MF_ENABLED : MF_GRAYED) |
                 (item.checked ? MF_CHECKED : MF_UNCHECKED);
    std::wstring label = NativeMenuDisplayLabel(item);
    AppendMenuW(menu, flags, command, label.c_str());
  }
}

std::string ShowNativeContextMenu(HWND owner,
                                  const flutter::EncodableMap& arguments) {
  std::vector<NativeMenuItemState> items = NativeMenuItemsArgument(arguments);
  if (items.empty()) {
    return std::string();
  }

  double logical_x = DoubleArgument(arguments, "x", 0.0);
  double logical_y = DoubleArgument(arguments, "y", 0.0);
  UINT dpi = GetDpiForWindow(owner);
  POINT point{
      MulDiv(static_cast<int>(std::lround(logical_x)), dpi, 96),
      MulDiv(static_cast<int>(std::lround(logical_y)), dpi, 96)};
  ClientToScreen(owner, &point);

  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return std::string();
  }

  UINT next_command = 7000;
  std::map<UINT, std::string> commands;
  AppendNativeMenuItems(menu, items, next_command, commands);

  SetForegroundWindow(owner);
  UINT command = TrackPopupMenu(
      menu,
      TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_LEFTALIGN |
          TPM_TOPALIGN,
      point.x, point.y, 0, owner, nullptr);
  DestroyMenu(menu);
  PostMessage(owner, WM_NULL, 0, 0);

  auto iterator = commands.find(command);
  if (iterator == commands.end()) {
    return std::string();
  }
  return iterator->second;
}

std::string ShowNativeFolderSubmenu(
    HWND owner,
    const flutter::EncodableMap& arguments) {
  std::vector<FolderManageItemState> folders =
      FolderManageItemsArgument(arguments);
  if (folders.empty()) {
    return std::string();
  }

  double logical_x = DoubleArgument(arguments, "x", 0.0);
  double logical_y = DoubleArgument(arguments, "y", 0.0);
  UINT dpi = GetDpiForWindow(owner);
  POINT point{
      MulDiv(static_cast<int>(std::lround(logical_x)), dpi, 96),
      MulDiv(static_cast<int>(std::lround(logical_y)), dpi, 96)};
  ClientToScreen(owner, &point);

  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return std::string();
  }

  constexpr UINT kFolderSubmenuCommandBase = 5200;
  for (size_t index = 0; index < folders.size(); ++index) {
    std::wstring label = folders[index].icon;
    if (!label.empty()) {
      label += L" ";
    }
    label += folders[index].name;
    AppendMenuW(menu, MF_STRING,
                kFolderSubmenuCommandBase + static_cast<UINT>(index),
                label.c_str());
  }

  SetForegroundWindow(owner);
  UINT command = TrackPopupMenu(
      menu,
      TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_LEFTALIGN |
          TPM_TOPALIGN,
      point.x, point.y, 0, owner, nullptr);
  DestroyMenu(menu);
  PostMessage(owner, WM_NULL, 0, 0);

  if (command < kFolderSubmenuCommandBase ||
      command >= kFolderSubmenuCommandBase + folders.size()) {
    return std::string();
  }
  size_t selected_index = command - kFolderSubmenuCommandBase;
  return std::string("folder:") + folders[selected_index].id;
}

void CloseNativeFolderSubmenu() {
  if (g_active_folder_submenu_popup) {
    DestroyWindow(g_active_folder_submenu_popup);
    g_active_folder_submenu_popup = nullptr;
  }
}

void ShowNativeFolderSubmenuPopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments) {
  std::vector<FolderManageItemState> folders =
      FolderManageItemsArgument(arguments);
  if (folders.empty()) {
    CloseNativeFolderSubmenu();
    return;
  }

  RegisterFolderSubmenuClass();
  CloseNativeFolderSubmenu();

  double logical_x = DoubleArgument(arguments, "x", 0.0);
  double logical_y = DoubleArgument(arguments, "y", 0.0);
  double parent_width = DoubleArgument(arguments, "parentWidth", 152.0);
  double parent_height = DoubleArgument(arguments, "parentHeight", 28.0);
  UINT dpi = GetDpiForWindow(owner);
  POINT point{
      MulDiv(static_cast<int>(std::lround(logical_x)), dpi, 96),
      MulDiv(static_cast<int>(std::lround(logical_y)), dpi, 96)};
  ClientToScreen(owner, &point);
  int parent_width_px =
      MulDiv(static_cast<int>(std::lround(parent_width)), dpi, 96);
  int parent_height_px =
      MulDiv(static_cast<int>(std::lround(parent_height)), dpi, 96);
  int width = kFolderSubmenuWidth;
  int height = std::max(kFolderSubmenuRowHeight,
                        kFolderSubmenuRowHeight *
                            static_cast<int>(folders.size()));

  auto* state = new FolderSubmenuState();
  state->folders = folders;
  state->channel = channel;
  state->parent_rect = RECT{point.x - parent_width_px + 1, point.y,
                            point.x + 1, point.y + parent_height_px};

  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
      kFolderSubmenuClassName,
      L"AVA Folder Submenu",
      WS_POPUP,
      point.x,
      point.y,
      width,
      height,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  g_active_folder_submenu_popup = window;
  ShowWindow(window, SW_SHOWNOACTIVATE);
}

POINT PopupOriginForOwner(HWND owner, int width, int height) {
  RECT owner_rect{};
  GetWindowRect(owner, &owner_rect);
  RECT work_area{};
  SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);

  int x = owner_rect.left - width - 10;
  if (x < work_area.left + 8) {
    x = owner_rect.right + 10;
  }
  int y = owner_rect.top + 24;
  int top_limit = static_cast<int>(work_area.top) + 8;
  int bottom_limit = static_cast<int>(work_area.bottom) - height - 8;
  y = std::max(top_limit, std::min(y, bottom_limit));
  return POINT{x, y};
}

void ShowNativeFolderCreatePopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments) {
  RegisterFolderCreateClass();
  if (g_active_folder_create_popup) {
    DestroyWindow(g_active_folder_create_popup);
    g_active_folder_create_popup = nullptr;
  }

  auto* state = new FolderCreateState();
  state->rooms = FolderRoomsArgument(arguments);
  state->selected_room_ids = StringListArgument(arguments, "initialRoomIds");
  state->initial_name = Utf16FromUtf8(StringArgument(arguments, "initialName"));
  state->is_edit = BoolArgument(arguments, "isEdit", false);
  std::wstring initial_icon =
      Utf16FromUtf8(StringArgument(arguments, "initialIcon"));
  if (!initial_icon.empty()) {
    state->selected_icon = initial_icon;
  }
  state->channel = channel;

  POINT origin = PopupOriginForOwner(owner, kFolderCreateNativeWidth,
                                    kFolderCreateNativeHeight);
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW,
      kFolderCreateClassName,
      L"AVA Folder Create",
      WS_POPUP,
      origin.x,
      origin.y,
      kFolderCreateNativeWidth,
      kFolderCreateNativeHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kFolderCreateNativeWidth,
                           kFolderCreateNativeHeight);
  g_active_folder_create_popup = window;
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

void CloseNativeNewChatPopup() {
  if (g_active_new_chat_popup) {
    auto* state = reinterpret_cast<NewChatState*>(
        GetWindowLongPtr(g_active_new_chat_popup, GWLP_USERDATA));
    if (state) {
      state->submitted = true;
    }
    DestroyWindow(g_active_new_chat_popup);
    g_active_new_chat_popup = nullptr;
  }
}

void ShowNativeNewChatPopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments) {
  RegisterNewChatClass();
  CloseNativeNewChatPopup();

  auto* state = new NewChatState();
  state->users = NewChatUsersArgument(arguments);
  state->channel = channel;

  POINT origin =
      PopupOriginForOwner(owner, kNewChatNativeWidth, kNewChatNativeHeight);
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW,
      kNewChatClassName,
      L"AVA New Chat",
      WS_POPUP,
      origin.x,
      origin.y,
      kNewChatNativeWidth,
      kNewChatNativeHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kNewChatNativeWidth, kNewChatNativeHeight);
  g_active_new_chat_popup = window;
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

void ShowNativeEmployeeAddPopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel) {
  RegisterEmployeeAddClass();
  if (g_active_employee_add_popup) {
    DestroyWindow(g_active_employee_add_popup);
    g_active_employee_add_popup = nullptr;
  }

  auto* state = new EmployeeAddState();
  state->channel = channel;

  POINT origin = PopupOriginForOwner(owner, kEmployeeAddNativeWidth,
                                    kEmployeeAddNativeHeight);
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW,
      kEmployeeAddClassName,
      L"AVA Employee Add",
      WS_POPUP,
      origin.x,
      origin.y,
      kEmployeeAddNativeWidth,
      kEmployeeAddNativeHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kEmployeeAddNativeWidth,
                           kEmployeeAddNativeHeight);
  g_active_employee_add_popup = window;
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

void UpdateNativeEmployeeAddPopup(const flutter::EncodableMap& arguments) {
  if (!g_active_employee_add_popup) {
    return;
  }
  auto* state = reinterpret_cast<EmployeeAddState*>(
      GetWindowLongPtr(g_active_employee_add_popup, GWLP_USERDATA));
  if (!state) {
    return;
  }
  UpdateEmployeeResult(state, arguments);
  InvalidateRect(g_active_employee_add_popup, nullptr, TRUE);
}

void CloseNativeEmployeeAddPopup() {
  if (g_active_employee_add_popup) {
    auto* state = reinterpret_cast<EmployeeAddState*>(
        GetWindowLongPtr(g_active_employee_add_popup, GWLP_USERDATA));
    if (state) {
      state->submitted = true;
    }
    DestroyWindow(g_active_employee_add_popup);
    g_active_employee_add_popup = nullptr;
  }
}

void ShowNativeFolderManagePopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments) {
  RegisterFolderManageClass();
  if (g_active_folder_manage_popup) {
    DestroyWindow(g_active_folder_manage_popup);
    g_active_folder_manage_popup = nullptr;
  }

  auto* state = new FolderManageState();
  state->folders = FolderManageItemsArgument(arguments);
  state->unread_count = IntArgument(arguments, "unreadCount", 0);
  state->has_favorite = BoolArgument(arguments, "hasFavorite", false);
  state->channel = channel;

  POINT origin = PopupOriginForOwner(owner, kFolderManageNativeWidth,
                                    kFolderManageNativeHeight);
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW,
      kFolderManageClassName,
      L"AVA Folder Manage",
      WS_POPUP,
      origin.x,
      origin.y,
      kFolderManageNativeWidth,
      kFolderManageNativeHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kFolderManageNativeWidth,
                           kFolderManageNativeHeight);
  g_active_folder_manage_popup = window;
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

void CloseNativeQuietRoomsPopup() {
  if (g_active_quiet_rooms_popup) {
    DestroyWindow(g_active_quiet_rooms_popup);
    g_active_quiet_rooms_popup = nullptr;
  }
}

void ShowNativeQuietRoomsPopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments) {
  std::vector<QuietRoomState> rooms = QuietRoomsArgument(arguments);
  RegisterQuietRoomsClass();
  CloseNativeQuietRoomsPopup();
  if (rooms.empty()) {
    return;
  }

  auto* state = new QuietRoomsState();
  state->rooms = rooms;
  state->channel = channel;

  POINT origin = PopupOriginForOwner(owner, kQuietRoomsNativeWidth,
                                    kQuietRoomsNativeHeight);
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW,
      kQuietRoomsClassName,
      L"AVA Quiet Rooms",
      WS_POPUP,
      origin.x,
      origin.y,
      kQuietRoomsNativeWidth,
      kQuietRoomsNativeHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kQuietRoomsNativeWidth,
                           kQuietRoomsNativeHeight);
  g_active_quiet_rooms_popup = window;
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

void CloseNativeMultiLeaveRoomsPopup() {
  if (g_active_multi_leave_rooms_popup) {
    DestroyWindow(g_active_multi_leave_rooms_popup);
    g_active_multi_leave_rooms_popup = nullptr;
  }
}

void ShowNativeMultiLeaveRoomsPopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments) {
  std::vector<QuietRoomState> rooms = QuietRoomsArgument(arguments);
  RegisterMultiLeaveRoomsClass();
  CloseNativeMultiLeaveRoomsPopup();
  if (rooms.empty()) {
    return;
  }

  auto* state = new MultiLeaveRoomsState();
  state->rooms = rooms;
  state->channel = channel;

  POINT origin =
      PopupOriginForOwner(owner, kMultiLeaveNativeWidth, kMultiLeaveNativeHeight);
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW,
      kMultiLeaveRoomsClassName,
      L"AVA Multi Leave Rooms",
      WS_POPUP,
      origin.x,
      origin.y,
      kMultiLeaveNativeWidth,
      kMultiLeaveNativeHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kMultiLeaveNativeWidth,
                           kMultiLeaveNativeHeight);
  g_active_multi_leave_rooms_popup = window;
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

std::vector<ImageViewerItemState> ImageViewerItemsArgument(
    const flutter::EncodableMap& arguments) {
  std::vector<ImageViewerItemState> items;
  auto iterator =
      arguments.find(flutter::EncodableValue(std::string("images")));
  if (iterator == arguments.end()) {
    return items;
  }
  const auto* list = std::get_if<flutter::EncodableList>(&iterator->second);
  if (!list) {
    return items;
  }
  for (const auto& item : *list) {
    const auto* map = std::get_if<flutter::EncodableMap>(&item);
    if (!map) {
      continue;
    }
    ImageViewerItemState image;
    image.path = Utf16FromUtf8(StringArgument(*map, "path"));
    image.name = Utf16FromUtf8(StringArgument(*map, "name"));
    if (image.name.empty()) {
      image.name = ImageViewerFileNameOnly(image.path);
    }
    if (!image.path.empty()) {
      items.push_back(image);
    }
  }
  return items;
}

void ShowNativeImageViewerPopup(HWND owner,
                                const flutter::EncodableMap& arguments) {
  std::vector<ImageViewerItemState> items = ImageViewerItemsArgument(arguments);
  if (items.empty()) {
    return;
  }
  RegisterImageViewerClass();
  if (g_active_image_viewer) {
    DestroyWindow(g_active_image_viewer);
    g_active_image_viewer = nullptr;
  }

  auto* state = new ImageViewerState();
  state->items = std::move(items);
  state->index = std::clamp(IntArgument(arguments, "initialIndex", 0), 0,
                            static_cast<int>(state->items.size()) - 1);
  state->sender = Utf16FromUtf8(StringArgument(arguments, "sender"));
  state->date = Utf16FromUtf8(StringArgument(arguments, "date"));

  std::wstring title = state->sender;
  if (!state->date.empty()) {
    if (!title.empty()) {
      title += L"  ";
    }
    title += state->date;
  }
  if (title.empty()) {
    title = L"AVA";
  }

  RECT work_area{};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
  int width = std::min<int>(
      kImageViewerDefaultWidth,
      static_cast<int>(work_area.right - work_area.left) - 20);
  int height = std::min<int>(
      kImageViewerDefaultHeight,
      static_cast<int>(work_area.bottom - work_area.top) - 20);
  width = std::max(760, width);
  height = std::max(500, height);
  int x = work_area.left + (work_area.right - work_area.left - width) / 2;
  int y = work_area.top + (work_area.bottom - work_area.top - height) / 2;

  HWND window = CreateWindowExW(
      WS_EX_APPWINDOW,
      kImageViewerClassName,
      title.c_str(),
      WS_OVERLAPPEDWINDOW,
      x,
      y,
      width,
      height,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  g_active_image_viewer = window;
  ShowWindow(window, SW_SHOWNORMAL);
  UpdateWindow(window);
  SetForegroundWindow(window);
}

void ShowNativeVideoViewerPopup(HWND owner,
                                const flutter::EncodableMap& arguments) {
  std::wstring path = Utf16FromUtf8(StringArgument(arguments, "path"));
  if (path.empty() || !ImageViewerFileExists(path)) {
    return;
  }
  RegisterVideoViewerClass();
  if (g_active_video_viewer) {
    DestroyWindow(g_active_video_viewer);
    g_active_video_viewer = nullptr;
  }

  auto* state = new VideoViewerState();
  state->path = path;
  state->name = Utf16FromUtf8(StringArgument(arguments, "name"));
  if (state->name.empty()) {
    state->name = ImageViewerFileNameOnly(path);
  }
  state->sender = Utf16FromUtf8(StringArgument(arguments, "sender"));
  state->date = Utf16FromUtf8(StringArgument(arguments, "date"));

  std::wstring title = state->sender;
  if (!state->date.empty()) {
    if (!title.empty()) {
      title += L"  ";
    }
    title += state->date;
  }
  if (title.empty()) {
    title = L"AVA";
  }

  RECT work_area{};
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0);
  int width = std::min<int>(
      kVideoViewerDefaultWidth,
      static_cast<int>(work_area.right - work_area.left) - 20);
  int height = std::min<int>(
      kVideoViewerDefaultHeight,
      static_cast<int>(work_area.bottom - work_area.top) - 20);
  width = std::max(760, width);
  height = std::max(500, height);
  int x = work_area.left + (work_area.right - work_area.left - width) / 2;
  int y = work_area.top + (work_area.bottom - work_area.top - height) / 2;

  HWND window = CreateWindowExW(
      WS_EX_APPWINDOW,
      kVideoViewerClassName,
      title.c_str(),
      WS_OVERLAPPEDWINDOW,
      x,
      y,
      width,
      height,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  g_active_video_viewer = window;
  ShowWindow(window, SW_SHOWNORMAL);
  UpdateWindow(window);
  SetForegroundWindow(window);
}

void ShowNativeProfilePopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments) {
  RegisterProfilePopupClass();
  if (g_active_profile_popup) {
    DestroyWindow(g_active_profile_popup);
    g_active_profile_popup = nullptr;
  }
  if (g_active_profile_edit_popup) {
    DestroyWindow(g_active_profile_edit_popup);
    g_active_profile_edit_popup = nullptr;
  }

  auto* state = new ProfilePopupState();
  state->is_self = BoolArgument(arguments, "isSelf", false);
  state->id = StringArgument(arguments, "id");
  state->email = StringArgument(arguments, "email");
  state->avatar_image_url = StringArgument(arguments, "avatarImageUrl");
  state->background_image_url = StringArgument(arguments, "backgroundImageUrl");
  state->name = Utf16FromUtf8(StringArgument(arguments, "name"));
  state->nickname = Utf16FromUtf8(StringArgument(arguments, "nickname"));
  state->status_message =
      Utf16FromUtf8(StringArgument(arguments, "statusMessage"));
  state->avatar_color =
      ColorArgument(arguments, "avatarColor", RGB(122, 160, 106));
  state->background_color =
      ColorArgument(arguments, "backgroundColor", state->avatar_color);
  state->channel = channel;

  POINT origin =
      PopupOriginForOwner(owner, kProfilePopupNativeWidth,
                          kProfilePopupNativeHeight);
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW,
      kProfilePopupClassName,
      L"AVA Profile",
      WS_POPUP,
      origin.x,
      origin.y,
      kProfilePopupNativeWidth,
      kProfilePopupNativeHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kProfilePopupNativeWidth,
                           kProfilePopupNativeHeight);
  g_active_profile_popup = window;
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

void ShowNativeProfileEditPopup(
    HWND owner,
    flutter::MethodChannel<flutter::EncodableValue>* channel,
    const flutter::EncodableMap& arguments) {
  RegisterProfileEditClass();
  if (g_active_profile_popup) {
    DestroyWindow(g_active_profile_popup);
    g_active_profile_popup = nullptr;
  }
  if (g_active_profile_edit_popup) {
    DestroyWindow(g_active_profile_edit_popup);
    g_active_profile_edit_popup = nullptr;
  }

  auto* state = new ProfileEditState();
  state->id = StringArgument(arguments, "id");
  state->email = StringArgument(arguments, "email");
  state->avatar_image_url = StringArgument(arguments, "avatarImageUrl");
  state->name = Utf16FromUtf8(StringArgument(arguments, "name"));
  state->nickname = Utf16FromUtf8(StringArgument(arguments, "nickname"));
  state->status_message =
      Utf16FromUtf8(StringArgument(arguments, "statusMessage"));
  state->avatar_color =
      ColorArgument(arguments, "avatarColor", RGB(122, 160, 106));
  state->channel = channel;

  POINT origin = PopupOriginForOwner(owner, kProfileEditNativeWidth,
                                    kProfileEditNativeHeight);
  HWND window = CreateWindowExW(
      WS_EX_TOOLWINDOW,
      kProfileEditClassName,
      L"AVA Profile Edit",
      WS_POPUP,
      origin.x,
      origin.y,
      kProfileEditNativeWidth,
      kProfileEditNativeHeight,
      owner,
      nullptr,
      GetModuleHandle(nullptr),
      state);
  if (!window) {
    delete state;
    return;
  }
  ApplyRoundedWindowRegion(window, kProfileEditNativeWidth,
                           kProfileEditNativeHeight);
  g_active_profile_edit_popup = window;
  ShowWindow(window, SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

bool IsAvaOwnedForeground(HWND main_window) {
  HWND foreground = GetForegroundWindow();
  if (!foreground) {
    return false;
  }

  HWND ava_windows[] = {
      main_window,
      g_active_profile_popup,
      g_active_profile_edit_popup,
      g_active_folder_create_popup,
      g_active_employee_add_popup,
      g_active_folder_manage_popup,
      g_active_folder_submenu_popup,
      g_active_quiet_rooms_popup,
      g_active_multi_leave_rooms_popup,
      g_active_image_viewer,
      g_active_quiet_toast,
  };
  for (HWND current = foreground; current != nullptr;
       current = GetWindow(current, GW_OWNER)) {
    HWND root = GetAncestor(current, GA_ROOT);
    for (HWND ava_window : ava_windows) {
      if (!ava_window) {
        continue;
      }
      if (current == ava_window || root == ava_window ||
          IsChild(ava_window, current)) {
        return true;
      }
    }
    for (const auto& item : g_chat_floatings) {
      HWND floating = item.second;
      if (!floating) {
        continue;
      }
      if (current == floating || root == floating ||
          IsChild(floating, current)) {
        return true;
      }
    }
  }
  return false;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_added_) {
    return;
  }
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayIconMessage;
  data.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(data.szTip, L"AVA");
  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &data) == TRUE;
  if (tray_icon_added_) {
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  HWND window = GetHandle();
  if (!window) {
    tray_icon_added_ = false;
    return;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_icon_added_ = false;
}

void FlutterWindow::ShowTrayBalloon() {
  HWND window = GetHandle();
  if (!window || !tray_icon_added_) {
    return;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = kTrayIconId;
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO;
  wcscpy_s(data.szInfoTitle, L"AVA \xC2E4\xD589 \xC911");
  wcscpy_s(data.szInfo,
           L"\xCC3D\xC744 \xB2EB\xC544\xB3C4 \xC2DC\xC2A4\xD15C "
           L"\xD2B8\xB808\xC774\xC5D0\xC11C \xACC4\xC18D "
           L"\xC2E4\xD589\xB429\xB2C8\xB2E4.");
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void FlutterWindow::ShowMainWindowFromTray() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  if (quick_ai_window_mode_) {
    RestoreNormalWindowPlacement();
    quick_ai_window_mode_ = false;
  }
  SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOWNORMAL);
  SetForegroundWindow(window);
}

void FlutterWindow::HideToTray() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  if (!quick_ai_window_mode_) {
    StoreNormalWindowPlacement();
  }
  AddTrayIcon();
  ShowWindow(window, SW_HIDE);
  if (!tray_balloon_shown_) {
    ShowTrayBalloon();
    tray_balloon_shown_ = true;
  }
}

void FlutterWindow::ShowTrayMenu() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kTrayMenuOpen, L"\xC5F4\xAE30");
  AppendMenuW(menu, MF_STRING, kTrayMenuLock,
              L"\xC7A0\xAE08\xBAA8\xB4DC \xC124\xC815");
  AppendMenuW(menu, MF_STRING, kTrayMenuLogout,
              L"\xB85C\xADF8\xC544\xC6C3");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit, L"\xC885\xB8CC");

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(window);
  UINT command = TrackPopupMenu(menu,
                                TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
                                cursor.x, cursor.y, 0, window, nullptr);
  DestroyMenu(menu);
  PostMessage(window, WM_NULL, 0, 0);

  switch (command) {
    case kTrayMenuOpen:
      ShowMainWindowFromTray();
      InvokeTrayAction("open");
      break;
    case kTrayMenuLock:
      ShowMainWindowFromTray();
      InvokeTrayAction("lock");
      break;
    case kTrayMenuLogout:
      ShowMainWindowFromTray();
      InvokeTrayAction("logout");
      break;
    case kTrayMenuExit:
      ExitFromTray();
      break;
    default:
      break;
  }
}

void FlutterWindow::InvokeTrayAction(const std::string& action) {
  if (!window_channel_) {
    return;
  }
  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("action")] =
      flutter::EncodableValue(action);
  window_channel_->InvokeMethod(
      "trayMenuAction", std::make_unique<flutter::EncodableValue>(arguments));
}

void FlutterWindow::RegisterQuickAvaAiHotkey() {
  if (quick_hotkey_registered_) {
    return;
  }
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  quick_hotkey_registered_ =
      RegisterHotKey(window, kQuickAvaAiHotkeyId, MOD_CONTROL | MOD_NOREPEAT,
                     'Q') == TRUE;
}

void FlutterWindow::UnregisterQuickAvaAiHotkey() {
  if (!quick_hotkey_registered_) {
    return;
  }
  HWND window = GetHandle();
  if (window) {
    UnregisterHotKey(window, kQuickAvaAiHotkeyId);
  }
  quick_hotkey_registered_ = false;
}

void FlutterWindow::StoreNormalWindowPlacement() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(window, &placement)) {
    return;
  }
  normal_window_placement_ = placement;
  has_normal_window_placement_ = true;
}

void FlutterWindow::RestoreNormalWindowPlacement() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  if (has_normal_window_placement_) {
    WINDOWPLACEMENT placement = normal_window_placement_;
    placement.length = sizeof(WINDOWPLACEMENT);
    SetWindowPlacement(window, &placement);
    return;
  }
  ResizeWindowToLogicalSize(window, kCompactMessengerWidth,
                            kCompactMessengerHeight);
}

void FlutterWindow::ShowQuickAvaAiWindow() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  if (!quick_ai_window_mode_) {
    StoreNormalWindowPlacement();
  }
  PositionQuickAvaAiWindow(window);
  quick_ai_window_mode_ = true;
  if (!AnimateWindow(window, 180, AW_ACTIVATE | AW_SLIDE | AW_VER_NEGATIVE)) {
    ShowWindow(window, SW_SHOWNORMAL);
  }
  SetForegroundWindow(window);
}

void FlutterWindow::HideQuickAvaAiWindow() {
  HWND window = GetHandle();
  if (!window) {
    return;
  }
  if (IsWindowVisible(window)) {
    if (!AnimateWindow(window, 180, AW_HIDE | AW_SLIDE | AW_VER_POSITIVE)) {
      ShowWindow(window, SW_HIDE);
    }
  } else {
    ShowWindow(window, SW_HIDE);
  }
}

void FlutterWindow::InvokeQuickAvaAi() {
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod("quickAvaAiRequested", nullptr);
}

void FlutterWindow::ExitFromTray() {
  exit_requested_ = true;
  RemoveTrayIcon();
  HWND window = GetHandle();
  if (window) {
    DestroyWindow(window);
  }
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "ava/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        HWND window = GetHandle();
        if (!window) {
          result->Error("unavailable", "Window handle is unavailable.");
          return;
        }

        const std::string& method = call.method_name();
        if (method == "startDrag") {
          ReleaseCapture();
          SendMessage(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
        } else if (method == "minimize") {
          ShowWindow(window, SW_MINIMIZE);
          result->Success();
        } else if (method == "toggleMaximize") {
          ShowWindow(window, IsZoomed(window) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success();
        } else if (method == "close") {
          PostMessage(window, WM_CLOSE, 0, 0);
          result->Success();
        } else if (method == "setWindowTitle") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          std::string title = map ? StringArgument(*map, "title") : "AVA";
          if (title.empty()) {
            title = "AVA";
          }
          std::wstring window_title = Utf16FromUtf8(title);
          SetWindowTextW(window, window_title.c_str());
          result->Success();
        } else if (method == "compactMessenger") {
          ResizeWindowToLogicalWidth(window, kCompactMessengerWidth);
          result->Success();
        } else if (method == "expandMessenger") {
          ResizeWindowToLogicalWidth(window, kExpandedMessengerWidth);
          result->Success();
        } else if (method == "showMessengerWindow") {
          ShowMainWindowFromTray();
          result->Success();
        } else if (method == "showQuickAvaAiWindow") {
          ShowQuickAvaAiWindow();
          result->Success();
        } else if (method == "setQuickAvaAiEnabled") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          quick_ai_enabled_ =
              map ? BoolArgument(*map, "enabled", false) : false;
          result->Success();
        } else if (method == "openAzoomMessenger") {
          StorePreAzoomWindowPlacement(window);
          ResizeWindowToLogicalSize(window, kAzoomMessengerWidth,
                                    kAzoomMessengerHeight);
          result->Success();
        } else if (method == "restoreMessengerFromAzoom") {
          RestorePreAzoomWindowPlacement(window);
          result->Success();
        } else if (method == "setAzoomFullscreen") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          const bool fullscreen =
              map ? BoolArgument(*map, "fullscreen", false) : false;
          SetAzoomFullscreen(window, fullscreen);
          result->Success();
        } else if (method == "setMessengerOpacity") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          double opacity = map ? DoubleArgument(*map, "opacity", 1.0) : 1.0;
          opacity = std::clamp(opacity, 0.18, 1.0);
          LONG_PTR style = GetWindowLongPtr(window, GWL_EXSTYLE);
          SetWindowLongPtr(window, GWL_EXSTYLE, style | WS_EX_LAYERED);
          SetLayeredWindowAttributes(
              window, 0, static_cast<BYTE>(std::round(opacity * 255)),
              LWA_ALPHA);
          result->Success();
        } else if (method == "isAvaForeground") {
          result->Success(flutter::EncodableValue(IsAvaOwnedForeground(window)));
        } else if (method == "showProfilePopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args", "Profile popup arguments are invalid.");
            return;
          }
          ShowNativeProfilePopup(window, window_channel_.get(), *map);
          result->Success();
        } else if (method == "showProfileEditPopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Profile edit popup arguments are invalid.");
            return;
          }
          ShowNativeProfileEditPopup(window, window_channel_.get(), *map);
          result->Success();
        } else if (method == "showFolderCreatePopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args", "Folder popup arguments are invalid.");
            return;
          }
          ShowNativeFolderCreatePopup(window, window_channel_.get(), *map);
          result->Success();
        } else if (method == "showNewChatPopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args", "New chat popup arguments are invalid.");
            return;
          }
          ShowNativeNewChatPopup(window, window_channel_.get(), *map);
          result->Success();
        } else if (method == "closeNewChatPopup") {
          CloseNativeNewChatPopup();
          result->Success();
        } else if (method == "showEmployeeAddPopup") {
          ShowNativeEmployeeAddPopup(window, window_channel_.get());
          result->Success();
        } else if (method == "updateEmployeeAddPopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Employee popup arguments are invalid.");
            return;
          }
          UpdateNativeEmployeeAddPopup(*map);
          result->Success();
        } else if (method == "closeEmployeeAddPopup") {
          CloseNativeEmployeeAddPopup();
          result->Success();
        } else if (method == "showFolderManagePopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Folder manage popup arguments are invalid.");
            return;
          }
          ShowNativeFolderManagePopup(window, window_channel_.get(), *map);
          result->Success();
        } else if (method == "showFolderSubmenu") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Folder submenu arguments are invalid.");
            return;
          }
          result->Success(
              flutter::EncodableValue(ShowNativeFolderSubmenu(window, *map)));
        } else if (method == "showNativeMenu") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args", "Native menu arguments are invalid.");
            return;
          }
          result->Success(
              flutter::EncodableValue(ShowNativeContextMenu(window, *map)));
        } else if (method == "showFolderSubmenuPopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Folder submenu popup arguments are invalid.");
            return;
          }
          ShowNativeFolderSubmenuPopup(window, window_channel_.get(), *map);
          result->Success();
        } else if (method == "closeFolderSubmenuPopup") {
          CloseNativeFolderSubmenu();
          result->Success();
        } else if (method == "showQuietRoomsPopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Quiet rooms popup arguments are invalid.");
            return;
          }
          ShowNativeQuietRoomsPopup(window, window_channel_.get(), *map);
          result->Success();
        } else if (method == "closeQuietRoomsPopup") {
          CloseNativeQuietRoomsPopup();
          result->Success();
        } else if (method == "showMultiLeaveRoomsPopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Multi leave popup arguments are invalid.");
            return;
          }
          ShowNativeMultiLeaveRoomsPopup(window, window_channel_.get(), *map);
          result->Success();
        } else if (method == "closeMultiLeaveRoomsPopup") {
          CloseNativeMultiLeaveRoomsPopup();
          result->Success();
        } else if (method == "showImageViewerPopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Image viewer popup arguments are invalid.");
            return;
          }
          ShowNativeImageViewerPopup(window, *map);
          result->Success();
        } else if (method == "showVideoViewerPopup") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args",
                          "Video viewer popup arguments are invalid.");
            return;
          }
          ShowNativeVideoViewerPopup(window, *map);
          result->Success();
        } else if (method == "showChatNotification") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args", "Notification arguments are invalid.");
            return;
          }
          ShowNativeChatNotification(
              window_channel_.get(),
              StringArgument(*map, "roomId"),
              StringArgument(*map, "roomTitle"),
              StringArgument(*map, "senderName"),
              StringArgument(*map, "senderNickname"),
              ColorArgument(*map, "avatarColor", RGB(122, 160, 106)),
              StringArgument(*map, "body"));
          result->Success(flutter::EncodableValue(true));
        } else if (method == "showChatFloating" ||
                   method == "updateChatFloating") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (!map) {
            result->Error("bad_args", "Floating arguments are invalid.");
            return;
          }
          ShowOrUpdateChatFloating(
              window_channel_.get(), *map, method == "showChatFloating");
          result->Success();
        } else if (method == "closeChatFloating") {
          const auto* arguments = call.arguments();
          const auto* map = arguments
              ? std::get_if<flutter::EncodableMap>(arguments)
              : nullptr;
          if (map) {
            CloseChatFloating(StringArgument(*map, "roomId"));
          }
          result->Success();
        } else if (method == "closeAllChatFloatings") {
          CloseAllChatFloatings();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  AddTrayIcon();
  RegisterQuickAvaAiHotkey();
  HWND flutter_view_window = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view_window);
  file_drop_window_registered_ =
      RegisterFileDropTarget(GetHandle(), window_channel_.get());
  file_drop_view_window_ = flutter_view_window;
  file_drop_view_registered_ =
      RegisterFileDropTarget(flutter_view_window, window_channel_.get());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  UnregisterQuickAvaAiHotkey();
  RemoveTrayIcon();
  if (file_drop_view_registered_ && file_drop_view_window_) {
    RevokeDragDrop(file_drop_view_window_);
    file_drop_view_registered_ = false;
    file_drop_view_window_ = nullptr;
  }
  if (file_drop_window_registered_) {
    RevokeDragDrop(GetHandle());
    file_drop_window_registered_ = false;
  }
  if (g_active_profile_popup) {
    DestroyWindow(g_active_profile_popup);
    g_active_profile_popup = nullptr;
  }
  if (g_active_profile_edit_popup) {
    DestroyWindow(g_active_profile_edit_popup);
    g_active_profile_edit_popup = nullptr;
  }
  if (g_active_folder_create_popup) {
    DestroyWindow(g_active_folder_create_popup);
    g_active_folder_create_popup = nullptr;
  }
  if (g_active_employee_add_popup) {
    DestroyWindow(g_active_employee_add_popup);
    g_active_employee_add_popup = nullptr;
  }
  if (g_active_folder_manage_popup) {
    DestroyWindow(g_active_folder_manage_popup);
    g_active_folder_manage_popup = nullptr;
  }
  if (g_active_folder_submenu_popup) {
    DestroyWindow(g_active_folder_submenu_popup);
    g_active_folder_submenu_popup = nullptr;
  }
  if (g_active_quiet_rooms_popup) {
    DestroyWindow(g_active_quiet_rooms_popup);
    g_active_quiet_rooms_popup = nullptr;
  }
  if (g_active_multi_leave_rooms_popup) {
    DestroyWindow(g_active_multi_leave_rooms_popup);
    g_active_multi_leave_rooms_popup = nullptr;
  }
  if (g_active_image_viewer) {
    DestroyWindow(g_active_image_viewer);
    g_active_image_viewer = nullptr;
  }
  if (g_active_video_viewer) {
    DestroyWindow(g_active_video_viewer);
    g_active_video_viewer = nullptr;
  }
  if (g_active_quiet_toast) {
    DestroyWindow(g_active_quiet_toast);
    g_active_quiet_toast = nullptr;
  }
  if (g_active_notification) {
    DestroyWindow(g_active_notification);
    g_active_notification = nullptr;
  }
  CloseAllChatFloatings();
  window_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  ShutdownMediaFoundation();
  ShutdownOle();
  ShutdownGdiplus();

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == AvaShowMainWindowMessage()) {
    ShowMainWindowFromTray();
    InvokeTrayAction("open");
    return 0;
  }
  if (message == WM_CLOSE && !exit_requested_) {
    HideToTray();
    return 0;
  }
  if (message == kTrayIconMessage) {
    const UINT tray_event = LOWORD(lparam);
    if (tray_event == WM_RBUTTONUP || tray_event == WM_CONTEXTMENU) {
      ShowTrayMenu();
      return 0;
    }
    if (tray_event == WM_LBUTTONDBLCLK || tray_event == NIN_SELECT ||
        tray_event == WM_LBUTTONUP) {
      ShowMainWindowFromTray();
      InvokeTrayAction("open");
      return 0;
    }
  }
  if (message == WM_HOTKEY && static_cast<int>(wparam) == kQuickAvaAiHotkeyId) {
    if (quick_ai_window_mode_ && IsWindowVisible(hwnd)) {
      HideQuickAvaAiWindow();
    } else if (quick_ai_enabled_) {
      ShowQuickAvaAiWindow();
      InvokeQuickAvaAi();
    } else {
      ShowMainWindowFromTray();
      InvokeQuickAvaAi();
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
