#include "wotex_matter/controller.hpp"

#include "wotex_matter/authority.hpp"
#include "wotex_matter/resource_testing.hpp"
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
#include <clusters/AdministratorCommissioning/Attributes.h>
#include <clusters/AccessControl/Attributes.h>
#include <clusters/Descriptor/Attributes.h>
#include <clusters/OnOff/Attributes.h>
#include <clusters/OnOff/Commands.h>
#include <clusters/TemperatureMeasurement/Attributes.h>
#include <clusters/Thermostat/Attributes.h>
#include <controller/CHIPDeviceControllerFactory.h>
#include <controller/CommissioningWindowOpener.h>
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
#include <protocols/secure_channel/Constants.h>
#include <setup_payload/ManualSetupPayloadGenerator.h>
#include <setup_payload/QRCodeSetupPayloadGenerator.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <new>
#include <optional>
#include <type_traits>
#include <thread>
#include <utility>
#include <vector>

#ifdef WOTEX_MATTER_RESOURCE_TESTING
#define WOTEX_STARTUP_STAGE(name) \
  if (resource_testing::StartupStage(name)) { \
    Cleanup(); \
    return {false, "controller_start_failed"}; \
  }
#else
#define WOTEX_STARTUP_STAGE(name)
#endif

namespace wotex::matter {
namespace {

bool SamePublicKey(const chip::Crypto::P256PublicKey &left,
                   const chip::Crypto::P256PublicKey &right) {
  return left.Length() == right.Length() &&
      std::memcmp(left.ConstBytes(), right.ConstBytes(), left.Length()) == 0;
}

// The concrete path of a selector that names all three components. The backend
// sees only requests the validators admitted: valid_interaction_request for
// event reads, writes and invokes, valid_subscription_request for every
// subscription path.
ConcretePath AdmittedPath(const PathSelector &path) {
  // NOLINTNEXTLINE(bugprone-unchecked-optional-access): the validators admit only concrete paths here
  return {path.fabric_id, path.node_id, *path.endpoint, *path.cluster, *path.member};
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
CHIP_ERROR DecodeNullableUnsigned(chip::TLV::TLVReader &reader,
                                  NativeValue &output) {
  T value;
  ReturnErrorOnFailure(chip::app::DataModel::Decode(reader, value));
  output = value.IsNull()
      ? NativeValue::null_value()
      : NativeValue::unsigned_integer(
            static_cast<std::uint64_t>(value.Value()));
  return CHIP_NO_ERROR;
}

CHIP_ERROR DecodeTag(const chip::TLV::TLVReader &reader, Tag &tag) {
  const chip::TLV::Tag native = reader.GetTag();
  if (native == chip::TLV::AnonymousTag()) {
    tag = Tag{};
    return CHIP_NO_ERROR;
  }
  VerifyOrReturnError(chip::TLV::IsContextTag(native),
                      CHIP_ERROR_INVALID_TLV_TAG);
  tag = Tag{TagKind::Context,
            static_cast<std::uint8_t>(chip::TLV::TagNumFromTag(native))};
  return CHIP_NO_ERROR;
}

CHIP_ERROR DecodeRawElement(chip::TLV::TLVReader &reader, Element &output,
                            std::size_t depth, std::size_t &nodes) {
  VerifyOrReturnError(depth <= 8U && ++nodes <= 1024U,
                      CHIP_ERROR_BUFFER_TOO_SMALL);
  ReturnErrorOnFailure(DecodeTag(reader, output.tag));
  switch (reader.GetType()) {
  case chip::TLV::kTLVType_Null:
    output.type = ElementType::Null;
    return CHIP_NO_ERROR;
  case chip::TLV::kTLVType_SignedInteger:
    output.type = ElementType::I16;
    return reader.Get(output.signed_value);
  case chip::TLV::kTLVType_UnsignedInteger:
    output.type = ElementType::U64;
    return reader.Get(output.unsigned_value);
  case chip::TLV::kTLVType_Boolean:
    output.type = ElementType::Boolean;
    return reader.Get(output.boolean_value);
  case chip::TLV::kTLVType_Structure:
  case chip::TLV::kTLVType_Array: {
    output.type = reader.GetType() == chip::TLV::kTLVType_Structure
        ? ElementType::Structure : ElementType::Array;
    chip::TLV::TLVType outer;
    ReturnErrorOnFailure(reader.EnterContainer(outer));
    CHIP_ERROR error = CHIP_NO_ERROR;
    while ((error = reader.Next()) == CHIP_NO_ERROR) {
      Element child;
      ReturnErrorOnFailure(DecodeRawElement(reader, child, depth + 1U, nodes));
      output.children.push_back(std::move(child));
    }
    VerifyOrReturnError(error == CHIP_END_OF_TLV, error);
    return reader.ExitContainer(outer);
  }
  default:
    return CHIP_ERROR_UNSUPPORTED_CHIP_FEATURE;
  }
}

CHIP_ERROR NormalizeAccessControl(Element &element) {
  VerifyOrReturnError(element.tag.kind == TagKind::Anonymous &&
                          element.type == ElementType::Array &&
                          element.children.size() <= 64U,
                      CHIP_ERROR_INVALID_ARGUMENT);
  for (Element &entry : element.children) {
    VerifyOrReturnError(entry.tag.kind == TagKind::Anonymous &&
                            entry.type == ElementType::Structure,
                        CHIP_ERROR_INVALID_ARGUMENT);
    for (Element &field : entry.children) {
      VerifyOrReturnError(field.tag.kind == TagKind::Context,
                          CHIP_ERROR_INVALID_ARGUMENT);
      if (field.type == ElementType::U64 &&
          (field.tag.id == 1U || field.tag.id == 2U || field.tag.id == 5U ||
           field.tag.id == 254U)) {
        field.type = ElementType::U8;
      } else if (field.tag.id == 4U && field.type == ElementType::Array) {
        for (Element &target : field.children) {
          VerifyOrReturnError(target.tag.kind == TagKind::Anonymous &&
                                  target.type == ElementType::Structure,
                              CHIP_ERROR_INVALID_ARGUMENT);
          for (Element &target_field : target.children) {
            VerifyOrReturnError(target_field.tag.kind == TagKind::Context,
                                CHIP_ERROR_INVALID_ARGUMENT);
            if (target_field.type == ElementType::U64) {
              target_field.type = target_field.tag.id == 1U
                  ? ElementType::U16 : ElementType::U32;
            }
          }
        }
      }
    }
  }
  return validate_element(MemberKind::Attribute, 0x001FU, 0x0000U,
                          Operation::Read, element) == ConversionError::None
      ? CHIP_NO_ERROR : CHIP_ERROR_INVALID_ARGUMENT;
}

chip::TLV::Tag NativeTag(const Tag &tag) {
  return tag.kind == TagKind::Anonymous
      ? chip::TLV::AnonymousTag() : chip::TLV::ContextTag(tag.id);
}

CHIP_ERROR EncodeElement(chip::TLV::TLVWriter &writer,
                         const Element &element) {
  const chip::TLV::Tag tag = NativeTag(element.tag);
  switch (element.type) {
  case ElementType::Null:
    return writer.PutNull(tag);
  case ElementType::I16:
    return writer.Put(tag, static_cast<std::int16_t>(element.signed_value));
  case ElementType::U8:
    return writer.Put(tag, static_cast<std::uint8_t>(element.unsigned_value));
  case ElementType::U16:
    return writer.Put(tag, static_cast<std::uint16_t>(element.unsigned_value));
  case ElementType::U32:
    return writer.Put(tag, static_cast<std::uint32_t>(element.unsigned_value));
  case ElementType::U64:
    return writer.Put(tag, element.unsigned_value);
  case ElementType::Boolean:
    return writer.Put(tag, element.boolean_value);
  case ElementType::Structure:
  case ElementType::Array: {
    chip::TLV::TLVType outer;
    ReturnErrorOnFailure(writer.StartContainer(
        tag, element.type == ElementType::Structure
                 ? chip::TLV::kTLVType_Structure : chip::TLV::kTLVType_Array,
        outer));
    for (const Element &child : element.children) {
      ReturnErrorOnFailure(EncodeElement(writer, child));
    }
    return writer.EndContainer(outer);
  }
  }
  return CHIP_ERROR_INVALID_ARGUMENT;
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
  } else if (path.cluster == AccessControl::Id &&
             path.member == AccessControl::Attributes::Acl::Id) {
    std::size_t nodes = 0;
    ReturnErrorOnFailure(DecodeRawElement(reader, output, 0U, nodes));
    return NormalizeAccessControl(output);
  } else if (path.cluster == AdministratorCommissioning::Id &&
             path.member == AdministratorCommissioning::Attributes::WindowStatus::Id) {
    using Type = AdministratorCommissioning::Attributes::WindowStatus::TypeInfo::DecodableType;
    error = DecodeScalar<Type>(reader, value);
  } else if (path.cluster == AdministratorCommissioning::Id &&
             path.member == AdministratorCommissioning::Attributes::AdminFabricIndex::Id) {
    using Type = AdministratorCommissioning::Attributes::AdminFabricIndex::TypeInfo::DecodableType;
    error = DecodeNullableUnsigned<Type>(reader, value);
  } else if (path.cluster == AdministratorCommissioning::Id &&
             path.member == AdministratorCommissioning::Attributes::AdminVendorId::Id) {
    using Type = AdministratorCommissioning::Attributes::AdminVendorId::TypeInfo::DecodableType;
    error = DecodeNullableUnsigned<Type>(reader, value);
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
  if (path.cluster == AccessControl::Id &&
      path.member == AccessControl::Attributes::Acl::Id) {
    VerifyOrReturnError(
        validate_element(MemberKind::Attribute, path.cluster, path.member,
                         Operation::Write, element) == ConversionError::None,
        CHIP_ERROR_INVALID_ARGUMENT);
    return EncodeElement(writer, element);
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

class SdkControllerBackend::Impl final
    : public chip::Controller::DevicePairingDelegate {
  class Pending;
  class NativeSubscription;
  class PendingCommissioning;
  class PendingWindow;

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
    WOTEX_STARTUP_STAGE("memory")

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
    WOTEX_STARTUP_STAGE("storage")
    error = storage_->EnterProcessDirectory();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "storage_open_failed"};
    }
    WOTEX_STARTUP_STAGE("storage_directory")
    error = sdk_storage_.Init(*storage_);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "sdk_storage_failed"};
    }
    sdk_storage_initialized_ = true;
    WOTEX_STARTUP_STAGE("sdk_storage")

