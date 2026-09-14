#include "wotex_matter/controller.hpp"

#include "wotex_matter/authority.hpp"
#include "wotex_matter/sdk_storage.hpp"
#include "wotex_matter/storage.hpp"

#include <app/BufferedReadCallback.h>
#include <app/CommandSender.h>
#include <app/InteractionModelEngine.h>
#include <app/ReadClient.h>
#include <app/WriteClient.h>
#include <app/data-model/Decode.h>
#include <app/data-model/Encode.h>
#include <app/MessageDef/StatusIB.h>
#include <clusters/BridgedDeviceBasicInformation/Attributes.h>
#include <clusters/BridgedDeviceBasicInformation/Events.h>
#include <clusters/Descriptor/Attributes.h>
#include <clusters/OnOff/Attributes.h>
#include <clusters/OnOff/Commands.h>
#include <clusters/TemperatureMeasurement/Attributes.h>
#include <clusters/Thermostat/Attributes.h>
#include <controller/CHIPDeviceControllerFactory.h>
#include <credentials/GroupDataProviderImpl.h>
#include <credentials/attestation_verifier/DefaultDeviceAttestationVerifier.h>
#include <credentials/attestation_verifier/FileAttestationTrustStore.h>
#include <crypto/RawKeySessionKeystore.h>
#include <data-model-providers/codegen/Instance.h>
#include <lib/core/CHIPVendorIdentifiers.hpp>
#include <lib/support/CHIPMem.h>
#include <lib/support/CodeUtils.h>
#include <platform/CHIPDeviceLayer.h>
#include <platform/Linux/ConfigurationManagerImpl.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <optional>
#include <type_traits>
#include <utility>
#include <vector>

namespace wotex::matter {
namespace {

bool SamePublicKey(const chip::Crypto::P256PublicKey &left,
                   const chip::Crypto::P256PublicKey &right) {
  return left.Length() == right.Length() &&
      std::memcmp(left.ConstBytes(), right.ConstBytes(), left.Length()) == 0;
}

ConcretePath NativePath(std::uint64_t fabric_id, std::uint64_t node_id,
                        const chip::app::ConcreteAttributePath &path) {
  return {fabric_id, node_id, path.mEndpointId, path.mClusterId,
          path.mAttributeId};
}

ConcretePath NativePath(std::uint64_t fabric_id, std::uint64_t node_id,
                        const chip::app::ConcreteEventPath &path) {
  return {fabric_id, node_id, path.mEndpointId, path.mClusterId, path.mEventId};
}

ConcretePath NativePath(std::uint64_t fabric_id, std::uint64_t node_id,
                        const chip::app::ConcreteCommandPath &path) {
  return {fabric_id, node_id, path.mEndpointId, path.mClusterId,
          path.mCommandId};
}

InteractionError StatusError(const chip::app::StatusIB &status,
                             InteractionEffect effect = InteractionEffect::None) {
  InteractionError error{"interaction_status",
                         static_cast<std::uint8_t>(status.mStatus),
                         std::nullopt, effect};
  if (status.mClusterStatus.has_value()) {
    error.cluster_status = static_cast<std::uint8_t>(*status.mClusterStatus);
  }
  return error;
}

template <typename T>
CHIP_ERROR DecodeScalar(chip::TLV::TLVReader &reader, NativeValue &output) {
  T value{};
  ReturnErrorOnFailure(chip::app::DataModel::Decode(reader, value));
  if constexpr (std::is_same_v<T, bool>) {
    output = NativeValue::boolean(value);
  } else if constexpr (std::is_signed_v<T>) {
    output = NativeValue::signed_integer(value);
  } else if constexpr (std::is_enum_v<T>) {
    output = NativeValue::unsigned_integer(
        static_cast<std::underlying_type_t<T>>(value));
  } else {
    output = NativeValue::unsigned_integer(value);
  }
  return CHIP_NO_ERROR;
}

template <typename T>
CHIP_ERROR DecodeNullableI16(chip::TLV::TLVReader &reader,
                            NativeValue &output) {
  T value;
  ReturnErrorOnFailure(chip::app::DataModel::Decode(reader, value));
  output = value.IsNull() ? NativeValue::null_value()
                          : NativeValue::signed_integer(value.Value());
  return CHIP_NO_ERROR;
}

template <typename T>
CHIP_ERROR DecodeIdentifiers(chip::TLV::TLVReader &reader,
                             NativeValue &output) {
  T value;
  ReturnErrorOnFailure(chip::app::DataModel::Decode(reader, value));
  std::vector<std::uint32_t> identifiers;
  auto iterator = value.begin();
  while (iterator.Next()) {
    VerifyOrReturnError(identifiers.size() < 1023U, CHIP_ERROR_BUFFER_TOO_SMALL);
    identifiers.push_back(static_cast<std::uint32_t>(iterator.GetValue()));
  }
  ReturnErrorOnFailure(iterator.GetStatus());
  output = NativeValue::identifier_list(std::move(identifiers));
  return CHIP_NO_ERROR;
}

CHIP_ERROR DecodeDeviceTypes(chip::TLV::TLVReader &reader,
                             NativeValue &output) {
  using Type = chip::app::Clusters::Descriptor::Attributes::DeviceTypeList::TypeInfo::DecodableType;
  Type value;
  ReturnErrorOnFailure(chip::app::DataModel::Decode(reader, value));
  std::vector<DeviceType> device_types;
  auto iterator = value.begin();
  while (iterator.Next()) {
    VerifyOrReturnError(device_types.size() < 1023U, CHIP_ERROR_BUFFER_TOO_SMALL);
    const auto &entry = iterator.GetValue();
    device_types.push_back({static_cast<std::uint32_t>(entry.deviceType),
                            entry.revision});
  }
  ReturnErrorOnFailure(iterator.GetStatus());
  output = NativeValue::device_type_list(std::move(device_types));
  return CHIP_NO_ERROR;
}

CHIP_ERROR DecodeAttribute(const ConcretePath &path,
                           chip::TLV::TLVReader &reader, Element &output) {
  NativeValue value;
  CHIP_ERROR error = CHIP_ERROR_UNSUPPORTED_CHIP_FEATURE;
  using namespace chip::app::Clusters;
  if (path.cluster == Thermostat::Id &&
      path.member == Thermostat::Attributes::LocalTemperature::Id) {
    using Type =
        Thermostat::Attributes::LocalTemperature::TypeInfo::DecodableType;
    error = DecodeNullableI16<Type>(reader, value);
  } else if (path.cluster == Thermostat::Id &&
             path.member == Thermostat::Attributes::OccupiedCoolingSetpoint::Id) {
    using Type = Thermostat::Attributes::OccupiedCoolingSetpoint::TypeInfo::
        DecodableType;
    error = DecodeScalar<Type>(reader, value);
  } else if (path.cluster == Thermostat::Id &&
             path.member == Thermostat::Attributes::OccupiedHeatingSetpoint::Id) {
    using Type = Thermostat::Attributes::OccupiedHeatingSetpoint::TypeInfo::
        DecodableType;
    error = DecodeScalar<Type>(reader, value);
  } else if (path.cluster == Thermostat::Id &&
             path.member == Thermostat::Attributes::SystemMode::Id) {
    using Type = Thermostat::Attributes::SystemMode::TypeInfo::DecodableType;
    error = DecodeScalar<Type>(reader, value);
  } else if (path.cluster == OnOff::Id &&
             path.member == OnOff::Attributes::OnOff::Id) {
    error = DecodeScalar<OnOff::Attributes::OnOff::TypeInfo::DecodableType>(reader, value);
  } else if (path.cluster == chip::app::Clusters::Descriptor::Id &&
             path.member == chip::app::Clusters::Descriptor::Attributes::DeviceTypeList::Id) {
    error = DecodeDeviceTypes(reader, value);
  } else if (path.cluster == chip::app::Clusters::Descriptor::Id &&
             path.member == chip::app::Clusters::Descriptor::Attributes::ServerList::Id) {
    using Type = chip::app::Clusters::Descriptor::Attributes::ServerList::
        TypeInfo::DecodableType;
    error = DecodeIdentifiers<Type>(reader, value);
  } else if (path.cluster == chip::app::Clusters::Descriptor::Id &&
             path.member == chip::app::Clusters::Descriptor::Attributes::ClientList::Id) {
    using Type = chip::app::Clusters::Descriptor::Attributes::ClientList::
        TypeInfo::DecodableType;
    error = DecodeIdentifiers<Type>(reader, value);
  } else if (path.cluster == chip::app::Clusters::Descriptor::Id &&
             path.member == chip::app::Clusters::Descriptor::Attributes::PartsList::Id) {
    using Type = chip::app::Clusters::Descriptor::Attributes::PartsList::
        TypeInfo::DecodableType;
    error = DecodeIdentifiers<Type>(reader, value);
  } else if (path.cluster == BridgedDeviceBasicInformation::Id &&
             path.member == BridgedDeviceBasicInformation::Attributes::Reachable::Id) {
    using Type = BridgedDeviceBasicInformation::Attributes::Reachable::TypeInfo::
        DecodableType;
    error = DecodeScalar<Type>(reader, value);
  } else if (path.cluster == TemperatureMeasurement::Id &&
             path.member == TemperatureMeasurement::Attributes::MeasuredValue::Id) {
    using Type = TemperatureMeasurement::Attributes::MeasuredValue::TypeInfo::
        DecodableType;
    error = DecodeNullableI16<Type>(reader, value);
  }
  ReturnErrorOnFailure(error);
  Conversion conversion = convert_value(MemberKind::Attribute, path.cluster,
                                        path.member, Operation::Read, value);
  VerifyOrReturnError(conversion.error == ConversionError::None &&
                          conversion.element.has_value(),
                      CHIP_ERROR_INVALID_ARGUMENT);
  output = std::move(*conversion.element);
  return CHIP_NO_ERROR;
}

CHIP_ERROR DecodeEvent(const ConcretePath &path, chip::TLV::TLVReader &reader,
                       Element &output) {
  using Event = chip::app::Clusters::BridgedDeviceBasicInformation::Events::
      ReachableChanged::DecodableType;
  VerifyOrReturnError(path.cluster ==
                              chip::app::Clusters::BridgedDeviceBasicInformation::Id &&
                          path.member == chip::app::Clusters::
                              BridgedDeviceBasicInformation::Events::
                                  ReachableChanged::Id,
                      CHIP_ERROR_UNSUPPORTED_CHIP_FEATURE);
  Event value;
  ReturnErrorOnFailure(chip::app::DataModel::Decode(reader, value));
  Conversion conversion = convert_value(
      MemberKind::Event, path.cluster, path.member, Operation::Read,
      NativeValue::reachable(value.reachableNewValue));
  VerifyOrReturnError(conversion.error == ConversionError::None &&
                          conversion.element.has_value(),
                      CHIP_ERROR_INVALID_ARGUMENT);
  output = std::move(*conversion.element);
  return CHIP_NO_ERROR;
}

CHIP_ERROR EncodeWriteValue(const ConcretePath &path, const Element &element,
                            chip::TLV::TLVWriter &writer) {
  using namespace chip::app::Clusters;
  if (path.cluster == Thermostat::Id &&
      (path.member == Thermostat::Attributes::OccupiedCoolingSetpoint::Id ||
       path.member == Thermostat::Attributes::OccupiedHeatingSetpoint::Id)) {
    return chip::app::DataModel::Encode(
        writer, chip::TLV::AnonymousTag(),
        static_cast<std::int16_t>(element.signed_value));
  }
  if (path.cluster == Thermostat::Id &&
      path.member == Thermostat::Attributes::SystemMode::Id) {
    return chip::app::DataModel::Encode(
        writer, chip::TLV::AnonymousTag(),
        static_cast<Thermostat::SystemModeEnum>(element.unsigned_value));
  }
  return CHIP_ERROR_UNSUPPORTED_CHIP_FEATURE;
}

std::size_t EstimatedElementBytes(const Element &element) {
  std::size_t size = 96;
  for (const Element &child : element.children) {
    const std::size_t child_size = EstimatedElementBytes(child);
    if (size > kMaximumInteractionResultBytes -
            std::min(child_size, kMaximumInteractionResultBytes)) {
      return kMaximumInteractionResultBytes + 1;
    }
    size += child_size;
  }
  return size;
}

class ControllerConfigurationManager final
    : public chip::DeviceLayer::ConfigurationManagerImpl {
 private:
  CHIP_ERROR Init() override { return CHIP_NO_ERROR; }
};

} // namespace

class SdkControllerBackend::Impl final {
  class Pending;
  class NativeSubscription;

