#include "client_context.h"

#include <algorithm>
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
constexpr auto kPropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr auto kGatewayInterface = "org.pipewire.Telephony.AudioGateway1";
constexpr auto kCallInterface = "org.pipewire.Telephony.Call1";
constexpr auto kTransportInterface =
    "org.pipewire.Telephony.AudioGatewayTransport1";
constexpr auto kOperationTimeout = std::chrono::seconds{30};

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
          fail_pending("org.pipewire.Telephony.Error.ServiceChanged",
                       "telephony service owner changed");
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
        },
        [this](const std::string &kind, const CallProperties &call) {
          post_call(kind, call);
        });
    gateways_->synchronize();
    while (connection_->processPendingEvent()) {
    }
    auto snapshot = gateways_->activate();
    if (commands_.stopping()) {
      finish_startup({.ready = false,
                      .errorName = "org.pipewire.Telephony.Error.Cancelled",
                      .errorMessage = "telephony startup was cancelled"});
    } else {
      post_ready(std::move(snapshot));
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

  fail_pending("org.pipewire.Telephony.Error.Closed",
               "telephony client is closing");
  owner_subscription_.reset();
  gateways_.reset();
  operation_proxies_.clear();
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
    auto timeout = bus.getPollTimeout();
    if (!pending_.empty() && (timeout < 0 || timeout > 100)) {
      timeout = 100;
    }
    pollfd descriptors[]{
        {.fd = bus.fd, .events = bus.events, .revents = 0},
        {.fd = bus.eventFd, .events = POLLIN, .revents = 0},
        {.fd = commands_.fd(), .events = POLLIN, .revents = 0},
    };
    const int result = poll(descriptors, 3, timeout);
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
    expire_requests();
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
    dispatch_request(*request, command->resultPort);
  }
}