    error = authority_.Init(*storage_, authority_mode, identity_);
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "authority_invalid"};
    }

    WOTEX_STARTUP_STAGE("authority")
    paa_store_ = std::make_unique<chip::Credentials::FileAttestationTrustStore>(
        options.paa_trust_store.c_str());
    if (!paa_store_->IsInitialized() || paa_store_->paaCount() == 0) {
      Cleanup();
      return {false, "paa_trust_store_invalid"};
    }
    attestation_verifier_ =
        std::make_unique<chip::Credentials::DefaultDACVerifier>(paa_store_.get());

    WOTEX_STARTUP_STAGE("attestation")
    group_provider_.SetStorageDelegate(storage_.get());
    group_provider_.SetSessionKeystore(&session_keystore_);
    error = group_provider_.Init();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "controller_start_failed"};
    }
    group_initialized_ = true;
    chip::Credentials::SetGroupDataProvider(&group_provider_);
    WOTEX_STARTUP_STAGE("groups")

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
    WOTEX_STARTUP_STAGE("factory")
    factory.RetainSystemState();
    system_state_retained_ = true;
    WOTEX_STARTUP_STAGE("system_state")

    error = factory.ServiceEvents();
    if (error != CHIP_NO_ERROR) {
      Cleanup();
      return {false, "controller_start_failed"};
    }
    event_loop_started_ = true;
    WOTEX_STARTUP_STAGE("event_loop")

    error = Execute(Action::Setup, options.timeout_ms);
    if (error != CHIP_NO_ERROR) {
      const std::string code = error == CHIP_ERROR_TIMEOUT
          ? "controller_start_timeout"
          : "controller_start_failed";
      Cleanup();
      return {false, code};
    }

    WOTEX_STARTUP_STAGE("commissioner")
    open_ = true;
    accepting_interactions_ = true;
    return {true, {}};
  }

  void SetControlPump(std::function<bool()> pump) {
    control_pump_ = std::move(pump);
    control_thread_ = std::this_thread::get_id();
  }

  template <typename Predicate>
  bool WaitForControl(std::condition_variable &condition,
                      std::unique_lock<std::mutex> &lock,
                      std::uint32_t timeout_ms, Predicate complete) {
    if (!control_pump_ || std::this_thread::get_id() != control_thread_) {
      return condition.wait_for(lock, std::chrono::milliseconds(timeout_ms), complete);
    }
    auto deadline = std::chrono::steady_clock::now() +
        std::chrono::milliseconds(timeout_ms);
    if (control_deadline_) {
      deadline = std::min(deadline, *control_deadline_);
    }
    struct DeadlineOwner {
      std::optional<std::chrono::steady_clock::time_point> &slot;
      std::optional<std::chrono::steady_clock::time_point> previous;
      ~DeadlineOwner() { slot = previous; }
    } deadline_owner{control_deadline_, control_deadline_};
    control_deadline_ = deadline;
    while (!complete()) {
      const auto now = std::chrono::steady_clock::now();
      if (now >= deadline) {
        return false;
      }
      const auto next = std::min(deadline, now + std::chrono::milliseconds(5));
      if (condition.wait_until(lock, next, complete)) {
        return true;
      }
      // Controls may cancel another SDK context. No context mutex is retained
      // while dispatching them, and each wait retains its original deadline.
      lock.unlock();
      const bool keep_waiting = control_pump_();
      lock.lock();
      if (!keep_waiting) {
        return false;
      }
    }
    return true;
  }

  void Close() { Cleanup(); }
  bool IsOpen() const { return open_; }

#ifdef WOTEX_MATTER_RESOURCE_TESTING
  std::string ResourceSnapshotForTesting() {
    if (!event_loop_started_) {
      return resource_testing::SnapshotJson();
    }
    if (Execute(Action::ObserveResources, 1000) != CHIP_NO_ERROR) {
      return {};
    }
    return resource_snapshot_;
  }