 public:
  BackendResult Open(const NativeOpenOptions &options) {
    if (open_ || memory_initialized_) {
      return {false, "controller_already_open"};
    }

    options_ = options;
    identity_ = {options.fabric_id, options.controller_node_id,
                 options.vendor_id};
    if (!chip::IsOperationalNodeId(identity_.controller_node_id) ||
        !chip::IsVendorIdValidOperationally(
            static_cast<chip::VendorId>(identity_.vendor_id))) {
      return {false, "invalid_controller_identity"};
    }

    CHIP_ERROR error = chip::Platform::MemoryInit();
    if (error != CHIP_NO_ERROR) {
      return {false, "controller_start_failed"};
    }
    memory_initialized_ = true;

    const StorageMode storage_mode = options.storage_mode == "create_new"
        ? StorageMode::CreateNew
        : StorageMode::OpenExisting;
    const AuthorityMode authority_mode = options.authority == "generate_root"
        ? AuthorityMode::GenerateRoot
        : AuthorityMode::Stored;

    error = DurableStorage::Open(options.storage_path, storage_mode,
                                 authority_mode, identity_, storage_);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "storage_open_failed"};
    }
    error = storage_->EnterProcessDirectory();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "storage_open_failed"};
    }
    error = sdk_storage_.Init(*storage_);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "sdk_storage_failed"};
    }
    sdk_storage_initialized_ = true;

    error = authority_.Init(*storage_, authority_mode, identity_);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "authority_invalid"};
    }

    paa_store_ = std::make_unique<chip::Credentials::FileAttestationTrustStore>(
        options.paa_trust_store.c_str());
    if (!paa_store_->IsInitialized() || paa_store_->paaCount() == 0) {
      Cleanup();
      return {false, "paa_trust_store_invalid"};
    }
    attestation_verifier_ =
        std::make_unique<chip::Credentials::DefaultDACVerifier>(paa_store_.get());

    group_provider_.SetStorageDelegate(storage_.get());
    group_provider_.SetSessionKeystore(&session_keystore_);
    error = group_provider_.Init();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "controller_start_failed"};
    }
    group_initialized_ = true;
    chip::Credentials::SetGroupDataProvider(&group_provider_);

    chip::Controller::FactoryInitParams factory_params;
    factory_params.fabricIndependentStorage = storage_.get();
    factory_params.groupDataProvider = &group_provider_;
    factory_params.sessionKeystore = &session_keystore_;
    factory_params.operationalKeystore = &sdk_storage_.operational_keystore();
    factory_params.opCertStore = &sdk_storage_.certificate_store();
    factory_params.dataModelProvider =
        chip::app::CodegenDataModelProviderInstance(storage_.get());

    auto &factory = chip::Controller::DeviceControllerFactory::GetInstance();
    chip::DeviceLayer::SetConfigurationMgr(&configuration_manager_);
    error = factory.Init(factory_params);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "controller_start_failed"};
    }
    factory_initialized_ = true;
    factory.RetainSystemState();
    system_state_retained_ = true;

    error = factory.ServiceEvents();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "controller_start_failed"};
    }
    event_loop_started_ = true;

    error = Execute(Action::Setup, options.timeout_ms);
    if (error != CHIP_NO_ERROR) {
      const std::string code = error == CHIP_ERROR_TIMEOUT
          ? "controller_start_timeout"
          : "controller_start_failed";
      Cleanup();
      return {false, code};
    }

    open_ = true;
    accepting_interactions_ = true;
    return {true, {}};
  }

  void Close() { Cleanup(); }
  bool IsOpen() const { return open_; }

  InteractionResponse Interact(const InteractionRequest &request);
  void SetSubscriptionSinks(ControllerBackend::ReportSink report,
                            ControllerBackend::FailureSink failure) {
    std::lock_guard<std::mutex> lock(sink_mutex_);
    report_sink_ = std::move(report);
    failure_sink_ = std::move(failure);
  }
  SubscriptionResponse Subscribe(const SubscriptionRequest &request);
  bool ActivateSubscription(const std::string &subscription_id,
                            std::uint64_t generation);
  BackendResult CancelSubscription(const std::string &subscription_id,
                                   std::uint64_t generation,
                                   std::uint32_t timeout_ms);

 private:
  class Pending final : public chip::app::ReadClient::Callback,
                        public chip::app::WriteClient::Callback,
                        public chip::app::CommandSender::ExtendableCallback {
   public:
    friend class Impl;
    Pending(Impl &owner, InteractionRequest request)
        : owner_(owner), request_(std::move(request)),
          started_(std::chrono::steady_clock::now()), buffered_read_(*this),
          connected_(&Connected, this), connection_failed_(&ConnectionFailed, this) {}

    InteractionResponse Wait() {
      std::unique_lock<std::mutex> lock(mutex_);
      if (!condition_.wait_for(lock, std::chrono::milliseconds(Remaining()),
                               [this] { return published_; })) {
        InteractionEffect effect = mutation_.submitted() && IsMutation()
            ? InteractionEffect::Unknown
            : InteractionEffect::None;
        response_ = {false,
                     InteractionError{"interaction_timeout", std::nullopt,
                                      std::nullopt, effect}};
        published_ = true;
      }
      return response_;
    }

    void Start() {
      if (Remaining() == 0) {
        FailBeforeSubmission("interaction_timeout");
        DoneWithoutClient();
        return;
      }
      CHIP_ERROR error = owner_.commissioner_.GetConnectedDevice(
          request_.node_id, &connected_, &connection_failed_);
      if (error != CHIP_NO_ERROR) {
        FailBeforeSubmission("session_establishment_failed");
        DoneWithoutClient();
      }
    }

    void FailBeforeSubmission(std::string code) {
      Publish({false, InteractionError{std::move(code)}});
    }

    bool done() const {
      std::lock_guard<std::mutex> lock(mutex_);
      return done_;
    }

    void AbortOnSdkThread() {
      connected_.Cancel();
      connection_failed_.Cancel();
      read_client_.reset();
      write_client_.reset();
      command_sender_.reset();
      Publish({false,
               InteractionError{"controller_closed", std::nullopt,
                                std::nullopt,
                                mutation_.submitted() && IsMutation()
                                    ? InteractionEffect::Unknown
                                    : InteractionEffect::None}});
      std::lock_guard<std::mutex> lock(mutex_);
      done_ = true;
    }

   private:
    static void Connected(void *context,
                          chip::Messaging::ExchangeManager &exchange_manager,
                          const chip::SessionHandle &session) {
      static_cast<Pending *>(context)->OnConnected(exchange_manager, session);
    }

    static void ConnectionFailed(void *context, const chip::ScopedNodeId &,
                                 CHIP_ERROR) {
      auto *self = static_cast<Pending *>(context);
      self->FailBeforeSubmission("session_establishment_failed");
      self->DoneWithoutClient();
    }

    void OnConnected(chip::Messaging::ExchangeManager &exchange_manager,
                     const chip::SessionHandle &session) {
      const std::uint32_t remaining = Remaining();
      if (remaining == 0 || (request_.timed_request_timeout_ms.has_value() &&
                             *request_.timed_request_timeout_ms > remaining)) {
        FailBeforeSubmission("interaction_timeout");
        DoneWithoutClient();
        return;
      }

      CHIP_ERROR error = CHIP_ERROR_INVALID_ARGUMENT;
      if (request_.kind == InteractionKind::ReadAttribute ||
          request_.kind == InteractionKind::ReadAttributes ||
          request_.kind == InteractionKind::ReadEvents) {
        error = StartRead(exchange_manager, session, remaining);
      } else if (request_.kind == InteractionKind::Write) {
        error = StartWrite(exchange_manager, session, remaining);
      } else if (request_.kind == InteractionKind::Invoke) {
        error = StartInvoke(exchange_manager, session, remaining);
      }

      if (error != CHIP_NO_ERROR) {
        read_client_.reset();
        write_client_.reset();
        command_sender_.reset();
        FailBeforeSubmission("interaction_submit_failed");
        DoneWithoutClient();
      }
    }

    CHIP_ERROR StartRead(chip::Messaging::ExchangeManager &exchange_manager,
                         const chip::SessionHandle &session,
                         std::uint32_t remaining) {
      read_client_ = std::make_unique<chip::app::ReadClient>(
          chip::app::InteractionModelEngine::GetInstance(), &exchange_manager,
          buffered_read_, chip::app::ReadClient::InteractionType::Read);

      chip::app::ReadPrepareParams params(session);
      params.mTimeout = chip::System::Clock::Milliseconds32(remaining);
      params.mKeepSubscriptions = false;
      params.mIsFabricFiltered = true;

      if (request_.kind == InteractionKind::ReadEvents) {
        event_paths_.reserve(request_.paths.size());
        for (const PathSelector &path : request_.paths) {
          event_paths_.emplace_back(*path.endpoint, *path.cluster, *path.member);
        }
        params.mpEventPathParamsList = event_paths_.data();
        params.mEventPathParamsListSize = event_paths_.size();
        if (request_.minimum_event_number.has_value()) {
          params.mEventNumber.SetValue(*request_.minimum_event_number);
        }
      } else {
        attribute_paths_.reserve(request_.paths.size());
        for (const PathSelector &path : request_.paths) {
          chip::app::AttributePathParams native;
          if (path.endpoint) {
            native.mEndpointId = *path.endpoint;
          } else {
            native.SetWildcardEndpointId();
          }
          if (path.cluster) {
            native.mClusterId = *path.cluster;
          } else {
            native.SetWildcardClusterId();
          }
          if (path.member) {
            native.mAttributeId = *path.member;
          } else {
            native.SetWildcardAttributeId();
          }
          attribute_paths_.push_back(native);
        }
        params.mpAttributePathParamsList = attribute_paths_.data();
        params.mAttributePathParamsListSize = attribute_paths_.size();
      }
      return read_client_->SendRequest(params);
    }

    CHIP_ERROR StartWrite(chip::Messaging::ExchangeManager &exchange_manager,
                          const chip::SessionHandle &session,
                          std::uint32_t remaining) {
      chip::Optional<std::uint16_t> timed;
      if (request_.timed_request_timeout_ms) {
        timed.SetValue(*request_.timed_request_timeout_ms);
      }
      write_client_ = std::make_unique<chip::app::WriteClient>(
          &exchange_manager, this, timed, false);

      const PathSelector &path = request_.paths.front();
      const ConcretePath concrete{request_.fabric_id, request_.node_id,
                                  *path.endpoint, *path.cluster, *path.member};
      chip::Optional<chip::DataVersion> version;
      if (request_.expected_data_version) {
        version.SetValue(*request_.expected_data_version);
      }
      chip::app::ConcreteDataAttributePath native(
          concrete.endpoint, concrete.cluster, concrete.member, version);

      write_buffer_.fill(0);
      chip::TLV::TLVWriter writer;
      writer.Init(write_buffer_.data(), write_buffer_.size());
      ReturnErrorOnFailure(EncodeWriteValue(concrete, *request_.value, writer));
      ReturnErrorOnFailure(writer.Finalize());
      chip::TLV::TLVReader reader;
      reader.Init(write_buffer_.data(), writer.GetLengthWritten());
      ReturnErrorOnFailure(reader.Next());
      ReturnErrorOnFailure(write_client_->PutPreencodedAttribute(native, reader));
      mutation_.Submit();
      return write_client_->SendWriteRequest(
          session, chip::System::Clock::Milliseconds32(remaining));
    }

    CHIP_ERROR StartInvoke(chip::Messaging::ExchangeManager &exchange_manager,
                           const chip::SessionHandle &session,
                           std::uint32_t remaining) {
      const bool timed = request_.timed_request_timeout_ms.has_value();
      command_sender_ = std::make_unique<chip::app::CommandSender>(
          this, &exchange_manager, timed, false, false);
      const PathSelector &path = request_.paths.front();
      chip::app::CommandPathParams native(
          *path.endpoint, *path.cluster, *path.member,
          chip::app::CommandPathFlags::kEndpointIdValid);
      chip::Optional<std::uint16_t> timed_value;
      if (request_.timed_request_timeout_ms) {
        timed_value.SetValue(*request_.timed_request_timeout_ms);
      }
      chip::app::CommandSender::AddRequestDataParameters params(timed_value);
      CHIP_ERROR error = CHIP_ERROR_UNSUPPORTED_CHIP_FEATURE;
      using namespace chip::app::Clusters::OnOff::Commands;
      if (*path.cluster == chip::app::Clusters::OnOff::Id &&
          *path.member == Off::Id) {
        error = command_sender_->AddRequestData(native, Off::Type{}, params);
      } else if (*path.cluster == chip::app::Clusters::OnOff::Id &&
                 *path.member == On::Id) {
        error = command_sender_->AddRequestData(native, On::Type{}, params);
      } else if (*path.cluster == chip::app::Clusters::OnOff::Id &&
                 *path.member == Toggle::Id) {
        error = command_sender_->AddRequestData(native, Toggle::Type{}, params);
      }
      ReturnErrorOnFailure(error);
      mutation_.Submit();
      return command_sender_->SendCommandRequest(
          session, chip::MakeOptional(chip::System::Clock::Milliseconds32(remaining)));
    }

    void OnAttributeData(const chip::app::ConcreteDataAttributePath &path,
                         chip::TLV::TLVReader *data,
                         const chip::app::StatusIB &status) override {
      PathResult result;
      result.path = NativePath(request_.fabric_id, request_.node_id, path);
      if (!status.IsSuccess()) {
        result.error = StatusError(status);
      } else if (data == nullptr) {
        result.error = InteractionError{"invalid_attribute_data"};
      } else {
        Element value;
        chip::TLV::TLVReader copy = *data;
        if (DecodeAttribute(result.path, copy, value) == CHIP_NO_ERROR) {
          AttributeData attribute{result.path, std::move(value), std::nullopt};
          if (path.mDataVersion.HasValue()) {
            attribute.data_version = path.mDataVersion.Value();
          }
          result.attribute = std::move(attribute);
        } else {
          result.error = InteractionError{"unsupported_schema"};
        }
      }
      AppendResult(std::move(result));
    }

    void OnEventData(const chip::app::EventHeader &header,
                     chip::TLV::TLVReader *data,
                     const chip::app::StatusIB *status) override {
      PathResult result;
      result.path = NativePath(request_.fabric_id, request_.node_id, header.mPath);
      if (status != nullptr && !status->IsSuccess()) {
        result.error = StatusError(*status);
      } else if (data == nullptr) {
        result.error = InteractionError{"invalid_event_data"};
      } else {
        Element value;
        chip::TLV::TLVReader copy = *data;
        if (DecodeEvent(result.path, copy, value) != CHIP_NO_ERROR) {
          result.error = InteractionError{"unsupported_schema"};
        } else if (!header.mTimestamp.IsSystem() &&
                   !header.mTimestamp.IsEpoch()) {
          result.error = InteractionError{"unsupported_timestamp"};
        } else {
          result.event = EventData{
              result.path, std::move(value), header.mEventNumber,
              static_cast<std::uint8_t>(header.mPriorityLevel),
              header.mTimestamp.IsEpoch() ? EventData::TimestampKind::Epoch
                                          : EventData::TimestampKind::System,
              header.mTimestamp.mValue};
        }
      }
      AppendResult(std::move(result));
    }

    void OnError(CHIP_ERROR) override {
      overall_error_ = InteractionError{
          "interaction_failed", std::nullopt, std::nullopt,
          mutation_.submitted() && IsMutation() ? InteractionEffect::Unknown
                                                 : InteractionEffect::None};
    }

    void OnResponse(const chip::app::WriteClient *,
                    const chip::app::ConcreteDataAttributePath &path,
                    chip::app::StatusIB status) override {
      const ConcretePath actual = NativePath(request_.fabric_id, request_.node_id, path);
      if (!SameRequestedPath(actual)) {
        overall_error_ = InteractionError{"invalid_response_path", std::nullopt,
                                          std::nullopt, InteractionEffect::Unknown};
      } else if (!status.IsSuccess()) {
        overall_error_ = StatusError(status, InteractionEffect::Unknown);
      } else {
        mutation_path_ = actual;
        ++mutation_responses_;
      }
    }

    void OnResponse(chip::app::CommandSender *,
                    const chip::app::CommandSender::ResponseData &response) override {
      const ConcretePath actual =
          NativePath(request_.fabric_id, request_.node_id, response.path);
      if (!response.statusIB.IsSuccess()) {
        overall_error_ = StatusError(response.statusIB, InteractionEffect::Unknown);
      } else if (response.data != nullptr) {
        overall_error_ = InteractionError{"unsupported_schema", std::nullopt,
                                          std::nullopt, InteractionEffect::Unknown};
      } else if (!SameRequestedPath(actual)) {
        overall_error_ = InteractionError{"invalid_response_path", std::nullopt,
                                          std::nullopt, InteractionEffect::Unknown};
      } else {
        mutation_path_.reset();
        ++mutation_responses_;
      }
    }

    void OnNoResponse(chip::app::CommandSender *,
                      const chip::app::CommandSender::NoResponseData &) override {
      overall_error_ = InteractionError{"interaction_no_response", std::nullopt,
                                        std::nullopt, InteractionEffect::Unknown};
    }

    void OnError(const chip::app::CommandSender *,
                 const chip::app::CommandSender::ErrorData &) override {
      overall_error_ = InteractionError{"interaction_failed", std::nullopt,
                                        std::nullopt, InteractionEffect::Unknown};
    }

    void OnDone(chip::app::ReadClient *) override {
      read_client_.reset();
      FinishRead();
    }

    void OnDone(chip::app::WriteClient *) override {
      write_client_.reset();
      FinishMutation();
    }

    void OnDone(chip::app::CommandSender *) override {
      command_sender_.reset();
      FinishMutation();
    }

    void FinishRead() {
      if (!overall_error_.has_value()) {
        AddMissingConcreteResults();
      }
      if (overall_error_) {
        Publish({false, *overall_error_});
      } else {
        InteractionResponse response;
        response.ok = true;
        response.results = std::move(results_);
        Publish(std::move(response));
      }
      MarkDone();
    }

    void FinishMutation() {
      if (!overall_error_ && mutation_responses_ != 1U) {
        overall_error_ = InteractionError{"interaction_no_response", std::nullopt,
                                          std::nullopt, InteractionEffect::Unknown};
      }
      if (overall_error_) {
        Publish({false, *overall_error_});
      } else {
        InteractionResponse response;
        response.ok = true;
        response.response_path = mutation_path_;
        response.status = 0;
        Publish(std::move(response));
      }
      mutation_.Complete();
      MarkDone();
    }

    void AddMissingConcreteResults() {
      for (const PathSelector &path : request_.paths) {
        if (!path.endpoint || !path.cluster || !path.member) {
          continue;
        }
        ConcretePath concrete{path.fabric_id, path.node_id, *path.endpoint,
                              *path.cluster, *path.member};
        const bool found = std::any_of(
            results_.begin(), results_.end(), [&](const PathResult &result) {
              return result.path.fabric_id == concrete.fabric_id &&
                  result.path.node_id == concrete.node_id &&
                  result.path.endpoint == concrete.endpoint &&
                  result.path.cluster == concrete.cluster &&
                  result.path.member == concrete.member;
            });
        if (!found) {
          PathResult missing;
          missing.path = concrete;
          missing.error = InteractionError{"missing_path_result"};
          AppendResult(std::move(missing));
        }
      }
    }

    bool SameRequestedPath(const ConcretePath &path) const {
      const PathSelector &expected = request_.paths.front();
      return path.fabric_id == expected.fabric_id &&
          path.node_id == expected.node_id && path.endpoint == *expected.endpoint &&
          path.cluster == *expected.cluster && path.member == *expected.member;
    }

    void AppendResult(PathResult result) {
      std::size_t size = 256;
      if (result.attribute) {
        size += EstimatedElementBytes(result.attribute->value);
      }
      if (result.event) {
        size += EstimatedElementBytes(result.event->value) + 96;
      }
      if (results_.size() >= kMaximumInteractionReports ||
          retained_result_bytes_ > kMaximumInteractionResultBytes ||
          size > kMaximumInteractionResultBytes - retained_result_bytes_) {
        overall_error_ = InteractionError{"response_limit"};
        return;
      }
      retained_result_bytes_ += size;
      results_.push_back(std::move(result));
    }

    void Publish(InteractionResponse response) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (published_) {
          return;
        }
        response_ = std::move(response);
        published_ = true;
      }
      condition_.notify_one();
    }

    void DoneWithoutClient() {
      MarkDone();
    }

    void MarkDone() {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        done_ = true;
      }
      (void) chip::DeviceLayer::PlatformMgr().ScheduleWork(
          ReapPending, reinterpret_cast<intptr_t>(this));
    }

    std::uint32_t Remaining() const {
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - started_);
      return remaining_timeout_ms(request_.timeout_ms,
                                  static_cast<std::uint64_t>(elapsed.count()));
    }

    bool IsMutation() const {
      return request_.kind == InteractionKind::Write ||
          request_.kind == InteractionKind::Invoke;
    }

    Impl &owner_;
    InteractionRequest request_;
    std::chrono::steady_clock::time_point started_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    InteractionResponse response_;
    bool published_{false};
    bool done_{false};
    MutationCompletion mutation_;
    std::optional<InteractionError> overall_error_;
    std::vector<PathResult> results_;
    std::optional<ConcretePath> mutation_path_;
    unsigned mutation_responses_{0};
    std::size_t retained_result_bytes_{0};
    chip::app::BufferedReadCallback buffered_read_;
    chip::Callback::Callback<chip::OnDeviceConnected> connected_;
    chip::Callback::Callback<chip::OnDeviceConnectionFailure> connection_failed_;
    std::unique_ptr<chip::app::ReadClient> read_client_;
    std::unique_ptr<chip::app::WriteClient> write_client_;
    std::unique_ptr<chip::app::CommandSender> command_sender_;
    std::vector<chip::app::AttributePathParams> attribute_paths_;
    std::vector<chip::app::EventPathParams> event_paths_;
    std::array<std::uint8_t, 64> write_buffer_{};
  };

  class NativeSubscription final : public chip::app::ReadClient::Callback {
   public:
    friend class Impl;

    NativeSubscription(Impl &owner, SubscriptionRequest request)
        : owner_(owner), request_(std::move(request)), buffer_(request_),
          started_(std::chrono::steady_clock::now()),
          connected_(&Connected, this), connection_failed_(&ConnectionFailed, this) {}

    SubscriptionResponse Wait() {
      std::unique_lock<std::mutex> lock(mutex_);
      if (!condition_.wait_for(lock, std::chrono::milliseconds(Remaining()),
                               [this] { return published_; })) {
        response_.error_code = "subscription_timeout";
        published_ = true;
        lock.unlock();
        ScheduleCancel();
        lock.lock();
      }
      return response_;
    }

    void Start() {
      if (Remaining() == 0) {
        PublishFailure("subscription_timeout");
        MarkDone();
        return;
      }
      CHIP_ERROR error = owner_.commissioner_.GetConnectedDevice(
          request_.node_id, &connected_, &connection_failed_);
      if (error != CHIP_NO_ERROR) {
        PublishFailure("session_establishment_failed");
        MarkDone();
      }
    }

    bool Activate() {
      std::vector<SubscriptionReport> reports;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!response_.ok || done_ || cancelled_) {
          return false;
        }
        buffer_.Activate();
        reports = buffer_.TakeReady();
      }
      return Emit(std::move(reports));
    }

    bool CancelAndWait(std::uint32_t timeout_ms) {
      ScheduleCancel();
      std::unique_lock<std::mutex> lock(mutex_);
      return condition_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                                 [this] { return done_; });
    }

    bool done() const {
      std::lock_guard<std::mutex> lock(mutex_);
      return done_;
    }

    const std::string &id() const { return request_.subscription_id; }
    std::uint64_t generation() const { return generation_; }

    void CancelOnSdkThread() {
      connected_.Cancel();
      connection_failed_.Cancel();
      {
        std::lock_guard<std::mutex> lock(mutex_);
        cancelled_ = true;
        buffer_.Cancel();
      }
      read_client_.reset();
      MarkDone();
    }

   private:
    static void Connected(void *context,
                          chip::Messaging::ExchangeManager &exchange_manager,
                          const chip::SessionHandle &session) {
      static_cast<NativeSubscription *>(context)->OnConnected(exchange_manager,
                                                               session);
    }

    static void ConnectionFailed(void *context, const chip::ScopedNodeId &,
                                 CHIP_ERROR) {
      auto *self = static_cast<NativeSubscription *>(context);
      self->PublishFailure("session_establishment_failed");
      self->MarkDone();
    }

    void OnConnected(chip::Messaging::ExchangeManager &exchange_manager,
                     const chip::SessionHandle &session) {
      const std::uint32_t remaining = Remaining();
      if (remaining == 0) {
        PublishFailure("subscription_timeout");
        MarkDone();
        return;
      }

      read_client_ = std::make_unique<chip::app::ReadClient>(
          chip::app::InteractionModelEngine::GetInstance(), &exchange_manager,
          *this, chip::app::ReadClient::InteractionType::Subscribe);
      chip::app::ReadPrepareParams params(session);
      params.mTimeout = chip::System::Clock::Milliseconds32(remaining);
      params.mKeepSubscriptions = true;
      params.mIsFabricFiltered = true;
      params.mMinIntervalFloorSeconds = request_.min_interval_s;
      params.mMaxIntervalCeilingSeconds = request_.max_interval_s;

      if (request_.kind == SubscriptionKind::Attribute) {
        attribute_paths_.reserve(request_.paths.size());
        for (const PathSelector &path : request_.paths) {
          attribute_paths_.emplace_back(*path.endpoint, *path.cluster,
                                        *path.member);
        }
        params.mpAttributePathParamsList = attribute_paths_.data();
        params.mAttributePathParamsListSize = attribute_paths_.size();
      } else {
        event_paths_.reserve(request_.paths.size());
        for (const PathSelector &path : request_.paths) {
          event_paths_.emplace_back(*path.endpoint, *path.cluster, *path.member);
        }
        params.mpEventPathParamsList = event_paths_.data();
        params.mEventPathParamsListSize = event_paths_.size();
      }

      if (read_client_->SendRequest(params) != CHIP_NO_ERROR) {
        read_client_.reset();
        PublishFailure("subscription_submit_failed");
        MarkDone();
      }
    }

    void OnReportBegin() override {
      std::lock_guard<std::mutex> lock(mutex_);
      buffer_.BeginReport();
    }

    void OnReportEnd() override {
      std::vector<SubscriptionReport> reports;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        buffer_.EndReport();
        reports = buffer_.TakeReady();
      }
      (void) Emit(std::move(reports));
    }

    void OnAttributeData(const chip::app::ConcreteDataAttributePath &path,
                         chip::TLV::TLVReader *data,
                         const chip::app::StatusIB &status) override {
      PathResult result;
      result.path = NativePath(request_.fabric_id, request_.node_id, path);
      if (!status.IsSuccess()) {
        FailActive(StatusError(status));
        return;
      }
      if (data == nullptr) {
        FailActive(InteractionError{"invalid_attribute_data"});
        return;
      }
      Element value;
      chip::TLV::TLVReader copy = *data;
      if (DecodeAttribute(result.path, copy, value) != CHIP_NO_ERROR) {
        FailActive(InteractionError{"unsupported_schema"});
        return;
      }
      AttributeData attribute{result.path, std::move(value), std::nullopt};
      if (path.mDataVersion.HasValue()) {
        attribute.data_version = path.mDataVersion.Value();
      }
      result.attribute = std::move(attribute);
      Add(std::move(result));
    }

    void OnEventData(const chip::app::EventHeader &header,
                     chip::TLV::TLVReader *data,
                     const chip::app::StatusIB *status) override {
      PathResult result;
      result.path = NativePath(request_.fabric_id, request_.node_id, header.mPath);
      if (status != nullptr && !status->IsSuccess()) {
        FailActive(StatusError(*status));
        return;
      }
      if (data == nullptr) {
        FailActive(InteractionError{"invalid_event_data"});
        return;
      }
      Element value;
      chip::TLV::TLVReader copy = *data;
      if (DecodeEvent(result.path, copy, value) != CHIP_NO_ERROR) {
        FailActive(InteractionError{"unsupported_schema"});
        return;
      }
      if (!header.mTimestamp.IsSystem() && !header.mTimestamp.IsEpoch()) {
        FailActive(InteractionError{"unsupported_timestamp"});
        return;
      }
      result.event = EventData{
          result.path, std::move(value), header.mEventNumber,
          static_cast<std::uint8_t>(header.mPriorityLevel),
          header.mTimestamp.IsEpoch() ? EventData::TimestampKind::Epoch
                                      : EventData::TimestampKind::System,
          header.mTimestamp.mValue};
      Add(std::move(result));
    }

    void OnSubscriptionEstablished(chip::SubscriptionId id) override {
      std::uint16_t minimum = 0;
      std::uint16_t maximum = 0;
      if (read_client_ == nullptr ||
          read_client_->GetReportingIntervals(minimum, maximum) != CHIP_NO_ERROR) {
        PublishFailure("invalid_subscription_result");
        ScheduleCancel();
        return;
      }

      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!buffer_.Establish(static_cast<std::uint32_t>(id), minimum, maximum)) {
          response_.error_code = "invalid_subscription_result";
          published_ = true;
          condition_.notify_one();
          ScheduleCancelLocked();
          return;
        }
        response_ = {true, {}, request_.subscription_id, generation_, minimum,
                     maximum, static_cast<std::uint32_t>(id)};
        published_ = true;
      }
      condition_.notify_one();
    }

    CHIP_ERROR OnResubscriptionNeeded(chip::app::ReadClient *,
                                      CHIP_ERROR) override {
      return CHIP_ERROR_CANCELLED;
    }

    void OnError(CHIP_ERROR) override {
      FailActive(InteractionError{"session_lost"});
    }

    void OnDone(chip::app::ReadClient *) override {
      read_client_.reset();
      bool terminal = false;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        terminal = response_.ok && !cancelled_ && !failure_emitted_;
      }
      if (terminal) {
        FailActive(InteractionError{"session_lost"});
      }
      MarkDone();
    }

    void Add(PathResult result) {
      bool accepted = false;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        accepted = buffer_.Add(std::move(result));
      }
      if (!accepted) {
        FailActive(InteractionError{"invalid_subscription_report"});
      }
    }

    bool Emit(std::vector<SubscriptionReport> reports) {
      for (const SubscriptionReport &report : reports) {
        if (!owner_.EmitReport(report)) {
          ScheduleCancel();
          return false;
        }
      }
      return true;
    }

    void FailActive(InteractionError error) {
      bool emit = false;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (failure_emitted_) {
          return;
        }
        failure_emitted_ = true;
        buffer_.Cancel();
        if (response_.ok) {
          emit = true;
        } else if (!published_) {
          response_.error_code = error.code;
          published_ = true;
        }
      }
      condition_.notify_one();
      if (emit) {
        owner_.EmitFailure(request_.subscription_id, generation_, error);
      }
      ScheduleCancel();
    }

    void PublishFailure(std::string code) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (published_) {
          return;
        }
        response_.error_code = std::move(code);
        published_ = true;
      }
      condition_.notify_one();
    }

    void ScheduleCancel() {
      std::lock_guard<std::mutex> lock(mutex_);
      ScheduleCancelLocked();
    }

    void ScheduleCancelLocked() {
      if (cancel_scheduled_ || done_) {
        return;
      }
      cancel_scheduled_ = true;
      if (chip::DeviceLayer::PlatformMgr().ScheduleWork(
              CancelSubscriptionWork, reinterpret_cast<intptr_t>(this)) !=
          CHIP_NO_ERROR) {
        done_ = true;
        condition_.notify_all();
      }
    }

    void MarkDone() {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (done_) {
          return;
        }
        done_ = true;
      }
      condition_.notify_all();
      (void) chip::DeviceLayer::PlatformMgr().ScheduleWork(
          ReapSubscription, reinterpret_cast<intptr_t>(this));
    }

    std::uint32_t Remaining() const {
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - started_);
      return remaining_timeout_ms(request_.timeout_ms,
                                  static_cast<std::uint64_t>(elapsed.count()));
    }

    Impl &owner_;
    SubscriptionRequest request_;
    SubscriptionBuffer buffer_;
    std::chrono::steady_clock::time_point started_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    SubscriptionResponse response_;
    std::uint64_t generation_{1};
    bool published_{false};
    bool cancelled_{false};
    bool failure_emitted_{false};
    bool cancel_scheduled_{false};
    bool done_{false};
    chip::Callback::Callback<chip::OnDeviceConnected> connected_;
    chip::Callback::Callback<chip::OnDeviceConnectionFailure> connection_failed_;
    std::unique_ptr<chip::app::ReadClient> read_client_;
    std::vector<chip::app::AttributePathParams> attribute_paths_;
    std::vector<chip::app::EventPathParams> event_paths_;
  };

  static void StartPending(intptr_t context) {
    reinterpret_cast<Pending *>(context)->Start();
  }

  static void ReapPending(intptr_t context) {
    auto *pending = reinterpret_cast<Pending *>(context);
    pending->owner_.Reap(pending);
  }

  static void StartSubscription(intptr_t context) {
    reinterpret_cast<NativeSubscription *>(context)->Start();
  }

  static void CancelSubscriptionWork(intptr_t context) {
    reinterpret_cast<NativeSubscription *>(context)->CancelOnSdkThread();
  }

  static void ReapSubscription(intptr_t context) {
    auto *subscription = reinterpret_cast<NativeSubscription *>(context);
    subscription->owner_.Reap(subscription);
  }

  void Reap(Pending *pending) {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    pending_.erase(
        std::remove_if(pending_.begin(), pending_.end(),
                       [pending](const std::shared_ptr<Pending> &candidate) {
                         return candidate.get() == pending && candidate->done();
                       }),
        pending_.end());
  }

  void Reap(NativeSubscription *subscription) {
    std::lock_guard<std::mutex> lock(subscription_mutex_);
    subscriptions_.erase(
        std::remove_if(
            subscriptions_.begin(), subscriptions_.end(),
            [subscription](const std::shared_ptr<NativeSubscription> &candidate) {
              return candidate.get() == subscription && candidate->done();
            }),
        subscriptions_.end());
  }

  bool EmitReport(const SubscriptionReport &report) {
    ControllerBackend::ReportSink sink;
    {
      std::lock_guard<std::mutex> lock(sink_mutex_);
      sink = report_sink_;
    }
    return sink && sink(report);
  }

  void EmitFailure(const std::string &subscription_id,
                   std::uint64_t generation,
                   const InteractionError &error) {
    ControllerBackend::FailureSink sink;
    {
      std::lock_guard<std::mutex> lock(sink_mutex_);
      sink = failure_sink_;
    }
    if (sink) {
      sink(subscription_id, generation, error);
    }
  }

  enum class Action { None, Setup, Shutdown };

  static void Work(intptr_t context) {
    auto *self = reinterpret_cast<Impl *>(context);
    const Action action = self->action_;
    CHIP_ERROR error = CHIP_ERROR_INCORRECT_STATE;
    if (action == Action::Setup) {
      error = self->SetupOnSdkThread();
    } else if (action == Action::Shutdown) {
      std::vector<std::shared_ptr<Pending>> pending;
      std::vector<std::shared_ptr<NativeSubscription>> subscriptions;
      {
        std::lock_guard<std::mutex> lock(self->pending_mutex_);
        pending = self->pending_;
      }
      {
        std::lock_guard<std::mutex> lock(self->subscription_mutex_);
        subscriptions = self->subscriptions_;
      }
      for (const auto &subscription : subscriptions) {
        subscription->CancelOnSdkThread();
      }
      for (const auto &interaction : pending) {
        interaction->AbortOnSdkThread();
      }
      self->commissioner_.Shutdown();
      error = CHIP_NO_ERROR;
    }

    {
      std::lock_guard<std::mutex> lock(self->work_mutex_);
      self->work_error_ = error;
      self->work_done_ = true;
    }
    self->work_condition_.notify_one();
  }

  CHIP_ERROR Execute(Action action, std::uint32_t timeout_ms) {
    {
      std::lock_guard<std::mutex> lock(work_mutex_);
      action_ = action;
      work_done_ = false;
      work_error_ = CHIP_ERROR_INCORRECT_STATE;
    }
    ReturnErrorOnFailure(chip::DeviceLayer::PlatformMgr().ScheduleWork(
        Work, reinterpret_cast<intptr_t>(this)));

    std::unique_lock<std::mutex> lock(work_mutex_);
    if (!work_condition_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
                                  [this] { return work_done_; })) {
      // Keep the callback target alive until the scheduled SDK work returns.
      // The BEAM owner enforces the separate cleanup grace by terminating this
      // process if the SDK itself does not return.
      work_condition_.wait(lock, [this] { return work_done_; });
      return CHIP_ERROR_TIMEOUT;
    }
    return work_error_;
  }

  CHIP_ERROR SetupOnSdkThread() {
    chip::Controller::SetupParams setup;
    setup.operationalCredentialsDelegate = &authority_;
    setup.controllerVendorId = static_cast<chip::VendorId>(identity_.vendor_id);
    setup.deviceAttestationVerifier = attestation_verifier_.get();
    setup.removeFromFabricTableOnShutdown = false;
    setup.deleteFromFabricTableOnShutdown = false;

    if (options_.storage_mode == "create_new") {
      ReturnErrorOnFailure(controller_key_.Initialize(
          chip::Crypto::ECPKeyTarget::ECDSA));
      ReturnErrorOnFailure(authority_.GenerateControllerChain(
          controller_key_.Pubkey(), controller_noc_, controller_rcac_));
      setup.operationalKeypair = &controller_key_;
      setup.controllerNOC =
          chip::ByteSpan(controller_noc_.data(), controller_noc_.size());
      setup.controllerRCAC =
          chip::ByteSpan(controller_rcac_.data(), controller_rcac_.size());
    } else {
      auto *system_state =
          chip::Controller::DeviceControllerFactory::GetInstance()
              .GetSystemState();
      VerifyOrReturnError(system_state != nullptr, CHIP_ERROR_INCORRECT_STATE);
      chip::FabricIndex match = chip::kUndefinedFabricIndex;
      for (const auto &fabric : *system_state->Fabrics()) {
        chip::Crypto::P256PublicKey root_public_key;
        if (fabric.GetFabricId() == identity_.fabric_id &&
            fabric.GetNodeId() == identity_.controller_node_id &&
            static_cast<std::uint16_t>(fabric.GetVendorId()) ==
                identity_.vendor_id &&
            fabric.FetchRootPubkey(root_public_key) == CHIP_NO_ERROR &&
            SamePublicKey(root_public_key, authority_.root_public_key())) {
          VerifyOrReturnError(match == chip::kUndefinedFabricIndex,
                              CHIP_ERROR_DUPLICATE_KEY_ID);
          match = fabric.GetFabricIndex();
        }
      }
      VerifyOrReturnError(match != chip::kUndefinedFabricIndex,
                          CHIP_ERROR_KEY_NOT_FOUND);
      setup.fabricIndex.SetValue(match);
    }

    ReturnErrorOnFailure(
        chip::Controller::DeviceControllerFactory::GetInstance()
            .SetupCommissioner(setup, commissioner_));
    commissioner_initialized_ = true;

    VerifyOrReturnError(commissioner_.GetFabricId() == identity_.fabric_id &&
                            commissioner_.GetNodeId() ==
                                identity_.controller_node_id,
                        CHIP_ERROR_INVALID_ARGUMENT);
    std::uint8_t compressed[sizeof(std::uint64_t)]{};
    chip::MutableByteSpan compressed_span(compressed);
    ReturnErrorOnFailure(
        commissioner_.GetCompressedFabricIdBytes(compressed_span));
    ReturnErrorOnFailure(chip::Credentials::SetSingleIpkEpochKey(
        &group_provider_, commissioner_.GetFabricIndex(), authority_.ipk(),
        compressed_span));
    return CHIP_NO_ERROR;
  }

  void Cleanup() {
    open_ = false;
    accepting_interactions_ = false;
    if (commissioner_initialized_ && event_loop_started_) {
      (void) Execute(Action::Shutdown, 1000);
      commissioner_initialized_ = false;
    }
    if (event_loop_started_) {
      (void) chip::DeviceLayer::PlatformMgr().StopEventLoopTask();
      event_loop_started_ = false;
    }
    {
      std::lock_guard<std::mutex> lock(pending_mutex_);
      pending_.clear();
    }
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      subscriptions_.clear();
    }
    if (system_state_retained_) {
      (void) chip::Controller::DeviceControllerFactory::GetInstance()
          .ReleaseSystemState();
      system_state_retained_ = false;
    }
    if (factory_initialized_) {
      chip::Controller::DeviceControllerFactory::GetInstance().Shutdown();
      factory_initialized_ = false;
    }
    if (group_initialized_) {
      chip::Credentials::SetGroupDataProvider(nullptr);
      group_provider_.Finish();
      group_initialized_ = false;
    }
    attestation_verifier_.reset();
    paa_store_.reset();
    if (sdk_storage_initialized_) {
      sdk_storage_.Finish();
      sdk_storage_initialized_ = false;
    }
    storage_.reset();
    if (memory_initialized_) {
      chip::Platform::MemoryShutdown();
      memory_initialized_ = false;
    }
  }

  NativeOpenOptions options_;
  ControllerIdentity identity_;
  std::unique_ptr<DurableStorage> storage_;
  SdkStorageBinding sdk_storage_;
  RootAuthority authority_;
  chip::Crypto::RawKeySessionKeystore session_keystore_;
  chip::Credentials::GroupDataProviderImpl group_provider_;
  ControllerConfigurationManager configuration_manager_;
  std::unique_ptr<chip::Credentials::FileAttestationTrustStore> paa_store_;
  std::unique_ptr<chip::Credentials::DefaultDACVerifier>
      attestation_verifier_;
  chip::Controller::DeviceCommissioner commissioner_;
  chip::Crypto::P256Keypair controller_key_;
  std::vector<std::uint8_t> controller_noc_;
  std::vector<std::uint8_t> controller_rcac_;
  std::mutex work_mutex_;
  std::condition_variable work_condition_;
  Action action_{Action::None};
  CHIP_ERROR work_error_{CHIP_ERROR_INCORRECT_STATE};
  bool work_done_{false};
  bool memory_initialized_{false};
  bool sdk_storage_initialized_{false};
  bool group_initialized_{false};
  bool factory_initialized_{false};
  bool system_state_retained_{false};
  bool event_loop_started_{false};
  bool commissioner_initialized_{false};
  bool open_{false};
  bool accepting_interactions_{false};
  std::mutex pending_mutex_;
  std::vector<std::shared_ptr<Pending>> pending_;
  std::mutex subscription_mutex_;
  std::vector<std::shared_ptr<NativeSubscription>> subscriptions_;
  std::mutex sink_mutex_;
  ControllerBackend::ReportSink report_sink_;
  ControllerBackend::FailureSink failure_sink_;
};

