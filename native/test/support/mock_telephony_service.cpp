#include "mock_telephony_service.h"

#include <stdexcept>
#include <utility>

namespace pwt::test {

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
    register_gateway();
    register_call();
  }
  connection_->enterEventLoopAsync();
}

void MockTelephonyService::stop() {
  if (!connection_)
    return;
  connection_->leaveEventLoop();
  call_.reset();
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
  register_gateway();
  gateway_->emitInterfacesAddedSignal(std::vector<sdbus::InterfaceName>{
      sdbus::InterfaceName{kGatewayInterface},
      sdbus::InterfaceName{kTransportInterface}});
}

void MockTelephonyService::remove_gateway() {
  remove_call();
  if (!gateway_)
    return;
  gateway_->emitInterfacesRemovedSignal(std::vector<sdbus::InterfaceName>{
      sdbus::InterfaceName{kGatewayInterface},
      sdbus::InterfaceName{kTransportInterface}});
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

void MockTelephonyService::invoke(std::string operation, std::string argument) {
  std::optional<Failure> failure;
  {
    const std::lock_guard lock(mutex_);
    invocations_.emplace_back(operation, std::move(argument));
    if (const auto found = failures_.find(operation);
        found != failures_.end()) {
      failure = std::move(found->second);
      failures_.erase(found);
    }
  }
  if (failure) {
    throw sdbus::Error(sdbus::Error::Name{failure->name}, failure->message);
  }
}

void MockTelephonyService::register_gateway() {
  gateway_ = sdbus::createObject(*connection_, sdbus::ObjectPath{kGatewayPath});
  gateway_->addObjectManager();

  gateway_
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
              .withGetter([this] {
                const std::lock_guard lock(mutex_);
                return gateway_state_.address;
              })
              .withUpdateBehavior(sdbus::Flags::CONST_PROPERTY_VALUE),
          sdbus::registerProperty("SpeakerVolume")
              .withGetter([this] {
                const std::lock_guard lock(mutex_);
                return gateway_state_.speakerVolume;
              })
              .withSetter([this](const uint8_t &value) {
                const std::lock_guard lock(mutex_);
                gateway_state_.speakerVolume = value;
              }),
          sdbus::registerProperty("MicrophoneVolume")
              .withGetter([this] {
                const std::lock_guard lock(mutex_);
                return gateway_state_.microphoneVolume;
              })
              .withSetter([this](const uint8_t &value) {
                const std::lock_guard lock(mutex_);
                gateway_state_.microphoneVolume = value;
              }))
      .forInterface(kGatewayInterface);

  gateway_
      ->addVTable(sdbus::registerMethod("Activate").implementedAs([this] {
        invoke("Activate");
      }),
                  sdbus::registerProperty("State").withGetter([this] {
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
