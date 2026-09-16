#include "mock_telephony_service.h"

#include <stdexcept>
#include <thread>
#include <utility>

namespace pwt::test {
namespace {

using Properties = std::map<std::string, sdbus::Variant>;
using Interfaces = std::map<std::string, Properties>;

Interfaces gateway_interfaces(const GatewayState &gateway,
                              const TransportState &transport) {
  return {
      {kGatewayInterface,
       {{"Address", sdbus::Variant{gateway.address}},
        {"SpeakerVolume", sdbus::Variant{gateway.speakerVolume}},
        {"MicrophoneVolume", sdbus::Variant{gateway.microphoneVolume}}}},
      {kTransportInterface,
       {{"State", sdbus::Variant{transport.state}},
        {"Codec", sdbus::Variant{transport.codec}},
        {"RejectSCO", sdbus::Variant{transport.rejectSco}}}},
  };
}

} // namespace

MockTelephonyService::MockTelephonyService(std::string bus_address,
                                           bool populate_initially)
    : bus_address_(std::move(bus_address)),
      populate_initially_(populate_initially) {}

MockTelephonyService::~MockTelephonyService() { stop(); }

void MockTelephonyService::start() {
  if (connection_) {
    throw std::logic_error("mock service is already running");
  }
  connection_ = sdbus::createSessionBusConnectionWithAddress(bus_address_);
  connection_->requestName(sdbus::ServiceName{kServiceName});

  root_ = sdbus::createObject(*connection_, sdbus::ObjectPath{kRootPath});
  root_->addObjectManager();
  if (populate_initially_) {
    register_gateway(kGatewayPath, gateway_state_, gateway_);
    register_call();
  }
  connection_->enterEventLoopAsync();
}

void MockTelephonyService::stop() {
  if (!connection_)
    return;
  connection_->leaveEventLoop();
  call_.reset();
  second_gateway_.reset();
  gateway_.reset();
  root_.reset();
  connection_->releaseName(sdbus::ServiceName{kServiceName});
  connection_.reset();
}

void MockTelephonyService::restart() {
  stop();
  start();
}

void MockTelephonyService::add_gateway() {
  if (gateway_)
    return;
  register_gateway(kGatewayPath, gateway_state_, gateway_);
  root_->emitSignal("InterfacesAdded")
      .onInterface("org.freedesktop.DBus.ObjectManager")
      .withArguments(sdbus::ObjectPath{kGatewayPath},
                     gateway_interfaces(gateway_state_, transport_state_));
}

void MockTelephonyService::add_second_gateway() {
  if (second_gateway_)
    return;
  register_gateway(kSecondGatewayPath, second_gateway_state_, second_gateway_);
  root_->emitSignal("InterfacesAdded")
      .onInterface("org.freedesktop.DBus.ObjectManager")
      .withArguments(
          sdbus::ObjectPath{kSecondGatewayPath},
          gateway_interfaces(second_gateway_state_, transport_state_));
}

void MockTelephonyService::remove_second_gateway() {
  if (!second_gateway_)
    return;
  root_->emitSignal("InterfacesRemoved")
      .onInterface("org.freedesktop.DBus.ObjectManager")
      .withArguments(
          sdbus::ObjectPath{kSecondGatewayPath},
          std::vector<std::string>{kGatewayInterface, kTransportInterface});
  second_gateway_.reset();
}

void MockTelephonyService::remove_gateway() {
  remove_call();
  if (!gateway_)
    return;
  root_->emitSignal("InterfacesRemoved")
      .onInterface("org.freedesktop.DBus.ObjectManager")
      .withArguments(
          sdbus::ObjectPath{kGatewayPath},
          std::vector<std::string>{kGatewayInterface, kTransportInterface});
  gateway_.reset();
}

void MockTelephonyService::add_call() {
  if (call_ || !gateway_)
    return;
  register_call();
  call_->emitInterfacesAddedSignal(
      std::vector<sdbus::InterfaceName>{sdbus::InterfaceName{kCallInterface}});
}

void MockTelephonyService::remove_call() {
  if (!call_)
    return;
  call_->emitInterfacesRemovedSignal(
      std::vector<sdbus::InterfaceName>{sdbus::InterfaceName{kCallInterface}});
  call_.reset();
}

void MockTelephonyService::add_transport() {
  root_->emitSignal("InterfacesAdded")
      .onInterface("org.freedesktop.DBus.ObjectManager")
      .withArguments(
          sdbus::ObjectPath{kGatewayPath},
          Interfaces{
              {kTransportInterface,
               {{"State", sdbus::Variant{transport_state_.state}},
                {"Codec", sdbus::Variant{transport_state_.codec}},
                {"RejectSCO", sdbus::Variant{transport_state_.rejectSco}}}}});
}

void MockTelephonyService::remove_transport() {
  root_->emitSignal("InterfacesRemoved")
      .onInterface("org.freedesktop.DBus.ObjectManager")
      .withArguments(sdbus::ObjectPath{kGatewayPath},
                     std::vector<std::string>{kTransportInterface});
}

std::string MockTelephonyService::unique_owner() const {
  if (!connection_)
    return {};
  return connection_->getUniqueName();
}

void MockTelephonyService::fail_next(std::string operation, std::string name,
                                     std::string message) {
  const std::lock_guard lock(mutex_);
  failures_.insert_or_assign(
      std::move(operation),
      Failure{.name = std::move(name), .message = std::move(message)});
}

void MockTelephonyService::set_operation_delay(
    std::chrono::milliseconds delay) {
  const std::lock_guard lock(mutex_);
  operation_delay_ = delay;
}

std::vector<std::pair<std::string, std::string>>
MockTelephonyService::invocations() const {
  const std::lock_guard lock(mutex_);
  return invocations_;
}

void MockTelephonyService::set_gateway_state(GatewayState state) {
  {
    const std::lock_guard lock(mutex_);
    gateway_state_ = std::move(state);
  }
  if (gateway_)
    gateway_->emitPropertiesChangedSignal(kGatewayInterface);
}

void MockTelephonyService::set_transport_state(TransportState state) {
  {
    const std::lock_guard lock(mutex_);
    transport_state_ = std::move(state);
  }
  if (gateway_)
    gateway_->emitPropertiesChangedSignal(kTransportInterface);
}

void MockTelephonyService::set_call_state(CallState state) {
  {
    const std::lock_guard lock(mutex_);
    call_state_ = std::move(state);
  }
  if (call_)
    call_->emitPropertiesChangedSignal(
        kCallInterface,
        std::vector<sdbus::PropertyName>{
            sdbus::PropertyName{"LineIdentification"},
            sdbus::PropertyName{"IncomingLine"}, sdbus::PropertyName{"Name"},
            sdbus::PropertyName{"Multiparty"}, sdbus::PropertyName{"State"}});
}

void MockTelephonyService::change_gateway_state(
    GatewayState state, std::vector<std::string> changed,
    std::vector<std::string> invalidated) {
  Properties properties;
  for (const auto &name : changed) {
    if (name == "Address")
      properties.emplace(name, sdbus::Variant{state.address});
    if (name == "SpeakerVolume")
      properties.emplace(name, sdbus::Variant{state.speakerVolume});
    if (name == "MicrophoneVolume")
      properties.emplace(name, sdbus::Variant{state.microphoneVolume});
  }
  {
    const std::lock_guard lock(mutex_);
    gateway_state_ = std::move(state);
  }
  if (!gateway_)
    return;
  gateway_->emitSignal("PropertiesChanged")
      .onInterface("org.freedesktop.DBus.Properties")
      .withArguments(std::string{kGatewayInterface}, properties, invalidated);
}

void MockTelephonyService::change_call_state(
    CallState state, std::vector<std::string> changed,
    std::vector<std::string> invalidated) {
  Properties properties;
  for (const auto &name : changed) {
    if (name == "LineIdentification")
      properties.emplace(name, sdbus::Variant{state.lineIdentification});
    if (name == "IncomingLine")
      properties.emplace(name, sdbus::Variant{state.incomingLine});
    if (name == "Name")
      properties.emplace(name, sdbus::Variant{state.name});
    if (name == "Multiparty")
      properties.emplace(name, sdbus::Variant{state.multiparty});
    if (name == "State")
      properties.emplace(name, sdbus::Variant{state.state});
  }
  {
    const std::lock_guard lock(mutex_);
    call_state_ = std::move(state);
  }
  if (!call_)
    return;
  call_->emitSignal("PropertiesChanged")
      .onInterface("org.freedesktop.DBus.Properties")
      .withArguments(std::string{kCallInterface}, properties, invalidated);
}

void MockTelephonyService::invoke(std::string operation, std::string argument) {
  std::optional<Failure> failure;
  std::chrono::milliseconds delay;
  {
    const std::lock_guard lock(mutex_);
    invocations_.emplace_back(operation, std::move(argument));
    if (const auto found = failures_.find(operation);
        found != failures_.end()) {
      failure = std::move(found->second);
      failures_.erase(found);
    }
    delay = operation_delay_;
  }
  std::this_thread::sleep_for(delay);
  if (failure) {
    throw sdbus::Error(sdbus::Error::Name{failure->name}, failure->message);
  }
}

void MockTelephonyService::read_property(std::string operation) {
  std::optional<Failure> failure;
  std::chrono::milliseconds delay;
  {
    const std::lock_guard lock(mutex_);
    if (const auto found = failures_.find(operation);
        found != failures_.end()) {
      failure = std::move(found->second);
      failures_.erase(found);
    }
    delay = operation_delay_;
  }
  std::this_thread::sleep_for(delay);
  if (failure) {
    throw sdbus::Error(sdbus::Error::Name{failure->name}, failure->message);
  }
}

void MockTelephonyService::register_gateway(
    const char *path, GatewayState &state,
    std::unique_ptr<sdbus::IObject> &object) {
  object = sdbus::createObject(*connection_, sdbus::ObjectPath{path});
  object->addObjectManager();

  object
      ->addVTable(
          sdbus::registerMethod("Dial").implementedAs(
              [this](const std::string &number) { invoke("Dial", number); }),
          sdbus::registerMethod("SwapCalls").implementedAs([this] {
            invoke("SwapCalls");
          }),
          sdbus::registerMethod("ReleaseAndAnswer").implementedAs([this] {
            invoke("ReleaseAndAnswer");
          }),
          sdbus::registerMethod("ReleaseAndSwap").implementedAs([this] {
            invoke("ReleaseAndSwap");
          }),
          sdbus::registerMethod("HoldAndAnswer").implementedAs([this] {
            invoke("HoldAndAnswer");
          }),
          sdbus::registerMethod("HangupAll").implementedAs([this] {
            invoke("HangupAll");
          }),
          sdbus::registerMethod("CreateMultiparty").implementedAs([this] {
            invoke("CreateMultiparty");
          }),
          sdbus::registerMethod("SendTones")
              .implementedAs([this](const std::string &tones) {
                invoke("SendTones", tones);
              }),
          sdbus::registerProperty("Address")
              .withGetter([this, &state] {
                read_property("GetGatewayProperties");
                const std::lock_guard lock(mutex_);
                return state.address;
              })
              .withUpdateBehavior(sdbus::Flags::CONST_PROPERTY_VALUE),
          sdbus::registerProperty("SpeakerVolume")
              .withGetter([this, &state] {
                const std::lock_guard lock(mutex_);
                return state.speakerVolume;
              })
              .withSetter([this, &state](const uint8_t &value) {
                invoke("SetSpeakerVolume", std::to_string(value));
                const std::lock_guard lock(mutex_);
                state.speakerVolume = value;
              }),
          sdbus::registerProperty("MicrophoneVolume")
              .withGetter([this, &state] {
                const std::lock_guard lock(mutex_);
                return state.microphoneVolume;
              })
              .withSetter([this, &state](const uint8_t &value) {
                invoke("SetMicrophoneVolume", std::to_string(value));
                const std::lock_guard lock(mutex_);
                state.microphoneVolume = value;
              }))
      .forInterface(kGatewayInterface);

  object
      ->addVTable(sdbus::registerMethod("Activate").implementedAs([this] {
        invoke("Activate");
      }),
                  sdbus::registerProperty("State").withGetter([this] {
                    read_property("GetTransportProperties");
                    const std::lock_guard lock(mutex_);
                    return transport_state_.state;
                  }),
                  sdbus::registerProperty("Codec").withGetter([this] {
                    const std::lock_guard lock(mutex_);
                    return transport_state_.codec;
                  }),
                  sdbus::registerProperty("RejectSCO")
                      .withGetter([this] {
                        const std::lock_guard lock(mutex_);
                        return transport_state_.rejectSco;
                      })
                      .withSetter([this](const bool &value) {
                        invoke("SetRejectSCO", value ? "true" : "false");
                        const std::lock_guard lock(mutex_);
                        transport_state_.rejectSco = value;
                      }))
      .forInterface(kTransportInterface);
}

void MockTelephonyService::register_call() {
  call_ = sdbus::createObject(*connection_, sdbus::ObjectPath{kCallPath});
  call_
      ->addVTable(
          sdbus::registerMethod("Answer").implementedAs(
              [this] { invoke("Answer"); }),
          sdbus::registerMethod("Hangup").implementedAs(
              [this] { invoke("Hangup"); }),
          sdbus::registerProperty("LineIdentification").withGetter([this] {
            read_property("GetCallProperties");
            const std::lock_guard lock(mutex_);
            return call_state_.lineIdentification;
          }),
          sdbus::registerProperty("IncomingLine").withGetter([this] {
            const std::lock_guard lock(mutex_);
            return call_state_.incomingLine;
          }),
          sdbus::registerProperty("Name").withGetter([this] {
            const std::lock_guard lock(mutex_);
            return call_state_.name;
          }),
          sdbus::registerProperty("Multiparty").withGetter([this] {
            const std::lock_guard lock(mutex_);
            return call_state_.multiparty;
          }),
          sdbus::registerProperty("State").withGetter([this] {
            const std::lock_guard lock(mutex_);
            return call_state_.state;
          }))
      .forInterface(kCallInterface);
}

} // namespace pwt::test
