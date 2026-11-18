#include "flutter_window.h"

#include <chrono>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <optional>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// Shared state that outlives the MethodResult owned by the channel.
struct ShutdownSignal {
  void Complete() {
    {
      std::lock_guard<std::mutex> lock(mutex);
      completed = true;
    }
    condition.notify_all();
  }

  void Wait(std::chrono::milliseconds timeout) {
    std::unique_lock<std::mutex> lock(mutex);
    condition.wait_for(lock, timeout, [this] { return completed; });
  }

  std::mutex mutex;
  std::condition_variable condition;
  bool completed = false;
};

class ShutdownResult : public flutter::MethodResult<flutter::EncodableValue> {
 public:
  explicit ShutdownResult(std::shared_ptr<ShutdownSignal> signal)
      : signal_(std::move(signal)) {}

 protected:
  void SuccessInternal(const flutter::EncodableValue*) override {
    signal_->Complete();
  }

  void ErrorInternal(const std::string&, const std::string&,
                     const flutter::EncodableValue*) override {
    signal_->Complete();
  }

  void NotImplementedInternal() override { signal_->Complete(); }

 private:
  std::shared_ptr<ShutdownSignal> signal_;
};

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  if (flutter_controller_) {
    // Give Dart a bounded chance to stop and log the hidden API before the
    // engine is torn down. The Windows job handle still reaps the whole child
    // tree if this callback is missed or times out.
    auto signal = std::make_shared<ShutdownSignal>();
    flutter::MethodChannel<flutter::EncodableValue> lifecycle_channel(
        flutter_controller_->engine()->messenger(), "aura_hub/lifecycle",
        &flutter::StandardMethodCodec::GetInstance());
    lifecycle_channel.InvokeMethod(
        "shutdown", nullptr, std::make_unique<ShutdownResult>(signal));
    signal->Wait(std::chrono::seconds(3));
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