InteractionResponse SdkControllerBackend::Impl::Interact(
    const InteractionRequest &request) {
  if (!open_ || !valid_interaction_request(request)) {
    return {false, InteractionError{"invalid_request"}};
  }

  std::shared_ptr<Pending> pending;
  {
    std::lock_guard<std::mutex> lock(pending_mutex_);
    pending_.erase(
        std::remove_if(pending_.begin(), pending_.end(),
                       [](const std::shared_ptr<Pending> &candidate) {
                         return candidate->done();
                       }),
        pending_.end());
    if (!accepting_interactions_ || pending_.size() >= 64U) {
      return {false, InteractionError{"interaction_busy"}};
    }
    pending = std::make_shared<Pending>(*this, request);
    pending_.push_back(pending);
  }

  CHIP_ERROR error = chip::DeviceLayer::PlatformMgr().ScheduleWork(
      StartPending, reinterpret_cast<intptr_t>(pending.get()));
  if (error != CHIP_NO_ERROR) {
    pending->FailBeforeSubmission("interaction_unavailable");
    {
      std::lock_guard<std::mutex> lock(pending->mutex_);
      pending->done_ = true;
    }
    Reap(pending.get());
  }
  return pending->Wait();
}

SubscriptionResponse SdkControllerBackend::Impl::Subscribe(
    const SubscriptionRequest &request) {
  if (!open_ || !valid_subscription_request(request)) {
    SubscriptionResponse invalid;
    invalid.error_code = "invalid_request";
    return invalid;
  }
  if (request.resubscribe) {
    SubscriptionResponse unsupported;
    unsupported.error_code = "not_supported";
    return unsupported;
  }

  std::shared_ptr<NativeSubscription> subscription;
  {
    std::lock_guard<std::mutex> lock(subscription_mutex_);
    subscriptions_.erase(
        std::remove_if(
            subscriptions_.begin(), subscriptions_.end(),
            [](const std::shared_ptr<NativeSubscription> &candidate) {
              return candidate->done();
            }),
        subscriptions_.end());
    if (!accepting_interactions_ || subscriptions_.size() >= 64U) {
      SubscriptionResponse busy;
      busy.error_code = "subscription_busy";
      return busy;
    }
    subscription = std::make_shared<NativeSubscription>(*this, request);
    subscriptions_.push_back(subscription);
  }

  if (chip::DeviceLayer::PlatformMgr().ScheduleWork(
          StartSubscription,
          reinterpret_cast<intptr_t>(subscription.get())) != CHIP_NO_ERROR) {
    subscription->PublishFailure("subscription_unavailable");
    subscription->MarkDone();
  }
  return subscription->Wait();
}