void ClientContext::dispatch_request(const Request &request,
                                     int64_t result_port) {
  auto reject = [&](std::string name, std::string message) {
    auto error = local_error(std::move(name), std::move(message));
    error.operation = request.operation;
    error.path = request.target.path;
    post_reply(request.requestId, result_port, std::move(error));
  };
  if (request.target.clientGeneration != generation_) {
    reject("org.pipewire.Telephony.Error.StaleClient",
           "target belongs to another client generation");
    return;
  }
  if (pending_.contains(request.requestId)) {
    reject("org.pipewire.Telephony.Error.DuplicateRequest",
           "request ID is already pending");
    return;
  }

  std::optional<std::string> gateway_path;
  if (request.target.interface == kGatewayInterface && gateways_ &&
      gateways_->contains(request.target.path,
                          request.target.objectIncarnation)) {
    gateway_path = request.target.path;
  } else if (request.target.interface == kCallInterface && gateways_) {
    gateway_path = gateways_->gateway_path_for_call(
        request.target.path, request.target.objectIncarnation);
  }
  if (!gateway_path) {
    reject("org.pipewire.Telephony.Error.StaleObject",
           "target object is no longer available");
    return;
  }

  const bool refresh = request.operation == "refreshGateway" ||
                       request.operation == "refreshCall";
  const bool call_operation = request.operation == "refreshCall" ||
                              request.operation == "answer" ||
                              request.operation == "hangup";
  if ((call_operation && request.target.interface != kCallInterface) ||
      (!call_operation && request.target.interface != kGatewayInterface)) {
    reject("org.pipewire.Telephony.Error.InvalidArguments",
           "operation does not match target interface");
    return;
  }
  if (!refresh && busy_gateways_.contains(*gateway_path)) {
    reject("org.pipewire.Telephony.Error.Busy",
           "another mutation is pending for this gateway");
    return;
  }

  auto &proxy = operation_proxies_[request.target.path];
  if (!proxy) {
    proxy = sdbus::createProxy(*connection_, sdbus::ServiceName{kService},
                               sdbus::ObjectPath{request.target.path});
  }
  pending_.emplace(
      request.requestId,
      PendingRequest{.requestId = request.requestId,
                     .resultPort = result_port,
                     .operation = request.operation,
                     .path = request.target.path,
                     .incarnation = request.target.objectIncarnation,
                     .gatewayPath = refresh ? std::string{} : *gateway_path,
                     .deadline =
                         std::chrono::steady_clock::now() + kOperationTimeout});
  if (!refresh) {
    busy_gateways_.insert(*gateway_path);
  }

  try {
    auto &target = *proxy;
    if (refresh) {
      const auto interface = request.operation == "refreshGateway"
                                 ? kGatewayInterface
                                 : kCallInterface;
      target.callMethodAsync("GetAll")
          .onInterface(kPropertiesInterface)
          .withArguments(std::string{interface})
          .uponReplyInvoke(
              [this, id = request.requestId](
                  std::optional<sdbus::Error> error,
                  const std::map<std::string, sdbus::Variant> &properties) {
                complete_refresh(id, properties, std::move(error));
              });
      return;
    }

    const auto complete =
        [this, id = request.requestId](std::optional<sdbus::Error> error) {
          if (!error) {
            complete_request(id);
            return;
          }
          const auto pending = pending_.find(id);
          if (pending == pending_.end()) {
            return;
          }
          complete_request(id, Error{.category = "remote",
                                     .name = error->getName(),
                                     .message = error->getMessage(),
                                     .operation = pending->second.operation,
                                     .path = pending->second.path});
        };
    const auto method = [&](const char *name, const char *interface) {
      target.callMethodAsync(name).onInterface(interface).uponReplyInvoke(
          complete);
    };

    if (request.operation == "dial" || request.operation == "sendTones") {
      if (!request.arguments.text) {
        throw std::invalid_argument("text argument is required");
      }
      target.callMethodAsync(request.operation == "dial" ? "Dial" : "SendTones")
          .onInterface(kGatewayInterface)
          .withArguments(*request.arguments.text)
          .uponReplyInvoke(complete);
    } else if (request.operation == "answer") {
      method("Answer", kCallInterface);
    } else if (request.operation == "hangup") {
      method("Hangup", kCallInterface);
    } else if (request.operation == "hangupAll") {
      method("HangupAll", kGatewayInterface);
    } else if (request.operation == "swapCalls") {
      method("SwapCalls", kGatewayInterface);
    } else if (request.operation == "releaseAndAnswer") {
      method("ReleaseAndAnswer", kGatewayInterface);
    } else if (request.operation == "releaseAndSwap") {
      method("ReleaseAndSwap", kGatewayInterface);
    } else if (request.operation == "holdAndAnswer") {
      method("HoldAndAnswer", kGatewayInterface);
    } else if (request.operation == "createMultiparty") {
      method("CreateMultiparty", kGatewayInterface);
    } else if (request.operation == "setSpeakerVolume" ||
               request.operation == "setMicrophoneVolume") {
      if (!request.arguments.volume) {
        throw std::invalid_argument("volume argument is required");
      }
      target.callMethodAsync("Set")
          .onInterface(kPropertiesInterface)
          .withArguments(std::string{kGatewayInterface},
                         request.operation == "setSpeakerVolume"
                             ? std::string{"SpeakerVolume"}
                             : std::string{"MicrophoneVolume"},
                         sdbus::Variant{*request.arguments.volume})
          .uponReplyInvoke(complete);
    } else if (request.target.interface == kTransportInterface) {
      throw std::invalid_argument("transport is not available");
    } else {
      throw std::invalid_argument("operation is not implemented");
    }
  } catch (const std::exception &error) {
    auto local = local_error("org.pipewire.Telephony.Error.InvalidArguments",
                             error.what());
    local.operation = request.operation;
    local.path = request.target.path;
    complete_request(request.requestId, std::move(local));
  }
}

