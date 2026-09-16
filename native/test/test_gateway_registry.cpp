#include "gateway_registry.h"
#include "support/mock_telephony_service.h"

#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include <gtest/gtest.h>

namespace {

using namespace std::chrono_literals;

std::string private_bus_address() {
  const char *address = std::getenv("DBUS_SESSION_BUS_ADDRESS");
  return address == nullptr ? std::string{} : std::string{address};
}

TEST(GatewayRegistry, EmptyServiceHasAnEmptySnapshot) {
  pwt::test::MockTelephonyService service(private_bus_address(), false);
  service.start();
  auto connection =
      sdbus::createSessionBusConnectionWithAddress(private_bus_address());
  pwt::GatewayRegistry registry(*connection, [](const auto &, const auto &) {});

  EXPECT_TRUE(registry.synchronize().empty());
}

TEST(GatewayRegistry, DiscoversMultipleGatewaysAndRenewsReusedPaths) {
  pwt::test::MockTelephonyService service(private_bus_address());
  service.start();
  service.add_second_gateway();
  auto connection =
      sdbus::createSessionBusConnectionWithAddress(private_bus_address());

  std::mutex mutex;
  std::condition_variable changed;
  std::vector<std::pair<std::string, pwt::GatewayProperties>> events;
  pwt::GatewayRegistry registry(
      *connection,
      [&](const std::string &kind, const pwt::GatewayProperties &gateway) {
        {
          const std::lock_guard lock(mutex);
          events.emplace_back(kind, gateway);
        }
        changed.notify_all();
      });

  const auto snapshot = registry.synchronize();
  ASSERT_EQ(snapshot.size(), 2);
  std::map<std::string, pwt::GatewayProperties> gateways;
  for (const auto &gateway : snapshot) {
    gateways.emplace(gateway.path, gateway);
  }
  EXPECT_EQ(gateways.at(pwt::test::kGatewayPath).address, "AA:BB:CC:DD:EE:FF");
  EXPECT_EQ(gateways.at(pwt::test::kSecondGatewayPath).address,
            "11:22:33:44:55:66");
  const auto original_incarnation =
      gateways.at(pwt::test::kGatewayPath).incarnation;

  connection->enterEventLoopAsync();
  service.remove_gateway();
  service.add_gateway();

  std::unique_lock lock(mutex);
  ASSERT_TRUE(changed.wait_for(lock, 2s, [&] { return events.size() >= 2; }));
  ASSERT_EQ(events[0].first, "gatewayRemoved");
  ASSERT_EQ(events[1].first, "gatewayAdded");
  EXPECT_EQ(events[0].second.incarnation, original_incarnation);
  EXPECT_GT(events[1].second.incarnation, original_incarnation);
  const auto replacement_incarnation = events[1].second.incarnation;
  lock.unlock();

  EXPECT_FALSE(
      registry.contains(pwt::test::kGatewayPath, original_incarnation));
  EXPECT_TRUE(
      registry.contains(pwt::test::kGatewayPath, replacement_incarnation));
  connection->leaveEventLoop();
}

} // namespace