bool SdkControllerBackend::Impl::ActivateSubscription(
    const std::string &subscription_id, std::uint64_t generation) {
  std::shared_ptr<NativeSubscription> subscription;
  {
    std::lock_guard<std::mutex> lock(subscription_mutex_);
    const auto found = std::find_if(
        subscriptions_.begin(), subscriptions_.end(),
        [&](const std::shared_ptr<NativeSubscription> &candidate) {
          return candidate->id() == subscription_id &&
              candidate->generation() == generation && !candidate->done();
        });
    if (found == subscriptions_.end()) {
      return false;
    }
    subscription = *found;
  }
  return subscription->Activate();
}

BackendResult SdkControllerBackend::Impl::CancelSubscription(
    const std::string &subscription_id, std::uint64_t generation,
    std::uint32_t timeout_ms) {
  std::shared_ptr<NativeSubscription> subscription;
  {
    std::lock_guard<std::mutex> lock(subscription_mutex_);
    const auto found = std::find_if(
        subscriptions_.begin(), subscriptions_.end(),
        [&](const std::shared_ptr<NativeSubscription> &candidate) {
          return candidate->id() == subscription_id &&
              candidate->generation() == generation && !candidate->done();
        });
    if (found == subscriptions_.end()) {
      return {false, "invalid_subscription"};
    }
    subscription = *found;
  }
  if (!subscription->CancelAndWait(timeout_ms)) {
    return {false, "subscription_cancel_timeout"};
  }
  return {true, {}};
}

