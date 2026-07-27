// Minimal reference entrypoint. `flutter create .` regenerates the full
// Windows runner (flutter_window, utils, resources) on a Windows host.
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

int APIENTRY wWinMain(_In_ HINSTANCE, _In_opt_ HINSTANCE, _In_ wchar_t*, _In_ int) {
  return EXIT_SUCCESS;
}
