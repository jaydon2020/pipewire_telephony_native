#include "client_context.h"

#include <cerrno>
#include <map>
#include <utility>

#include <poll.h>

#include <dart_api_dl.h>

#include "gateway_registry.h"
#include "telephony_codec.h"

namespace pwt {
namespace {

constexpr auto kService = "org.pipewire.Telephony";
constexpr auto kDbusService = "org.freedesktop.DBus";
constexpr auto kDbusPath = "/org/freedesktop/DBus";
constexpr auto kDbusInterface = "org.freedesktop.DBus";

Error local_error(std::string name, std::string message) {
  return {.category = "connection",
          .name = std::move(name),
          .message = std::move(message),
          .operation = "connect",
          .path = "/org/pipewire/Telephony"};
}

} // namespace

ClientContext::ClientContext(int64_t event_port, uint64_t generation,
                             BusType bus, std::string test_bus_address)
    : event_port_(event_port), generation_(generation), bus_(bus),
      test_bus_address_(std::move(test_bus_address)) {}

ClientContext::~ClientContext() {
  stop();
  join();
}

pwt_status ClientContext::start() {
  const std::lock_guard lock(state_mutex_);
  if (state_ != State::created) {
    return PWT_STATUS_INVALID_STATE;
  }

  try {
    owner_thread_ = std::thread([this] { run(); });
    state_ = State::running;
    return PWT_STATUS_OK;
  } catch (...) {
    state_ = State::stopped;
    return PWT_STATUS_INTERNAL_ERROR;
  }
}

pwt_status ClientContext::submit(std::vector<uint8_t> bytes,
                                 int64_t result_port) {
  {
    const std::lock_guard lock(state_mutex_);
    if (state_ != State::running) {
      return PWT_STATUS_INVALID_STATE;
    }
  }
  if (!commands_.push({.bytes = std::move(bytes), .resultPort = result_port})) {
    return commands_.stopping() ? PWT_STATUS_INVALID_STATE
                                : PWT_STATUS_QUEUE_FULL;
  }
  return PWT_STATUS_OK;
}

pwt_status ClientContext::stop() {
  {
    const std::lock_guard lock(state_mutex_);
    if (state_ == State::stopped || state_ == State::stopping) {
      return PWT_STATUS_OK;
    }
    state_ = State::stopping;
  }
  commands_.request_stop();
  return PWT_STATUS_OK;
}

void ClientContext::join() {
  if (owner_thread_.joinable()) {
    owner_thread_.join();
  }
}

StartupResult
ClientContext::wait_for_startup(std::chrono::milliseconds timeout) {
  std::unique_lock lock(startup_mutex_);
  if (!startup_changed_.wait_for(lock, timeout,
                                 [this] { return startup_finished_; })) {
    return {.ready = false,
            .errorName = "org.pipewire.Telephony.Error.Timeout",
            .errorMessage = "telephony startup timed out"};
  }
  return startup_result_;
}

bool ClientContext::wait_for_shutdown(std::chrono::milliseconds timeout) {
  std::unique_lock lock(state_mutex_);
  return state_changed_.wait_for(lock, timeout,
                                 [this] { return state_ == State::stopped; });
}

void ClientContext::run() {
  try {
    if (!test_bus_address_.empty()) {
      connection_ =
          sdbus::createSessionBusConnectionWithAddress(test_bus_address_);
    } else if (bus_ == BusType::session) {
      connection_ = sdbus::createSessionBusConnection();
    } else {
      connection_ = sdbus::createSystemBusConnection();
    }

    owner_subscription_ = connection_->addMatch(
        "type='signal',sender='org.freedesktop.DBus',"
        "interface='org.freedesktop.DBus',member='NameOwnerChanged',"
        "arg0='org.pipewire.Telephony'",
        [this](sdbus::Message message) {
          std::string name;
          std::string previous;
          std::string current;
          message >> name >> previous >> current;
          if (current == service_owner_) {
            return;
          }
          if (gateways_) {
            gateways_->invalidate_all();
          }
          post_unavailable("org.pipewire.Telephony.Error.ServiceChanged",
                           current.empty() ? "telephony service disappeared"
                                           : "telephony service owner changed");
          commands_.request_stop();
        },
        sdbus::return_slot);

    service_owner_ = get_service_owner();
    if (service_owner_.empty()) {
      throw std::runtime_error("telephony service has no owner");
    }
    if (get_service_owner() != service_owner_) {
      throw std::runtime_error(
          "telephony service owner changed during startup");
    }
    gateways_ = std::make_unique<GatewayRegistry>(
        *connection_,
        [this](const std::string &kind, const GatewayProperties &gateway) {
          post_gateway(kind, gateway);
        });
    auto gateways = gateways_->synchronize();
    if (commands_.stopping()) {
      finish_startup({.ready = false,
                      .errorName = "org.pipewire.Telephony.Error.Cancelled",
                      .errorMessage = "telephony startup was cancelled"});
    } else {
      post_ready(std::move(gateways));
      finish_startup({.ready = true});
      run_event_loop();
    }
  } catch (const sdbus::Error &error) {
    post_unavailable(error.getName(), error.getMessage());
    finish_startup({.ready = false,
                    .errorName = error.getName(),
                    .errorMessage = error.getMessage()});
  } catch (const std::exception &error) {
    constexpr auto name = "org.pipewire.Telephony.Error.Unavailable";
    post_unavailable(name, error.what());
    finish_startup(
        {.ready = false, .errorName = name, .errorMessage = error.what()});
  }

  owner_subscription_.reset();
  gateways_.reset();
  connection_.reset();
  {
    const std::lock_guard lock(state_mutex_);
    state_ = State::stopped;
  }
  state_changed_.notify_all();
}

void ClientContext::run_event_loop() {
  while (!commands_.stopping()) {
    const auto bus = connection_->getEventLoopPollData();
    pollfd descriptors[]{
        {.fd = bus.fd, .events = bus.events, .revents = 0},
        {.fd = bus.eventFd, .events = POLLIN, .revents = 0},
        {.fd = commands_.fd(), .events = POLLIN, .revents = 0},
    };
    const int result = poll(descriptors, 3, bus.getPollTimeout());
    if (result < 0) {
      if (errno == EINTR) {
        continue;
      }
      throw std::runtime_error("failed to poll telephony bus");
    }

    if ((descriptors[2].revents & POLLIN) != 0) {
      commands_.consume_wakeup();
      dispatch_commands();
    }
    if (commands_.stopping()) {
      break;
    }
    while (connection_->processPendingEvent()) {
    }
  }
}

void ClientContext::dispatch_commands() {
  while (auto command = commands_.try_pop()) {
    std::string decode_error;
    const std::string_view json{
        reinterpret_cast<const char *>(command->bytes.data()),
        command->bytes.size()};
    const auto request = decode_request(json, decode_error);
    if (!request) {
      continue;
    }
    const bool current_gateway =
        gateways_ &&
        request->target.interface == "org.pipewire.Telephony.AudioGateway1" &&
        gateways_->contains(request->target.path,
                            request->target.objectIncarnation);
    Reply reply{
        .version = kProtocolVersion,
        .clientGeneration = generation_,
        .sequence = ++sequence_,
        .kind = "reply",
        .requestId = request->requestId,
        .ok = false,
        .error =
            current_gateway
                ? local_error("org.pipewire.Telephony.Error.NotImplemented",
                              "operation is not implemented in this delivery")
                : local_error("org.pipewire.Telephony.Error.StaleObject",
                              "target gateway is no longer available")};
    reply.error->operation = request->operation;
    reply.error->path = request->target.path;
    post_json(command->resultPort, encode_reply(reply));
  }
}

void ClientContext::finish_startup(StartupResult result) {
  {
    const std::lock_guard lock(startup_mutex_);
    if (startup_finished_) {
      return;
    }
    startup_result_ = std::move(result);
    startup_finished_ = true;
  }
  startup_changed_.notify_all();
}

void ClientContext::post_ready(std::vector<GatewayProperties> gateways) {
  Event event{.version = kProtocolVersion,
              .clientGeneration = generation_,
              .sequence = ++sequence_,
              .kind = "startup",
              .payload = {.startup =
                              StartupSnapshot{
                                  .gateways = std::move(gateways),
                                  .calls = {},
                                  .transports = {},
                              },
                          .lifecycle = Lifecycle{.state = "ready"}}};
  if (!post_json(event_port_, encode_event(event))) {
    commands_.request_stop();
  }
}

void ClientContext::post_gateway(const std::string &kind,
                                 const GatewayProperties &gateway) {
  Event event{.version = kProtocolVersion,
              .clientGeneration = generation_,
              .sequence = ++sequence_,
              .kind = kind,
              .payload = {.gateway = gateway}};
  if (!post_json(event_port_, encode_event(event))) {
    commands_.request_stop();
  }
}

void ClientContext::post_unavailable(const std::string &name,
                                     const std::string &message) {
  Event event{.version = kProtocolVersion,
              .clientGeneration = generation_,
              .sequence = ++sequence_,
              .kind = "lifecycle",
              .payload = {
                  .lifecycle = Lifecycle{.state = "unavailable"},
                  .error = local_error(name, message),
              }};
  post_json(event_port_, encode_event(event));
}

bool ClientContext::post_json(int64_t port, const std::string &json) const {
  if (port <= 0 || Dart_PostCObject_DL == nullptr || json.empty()) {
    return port <= 0;
  }
  Dart_CObject message;
  message.type = Dart_CObject_kTypedData;
  message.value.as_typed_data.type = Dart_TypedData_kUint8;
  message.value.as_typed_data.length = static_cast<intptr_t>(json.size());
  message.value.as_typed_data.values =
      reinterpret_cast<uint8_t *>(const_cast<char *>(json.data()));
  return Dart_PostCObject_DL(port, &message);
}

std::string ClientContext::get_service_owner() {
  auto proxy =
      sdbus::createProxy(*connection_, sdbus::ServiceName{kDbusService},
                         sdbus::ObjectPath{kDbusPath});
  std::string owner;
  proxy->callMethod("GetNameOwner")
      .onInterface(kDbusInterface)
      .withArguments(std::string{kService})
      .storeResultsTo(owner);
  return owner;
}

} // namespace pwt