void ClientContext::complete_request(uint64_t request_id,
                                     std::optional<Error> error) {
  const auto found = pending_.find(request_id);
  if (found == pending_.end()) {
    return;
  }
  const auto result_port = found->second.resultPort;
  if (!found->second.gatewayPath.empty()) {
    busy_gateways_.erase(found->second.gatewayPath);
  }
  pending_.erase(found);
  post_reply(request_id, result_port, std::move(error));
}

void ClientContext::complete_refresh(
    uint64_t request_id,
    const std::map<std::string, sdbus::Variant> &properties,
    std::optional<sdbus::Error> error) {
  const auto found = pending_.find(request_id);
  if (found == pending_.end()) {
    return;
  }
  if (error) {
    complete_request(request_id, Error{.category = "remote",
                                       .name = error->getName(),
                                       .message = error->getMessage(),
                                       .operation = found->second.operation,
                                       .path = found->second.path});
    return;
  }
  const auto request = found->second.operation;
  const auto path = found->second.path;
  const auto incarnation = found->second.incarnation;
  bool applied = false;
  if (request == "refreshGateway") {
    applied = gateways_->apply_gateway_refresh(path, incarnation, properties);
  } else if (request == "refreshCall") {
    applied = gateways_->apply_call_refresh(path, incarnation, properties);
  }
  if (!applied) {
    auto stale = local_error("org.pipewire.Telephony.Error.StaleObject",
                             "target object disappeared during refresh");
    stale.operation = request;
    stale.path = path;
    complete_request(request_id, std::move(stale));
    return;
  }
  complete_request(request_id);
}

void ClientContext::expire_requests() {
  const auto now = std::chrono::steady_clock::now();
  std::vector<uint64_t> expired;
  for (const auto &[id, request] : pending_) {
    if (request.deadline <= now) {
      expired.push_back(id);
    }
  }
  for (const auto id : expired) {
    const auto found = pending_.find(id);
    if (found == pending_.end())
      continue;
    const auto gateway_path = found->second.gatewayPath;
    auto error = local_error("org.pipewire.Telephony.Error.Timeout",
                             "operation timed out; remote outcome is unknown");
    error.operation = found->second.operation;
    error.path = found->second.path;
    complete_request(id, std::move(error));
    if (!gateway_path.empty()) {
      gateways_->reconcile(gateway_path);
    }
  }
}

void ClientContext::fail_pending(const std::string &name,
                                 const std::string &message) {
  std::vector<uint64_t> ids;
  ids.reserve(pending_.size());
  for (const auto &[id, request] : pending_) {
    ids.push_back(id);
  }
  for (const auto id : ids) {
    const auto found = pending_.find(id);
    if (found == pending_.end())
      continue;
    auto error = local_error(name, message);
    error.operation = found->second.operation;
    error.path = found->second.path;
    complete_request(id, std::move(error));
  }
}

void ClientContext::post_reply(uint64_t request_id, int64_t result_port,
                               std::optional<Error> error) {
  Reply reply{.version = kProtocolVersion,
              .clientGeneration = generation_,
              .sequence = ++sequence_,
              .kind = "reply",
              .requestId = request_id,
              .ok = !error,
              .error = std::move(error)};
  post_json(result_port, encode_reply(reply));
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

void ClientContext::post_ready(DiscoverySnapshot snapshot) {
  Event event{.version = kProtocolVersion,
              .clientGeneration = generation_,
              .sequence = ++sequence_,
              .kind = "startup",
              .payload = {.startup =
                              StartupSnapshot{
                                  .gateways = std::move(snapshot.gateways),
                                  .calls = std::move(snapshot.calls),
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

void ClientContext::post_call(const std::string &kind,
                              const CallProperties &call) {
  Event event{.version = kProtocolVersion,
              .clientGeneration = generation_,
              .sequence = ++sequence_,
              .kind = kind,
              .payload = {.call = call}};
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
