/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

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
      [](const auto &, const auto &) {}, [](const auto &, const auto &) {});

  registry.synchronize();
  const auto snapshot = registry.activate();
  EXPECT_TRUE(snapshot.gateways.empty());
  EXPECT_TRUE(snapshot.calls.empty());
  EXPECT_TRUE(snapshot.transports.empty());
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
      },
      [](const auto &, const auto &) {});

  registry.synchronize();
  const auto snapshot = registry.activate();
  ASSERT_EQ(snapshot.gateways.size(), 2);
  ASSERT_EQ(snapshot.calls.size(), 1);
  ASSERT_EQ(snapshot.transports.size(), 2);
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

TEST(GatewayRegistry, RenewsTransportIdentityAfterInterfaceReuse) {
  pwt::test::MockTelephonyService service(private_bus_address());
  service.start();
  auto connection =
      sdbus::createSessionBusConnectionWithAddress(private_bus_address());

  std::mutex mutex;
  std::condition_variable changed;
  std::vector<std::pair<std::string, pwt::GatewayProperties>> gateway_events;
  std::vector<std::pair<std::string, pwt::TransportProperties>>
      transport_events;
  pwt::GatewayRegistry registry(
      *connection,
      [&](const std::string &kind, const pwt::GatewayProperties &gateway) {
        {
          const std::lock_guard lock(mutex);
          gateway_events.emplace_back(kind, gateway);
        }
        changed.notify_all();
      },
      [](const auto &, const auto &) {},
      [&](const std::string &kind, const pwt::TransportProperties &transport) {
        {
          const std::lock_guard lock(mutex);
          transport_events.emplace_back(kind, transport);
        }
        changed.notify_all();
      });
  registry.synchronize();
  const auto snapshot = registry.activate();
  ASSERT_EQ(snapshot.transports.size(), 1);
  const auto original = snapshot.transports.front();
  EXPECT_EQ(original.path, pwt::test::kGatewayPath);
  EXPECT_EQ(original.state, "active");
  EXPECT_EQ(original.codec, 2);
  EXPECT_EQ(original.rejectSco, false);
  EXPECT_TRUE(service.invocations().empty());

  connection->enterEventLoopAsync();
  service.remove_transport();
  service.add_transport();

  std::unique_lock lock(mutex);
  ASSERT_TRUE(changed.wait_for(lock, 2s, [&] {
    return transport_events.size() >= 2 && gateway_events.size() >= 2;
  }));
  EXPECT_EQ(transport_events[0].first, "transportRemoved");
  EXPECT_EQ(transport_events[1].first, "transportAdded");
  EXPECT_EQ(transport_events[0].second.incarnation, original.incarnation);
  EXPECT_GT(transport_events[1].second.incarnation, original.incarnation);
  EXPECT_EQ(gateway_events[0].first, "gatewayChanged");
  EXPECT_EQ(gateway_events[1].first, "gatewayChanged");
  const auto replacement = transport_events[1].second.incarnation;
  lock.unlock();

  EXPECT_FALSE(registry.contains_transport(pwt::test::kGatewayPath,
                                           original.incarnation));
  EXPECT_TRUE(
      registry.contains_transport(pwt::test::kGatewayPath, replacement));
  connection->leaveEventLoop();
}

TEST(GatewayRegistry, AppliesPartialChangesAndRefreshesInvalidations) {
  pwt::test::MockTelephonyService service(private_bus_address());
  service.start();
  auto connection =
      sdbus::createSessionBusConnectionWithAddress(private_bus_address());

  std::mutex mutex;
  std::condition_variable changed;
  std::vector<pwt::GatewayProperties> gateway_events;
  std::vector<pwt::CallProperties> call_events;
  pwt::GatewayRegistry registry(
      *connection,
      [&](const std::string &kind, const pwt::GatewayProperties &gateway) {
        if (kind != "gatewayChanged")
          return;
        {
          const std::lock_guard lock(mutex);
          gateway_events.push_back(gateway);
        }
        changed.notify_all();
      },
      [&](const std::string &kind, const pwt::CallProperties &call) {
        if (kind != "callChanged")
          return;
        {
          const std::lock_guard lock(mutex);
          call_events.push_back(call);
        }
        changed.notify_all();
      },
      [](const auto &, const auto &) {});
  registry.synchronize();
  registry.activate();
  connection->enterEventLoopAsync();

  service.change_gateway_state({.address = "AA:BB:CC:DD:EE:FF",
                                .speakerVolume = 0,
                                .microphoneVolume = 10},
                               {"SpeakerVolume"});
  service.change_call_state({.lineIdentification = "+123",
                             .incomingLine = "",
                             .name = "Ada",
                             .multiparty = false,
                             .state = "future-ringing"},
                            {"IncomingLine", "Multiparty", "State"});

  std::unique_lock lock(mutex);
  ASSERT_TRUE(changed.wait_for(lock, 2s, [&] {
    return !gateway_events.empty() && !call_events.empty();
  }));
  EXPECT_EQ(gateway_events.front().speakerVolume, 0);
  EXPECT_EQ(gateway_events.front().microphoneVolume, 10);
  EXPECT_EQ(gateway_events.front().changed,
            std::vector<std::string>{"SpeakerVolume"});
  EXPECT_EQ(call_events.front().incomingLine, "");
  EXPECT_EQ(call_events.front().multiparty, false);
  EXPECT_EQ(call_events.front().state, "future-ringing");
  lock.unlock();

  service.change_gateway_state({.address = "AA:BB:CC:DD:EE:FF",
                                .speakerVolume = 0,
                                .microphoneVolume = 0},
                               {}, {"MicrophoneVolume"});
  service.change_call_state({.lineIdentification = "+123",
                             .incomingLine = "",
                             .name = "Grace",
                             .multiparty = false,
                             .state = "future-ringing"},
                            {}, {"Name"});

  lock.lock();
  ASSERT_TRUE(changed.wait_for(lock, 2s, [&] {
    return gateway_events.size() >= 3 && call_events.size() >= 3;
  }));
  EXPECT_EQ(gateway_events[1].microphoneVolume, std::nullopt);
  EXPECT_EQ(gateway_events[2].microphoneVolume, 0);
  EXPECT_EQ(call_events[1].name, std::nullopt);
  EXPECT_EQ(call_events[2].name, "Grace");
  lock.unlock();
  connection->leaveEventLoop();
}

} // namespace
