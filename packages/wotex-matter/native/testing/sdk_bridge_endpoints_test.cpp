#include "sdk_bridge_endpoints_test.hpp"

#include <app/AttributeValueEncoder.h>
#include <app/MessageDef/AttributeDataIB.h>
#include <app/MessageDef/AttributeReportIB.h>
#include <app/SafeAttributePersistenceProvider.h>
#include <app/persistence/AttributePersistenceProviderInstance.h>
#include <app/util/attribute-storage.h>
#include <credentials/GroupDataProvider.h>
#include <data-model-providers/codegen/CodegenDataModelProvider.h>

#include <algorithm>
#include <array>
#include <iostream>
#include <set>
#include <stdexcept>
#include <sys/stat.h>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error Endpoint lifecycle tests require the explicit test build.
#endif

namespace wotex::matter::testing {
namespace {
using namespace chip;
using namespace chip::app;

void Require(bool condition, const char *stage) {
  if (!condition) {
    std::cerr << "endpoint test failed: " << stage << '\n';
    throw std::runtime_error(stage);
  }
}

void Check(CHIP_ERROR error, const char *stage) { Require(error == CHIP_NO_ERROR, stage); }

template <typename Decoder>
void ReadAttribute(DataModel::Provider &model, EndpointId endpoint, ClusterId cluster,
                   AttributeId attribute, Decoder decode) {
  uint8_t bytes[512];
  TLV::TLVWriter writer;
  writer.Init(bytes);
  AttributeReportIBs::Builder reports;
  Check(reports.Init(&writer), "attribute report setup");
  Access::SubjectDescriptor subject;
  const ConcreteAttributePath path(endpoint, cluster, attribute);
  AttributeValueEncoder encoder(reports, subject, path, 0);
  DataModel::ReadAttributeRequest request(path, subject);
  Require(model.ReadAttribute(request, encoder).IsSuccess(), "cluster revision read");
  Check(reports.EndOfAttributeReportIBs(), "attribute report end");
  Check(writer.Finalize(), "attribute report finalized");
  TLV::TLVReader reader;
  reader.Init(bytes, writer.GetLengthWritten());
  Check(reader.Next(TLV::kTLVType_Array, TLV::AnonymousTag()), "attribute reports array");
  TLV::TLVType outer;
  Check(reader.EnterContainer(outer), "attribute reports enter");
  Check(reader.Next(TLV::kTLVType_Structure, TLV::AnonymousTag()), "attribute report entry");
  AttributeReportIB::Parser report;
  Check(report.Init(reader), "attribute report parser");
  AttributeDataIB::Parser data;
  Check(report.GetAttributeData(&data), "attribute data parser");
  TLV::TLVReader value;
  Check(data.GetData(&value), "attribute value parser");
  decode(value);
}

uint16_t ReadRevision(DataModel::Provider &model, EndpointId endpoint, ClusterId cluster) {
  uint16_t revision = 0;
  ReadAttribute(model, endpoint, cluster, 0xFFFD, [&](TLV::TLVReader &value) {
    Check(value.Get(revision), "attribute revision integer");
  });
  return revision;
}

std::vector<EndpointId> ReadParts(DataModel::Provider &model, EndpointId endpoint) {
  std::vector<EndpointId> parts;
  ReadAttribute(model, endpoint, 0x001D, 3, [&](TLV::TLVReader &value) {
    Require(value.GetType() == TLV::kTLVType_Array, "parts list array value");
    TLV::TLVType outer;
    Check(value.EnterContainer(outer), "parts list enter");
    CHIP_ERROR next;
    while ((next = value.Next()) == CHIP_NO_ERROR) {
      EndpointId child = kInvalidEndpointId;
      Check(value.Get(child), "parts list endpoint value");
      parts.push_back(child);
    }
    Require(next == CHIP_END_OF_TLV, "parts list end");
    Check(value.ExitContainer(outer), "parts list exit");
  });
  std::sort(parts.begin(), parts.end());
  return parts;
}

void CheckCommands(DataModel::Provider &model, EndpointId endpoint, ClusterId cluster,
                   std::vector<CommandId> expected_in, std::vector<CommandId> expected_out) {
  ReadOnlyBufferBuilder<DataModel::AcceptedCommandEntry> accepted;
  Check(model.AcceptedCommands({endpoint, cluster}, accepted), "accepted command enumeration");
  std::vector<CommandId> actual_in;
  for (const auto &entry : accepted.TakeBuffer()) actual_in.push_back(entry.commandId);
  std::sort(actual_in.begin(), actual_in.end());
  std::sort(expected_in.begin(), expected_in.end());
  Require(actual_in == expected_in, "exact accepted command set");
  ReadOnlyBufferBuilder<CommandId> generated;
  Check(model.GeneratedCommands({endpoint, cluster}, generated), "generated command enumeration");
  std::vector<CommandId> actual_out;
  for (CommandId id : generated.TakeBuffer()) actual_out.push_back(id);
  std::sort(actual_out.begin(), actual_out.end());
  std::sort(expected_out.begin(), expected_out.end());
  Require(actual_out == expected_out, "exact generated command set");
}

BridgeDeviceConfiguration Configuration(std::size_t index) {
  BridgeDeviceConfiguration configuration;
  configuration.thing_id = "child-" + std::to_string(index);
  if (index == 14) configuration.thing_id = std::string(256, '\0');
  configuration.node_label = "Child " + std::to_string(index);
  configuration.device_type = index % 2 == 0 ? BridgedDeviceType::OnOffLight
                                             : BridgedDeviceType::TemperatureSensor;
  if (index % 2 != 0) {
    configuration.minimum_temperature = -4000;
    configuration.maximum_temperature = 12500;
    if (index == 5 || index == 15) configuration.minimum_temperature.reset();
    if (index == 7 || index == 15) configuration.maximum_temperature.reset();
  }
  if (index == 0) configuration.node_label = std::string(28, 'x') + "\xF0\x9F\x92\xA1";
  return configuration;
}

std::string ReadUnique(DataModel::Provider &model, EndpointId endpoint) {
  std::string unique;
  ReadAttribute(model, endpoint, 0x0039, 0x0012, [&](TLV::TLVReader &value) {
    CharSpan bytes;
    Check(value.Get(bytes), "unique identifier string");
    unique.assign(bytes.data(), bytes.size());
  });
  return unique;
}

template <typename Value>
Value ReadValue(DataModel::Provider &model, EndpointId endpoint, ClusterId cluster,
                AttributeId attribute) {
  Value result{};
  ReadAttribute(model, endpoint, cluster, attribute,
                [&](TLV::TLVReader &value) { Check(value.Get(result), "attribute value decode"); });
  return result;
}

void ReadNull(DataModel::Provider &model, EndpointId endpoint, ClusterId cluster,
              AttributeId attribute) {
  ReadAttribute(model, endpoint, cluster, attribute, [&](TLV::TLVReader &value) {
    Require(value.GetType() == TLV::kTLVType_Null, "explicit unavailable value");
  });
}

void CheckRejectedConfigurations(SdkBridgeEndpointBinding &owner) {
  BridgeEndpoint output{777, BridgedDeviceType::OnOffLight};
  const auto refuse = [&](const BridgeDeviceConfiguration &configuration) {
    Require(owner.Add(configuration, output) == CHIP_ERROR_INVALID_ARGUMENT &&
                output.endpoint == 777 && output.device_type == BridgedDeviceType::OnOffLight,
            "invalid configuration preserves output");
  };
  auto value = Configuration(0);
  value.thing_id.clear();
  refuse(value);
  value.thing_id = std::string(257, 'x');
  refuse(value);
  value = Configuration(0);
  value.node_label = std::string(33, 'x');
  refuse(value);
  value.node_label = std::string(1, static_cast<char>(0xFF));
  refuse(value);
  value = Configuration(0);
  value.minimum_temperature = 0;
  refuse(value);
  value = Configuration(1);
  value.minimum_temperature = -27316;
  refuse(value);
  value.minimum_temperature = 32767;
  refuse(value);
  value.minimum_temperature = -4000;
  value.maximum_temperature = -4000;
  refuse(value);
  value.maximum_temperature = -27315;
  refuse(value);
  value = Configuration(0);
  // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): the fixed uint16_t underlying type permits this non-enumerator value; it exercises invalid Device Type admission.
  value.device_type = static_cast<BridgedDeviceType>(0xFFFF);
  refuse(value);
  value = Configuration(0);
  value.node_label = "changed capability";
  refuse(value);
}

void CheckChild(DataModel::Provider &model, SdkBridgeEndpointBinding &owner,
                const BridgeDeviceConfiguration &configuration, BridgeEndpoint endpoint) {
  const bool light = endpoint.device_type == BridgedDeviceType::OnOffLight;
  ReadOnlyBufferBuilder<DataModel::ServerClusterEntry> clusters;
  Check(model.ServerClusters(endpoint.endpoint, clusters), "child clusters");
  std::vector<ClusterId> actual;
  for (const auto &entry : clusters.TakeBuffer()) actual.push_back(entry.clusterId);
  std::sort(actual.begin(), actual.end());
  Require(actual ==
              (light ? std::vector<ClusterId>{3, 4, 6, 29, 57, 98}
                     : std::vector<ClusterId>{3, 29, 57, 1026}),
          "complete selected cluster set");
  ReadOnlyBufferBuilder<DataModel::DeviceTypeEntry> types;
  Check(model.DeviceTypes(endpoint.endpoint, types), "child device types");
  const auto values = types.TakeBuffer();
  Require(values.size() == 2 && values[0].deviceTypeId == 0x0013 &&
              values[0].deviceTypeRevision == 3 &&
              values[1].deviceTypeId == (light ? 0x0100U : 0x0302U) &&
              values[1].deviceTypeRevision == 3,
          "selected child device type revisions");
  Require(ReadRevision(model, endpoint.endpoint, 0x001D) == 3 &&
              ReadRevision(model, endpoint.endpoint, 0x0039) == 6 &&
              ReadRevision(model, endpoint.endpoint, 0x0003) == 6,
          "common cluster revisions");
  Require(ReadParts(model, endpoint.endpoint).empty(), "leaf parts list");
  CheckCommands(model, endpoint.endpoint, 3,
                light ? std::vector<CommandId>{0, 64} : std::vector<CommandId>{0}, {});
  Require(!ReadValue<bool>(model, endpoint.endpoint, 57, 17),
          "child reachability initially unknown");
  if (light) {
    Require(ReadRevision(model, endpoint.endpoint, 4) == 4 &&
                ReadRevision(model, endpoint.endpoint, 6) == 6 &&
                ReadRevision(model, endpoint.endpoint, 98) == 1,
            "light cluster revisions");
    CheckCommands(model, endpoint.endpoint, 4, {0, 1, 2, 3, 4, 5}, {0, 1, 2, 3});
    CheckCommands(model, endpoint.endpoint, 6, {0, 1, 2, 64, 65, 66}, {});
    CheckCommands(model, endpoint.endpoint, 98, {0, 1, 2, 3, 4, 5, 6, 64}, {0, 1, 2, 3, 4, 6, 64});
    Check(owner.Observe(configuration.thing_id, endpoint.endpoint, {true, false, std::nullopt}),
          "approved light observation");
    Require(!ReadValue<bool>(model, endpoint.endpoint, 6, 0), "approved light false value");
    Check(owner.Observe(configuration.thing_id, endpoint.endpoint, {false, true, std::nullopt}),
          "approved light state and reachability");
    Require(ReadValue<bool>(model, endpoint.endpoint, 6, 0) &&
                !ReadValue<bool>(model, endpoint.endpoint, 57, 17),
            "state does not imply reachability");
    Require(owner.Observe(configuration.thing_id, endpoint.endpoint, {true, false, 1200}) ==
                    CHIP_ERROR_INVALID_ARGUMENT &&
                ReadValue<bool>(model, endpoint.endpoint, 6, 0),
            "wrong light observation preserves approved state");
    Check(owner.Observe(configuration.thing_id, endpoint.endpoint, {}), "unavailable light");
    EmberAfAttributeMetadata attribute{EmberAfDefaultOrMinMaxAttributeValue(uint32_t{0})};
    attribute.attributeId = 0;
    std::uint8_t buffer = 0xA5;
    Require(SdkBridgeEndpointBinding::ReadExternal(endpoint.endpoint, 6, &attribute, &buffer, 1) ==
                    Protocols::InteractionModel::Status::Failure &&
                buffer == 0xA5,
            "missing light observation is unavailable");
  } else {
    Require(ReadRevision(model, endpoint.endpoint, 1026) == 6, "temperature revision six");
    ReadNull(model, endpoint.endpoint, 1026, 0);
    if (configuration.minimum_temperature) {
      Require(ReadValue<int16_t>(model, endpoint.endpoint, 1026, 1) ==
                  *configuration.minimum_temperature,
              "fixed minimum bound");
    } else {
      ReadNull(model, endpoint.endpoint, 1026, 1);
    }
    if (configuration.maximum_temperature) {
      Require(ReadValue<int16_t>(model, endpoint.endpoint, 1026, 2) ==
                  *configuration.maximum_temperature,
              "fixed maximum bound");
    } else {
      ReadNull(model, endpoint.endpoint, 1026, 2);
    }
    Check(owner.Observe(configuration.thing_id, endpoint.endpoint, {true, std::nullopt, 1200}),
          "approved temperature");
    Require(ReadValue<int16_t>(model, endpoint.endpoint, 1026, 0) == 1200 &&
                ReadValue<bool>(model, endpoint.endpoint, 57, 17),
            "exact approved temperature and reachability");
    std::vector<int16_t> invalid_values{-27316};
    if (configuration.minimum_temperature) invalid_values.push_back(-4001);
    if (configuration.maximum_temperature) invalid_values.push_back(12501);
    for (const int16_t invalid : invalid_values) {
      Require(owner.Observe(configuration.thing_id, endpoint.endpoint,
                            {false, std::nullopt, invalid}) != CHIP_NO_ERROR &&
                  ReadValue<int16_t>(model, endpoint.endpoint, 1026, 0) == 1200 &&
                  ReadValue<bool>(model, endpoint.endpoint, 57, 17),
              "invalid temperature preserves both approved fields");
    }
    Require(owner.Observe(configuration.thing_id, endpoint.endpoint, {false, false, 1500}) ==
                CHIP_ERROR_INVALID_ARGUMENT,
            "sensor rejects On/Off observation");
    Check(owner.Observe(configuration.thing_id, endpoint.endpoint, {}), "unavailable temperature");
    ReadNull(model, endpoint.endpoint, 1026, 0);
    Check(owner.Observe(configuration.thing_id, endpoint.endpoint, {true, std::nullopt, 1200}),
          "volatile measurement before restart");
  }
}

} // namespace

std::unique_ptr<SdkBridgeEndpointBinding> PrepareEndpoints(SdkBridgeServerBinding &server,
                                                           const std::string &mode) {
  auto owner = std::make_unique<SdkBridgeEndpointBinding>(server);
  auto &model = CodegenDataModelProvider::Instance();
  std::vector<BridgeDeviceConfiguration> configurations;
  if (mode == "endpoints_reopen") {
    for (std::size_t index = 0; index < 16; ++index) configurations.push_back(Configuration(index));
    Require(owner->Init({}) == CHIP_ERROR_INVALID_ARGUMENT, "restore requires every live Thing");
    auto wrong = configurations;
    wrong[0].device_type = BridgedDeviceType::TemperatureSensor;
    Require(owner->Init(wrong) == CHIP_ERROR_INVALID_ARGUMENT, "restore cannot rebind Device Type");
    wrong = configurations;
    wrong[1] = wrong[0];
    Require(owner->Init(wrong) == CHIP_ERROR_INVALID_ARGUMENT, "duplicate restore refused");
    wrong = configurations;
    wrong[0].node_label = std::string(1, static_cast<char>(0xFF));
    Require(owner->Init(wrong) == CHIP_ERROR_INVALID_ARGUMENT, "invalid restore label refused");
    std::reverse(configurations.begin(), configurations.end());
  }
  Check(owner->Init(configurations), "endpoint owner initialization");
  Require(owner->initialized() && owner->Init(configurations) == CHIP_ERROR_INCORRECT_STATE,
          "single endpoint lifetime");
  SdkBridgeEndpointBinding competing(server);
  Require(competing.Init(configurations) == CHIP_ERROR_INCORRECT_STATE, "competing owner refused");
  std::set<std::string> unique_ids;
  std::vector<EndpointId> expected_parts;
  for (std::size_t index = 0; index < 16; ++index) {
    const auto configuration = Configuration(index);
    BridgeEndpoint endpoint;
    Check(owner->Add(configuration, endpoint), "admitted child add or restore");
    Require(endpoint.endpoint == (mode == "endpoints_reopen" && index == 0 ? 19 : index + 3),
            "stable durable identity independent of SDK slot");
    CheckChild(model, *owner, configuration, endpoint);
    const auto unique = ReadUnique(model, endpoint.endpoint);
    Require(unique.size() == 32 && unique_ids.insert(unique).second,
            "distinct bounded identifiers");
    expected_parts.push_back(endpoint.endpoint);
  }
  CheckRejectedConfigurations(*owner);
  BridgeEndpoint refused{777, BridgedDeviceType::OnOffLight};
  Require(owner->Add(Configuration(16), refused) == CHIP_ERROR_ENDPOINT_POOL_FULL &&
              refused.endpoint == 777,
          "seventeenth child preserves output");
  Require(owner->Remove("absent") == CHIP_ERROR_NOT_FOUND &&
              owner->Observe("absent", 3, {}) == CHIP_ERROR_NOT_FOUND,
          "unadmitted Thing refused");
  Require(owner->Observe("child-1", 3, {}) == CHIP_ERROR_NOT_FOUND,
          "Thing and endpoint pair required");
  EmberAfAttributeMetadata feature{EmberAfDefaultOrMinMaxAttributeValue(uint32_t{0})};
  feature.attributeId = 0xFFFC;
  std::array<uint8_t, 4> feature_bytes{0xA5, 0xA5, 0xA5, 0xA5};
  Require(SdkBridgeEndpointBinding::ReadExternal(4, 1026, &feature, feature_bytes.data(), 3) ==
                  Protocols::InteractionModel::Status::ResourceExhausted &&
              feature_bytes == std::array<uint8_t, 4>{0xA5, 0xA5, 0xA5, 0xA5},
          "undersized attribute output preserved");
  Require(SdkBridgeEndpointBinding::ReadExternal(4, 6, &feature, feature_bytes.data(), 4) ==
                  Protocols::InteractionModel::Status::UnsupportedCluster &&
              SdkBridgeEndpointBinding::ReadExternal(2, 1026, &feature, feature_bytes.data(), 4) ==
                  Protocols::InteractionModel::Status::UnsupportedEndpoint &&
              SdkBridgeEndpointBinding::ReadExternal(4, 1026, nullptr, feature_bytes.data(), 4) ==
                  Protocols::InteractionModel::Status::UnsupportedAttribute &&
              SdkBridgeEndpointBinding::ReadExternal(4, 1026, &feature, nullptr, 4) ==
                  Protocols::InteractionModel::Status::UnsupportedAttribute,
          "callback refuses unadmitted paths and malformed storage");
  std::sort(expected_parts.begin(), expected_parts.end());
  Require(ReadParts(model, 1) == expected_parts, "aggregator exposes all children");
  expected_parts.insert(expected_parts.begin(), 1);
  Require(ReadParts(model, 0) == expected_parts, "root exposes aggregator and children");
  auto *groups = Credentials::GetGroupDataProvider();
  Require(groups != nullptr, "explicit group custody");
  const auto unique = ReadUnique(model, mode == "endpoints_reopen" ? 19 : 3);
  if (mode == "endpoints_reopen") {
    std::array<uint8_t, 32> bytes{};
    uint16_t size = bytes.size();
    Check(server.storage_delegate().SyncGetKeyValue("test.unique", bytes.data(), size),
          "saved unique identifier");
    Require(size == unique.size() && std::equal(bytes.begin(), bytes.end(), unique.begin()),
            "unique identifier stable across restart");
    bool retired = false;
    Check(server.bridge_storage().Retired(3, retired), "retired identity lookup");
    Require(retired && groups->HasEndpoint(1, 7, 5) && groups->HasEndpoint(2, 7, 5) &&
                groups->HasEndpoint(1, 7, 19) && !groups->HasEndpoint(2, 7, 19) &&
                !groups->HasEndpoint(1, 7, 3) && !groups->HasEndpoint(2, 7, 3),
            "retirement and fabric-scoped groups restored");
  } else {
    // Directly seed SDK custody, without commissioning operational fabrics or
    // claiming authenticated command admission.
    for (FabricIndex fabric : {1, 2}) {
      Check(groups->SetGroupInfo(fabric, Credentials::GroupDataProvider::GroupInfo(7, "")),
            "group seed");
      Check(groups->AddEndpoint(fabric, 7, 3), "retired child group seed");
      Check(groups->AddEndpoint(fabric, 7, 5), "retained child group seed");
    }
    const uint8_t saved = 1;
    Check(GetAttributePersistenceProvider()->WriteValue({3, 57, 5}, ByteSpan(&saved, 1)),
          "node label persistence seed");
    Check(GetSafeAttributePersistenceProvider()->SafeWriteValue({3, 6, 0}, ByteSpan(&saved, 1)),
          "safe attribute persistence seed");
    Check(owner->Remove("child-0"), "durable child removal and SDK cleanup");
    Require(!groups->HasEndpoint(1, 7, 3) && !groups->HasEndpoint(2, 7, 3),
            "removed endpoint pruned from every fabric");
    uint8_t bytes = 0;
    MutableByteSpan span(&bytes, 1);
    Require(GetAttributePersistenceProvider()->ReadValue({3, 57, 5}, span) ==
                CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND,
            "removed node label persistence retired");
    span = MutableByteSpan(&bytes, 1);
    Require(GetSafeAttributePersistenceProvider()->SafeReadValue({3, 6, 0}, span) ==
                CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND,
            "removed safe persistence retired");
    BridgeEndpoint replacement;
    Check(owner->Add(Configuration(0), replacement), "re-add retired Thing");
    Require(replacement.endpoint == 19 && ReadUnique(model, 19) == unique,
            "new endpoint preserves opaque Thing identifier");
    Require(owner->Observe("child-0", 3, {true, true, std::nullopt}) == CHIP_ERROR_NOT_FOUND,
            "stale observation cannot target replacement");
    Check(groups->AddEndpoint(1, 7, 19), "replacement membership fabric scope");
    Check(server.storage_delegate().SyncSetKeyValue("test.unique", unique.data(),
                                                    static_cast<uint16_t>(unique.size())),
          "unique identifier persistence test");
  }
  std::cout << "bridge endpoint metadata, custody and observations passed\n" << std::flush;
  return owner;
}

CHIP_ERROR ObserveDuringLoop(SdkBridgeEndpointBinding &endpoints) {
  return endpoints.Observe("child-1", 4, {true, std::nullopt, 1500});
}

void PoisonEndpoints(SdkBridgeEndpointBinding &endpoints, const std::string &mode) {
  if (mode == "endpoints_poison_add") {
    Check(endpoints.Remove("child-15"), "free endpoint before failed add commit");
  }
  Require(mkdir("store.tmp", 0700) == 0, "endpoint failed commit fixture");
  if (mode == "endpoints_poison_add") {
    BridgeEndpoint endpoint;
    (void)endpoints.Add(Configuration(16), endpoint);
  } else {
    (void)endpoints.Remove("child-1");
  }
  throw std::runtime_error("poisoned endpoint owner continued");
}

void FinishEndpoints(SdkBridgeEndpointBinding &endpoints, SdkBridgeServerBinding &server) {
  auto &model = CodegenDataModelProvider::Instance();
  Require(ReadValue<int16_t>(model, 4, 1026, 0) == 1500, "event loop observation delivered");
  endpoints.Finish();
  endpoints.Finish();
  Require(!endpoints.initialized(), "endpoint owner retired");
  BridgeEndpoint output{777, BridgedDeviceType::OnOffLight};
  Require(endpoints.Add(Configuration(16), output) == CHIP_ERROR_INCORRECT_STATE &&
              output.endpoint == 777 && endpoints.Remove("child-1") == CHIP_ERROR_INCORRECT_STATE &&
              endpoints.Observe("child-1", 4, {}) == CHIP_ERROR_INCORRECT_STATE &&
              endpoints.Init({}) == CHIP_ERROR_INCORRECT_STATE,
          "closed endpoint lifetime refuses further service");
  std::map<std::string, BridgeEndpoint> persisted;
  Check(server.bridge_storage().Endpoints(persisted), "custody retained on shutdown");
  for (const auto &[thing, endpoint] : persisted) {
    (void)thing;
    auto clusters = model.Registry().ClustersOnEndpoint(endpoint.endpoint);
    Require(clusters.begin() == clusters.end(), "all child SDK registrations retired");
  }
  Require(ReadParts(model, 1).empty() && ReadParts(model, 0) == std::vector<EndpointId>{1},
          "shutdown retires descriptor parts");
  auto *groups = Credentials::GetGroupDataProvider();
  Require(
      groups->HasEndpoint(1, 7, 5) && groups->HasEndpoint(2, 7, 5) && groups->HasEndpoint(1, 7, 19),
      "normal shutdown preserves group custody");
  EmberAfAttributeMetadata attribute{EmberAfDefaultOrMinMaxAttributeValue(uint32_t{0})};
  attribute.attributeId = 0;
  uint8_t byte = 0xA5;
  Require(SdkBridgeEndpointBinding::ReadExternal(4, 1026, &attribute, &byte, 1) ==
                  Protocols::InteractionModel::Status::UnsupportedAttribute &&
              byte == 0xA5,
          "callback refuses after owner retirement");
  std::cout << "bridge endpoint event loop and shutdown passed\n";
}

} // namespace wotex::matter::testing