#endif

  InteractionResponse Interact(const InteractionRequest &request);
  CommissioningResponse Commission(const CommissioningRequest &request);
  CommissioningWindowResponse OpenWindow(
      const CommissioningWindowRequest &request);
  void SetSubscriptionSinks(ControllerBackend::ReportSink report,
                            ControllerBackend::StatusSink status,
                            ControllerBackend::FailureSink failure) {
    std::lock_guard<std::mutex> lock(sink_mutex_);
    report_sink_ = std::move(report);
    status_sink_ = std::move(status);
    failure_sink_ = std::move(failure);
  }
  SubscriptionResponse Subscribe(const SubscriptionRequest &request);
  bool ActivateSubscription(const std::string &subscription_id,
                            std::uint64_t generation);
  BackendResult CancelSubscription(const std::string &subscription_id,
                                   std::uint64_t generation,
                                   std::uint32_t timeout_ms);

  void OnCommissioningComplete(chip::NodeId device_id,
                               CHIP_ERROR error) override;
  void OnCommissioningFailure(
      chip::PeerId, const chip::Controller::CompletionStatus &status) override;
  void OnCommissioningStageStart(
      chip::PeerId, chip::Controller::CommissioningStage stage) override;

 private:
  class PendingCommissioning final
      : public std::enable_shared_from_this<PendingCommissioning> {
   public:
    friend class Impl;

    PendingCommissioning(Impl &owner, CommissioningRequest request)
        : owner_(owner), request_(request),
          started_(std::chrono::steady_clock::now()),
          connected_(&CaseConnected, this),
          connection_failed_(&CaseConnectionFailed, this) {}

    CommissioningResponse Wait() {
      std::unique_lock<std::mutex> lock(mutex_);
      if (!owner_.WaitForControl(condition_, lock, Remaining(),
                                  [this] { return published_; })) {
        // Wait still owns mutex_; the accessor would lock it recursively.
        response_ = Failure("commissioning_timeout", CHIP_ERROR_TIMEOUT,
                            fabric_mutation_may_have_started_);
        published_ = true;
        resource_testing::Event("commissioning_published");
        lock.unlock();
        ScheduleAbort();
      }
      return response_;
    }

    void Start() {
      if (Remaining() == 0U) {
        Publish(Failure("commissioning_timeout", CHIP_ERROR_TIMEOUT, false));
        MarkDone();
        return;
      }

      chip::SetupPayload payload;
      payload.version = 0;
      payload.vendorID = 0;
      payload.productID = 0;
      payload.commissioningFlow = chip::CommissioningFlow::kStandard;
      payload.rendezvousInformation.SetValue(
          chip::RendezvousInformationFlags(
              chip::RendezvousInformationFlag::kOnNetwork));
      payload.discriminator.SetLongValue(request_.discriminator);
      payload.setUpPINCode = request_.setup_pin;

      std::string setup_code;
      CHIP_ERROR error =
          chip::QRCodeSetupPayloadGenerator(payload)
              .payloadBase38Representation(setup_code);
      if (error == CHIP_NO_ERROR) {
        error = owner_.commissioner_.DiscoverCommissionableNodes(
            chip::Dnssd::DiscoveryFilter(
                chip::Dnssd::DiscoveryFilterType::kLongDiscriminator,
                request_.discriminator));
      }
      if (error == CHIP_NO_ERROR) {
        (void) owner_.commissioner_.StopCommissionableDiscovery();
        submitted_ = true;
        error = owner_.commissioner_.PairDevice(
            request_.node_id, setup_code.c_str(),
            chip::Controller::DiscoveryType::kDiscoveryNetworkOnly);
      }
      if (error != CHIP_NO_ERROR) {
        Publish(Failure("commissioning_submit_failed", error, false));
        MarkDone();
      }
    }

    void StageStarted(chip::Controller::CommissioningStage stage) {
      if (stage == chip::Controller::CommissioningStage::kSendTrustedRootCert ||
          stage == chip::Controller::CommissioningStage::kSendNOC) {
        std::lock_guard<std::mutex> lock(mutex_);
        fabric_mutation_may_have_started_ = true;
      }
    }

    void RecordFailure(const chip::Controller::CompletionStatus &status) {
      std::lock_guard<std::mutex> lock(mutex_);
      final_status_ = status.err;
    }

    void CommissioningComplete(chip::NodeId device_id, CHIP_ERROR error) {
      (void) owner_.commissioner_.StopCommissionableDiscovery();
      if (device_id != request_.node_id || error != CHIP_NO_ERROR) {
        CHIP_ERROR status = error;
        {
          std::lock_guard<std::mutex> lock(mutex_);
          if (status == CHIP_NO_ERROR && final_status_.has_value()) {
            status = *final_status_;
          }
        }
        if (status == CHIP_NO_ERROR) {
          status = CHIP_ERROR_INVALID_ARGUMENT;
        }
        Publish(Failure("commissioning_failed", status,
                        FabricMutationMayHaveStarted()));
        MarkDone();
        return;
      }

      CHIP_ERROR case_error = owner_.commissioner_.GetConnectedDevice(
          request_.node_id, &connected_, &connection_failed_);
      if (case_error != CHIP_NO_ERROR) {
        Publish(Failure("commissioning_failed", case_error, true));
        MarkDone();
      }
    }

    void AbortOnSdkThread() {
      resource_testing::Event("commissioning_aborted");
      connected_.Cancel();
      connection_failed_.Cancel();
      if (submitted_) {
        (void) owner_.commissioner_.StopPairing(request_.node_id);
      }
      Publish(Failure("controller_closed", CHIP_ERROR_CANCELLED,
                      FabricMutationMayHaveStarted()));
      MarkDone();
    }

    bool done() const {
      std::lock_guard<std::mutex> lock(mutex_);
      return done_;
    }

   private:
    static void CaseConnected(void *context,
                              chip::Messaging::ExchangeManager &,
                              const chip::SessionHandle &) {
      auto *self = static_cast<PendingCommissioning *>(context);
      self->Publish({true, std::nullopt, self->request_.node_id,
                     self->owner_.identity_.fabric_id, true});
      self->MarkDone();
    }

    static void CaseConnectionFailed(void *context, const chip::ScopedNodeId &,
                                     CHIP_ERROR error) {
      auto *self = static_cast<PendingCommissioning *>(context);
      self->Publish(self->Failure("commissioning_failed", error, true));
      self->MarkDone();
    }

    static void CancelWork(intptr_t context) {
      std::unique_ptr<std::shared_ptr<PendingCommissioning>> holder(
          reinterpret_cast<std::shared_ptr<PendingCommissioning> *>(context));
      (*holder)->AbortOnSdkThread();
    }

    void ScheduleAbort() {
      auto *holder = new (std::nothrow)
          std::shared_ptr<PendingCommissioning>(shared_from_this());
      if (holder == nullptr) {
        return;
      }
      if (chip::DeviceLayer::PlatformMgr().ScheduleWork(
              CancelWork, reinterpret_cast<intptr_t>(holder)) !=
          CHIP_NO_ERROR) {
        delete holder;
      }
    }

    CommissioningResponse Failure(std::string code, CHIP_ERROR error,
                                  bool mutation) const {
      return {false,
              CommissioningError{
                  std::move(code),
                  static_cast<std::uint32_t>(error.AsInteger()),
                  mutation ? InteractionEffect::Unknown
                           : InteractionEffect::None},
              0, 0, false};
    }

    void Publish(CommissioningResponse response) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (published_) {
          return;
        }
        response_ = std::move(response);
        published_ = true;
        resource_testing::Event("commissioning_published");
      }
      condition_.notify_one();
    }

    void MarkDone() {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (done_) {
          return;
        }
        done_ = true;
      }
      (void) chip::DeviceLayer::PlatformMgr().ScheduleWork(
          ReapCommissioning, reinterpret_cast<intptr_t>(this));
    }

    bool FabricMutationMayHaveStarted() const {
      std::lock_guard<std::mutex> lock(mutex_);
      return fabric_mutation_may_have_started_;
    }

    std::uint32_t Remaining() const {
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - started_);
      return remaining_timeout_ms(request_.timeout_ms,
                                  static_cast<std::uint64_t>(elapsed.count()));
    }

