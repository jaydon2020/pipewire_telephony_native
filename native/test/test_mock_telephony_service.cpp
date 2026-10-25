/*
 * Copyright (c) 2026 Jian De jiande2020@gmail.com. All rights reserved.
 *
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include "support/mock_telephony_service.h"

#include <array>
#include <cstdlib>
#include <map>
#include <memory>
#include <string>

#include <gtest/gtest.h>
#include <sdbus-c++/sdbus-c++.h>

namespace {

using Properties = std::map<sdbus::PropertyName, sdbus::Variant>;
using Interfaces = std::map<sdbus::InterfaceName, Properties>;
using ManagedObjects = std::map<sdbus::ObjectPath, Interfaces>;

class MockTelephonyServiceTest : public ::testing::Test {
protected:
  void SetUp() override {
    const char *address = std::getenv("DBUS_SESSION_BUS_ADDRESS");
    ASSERT_NE(address, nullptr);
    address_ = address;
    service_ = std::make_unique<pwt::test::MockTelephonyService>(address_);
    service_->start();
    client_ = sdbus::createSessionBusConnectionWithAddress(address_);
  }

  void TearDown() override {
    client_.reset();
    service_.reset();
  }

  ManagedObjects managed_objects(const char *path) {
    auto proxy = sdbus::createProxy(*client_,
                                    sdbus::ServiceName{pwt::test::kServiceName},
                                    sdbus::ObjectPath{path});
    ManagedObjects objects;
    proxy->callMethod("GetManagedObjects")
        .onInterface("org.freedesktop.DBus.ObjectManager")
        .storeResultsTo(objects);
    return objects;
  }

  std::string address_;
  std::unique_ptr<pwt::test::MockTelephonyService> service_;
  std::unique_ptr<sdbus::IConnection> client_;
};

TEST_F(MockTelephonyServiceTest, ExposesNestedObjectManagersAndExactVariants) {
  const auto root = managed_objects(pwt::test::kRootPath);
  const auto &gateway = root.at(sdbus::ObjectPath{pwt::test::kGatewayPath});
  const auto &gateway_properties =
      gateway.at(sdbus::InterfaceName{pwt::test::kGatewayInterface});
  EXPECT_EQ(
      gateway_properties.at(sdbus::PropertyName{"Address"}).get<std::string>(),
      "AA:BB:CC:DD:EE:FF");
  EXPECT_EQ(gateway_properties.at(sdbus::PropertyName{"SpeakerVolume"})
                .get<uint8_t>(),
            12);
  EXPECT_EQ(gateway.at(sdbus::InterfaceName{pwt::test::kTransportInterface})
                .at(sdbus::PropertyName{"Codec"})
                .get<uint8_t>(),
            2);
  EXPECT_FALSE(gateway.at(sdbus::InterfaceName{pwt::test::kTransportInterface})
                   .at(sdbus::PropertyName{"RejectSCO"})
                   .get<bool>());

  const auto calls = managed_objects(pwt::test::kGatewayPath);
  const auto &call = calls.at(sdbus::ObjectPath{pwt::test::kCallPath})
                         .at(sdbus::InterfaceName{pwt::test::kCallInterface});
  EXPECT_EQ(
      call.at(sdbus::PropertyName{"LineIdentification"}).get<std::string>(),
      "+123");
  EXPECT_EQ(call.at(sdbus::PropertyName{"IncomingLine"}).get<std::string>(),
            "");
  EXPECT_FALSE(call.at(sdbus::PropertyName{"Multiparty"}).get<bool>());
}

TEST_F(MockTelephonyServiceTest, RecordsMethodsPropertiesAndConfiguredErrors) {
  auto gateway =
      sdbus::createProxy(*client_, sdbus::ServiceName{pwt::test::kServiceName},
                         sdbus::ObjectPath{pwt::test::kGatewayPath});
  gateway->callMethod("Dial")
      .onInterface(pwt::test::kGatewayInterface)
      .withArguments(std::string{"+123#"});
  for (const auto method :
       std::array{"SwapCalls", "ReleaseAndAnswer", "ReleaseAndSwap",
                  "HoldAndAnswer", "HangupAll", "CreateMultiparty"}) {
    gateway->callMethod(method).onInterface(pwt::test::kGatewayInterface);
  }
  gateway->callMethod("SendTones")
      .onInterface(pwt::test::kGatewayInterface)
      .withArguments(std::string{"12#"});
  gateway->callMethod("Activate").onInterface(pwt::test::kTransportInterface);

  auto call =
      sdbus::createProxy(*client_, sdbus::ServiceName{pwt::test::kServiceName},
                         sdbus::ObjectPath{pwt::test::kCallPath});
  call->callMethod("Answer").onInterface(pwt::test::kCallInterface);
  call->callMethod("Hangup").onInterface(pwt::test::kCallInterface);

  const auto invocations = service_->invocations();
  ASSERT_EQ(invocations.size(), 11);
  EXPECT_EQ(invocations.front(),
            std::make_pair(std::string{"Dial"}, std::string{"+123#"}));
  EXPECT_EQ(invocations[7],
            std::make_pair(std::string{"SendTones"}, std::string{"12#"}));
  EXPECT_EQ(invocations[8].first, "Activate");
  EXPECT_EQ(invocations[9].first, "Answer");
  EXPECT_EQ(invocations[10].first, "Hangup");

  gateway->callMethod("Set")
      .onInterface("org.freedesktop.DBus.Properties")
      .withArguments(std::string{pwt::test::kGatewayInterface},
                     std::string{"SpeakerVolume"}, sdbus::Variant{uint8_t{14}});
  sdbus::Variant volume;
  gateway->callMethod("Get")
      .onInterface("org.freedesktop.DBus.Properties")
      .withArguments(std::string{pwt::test::kGatewayInterface},
                     std::string{"SpeakerVolume"})
      .storeResultsTo(volume);
  EXPECT_EQ(volume.get<uint8_t>(), 14);

  gateway->callMethod("Set")
      .onInterface("org.freedesktop.DBus.Properties")
      .withArguments(std::string{pwt::test::kGatewayInterface},
                     std::string{"MicrophoneVolume"},
                     sdbus::Variant{uint8_t{9}});
  gateway->callMethod("Set")
      .onInterface("org.freedesktop.DBus.Properties")
      .withArguments(std::string{pwt::test::kTransportInterface},
                     std::string{"RejectSCO"}, sdbus::Variant{true});
  sdbus::Variant reject_sco;
  gateway->callMethod("Get")
      .onInterface("org.freedesktop.DBus.Properties")
      .withArguments(std::string{pwt::test::kTransportInterface},
                     std::string{"RejectSCO"})
      .storeResultsTo(reject_sco);
  EXPECT_TRUE(reject_sco.get<bool>());

  service_->set_call_state({.lineIdentification = "",
                            .incomingLine = "+60123",
                            .name = "Lee",
                            .multiparty = true,
                            .state = "held"});
  sdbus::Variant state;
  call->callMethod("Get")
      .onInterface("org.freedesktop.DBus.Properties")
      .withArguments(std::string{pwt::test::kCallInterface},
                     std::string{"State"})
      .storeResultsTo(state);
  EXPECT_EQ(state.get<std::string>(), "held");

  service_->fail_next("Dial", "org.pipewire.Telephony.Error.InvalidState",
                      "dial is not valid now");
  try {
    gateway->callMethod("Dial")
        .onInterface(pwt::test::kGatewayInterface)
        .withArguments(std::string{"123"});
    FAIL() << "expected configured D-Bus error";
  } catch (const sdbus::Error &error) {
    EXPECT_EQ(error.getName(), "org.pipewire.Telephony.Error.InvalidState");
    EXPECT_EQ(error.getMessage(), "dial is not valid now");
  }
}

TEST_F(MockTelephonyServiceTest, CanReplaceTheWellKnownNameOwner) {
  const auto original_owner = service_->unique_owner();
  ASSERT_FALSE(original_owner.empty());

  service_->restart();

  const auto replacement_owner = service_->unique_owner();
  EXPECT_FALSE(replacement_owner.empty());
  EXPECT_NE(replacement_owner, original_owner);
  EXPECT_NO_THROW(managed_objects(pwt::test::kRootPath));
}

TEST_F(MockTelephonyServiceTest, SupportsEmptyAndDynamicObjectTrees) {
  service_->stop();
  service_ = std::make_unique<pwt::test::MockTelephonyService>(address_, false);
  service_->start();

  EXPECT_TRUE(managed_objects(pwt::test::kRootPath).empty());
  service_->add_gateway();
  service_->add_second_gateway();
  EXPECT_EQ(managed_objects(pwt::test::kRootPath).size(), 2);
  service_->remove_second_gateway();
  EXPECT_EQ(managed_objects(pwt::test::kRootPath)
                .count(sdbus::ObjectPath{pwt::test::kGatewayPath}),
            1);
  EXPECT_TRUE(managed_objects(pwt::test::kGatewayPath).empty());

  service_->add_call();
  EXPECT_EQ(managed_objects(pwt::test::kGatewayPath)
                .count(sdbus::ObjectPath{pwt::test::kCallPath}),
            1);
  service_->remove_call();
  EXPECT_TRUE(managed_objects(pwt::test::kGatewayPath).empty());
  service_->remove_gateway();
  EXPECT_TRUE(managed_objects(pwt::test::kRootPath).empty());
}

} // namespace
