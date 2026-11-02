#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kAppMutexName[] = L"LeemonPOSDesktopSingleInstance";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"Leemon";

// Before Flutter loads application assets, recover an interrupted file swap.
// A trial/recovery launch from the updater is the only launch allowed while
// its file lock is held.
bool HandlePendingUpdate(const std::vector<std::string>& arguments) {
  for (size_t i = 0; i + 1 < arguments.size(); ++i) {
    if (arguments[i] == "--leemon-update-token" &&
        arguments[i + 1].size() == 32) return false;
  }
  wchar_t executable[32768];
  const DWORD length = ::GetModuleFileNameW(nullptr, executable, 32768);
  if (length == 0 || length >= 32768) return false;
  const std::wstring full(executable, length);
  const std::wstring directory = full.substr(0, full.find_last_of(L"\\/"));
  const auto work = directory + L"\\.leemon-update\\";
  HANDLE lock = ::CreateFileW((work + L"active.lock").c_str(),
      GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE |
      FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (lock == INVALID_HANDLE_VALUE && ::GetLastError() == ERROR_SHARING_VIOLATION) {
    ::MessageBoxW(nullptr, L"Обновление кассы ещё выполняется. Дождитесь автоматического запуска.",
        L"Обновление кассы", MB_OK | MB_ICONINFORMATION);
    return true;
  }
  if (lock != INVALID_HANDLE_VALUE) ::CloseHandle(lock);
  if (::GetFileAttributesW((work + L"pending.json").c_str()) == INVALID_FILE_ATTRIBUTES)
    return false;
  auto helper = directory + L"\\Leemon.Updater.exe";
  if (::GetFileAttributesW(helper.c_str()) == INVALID_FILE_ATTRIBUTES)
    helper = directory + L"\\updater\\Leemon.Updater.exe";
  std::wstring command = L"\"" + helper + L"\" --recover-only --target-dir \"" +
      directory + L"\" --app-exe Leemon.exe";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (::CreateProcessW(helper.c_str(), command.data(), nullptr, nullptr, FALSE,
      CREATE_NO_WINDOW, nullptr, directory.c_str(), &startup, &process)) {
    ::CloseHandle(process.hThread);
    ::CloseHandle(process.hProcess);
  } else {
    ::MessageBoxW(nullptr,
        L"Не удалось восстановить прерванное обновление. Запустите установщик кассы повторно. Данные продаж сохранены отдельно.",
        L"Восстановление кассы", MB_OK | MB_ICONERROR);
  }
  return true;
}

void ActivateExistingWindow() {
  HWND existing_window = ::FindWindow(kWindowClassName, kWindowTitle);
  if (existing_window == nullptr) {
    return;
  }

  if (::IsIconic(existing_window)) {
    ::ShowWindow(existing_window, SW_RESTORE);
  } else {
    ::ShowWindow(existing_window, SW_SHOWNORMAL);
  }
  ::SetForegroundWindow(existing_window);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  if (HandlePendingUpdate(command_line_arguments)) return EXIT_SUCCESS;
  HANDLE app_mutex = ::CreateMutex(nullptr, TRUE, kAppMutexName);
  if (app_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingWindow();
    ::CloseHandle(app_mutex);
    return EXIT_SUCCESS;
  }

  // A POS terminal must stay available while the application is running.
  // ES_CONTINUOUS keeps this request in effect until it is explicitly reset
  // below (or the process exits).
  ::SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED |
                            ES_DISPLAY_REQUIRED);

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Leemon", origin, size)) {
    ::SetThreadExecutionState(ES_CONTINUOUS);
    if (app_mutex != nullptr) {
      ::CloseHandle(app_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::SetThreadExecutionState(ES_CONTINUOUS);
  ::CoUninitialize();
  if (app_mutex != nullptr) {
    ::CloseHandle(app_mutex);
  }
  return EXIT_SUCCESS;
}
