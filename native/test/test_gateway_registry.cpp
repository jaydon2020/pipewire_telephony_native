#include "gateway_registry.h"
#include "support/mock_telephony_service.h"

#include <algorithm>
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
  pwt::GatewayRegistry registry(
      *connection, [](const auto &, const auto &) {},
      [](const auto &, const auto &) {});

  registry.synchronize();
  const auto snapshot = registry.activate();
  EXPECT_TRUE(snapshot.gateways.empty());
  EXPECT_TRUE(snapshot.calls.empty());
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
  std::vector<std::pair<std::string, pwt::CallProperties>> call_events;
  pwt::GatewayRegistry registry(
      *connection,
      [&](const std::string &kind, const pwt::GatewayProperties &gateway) {
        {
          const std::lock_guard lock(mutex);
          events.emplace_back(kind, gateway);
        }
        changed.notify_all();
      },
      [&](const std::string &kind, const pwt::CallProperties &call) {
        {
          const std::lock_guard lock(mutex);
          call_events.emplace_back(kind, call);
        }
        changed.notify_all();
      });

  registry.synchronize();
  const auto snapshot = registry.activate();
  ASSERT_EQ(snapshot.gateways.size(), 2);
  ASSERT_EQ(snapshot.calls.size(), 1);
  EXPECT_EQ(snapshot.calls.front().gatewayPath, pwt::test::kGatewayPath);
  std::map<std::string, pwt::GatewayProperties> gateways;
  for (const auto &gateway : snapshot.gateways) {
    gateways.emplace(gateway.path, gateway);
  }
  EXPECT_EQ(gateways.at(pwt::test::kGatewayPath).address, "AA:BB:CC:DD:EE:FF");
  EXPECT_EQ(gateways.at(pwt::test::kSecondGatewayPath).address,
            "11:22:33:44:55:66");
  const auto original_incarnation =
      gateways.at(pwt::test::kGatewayPath).incarnation;
  const auto original_call_incarnation = snapshot.calls.front().incarnation;

  connection->enterEventLoopAsync();
  service.remove_gateway();
  service.add_gateway();
  service.add_call();

  std::unique_lock lock(mutex);
  ASSERT_TRUE(changed.wait_for(
      lock, 2s, [&] { return events.size() >= 2 && call_events.size() >= 2; }));
  ASSERT_EQ(events[0].first, "gatewayRemoved");
  ASSERT_EQ(events[1].first, "gatewayAdded");
  EXPECT_EQ(events[0].second.incarnation, original_incarnation);
  EXPECT_GT(events[1].second.incarnation, original_incarnation);
  const auto replacement_incarnation = events[1].second.incarnation;
  EXPECT_EQ(call_events[0].first, "callRemoved");
  EXPECT_EQ(call_events[0].second.incarnation, original_call_incarnation);
  const auto added_call =
      std::ranges::find_if(call_events, [](const auto &event) {
        return event.first == "callAdded";
      });
  ASSERT_NE(added_call, call_events.end());
  EXPECT_GT(added_call->second.incarnation, original_call_incarnation);
  const auto replacement_call_incarnation = added_call->second.incarnation;
  lock.unlock();

  EXPECT_FALSE(
      registry.contains(pwt::test::kGatewayPath, original_incarnation));
  EXPECT_TRUE(
      registry.contains(pwt::test::kGatewayPath, replacement_incarnation));
  EXPECT_FALSE(
      registry.contains_call(pwt::test::kCallPath, original_call_incarnation));
  EXPECT_TRUE(registry.contains_call(pwt::test::kCallPath,
                                     replacement_call_incarnation));
  connection->leaveEventLoop();
}

} // namespace