SdkControllerBackend::SdkControllerBackend() : impl_(std::make_unique<Impl>()) {}

SdkControllerBackend::~SdkControllerBackend() = default;

BackendResult SdkControllerBackend::Open(const NativeOpenOptions &options) {
  return impl_->Open(options);
}

InteractionResponse SdkControllerBackend::Interact(
    const InteractionRequest &request) {
  return impl_->Interact(request);
}

void SdkControllerBackend::SetSubscriptionSinks(ReportSink report,
                                                FailureSink failure) {
  impl_->SetSubscriptionSinks(std::move(report), std::move(failure));
}

SubscriptionResponse SdkControllerBackend::Subscribe(
    const SubscriptionRequest &request) {
  return impl_->Subscribe(request);
}

bool SdkControllerBackend::ActivateSubscription(
    const std::string &subscription_id, std::uint64_t generation) {
  return impl_->ActivateSubscription(subscription_id, generation);
}

BackendResult SdkControllerBackend::CancelSubscription(
    const std::string &subscription_id, std::uint64_t generation,
    std::uint32_t timeout_ms) {
  return impl_->CancelSubscription(subscription_id, generation, timeout_ms);
}

void SdkControllerBackend::Close() { impl_->Close(); }

bool SdkControllerBackend::IsOpen() const { return impl_->IsOpen(); }

} // namespace wotex::matter
