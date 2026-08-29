#include <ApplicationServices/ApplicationServices.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <optional>
#include <pqrs/karabiner/driverkit/virtual_hid_device_driver.hpp>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
#include <string>
#include <thread>
#include <vector>

namespace {
using client_type = pqrs::karabiner::driverkit::virtual_hid_device_service::client;
using pointing_input = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report::pointing_input;

struct options {
  std::optional<CGPoint> target;
  bool click = true;
};

std::optional<double> parse_number(const char* value) {
  char* end = nullptr;
  const auto result = std::strtod(value, &end);
  if (end == value || *end != '\0' || !std::isfinite(result)) {
    return std::nullopt;
  }
  return result;
}

std::optional<options> parse_options(int argc, char* argv[]) {
  if (argc == 1) {
    return options{};
  }
  if (argc != 4) {
    return std::nullopt;
  }

  const std::string mode(argv[1]);
  if (mode != "--target" && mode != "--move") {
    return std::nullopt;
  }

  const auto x = parse_number(argv[2]);
  const auto y = parse_number(argv[3]);
  if (!x || !y) {
    return std::nullopt;
  }

  return options{
      .target = CGPointMake(*x, *y),
      .click = mode == "--target",
  };
}

std::optional<CGPoint> cursor_location() {
  const auto event = CGEventCreate(nullptr);
  if (!event) {
    return std::nullopt;
  }

  const auto location = CGEventGetLocation(event);
  CFRelease(event);
  return location;
}

bool is_on_active_display(CGPoint point) {
  uint32_t count = 0;
  if (CGGetActiveDisplayList(0, nullptr, &count) != kCGErrorSuccess || count == 0) {
    return false;
  }

  std::vector<CGDirectDisplayID> displays(count);
  if (CGGetActiveDisplayList(count, displays.data(), &count) != kCGErrorSuccess) {
    return false;
  }

  for (uint32_t i = 0; i < count; ++i) {
    if (CGRectContainsPoint(CGDisplayBounds(displays[i]), point)) {
      return true;
    }
  }
  return false;
}

int8_t movement_for_error(double error) {
  if (std::abs(error) <= 0.75) {
    return 0;
  }

  auto movement = static_cast<int>(std::lround(error * 0.2));
  if (movement == 0) {
    movement = error > 0 ? 1 : -1;
  }
  return static_cast<int8_t>(std::clamp(movement, -64, 64));
}

bool move_to(client_type& client, CGPoint target, CGPoint& final_location, size_t& report_count) {
  constexpr size_t maximum_reports = 800;
  report_count = 0;

  while (report_count < maximum_reports) {
    const auto current = cursor_location();
    if (!current) {
      return false;
    }

    const auto error_x = target.x - current->x;
    const auto error_y = target.y - current->y;
    if (std::abs(error_x) <= 0.75 && std::abs(error_y) <= 0.75) {
      final_location = *current;
      return true;
    }

    const auto x = movement_for_error(error_x);
    const auto y = movement_for_error(error_y);
    pointing_input report;
    report.x = static_cast<uint8_t>(x);
    report.y = static_cast<uint8_t>(y);
    client.async_post_report(report);
    ++report_count;
    std::this_thread::sleep_for(std::chrono::milliseconds(18));
  }

  const auto current = cursor_location();
  if (current) {
    final_location = *current;
  }
  return false;
}
} // namespace

int main(int argc, char* argv[]) {
  const auto parsed_options = parse_options(argc, argv);
  if (!parsed_options) {
    std::cerr << "usage: virtual-hid-device-service-client [--move x y | --target x y]" << std::endl;
    return 2;
  }
  if (parsed_options->target && !is_on_active_display(*parsed_options->target)) {
    std::cerr << "target is outside all active displays" << std::endl;
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

      if (parsed_options->target) {
        CGPoint final_location = CGPointZero;
        size_t report_count = 0;
        if (!move_to(*client, *parsed_options->target, final_location, report_count)) {
          std::cerr << "failed to reach target; final=" << final_location.x << "," << final_location.y
                    << " reports=" << report_count << std::endl;
          failed = true;
          complete = true;
          return;
        }
        std::cout << "moved target=" << parsed_options->target->x << "," << parsed_options->target->y
                  << " actual=" << final_location.x << "," << final_location.y
                  << " reports=" << report_count << std::endl;
      }

      if (parsed_options->click) {
        pointing_input down;
        down.buttons.insert(1);
        client->async_post_report(down);

        std::this_thread::sleep_for(std::chrono::milliseconds(120));

        pointing_input up;
        client->async_post_report(up);
      }

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

  client = nullptr;
  std::this_thread::sleep_for(std::chrono::milliseconds(200));
  pqrs::dispatcher::extra::terminate_shared_dispatcher();

  if (failed) {
    return 1;
  }

  if (parsed_options->click) {
    std::cout << "sent virtual HID left click" << std::endl;
  }
  return 0;
}
