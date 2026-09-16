#include "client_context.h"
#include "support/mock_telephony_service.h"

#include <chrono>
#include <cstdlib>
#include <string>
#include <vector>

#include <gtest/gtest.h>

namespace {

using namespace std::chrono_literals;

constexpr auto kRequest =
    R"({"version":1,"requestId":42,"operation":"dial","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/org/pipewire/Telephony/ag1","interface":"org.pipewire.Telephony.AudioGateway1"},"arguments":{"text":"+123#","volume":null,"value":null}})";

std::string private_bus_address() {
  const char *address = std::getenv("DBUS_SESSION_BUS_ADDRESS");
  return address == nullptr ? std::string{} : std::string{address};
}

TEST(ClientConnection, ConnectsToAnEmptyTelephonyService) {
  pwt::test::MockTelephonyService service(private_bus_address(), false);
  service.start();

  pwt::ClientContext client(0, 1, pwt::BusType::session, private_bus_address());
  ASSERT_EQ(client.start(), PWT_STATUS_OK);
  const auto startup = client.wait_for_startup(2s);
  EXPECT_TRUE(startup.ready)
      << startup.errorName << ": " << startup.errorMessage;
  EXPECT_EQ(client.stop(), PWT_STATUS_OK);
  client.join();
}

TEST(ClientConnection, ReportsAMissingService) {
  pwt::ClientContext client(0, 1, pwt::BusType::session, private_bus_address());
  ASSERT_EQ(client.start(), PWT_STATUS_OK);
  const auto startup = client.wait_for_startup(2s);
  EXPECT_FALSE(startup.ready);
  EXPECT_FALSE(startup.errorName.empty());
  EXPECT_TRUE(client.wait_for_shutdown(2s));
  client.join();
}

TEST(ClientConnection, StopsWhenTheServiceOwnerChanges) {
  pwt::test::MockTelephonyService service(private_bus_address(), false);
  service.start();
  pwt::ClientContext client(0, 1, pwt::BusType::session, private_bus_address());
  ASSERT_EQ(client.start(), PWT_STATUS_OK);
  ASSERT_TRUE(client.wait_for_startup(2s).ready);

  service.restart();

  EXPECT_TRUE(client.wait_for_shutdown(2s));
  client.join();
}

TEST(ClientConnection, OwnerReplacementDuringStartupAlwaysResolves) {
  pwt::test::MockTelephonyService service(private_bus_address(), false);
  service.start();
  pwt::ClientContext client(0, 1, pwt::BusType::session, private_bus_address());
  ASSERT_EQ(client.start(), PWT_STATUS_OK);

  service.restart();

  const auto startup = client.wait_for_startup(2s);
  if (startup.ready) {
    EXPECT_EQ(client.stop(), PWT_STATUS_OK);
    EXPECT_TRUE(client.wait_for_shutdown(2s));
  } else {
    EXPECT_FALSE(startup.errorName.empty());
  }
  client.stop();
  client.join();
}

TEST(ClientConnection, StopIsReservedWhileCommandsAreQueued) {
  pwt::test::MockTelephonyService service(private_bus_address(), false);
  service.start();
  pwt::ClientContext client(0, 1, pwt::BusType::session, private_bus_address());
  ASSERT_EQ(client.start(), PWT_STATUS_OK);
  ASSERT_TRUE(client.wait_for_startup(2s).ready);

  const auto *begin = reinterpret_cast<const uint8_t *>(kRequest);
  const std::vector<uint8_t> request(
      begin, begin + std::char_traits<char>::length(kRequest));
  for (int index = 0; index < 64; ++index) {
    const auto status = client.submit(request, 0);
    ASSERT_TRUE(status == PWT_STATUS_OK || status == PWT_STATUS_QUEUE_FULL);
  }

  EXPECT_EQ(client.stop(), PWT_STATUS_OK);
  EXPECT_TRUE(client.wait_for_shutdown(2s));
  client.join();
}

} // namespace
