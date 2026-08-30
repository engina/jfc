#include <atomic>
#include <chrono>
#include <iostream>
#include <memory>
#include <pqrs/karabiner/driverkit/virtual_hid_device_driver.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
#include <thread>

namespace {
using client_type = pqrs::karabiner::driverkit::virtual_hid_device_service::client;
using pointing_input = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::pointing_input;
} // namespace

int main(int argc, char*[]) {
  if (argc != 1) {
    std::cerr << "usage: jfc-e2e-virtual-hid-click" << std::endl;
    return 2;
  }

  pqrs::dispatcher::extra::initialize_shared_dispatcher();

  std::atomic<bool> started(false);
  std::atomic<bool> complete(false);
  std::atomic<bool> failed(false);
  std::thread action_thread;
  auto client = std::make_unique<client_type>();

  client->warning_reported.connect([&](const auto& message) {
    std::cerr << "warning: " << message << std::endl;
  });
  client->connect_failed.connect([&](const auto& error) {
    std::cerr << "connect failed: " << error << std::endl;
    failed = true;
    complete = true;
  });
  client->error_occurred.connect([&](const auto& error) {
    std::cerr << "client error: " << error << std::endl;
    failed = true;
    complete = true;
  });
  client->connected.connect([&] {
    client->async_virtual_hid_pointing_initialize();
  });
  client->virtual_hid_pointing_ready.connect([&](bool ready) {
    if (!ready || started.exchange(true)) {
      return;
    }

    action_thread = std::thread([&] {
      std::this_thread::sleep_for(std::chrono::milliseconds(200));

      pointing_input down;
      down.buttons.insert(1);
      client->async_post_report(down);

      std::this_thread::sleep_for(std::chrono::milliseconds(120));

      pointing_input up;
      client->async_post_report(up);

      std::this_thread::sleep_for(std::chrono::milliseconds(500));
      complete = true;
    });
  });

  client->async_start();

  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(25);
  while (!complete && std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(25));
  }

  if (!complete) {
    std::cerr << "timed out waiting for virtual pointing device" << std::endl;
    failed = true;
  }

  if (action_thread.joinable()) {
    action_thread.join();
  }

  client->async_stop();
  std::this_thread::sleep_for(std::chrono::milliseconds(200));
  client = nullptr;
  pqrs::dispatcher::extra::terminate_shared_dispatcher();

  if (failed) {
    return 1;
  }

  std::cout << "sent virtual HID left click" << std::endl;
  return 0;
}
