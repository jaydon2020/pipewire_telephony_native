/*
 * Copyright (c) 2026 Jian De Seak jiande2020@gmail.com. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include "telephony_codec.h"

#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <string>

#include <glaze/json/read.hpp>

namespace {

void require(bool condition) {
  if (!condition) {
    throw std::runtime_error("telephony codec assertion failed");
  }
}

std::string fixture(const char *name) {
  std::ifstream input(std::filesystem::path(PWT_FIXTURE_DIR) / name);
  require(input.good());
  std::string value{std::istreambuf_iterator<char>(input),
                    std::istreambuf_iterator<char>()};
  while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) {
    value.pop_back();
  }
  return value;
}

} // namespace

int main() {
  std::string error;
  const auto request = pwt::decode_request(fixture("request_dial.json"), error);
  require(request.has_value());
  require(error.empty());
  require(request->requestId == 42);
  require(request->target.clientGeneration == 7);
  require(request->target.objectIncarnation == 3);
  require(request->arguments.text == "+123#");

  pwt::Reply reply;
  const auto reply_json = fixture("reply_error.json");
  require(!glz::read_json(reply, reply_json));
  require(reply.error.has_value());
  require(reply.clientGeneration == 7);
  require(reply.sequence == 8);
  require(reply.kind == "reply");
  require(reply.error->name == "org.pipewire.Telephony.Error.InvalidState");
  pwt::Reply decoded_reply;
  require(!glz::read_json(decoded_reply, pwt::encode_reply(reply)));
  require(decoded_reply.error->message == reply.error->message);

  pwt::Event event;
  const auto event_json = fixture("event_call.json");
  require(!glz::read_json(event, event_json));
  require(event.payload.call.has_value());
  require(event.payload.call->lineIdentification == "");
  require(!event.payload.call->incomingLine.has_value());
  require(event.payload.call->name == "Ada \u674e");
  require(event.payload.call->state == "future-state");
  pwt::Event decoded_event;
  require(!glz::read_json(decoded_event, pwt::encode_event(event)));
  require(decoded_event.payload.call->name == event.payload.call->name);

  require(!pwt::decode_request("{}", error));
  require(!pwt::decode_request(
      R"({"version":1,"requestId":1,"operation":"unknown","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":null,"volume":null,"value":null}})",
      error));
  require(!pwt::decode_request(
      R"({"version":2,"requestId":1,"operation":"dial","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":"1","volume":null,"value":null}})",
      error));
  require(!pwt::decode_request(
      R"({"version":1,"requestId":"wrong","operation":"dial","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":"1","volume":null,"value":null}})",
      error));
  require(
      pwt::decode_request(
          R"({"version":1,"requestId":1,"operation":"dial","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x","future":true},"arguments":{"text":"1","volume":null,"value":null},"future":true})",
          error)
          .has_value());
  require(!pwt::decode_request(
      R"({"version":1,"requestId":1,"operation":"dial","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":"","volume":null,"value":null}})",
      error));
  require(!pwt::decode_request(
      R"({"version":1,"requestId":1,"operation":"dial","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":"12 3","volume":null,"value":null}})",
      error));
  require(!pwt::decode_request(
      R"({"version":1,"requestId":1,"operation":"dial","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":"1\u00002","volume":null,"value":null}})",
      error));
  require(
      pwt::decode_request(
          R"({"version":1,"requestId":1,"operation":"sendTones","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":"","volume":null,"value":null}})",
          error)
          .has_value());
  require(!pwt::decode_request(
      R"({"version":1,"requestId":1,"operation":"sendTones","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":"+","volume":null,"value":null}})",
      error));
  require(!pwt::decode_request(
      R"({"version":1,"requestId":1,"operation":"setSpeakerVolume","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":null,"volume":16,"value":null}})",
      error));
  require(
      pwt::decode_request(
          R"({"version":1,"requestId":1,"operation":"setMicrophoneVolume","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":null,"volume":15,"value":null}})",
          error)
          .has_value());
  const auto long_dial = std::string(81, '1');
  require(!pwt::decode_request(
      std::string{
          R"({"version":1,"requestId":1,"operation":"dial","target":{"clientGeneration":1,"objectIncarnation":1,"path":"/x","interface":"x"},"arguments":{"text":")"} +
          long_dial + R"(","volume":null,"value":null}})",
      error));
  require(
      !pwt::decode_request(std::string(pwt::kMaxMessageBytes + 1, 'x'), error));

  const pwt::GatewayProperties gateway{
      .path = "/org/pipewire/Telephony/ag1",
      .incarnation = 3,
      .address = "AA:BB:CC:DD:EE:FF",
      .speakerVolume = 12,
      .microphoneVolume = 10,
      .changed = {"SpeakerVolume"},
  };
  const pwt::TransportProperties transport{
      .path = gateway.path,
      .incarnation = 5,
      .state = "active",
      .codec = 2,
      .rejectSco = false,
      .changed = {"State", "Codec"},
  };
  const pwt::Event properties_event{
      .version = 1,
      .clientGeneration = 7,
      .sequence = 10,
      .kind = "gatewayChanged",
      .payload = {.gateway = gateway, .transport = transport},
  };
  pwt::Event decoded;
  const auto encoded = pwt::encode_event(properties_event);
  require(!encoded.empty());
  require(!glz::read_json(decoded, encoded));
  require(decoded.payload.gateway->speakerVolume == 12);
  require(decoded.payload.transport->rejectSco == false);

  const pwt::Event startup_event{
      .version = 1,
      .clientGeneration = 7,
      .sequence = 11,
      .kind = "startup",
      .payload = {.startup =
                      pwt::StartupSnapshot{
                          .gateways = {gateway},
                          .calls = {},
                          .transports = {transport},
                      },
                  .lifecycle = pwt::Lifecycle{.state = "ready"}},
  };
  require(!glz::read_json(decoded, pwt::encode_event(startup_event)));
  require(decoded.payload.startup->gateways.size() == 1);
  require(decoded.payload.lifecycle->state == "ready");
}