#ifdef WOTEX_MATTER_RESOURCE_TESTING
    resource_testing::Lifetime resource_lifetime_{resource_testing::Object::Commissioning};
#endif
    Impl &owner_;
    CommissioningRequest request_;
    std::chrono::steady_clock::time_point started_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    CommissioningResponse response_;
    std::optional<CHIP_ERROR> final_status_;
    bool submitted_{false};
    bool fabric_mutation_may_have_started_{false};
    bool published_{false};
    bool done_{false};
    chip::Callback::Callback<chip::OnDeviceConnected> connected_;
    chip::Callback::Callback<chip::OnDeviceConnectionFailure>
        connection_failed_;
  };

  class PendingWindow final
      : public std::enable_shared_from_this<PendingWindow> {
   public:
    friend class Impl;

    PendingWindow(Impl &owner, CommissioningWindowRequest request)
        : owner_(owner), request_(request),
          started_(std::chrono::steady_clock::now()),
          callback_(&Opened, this) {}

    CommissioningWindowResponse Wait() {
      std::unique_lock<std::mutex> lock(mutex_);
      if (!owner_.WaitForControl(condition_, lock, Remaining(),
                                  [this] { return published_; })) {
        response_ = Failure("window_timeout", CHIP_ERROR_TIMEOUT, submitted_);
        published_ = true;
        resource_testing::Event("window_published");
        lock.unlock();
        ScheduleAbort();
      }
      return response_;
    }

    void Start() {
      if (Remaining() == 0U) {
        Publish(Failure("window_timeout", CHIP_ERROR_TIMEOUT, false));
        MarkDone();
        return;
      }

      opener_ = resource_testing::Make<chip::Controller::CommissioningWindowOpener,
          resource_testing::Object::WindowOpener>(
          &owner_.commissioner_);
      chip::Controller::CommissioningWindowPasscodeParams params;
      params.SetNodeId(request_.node_id)
          .SetTimeout(request_.timeout_s)
          .SetIteration(request_.iteration_count)
          .SetDiscriminator(request_.discriminator)
          .SetSetupPIN(chip::NullOptional)
          .SetSalt(chip::NullOptional)
          .SetReadVIDPIDAttributes(false)
          .SetCallback(&callback_);
      chip::SetupPayload temporary_payload;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        submitted_ = true;
      }
      CHIP_ERROR error =
          opener_->OpenCommissioningWindow(params, temporary_payload);
      if (error != CHIP_NO_ERROR) {
        std::lock_guard<std::mutex> lock(mutex_);
        submitted_ = false;
      }
      if (error != CHIP_NO_ERROR) {
        Publish(Failure("window_submit_failed", error, false));
        MarkDone();
      }
    }

    void AbortOnSdkThread() {
      resource_testing::Event("window_aborted");
      callback_.Cancel();
      opener_.reset();
      Publish(Failure("controller_closed", CHIP_ERROR_CANCELLED, Submitted()));
      MarkDone();
    }

    bool done() const {
      std::lock_guard<std::mutex> lock(mutex_);
      return done_;
    }

   private:
    static void Opened(
        void *context, chip::NodeId device_id, CHIP_ERROR status,
        // NOLINTNEXTLINE(performance-unnecessary-value-param): the SDK's OnOpenCommissioningWindow callback type passes the payload by value
        chip::SetupPayload payload) {
      auto *self = static_cast<PendingWindow *>(context);
      if (status != CHIP_NO_ERROR || device_id != self->request_.node_id ||
          payload.discriminator.IsShortDiscriminator()) {
        if (status == CHIP_NO_ERROR) {
          status = CHIP_ERROR_INVALID_ARGUMENT;
        }
        self->Publish(self->Failure("window_failed", status, true));
        self->MarkDone();
        return;
      }

      std::string manual_code;
      std::string qr_code;
      CHIP_ERROR error =
          chip::ManualSetupPayloadGenerator(payload)
              .payloadDecimalStringRepresentation(manual_code);
      if (error == CHIP_NO_ERROR) {
        error = chip::QRCodeSetupPayloadGenerator(payload)
                    .payloadBase38Representation(qr_code);
      }
      if (error != CHIP_NO_ERROR ||
          !valid_setup_pin(payload.setUpPINCode) ||
          payload.discriminator.GetLongValue() != self->request_.discriminator) {
        self->Publish(self->Failure("window_failed",
                                    error == CHIP_NO_ERROR
                                        ? CHIP_ERROR_INVALID_ARGUMENT
                                        : error,
                                    true));
      } else {
        self->Publish({true,
                       std::nullopt,
                       device_id,
                       payload.setUpPINCode,
                       self->request_.discriminator,
                       self->request_.timeout_s,
                       std::move(manual_code),
                       std::move(qr_code)});
      }
      self->MarkDone();
    }

    CommissioningWindowResponse Failure(std::string code, CHIP_ERROR error,
                                        bool mutation) const {
      return {false,
              CommissioningError{
                  std::move(code),
                  static_cast<std::uint32_t>(error.AsInteger()),
                  mutation ? InteractionEffect::Unknown
                           : InteractionEffect::None},
              0, 0, 0, 0, {}, {}};
    }

    static void CancelWork(intptr_t context) {
      std::unique_ptr<std::shared_ptr<PendingWindow>> holder(
          reinterpret_cast<std::shared_ptr<PendingWindow> *>(context));
      (*holder)->AbortOnSdkThread();
    }

    void ScheduleAbort() {
      auto *holder =
          new (std::nothrow) std::shared_ptr<PendingWindow>(shared_from_this());
      if (holder == nullptr) {
        return;
      }
      if (chip::DeviceLayer::PlatformMgr().ScheduleWork(
              CancelWork, reinterpret_cast<intptr_t>(holder)) !=
          CHIP_NO_ERROR) {
        delete holder;
      }
    }

    bool Submitted() const {
      std::lock_guard<std::mutex> lock(mutex_);
      return submitted_;
    }

    void Publish(CommissioningWindowResponse response) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (published_) {
          return;
        }
        response_ = std::move(response);
        published_ = true;
        resource_testing::Event("window_published");
      }
      condition_.notify_one();
    }

    void MarkDone() {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (done_) {
          return;
        }
        done_ = true;
      }
      (void) chip::DeviceLayer::PlatformMgr().ScheduleWork(
          ReapWindow, reinterpret_cast<intptr_t>(this));
    }

    std::uint32_t Remaining() const {
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - started_);
      return remaining_timeout_ms(request_.timeout_ms,
                                  static_cast<std::uint64_t>(elapsed.count()));
    }

#ifdef WOTEX_MATTER_RESOURCE_TESTING
    resource_testing::Lifetime resource_lifetime_{resource_testing::Object::Window};
#endif
    Impl &owner_;
    CommissioningWindowRequest request_;
    std::chrono::steady_clock::time_point started_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    CommissioningWindowResponse response_;
    bool submitted_{false};
    bool published_{false};
    bool done_{false};
    chip::Callback::Callback<chip::Controller::OnOpenCommissioningWindow>
        callback_;
    resource_testing::Pointer<chip::Controller::CommissioningWindowOpener,
        resource_testing::Object::WindowOpener> opener_;
  };

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
      if (!owner_.WaitForControl(condition_, lock, Remaining(),
                                  [this] { return published_; })) {
        InteractionEffect effect = mutation_.submitted() && IsMutation()
            ? InteractionEffect::Unknown
            : InteractionEffect::None;
        response_ = {false,
                     InteractionError{"interaction_timeout", std::nullopt,
                                      std::nullopt, effect}};
        published_ = true;
        resource_testing::Event("interaction_published");
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
      resource_testing::Event("interaction_aborted");
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
      read_client_ = resource_testing::Make<chip::app::ReadClient,
          resource_testing::Object::ReadClient>(
          chip::app::InteractionModelEngine::GetInstance(), &exchange_manager,
          buffered_read_, chip::app::ReadClient::InteractionType::Read);

      chip::app::ReadPrepareParams params(session);
      params.mTimeout = chip::System::Clock::Milliseconds32(remaining);
      params.mKeepSubscriptions = false;
      params.mIsFabricFiltered = true;

      if (request_.kind == InteractionKind::ReadEvents) {
        event_paths_.reserve(request_.paths.size());
        for (const PathSelector &path : request_.paths) {
          const ConcretePath concrete = AdmittedPath(path);
          event_paths_.emplace_back(concrete.endpoint, concrete.cluster, concrete.member);
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
      write_client_ = resource_testing::Make<chip::app::WriteClient,
          resource_testing::Object::WriteClient>(
          &exchange_manager, this, timed, false);

      const ConcretePath concrete = AdmittedPath(request_.paths.front());
      chip::Optional<chip::DataVersion> version;
      if (request_.expected_data_version) {
        version.SetValue(*request_.expected_data_version);
      }
      chip::app::ConcreteDataAttributePath native(
          concrete.endpoint, concrete.cluster, concrete.member, version);

      write_buffer_.assign(kMaximumEncodedTlvBytes, 0);
      chip::TLV::TLVWriter writer;
      writer.Init(write_buffer_.data(), write_buffer_.size());
      // NOLINTNEXTLINE(bugprone-unchecked-optional-access): valid_interaction_request admits a write only with its value
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
      command_sender_ = resource_testing::Make<chip::app::CommandSender,
          resource_testing::Object::CommandSender>(
          this, &exchange_manager, timed, false, false);
      const ConcretePath path = AdmittedPath(request_.paths.front());
      chip::app::CommandPathParams native(path.endpoint, path.cluster, path.member,
                                          chip::app::CommandPathFlags::kEndpointIdValid);
      chip::Optional<std::uint16_t> timed_value;
      if (request_.timed_request_timeout_ms) {
        timed_value.SetValue(*request_.timed_request_timeout_ms);
      }
      chip::app::CommandSender::AddRequestDataParameters params(timed_value);
      CHIP_ERROR error = CHIP_ERROR_UNSUPPORTED_CHIP_FEATURE;
      using namespace chip::app::Clusters::OnOff::Commands;
      if (path.cluster == chip::app::Clusters::OnOff::Id && path.member == Off::Id) {
        error = command_sender_->AddRequestData(native, Off::Type{}, params);
      } else if (path.cluster == chip::app::Clusters::OnOff::Id && path.member == On::Id) {
        error = command_sender_->AddRequestData(native, On::Type{}, params);
      } else if (path.cluster == chip::app::Clusters::OnOff::Id && path.member == Toggle::Id) {
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
      resource_testing::Event("interaction_read_done");
      read_client_.reset();
      FinishRead();
    }

    void OnDone(chip::app::WriteClient *) override {
      resource_testing::Event("write_done");
      write_client_.reset();
      FinishMutation();
    }

    void OnDone(chip::app::CommandSender *) override {
      resource_testing::Event("command_done");
      command_sender_.reset();
      FinishMutation();
    }

    void FinishRead() {
      if (!overall_error_.has_value() && request_.kind != InteractionKind::ReadEvents) {
        AddMissingConcreteResults();
      }
      if (overall_error_) {
        Publish({false, overall_error_});
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
        Publish({false, overall_error_});
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
      const ConcretePath expected = AdmittedPath(request_.paths.front());
      return path.fabric_id == expected.fabric_id && path.node_id == expected.node_id &&
          path.endpoint == expected.endpoint && path.cluster == expected.cluster &&
          path.member == expected.member;
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
        resource_testing::Event("interaction_published");
      }
      condition_.notify_one();
    }

    void DoneWithoutClient() {
      MarkDone();
    }

    void MarkDone() {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (done_) {
          return;
        }
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

#ifdef WOTEX_MATTER_RESOURCE_TESTING
    resource_testing::Lifetime resource_lifetime_{resource_testing::Object::Interaction};
#endif
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
    resource_testing::Pointer<chip::app::ReadClient,
        resource_testing::Object::ReadClient> read_client_;
    resource_testing::Pointer<chip::app::WriteClient,
        resource_testing::Object::WriteClient> write_client_;
    resource_testing::Pointer<chip::app::CommandSender,
        resource_testing::Object::CommandSender> command_sender_;
    std::vector<chip::app::AttributePathParams> attribute_paths_;
    std::vector<chip::app::EventPathParams> event_paths_;
    std::vector<std::uint8_t> write_buffer_{};
  };

  class NativeSubscription final : public chip::app::ReadClient::Callback {
   public:
    friend class Impl;

    NativeSubscription(Impl &owner, SubscriptionRequest request)
        : owner_(owner), request_(std::move(request)), buffer_(request_),
          recovery_(request_.resubscribe),
          started_(std::chrono::steady_clock::now()),
          connected_(&Connected, this), connection_failed_(&ConnectionFailed, this) {}

    SubscriptionResponse Wait() {
      std::unique_lock<std::mutex> lock(mutex_);
      if (!owner_.WaitForControl(condition_, lock, Remaining(),
                                  [this] { return published_; })) {
        response_.error_code = "subscription_timeout";
        published_ = true;
        resource_testing::Event("subscription_published");
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
      return Emit(reports);
    }

    bool CancelAndWait(std::uint32_t timeout_ms) {
      ScheduleCancel();
      std::unique_lock<std::mutex> lock(mutex_);
      return owner_.WaitForControl(condition_, lock, timeout_ms,
                                  [this] { return done_; });
    }

    bool done() const {
      std::lock_guard<std::mutex> lock(mutex_);
      return done_;
    }

    const std::string &id() const { return request_.subscription_id; }
    std::uint64_t generation() const {
      std::lock_guard<std::mutex> lock(mutex_);
      return recovery_.generation();
    }

    void CancelOnSdkThread() {
      resource_testing::Event("subscription_cancelled");
      connected_.Cancel();
      connection_failed_.Cancel();
      {
        std::lock_guard<std::mutex> lock(mutex_);
        cancelled_ = true;
        recovery_.Cancel();
        buffer_.Cancel();
      }
      CancelRecoveryTimer();
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

      read_client_ = resource_testing::Make<chip::app::ReadClient,
          resource_testing::Object::ReadClient>(
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
          const ConcretePath concrete = AdmittedPath(path);
          attribute_paths_.emplace_back(concrete.endpoint, concrete.cluster, concrete.member);
        }
        params.mpAttributePathParamsList = attribute_paths_.data();
        params.mAttributePathParamsListSize = attribute_paths_.size();
      } else {
        event_paths_.reserve(request_.paths.size());
        for (const PathSelector &path : request_.paths) {
          const ConcretePath concrete = AdmittedPath(path);
          event_paths_.emplace_back(concrete.endpoint, concrete.cluster, concrete.member);
        }
        params.mpEventPathParamsList = event_paths_.data();
        params.mEventPathParamsListSize = event_paths_.size();
      }

      const CHIP_ERROR error = request_.resubscribe
          ? read_client_->SendAutoResubscribeRequest(std::move(params))
          : read_client_->SendRequest(params);
      if (error != CHIP_NO_ERROR) {
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
      (void)Emit(reports);
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
      bool previously_established = false;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        previously_established = response_.ok;
      }
      if (read_client_ == nullptr ||
          read_client_->GetReportingIntervals(minimum, maximum) != CHIP_NO_ERROR) {
        if (previously_established) {
          FailActive(InteractionError{"invalid_subscription_result"});
        } else {
          PublishFailure("invalid_subscription_result");
          ScheduleCancel();
        }
        return;
      }

      bool recovering = false;
      bool established = false;
      std::uint8_t attempt = 0;
      std::uint64_t generation = 0;
      std::vector<SubscriptionReport> reports;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        recovering = recovery_.recovering();
        established =
            buffer_.Establish(static_cast<std::uint32_t>(id), minimum, maximum);
        if (!established && !recovering) {
          response_.error_code = "invalid_subscription_result";
          published_ = true;
          resource_testing::Event("subscription_published");
          condition_.notify_one();
          ScheduleCancelLocked();
          return;
        }
        attempt = recovery_attempt_;
        generation = recovery_.generation();
        if (established && recovering) {
          buffer_.Activate();
          reports = buffer_.TakeReady();
        }
      }

      if (!established) {
        FailActive(InteractionError{"invalid_subscription_result"});
        return;
      }

      if (recovering) {
        CancelRecoveryTimer();
        SubscriptionStatus status{request_.subscription_id,
                                  generation,
                                  SubscriptionStatusKind::Resubscribed,
                                  SubscriptionContinuity::Unknown,
                                  attempt,
                                  minimum,
                                  maximum,
                                  static_cast<std::uint32_t>(id)};
        if (!owner_.EmitStatus(status)) {
          FailActive(InteractionError{"subscription_unavailable"});
          return;
        }
        {
          std::lock_guard<std::mutex> lock(mutex_);
          recovery_.Established();
        }
        (void)Emit(reports);
        return;
      }

      {
        std::lock_guard<std::mutex> lock(mutex_);
        response_ = {true, {}, request_.subscription_id, buffer_.generation(), minimum,
                     maximum, static_cast<std::uint32_t>(id)};
        published_ = true;
        resource_testing::Event("subscription_published");
      }
      condition_.notify_one();
    }

    CHIP_ERROR OnResubscriptionNeeded(chip::app::ReadClient *client,
                                      CHIP_ERROR termination) override {
      SubscriptionRecovery::Decision decision;
      bool prepared = true;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!response_.ok || cancelled_ || done_) {
          return CHIP_ERROR_CANCELLED;
        }
        decision = recovery_.Next(NowMs());
        if (decision.action == SubscriptionRecovery::Action::Retry &&
            decision.attempt == 1) {
          prepared = buffer_.PrepareRecovery(decision.generation);
        }
        recovery_attempt_ = decision.attempt;
      }
      if (!prepared ||
          decision.action != SubscriptionRecovery::Action::Retry) {
        FailActive(InteractionError{"session_lost"});
        return CHIP_ERROR_CANCELLED;
      }
      if (decision.attempt == 1 &&
          chip::DeviceLayer::SystemLayer().StartTimer(
              chip::System::Clock::Milliseconds32(decision.remaining_ms),
              RecoveryDeadline, this) != CHIP_NO_ERROR) {
        FailActive(InteractionError{"subscription_unavailable"});
        return CHIP_ERROR_CANCELLED;
      }
      if (!recovery_timer_active_) {
        resource_testing::Acquired(resource_testing::Object::RecoveryTimer);
      }
      recovery_timer_active_ = true;
      SubscriptionStatus status{request_.subscription_id,
                                decision.generation,
                                SubscriptionStatusKind::Resubscribing,
                                SubscriptionContinuity::Lost,
                                decision.attempt};
      if (!owner_.EmitStatus(status)) {
        FailActive(InteractionError{"subscription_unavailable"});
        return CHIP_ERROR_CANCELLED;
      }
      const std::uint32_t delay = std::min(
          client->ComputeTimeTillNextSubscription(), decision.remaining_ms - 1);
      return client->ScheduleResubscription(
          delay, chip::NullOptional, termination == CHIP_ERROR_TIMEOUT);
    }

    void OnError(CHIP_ERROR) override {
      FailActive(InteractionError{"session_lost"});
    }

    void OnDone(chip::app::ReadClient *) override {
      resource_testing::Event("subscription_read_done");
      CancelRecoveryTimer();
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

    bool Emit(const std::vector<SubscriptionReport> &reports) {
      for (const SubscriptionReport &report : reports) {
        if (!owner_.EmitReport(report)) {
          ScheduleCancel();
          return false;
        }
      }
      return true;
    }

    void FailActive(const InteractionError &error) {
      bool emit = false;
      std::uint64_t generation = 0;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (failure_emitted_) {
          return;
        }
        failure_emitted_ = true;
        buffer_.Cancel();
        if (response_.ok) {
          emit = true;
          generation = recovery_.generation();
        } else if (!published_) {
          response_.error_code = error.code;
          published_ = true;
          resource_testing::Event("subscription_published");
        }
      }
      condition_.notify_one();
      if (emit) {
        resource_testing::Event("subscription_terminal");
        owner_.EmitFailure(request_.subscription_id, generation, error);
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
        resource_testing::Event("subscription_published");
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

    static void RecoveryDeadline(chip::System::Layer *, void *context) {
      auto *self = static_cast<NativeSubscription *>(context);
      self->recovery_timer_active_ = false;
      resource_testing::Destroyed(resource_testing::Object::RecoveryTimer);
      self->FailActive(InteractionError{"session_lost"});
    }

    void CancelRecoveryTimer() {
      if (recovery_timer_active_) {
        chip::DeviceLayer::SystemLayer().CancelTimer(RecoveryDeadline, this);
        recovery_timer_active_ = false;
        resource_testing::Destroyed(resource_testing::Object::RecoveryTimer);
      }
    }

    static std::uint64_t NowMs() {
      return static_cast<std::uint64_t>(
          std::chrono::duration_cast<std::chrono::milliseconds>(
              std::chrono::steady_clock::now().time_since_epoch())
              .count());
    }

    std::uint32_t Remaining() const {
      const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - started_);
      return remaining_timeout_ms(request_.timeout_ms,
                                  static_cast<std::uint64_t>(elapsed.count()));
    }

#ifdef WOTEX_MATTER_RESOURCE_TESTING
    resource_testing::Lifetime resource_lifetime_{resource_testing::Object::Subscription};
#endif
    Impl &owner_;
    SubscriptionRequest request_;
    SubscriptionBuffer buffer_;
    SubscriptionRecovery recovery_;
    std::chrono::steady_clock::time_point started_;
    mutable std::mutex mutex_;
    std::condition_variable condition_;
    SubscriptionResponse response_;
    bool published_{false};
    bool cancelled_{false};
    bool failure_emitted_{false};
    bool cancel_scheduled_{false};
    bool done_{false};
    bool recovery_timer_active_{false};
    std::uint8_t recovery_attempt_{0};
    chip::Callback::Callback<chip::OnDeviceConnected> connected_;
    chip::Callback::Callback<chip::OnDeviceConnectionFailure> connection_failed_;
    resource_testing::Pointer<chip::app::ReadClient,
        resource_testing::Object::ReadClient> read_client_;
    std::vector<chip::app::AttributePathParams> attribute_paths_;
    std::vector<chip::app::EventPathParams> event_paths_;
  };

  static void StartPending(intptr_t context) {
    reinterpret_cast<Pending *>(context)->Start();
  }

  static void StartCommissioning(intptr_t context) {
    reinterpret_cast<PendingCommissioning *>(context)->Start();
  }

  static void StartWindow(intptr_t context) {
    reinterpret_cast<PendingWindow *>(context)->Start();
  }

  static void ReapPending(intptr_t context) {
    auto *pending = reinterpret_cast<Pending *>(context);
    auto &owner = pending->owner_;
    const auto node = pending->request_.node_id;
    owner.Reap(pending);
    owner.ReleaseUnusedSessionSetup(node);
  }

  static void ReapCommissioning(intptr_t context) {
    auto *pending = reinterpret_cast<PendingCommissioning *>(context);
    pending->owner_.Reap(pending);
  }

  static void ReapWindow(intptr_t context) {
    auto *pending = reinterpret_cast<PendingWindow *>(context);
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

  void Reap(PendingCommissioning *pending) {
    const auto node = pending->request_.node_id;
    {
      std::lock_guard<std::mutex> lock(control_mutex_);
      if (commissioning_ && commissioning_.get() == pending && pending->done()) {
        commissioning_.reset();
      }
    }
    ReleaseUnusedSessionSetup(node);
  }

  void Reap(PendingWindow *pending) {
    const auto node = pending->request_.node_id;
    {
      std::lock_guard<std::mutex> lock(control_mutex_);
      if (window_ && window_.get() == pending && pending->done()) {
        window_.reset();
      }
    }
    ReleaseUnusedSessionSetup(node);
  }

  void Reap(NativeSubscription *subscription) {
    const auto node = subscription->request_.node_id;
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      subscriptions_.erase(
          std::remove_if(
              subscriptions_.begin(), subscriptions_.end(),
              [subscription](const std::shared_ptr<NativeSubscription> &candidate) {
                return candidate.get() == subscription && candidate->done();
              }),
          subscriptions_.end());
    }
    ReleaseUnusedSessionSetup(node);
  }

  void ReleaseUnusedSessionSetup(chip::NodeId node) {
    // ReadClient destruction detaches its callbacks but the shared CASE setup
    // can retain address-resolution or retry timers. Release that setup only
    // after every local operation and subscription for the peer has completed.
    // This SDK-thread call does not evict established secure sessions.
    {
      std::scoped_lock lock(pending_mutex_, control_mutex_, subscription_mutex_);
      const auto active = [node](const auto &context) {
        return context && context->request_.node_id == node && !context->done();
      };
      if (std::any_of(pending_.begin(), pending_.end(), active) ||
          active(commissioning_) || active(window_) ||
          std::any_of(subscriptions_.begin(), subscriptions_.end(), active)) {
        return;
      }
    }
    if (auto *manager = commissioner_.CASESessionMgr(); manager != nullptr) {
      manager->ReleaseSession(commissioner_.GetPeerScopedId(node));
    }
  }

  bool EmitReport(const SubscriptionReport &report) {
    ControllerBackend::ReportSink sink;
    {
      std::lock_guard<std::mutex> lock(sink_mutex_);
      sink = report_sink_;
    }
    return sink && sink(report);
  }

  bool EmitStatus(const SubscriptionStatus &status) {
    ControllerBackend::StatusSink sink;
    {
      std::lock_guard<std::mutex> lock(sink_mutex_);
      sink = status_sink_;
    }
    return sink && sink(status);
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

  enum class Action {
    None,
    Setup,
    Shutdown,
#ifdef WOTEX_MATTER_RESOURCE_TESTING
    ObserveResources,
#endif
  };

  static void Work(intptr_t context) {
    auto *self = reinterpret_cast<Impl *>(context);
    const Action action = self->action_;
    CHIP_ERROR error = CHIP_ERROR_INCORRECT_STATE;
    if (action == Action::Setup) {
      error = self->SetupOnSdkThread();
#ifdef WOTEX_MATTER_RESOURCE_TESTING
    } else if (action == Action::ObserveResources) {
      self->resource_snapshot_ = resource_testing::SnapshotJson();
      error = CHIP_NO_ERROR;
#endif
    } else if (action == Action::Shutdown) {
      std::vector<std::shared_ptr<Pending>> pending;
      std::vector<std::shared_ptr<NativeSubscription>> subscriptions;
      std::shared_ptr<PendingCommissioning> commissioning;
      std::shared_ptr<PendingWindow> window;
      {
        std::lock_guard<std::mutex> lock(self->pending_mutex_);
        pending = self->pending_;
      }
      {
        std::lock_guard<std::mutex> lock(self->subscription_mutex_);
        subscriptions = self->subscriptions_;
      }
      {
        std::lock_guard<std::mutex> lock(self->control_mutex_);
        commissioning = self->commissioning_;
        window = self->window_;
      }
      for (const auto &subscription : subscriptions) {
        subscription->CancelOnSdkThread();
      }
      for (const auto &interaction : pending) {
        interaction->AbortOnSdkThread();
      }
      if (commissioning) {
        commissioning->AbortOnSdkThread();
      }
      if (window) {
        window->AbortOnSdkThread();
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
    setup.pairingDelegate = this;
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
    if (factory_initialized_) {
      auto *system = chip::Controller::DeviceControllerFactory::GetInstance()
                         .GetSystemState();
      if (system != nullptr) {
        // The pinned factory deletes these handlers without unregistering
        // their exchange slots. No SDK callback can run after the loop stops.
        if (system->MessageCounterManager() != nullptr) {
          system->MessageCounterManager()->Shutdown();
        }
        if (system->ExchangeMgr() != nullptr) {
          (void) system->ExchangeMgr()->UnregisterUnsolicitedMessageHandlerForType(
              chip::Protocols::SecureChannel::MsgType::StatusReport);
        }
      }
    }
    {
      std::lock_guard<std::mutex> lock(pending_mutex_);
      pending_.clear();
    }
    {
      std::lock_guard<std::mutex> lock(subscription_mutex_);
      subscriptions_.clear();
    }
    {
      std::lock_guard<std::mutex> lock(control_mutex_);
      commissioning_.reset();
      window_.reset();
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
#ifdef WOTEX_MATTER_RESOURCE_TESTING
  std::string resource_snapshot_;
#endif
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
  std::mutex control_mutex_;
  std::shared_ptr<PendingCommissioning> commissioning_;
  std::shared_ptr<PendingWindow> window_;
  std::mutex subscription_mutex_;
  std::vector<std::shared_ptr<NativeSubscription>> subscriptions_;
  std::mutex sink_mutex_;
  std::function<bool()> control_pump_;
  std::thread::id control_thread_;
  std::optional<std::chrono::steady_clock::time_point> control_deadline_;
  ControllerBackend::ReportSink report_sink_;
  ControllerBackend::StatusSink status_sink_;
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
    // A completed context still owns a queued SDK reaper callback. Only that
    // callback may release its entry before the event loop has stopped.
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

CommissioningResponse SdkControllerBackend::Impl::Commission(
    const CommissioningRequest &request) {
  if (!open_ || !valid_commissioning_request(request)) {
    return {false,
            CommissioningError{"invalid_request", std::nullopt,
                               InteractionEffect::None},
            0, 0, false};
  }

  std::shared_ptr<PendingCommissioning> pending;
  {
    std::lock_guard<std::mutex> lock(control_mutex_);
    if (!accepting_interactions_ || commissioning_ || window_) {
      return {false,
              CommissioningError{"commissioning_busy", std::nullopt,
                                 InteractionEffect::None},
              0, 0, false};
    }
    {
      std::lock_guard<std::mutex> pending_lock(pending_mutex_);
      if (pending_.size() >= 64U) {
        return {false,
                CommissioningError{"commissioning_busy", std::nullopt,
                                   InteractionEffect::None},
                0, 0, false};
      }
    }
    pending = std::make_shared<PendingCommissioning>(*this, request);
    commissioning_ = pending;
  }

  CHIP_ERROR error = chip::DeviceLayer::PlatformMgr().ScheduleWork(
      StartCommissioning, reinterpret_cast<intptr_t>(pending.get()));
  if (error != CHIP_NO_ERROR) {
    pending->Publish({false,
                      CommissioningError{
                          "commissioning_unavailable",
                          static_cast<std::uint32_t>(error.AsInteger()),
                          InteractionEffect::None},
                      0, 0, false});
    pending->MarkDone();
  }
  return pending->Wait();
}

CommissioningWindowResponse SdkControllerBackend::Impl::OpenWindow(
    const CommissioningWindowRequest &request) {
  if (!open_ || !valid_commissioning_window_request(request)) {
    return {false,
            CommissioningError{"invalid_request", std::nullopt,
                               InteractionEffect::None},
            0, 0, 0, 0, {}, {}};
  }

  std::shared_ptr<PendingWindow> pending;
  {
    std::lock_guard<std::mutex> lock(control_mutex_);
    if (!accepting_interactions_ || commissioning_ || window_) {
      return {false,
              CommissioningError{"window_busy", std::nullopt,
                                 InteractionEffect::None},
              0, 0, 0, 0, {}, {}};
    }
    {
      std::lock_guard<std::mutex> pending_lock(pending_mutex_);
      if (pending_.size() >= 64U) {
        return {false,
                CommissioningError{"window_busy", std::nullopt,
                                   InteractionEffect::None},
                0, 0, 0, 0, {}, {}};
      }
    }
    pending = std::make_shared<PendingWindow>(*this, request);
    window_ = pending;
  }

  CHIP_ERROR error = chip::DeviceLayer::PlatformMgr().ScheduleWork(
      StartWindow, reinterpret_cast<intptr_t>(pending.get()));
  if (error != CHIP_NO_ERROR) {
    pending->Publish({false,
                      CommissioningError{
                          "window_unavailable",
                          static_cast<std::uint32_t>(error.AsInteger()),
                          InteractionEffect::None},
                      0, 0, 0, 0, {}, {}});
    pending->MarkDone();
  }
  return pending->Wait();
}

void SdkControllerBackend::Impl::OnCommissioningComplete(
    chip::NodeId device_id, CHIP_ERROR error) {
  std::shared_ptr<PendingCommissioning> pending;
  {
    std::lock_guard<std::mutex> lock(control_mutex_);
    pending = commissioning_;
  }
  if (pending) {
    pending->CommissioningComplete(device_id, error);
  }
}

void SdkControllerBackend::Impl::OnCommissioningFailure(
    chip::PeerId, const chip::Controller::CompletionStatus &status) {
  std::shared_ptr<PendingCommissioning> pending;
  {
    std::lock_guard<std::mutex> lock(control_mutex_);
    pending = commissioning_;
  }
  if (pending) {
    pending->RecordFailure(status);
  }
}

void SdkControllerBackend::Impl::OnCommissioningStageStart(
    chip::PeerId, chip::Controller::CommissioningStage stage) {
  std::shared_ptr<PendingCommissioning> pending;
  {
    std::lock_guard<std::mutex> lock(control_mutex_);
    pending = commissioning_;
  }
  if (pending) {
    pending->StageStarted(stage);
  }
}

SubscriptionResponse SdkControllerBackend::Impl::Subscribe(
    const SubscriptionRequest &request) {
  if (!open_ || !valid_subscription_request(request)) {
    SubscriptionResponse invalid;
    invalid.error_code = "invalid_request";
    return invalid;
  }

  std::shared_ptr<NativeSubscription> subscription;
  {
    std::lock_guard<std::mutex> lock(subscription_mutex_);
    // ReapSubscription retains ownership through its scheduled SDK callback.
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

SdkControllerBackend::~SdkControllerBackend() { impl_->Close(); }

BackendResult SdkControllerBackend::Open(const NativeOpenOptions &options) {
  return impl_->Open(options);
}

InteractionResponse SdkControllerBackend::Interact(
    const InteractionRequest &request) {
  return impl_->Interact(request);
}

CommissioningResponse SdkControllerBackend::Commission(
    const CommissioningRequest &request) {
  return impl_->Commission(request);
}

CommissioningWindowResponse SdkControllerBackend::OpenWindow(
    const CommissioningWindowRequest &request) {
  return impl_->OpenWindow(request);
}

void SdkControllerBackend::SetSubscriptionSinks(ReportSink report,
                                                StatusSink status,
                                                FailureSink failure) {
  impl_->SetSubscriptionSinks(std::move(report), std::move(status),
                              std::move(failure));
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

void SdkControllerBackend::SetControlPump(std::function<bool()> pump) {
  impl_->SetControlPump(std::move(pump));
}

void SdkControllerBackend::Close() { impl_->Close(); }

bool SdkControllerBackend::IsOpen() const { return impl_->IsOpen(); }

#ifdef WOTEX_MATTER_RESOURCE_TESTING
std::string SdkControllerBackend::ResourceSnapshotForTesting() {
  return impl_->ResourceSnapshotForTesting();
}
#endif

} // namespace wotex::matter
