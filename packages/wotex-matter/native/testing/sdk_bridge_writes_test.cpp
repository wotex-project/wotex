#include "sdk_bridge_writes_test.hpp"
#include "wotex_matter/bridge_writes.hpp"

#include <lib/core/TLVWriter.h>

#include <algorithm>
#include <array>
#include <iostream>
#include <stdexcept>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error This standalone probe requires an explicit test build.
#endif

namespace wotex::matter::testing {
namespace {

using Handoff = BridgeConsumerHandoff;
using List = chip::app::ConcreteDataAttributePath::ListOperation;

void Require(bool value, const char *stage) {
  if (!value) throw std::runtime_error(stage);
}

BridgeRequestMetadata Metadata(chip::ClusterId cluster, std::uint32_t member) {
  chip::Access::SubjectDescriptor principal;
  principal.fabricIndex = 2;
  principal.authMode = chip::Access::AuthMode::kCase;
  principal.subject = 42;
  principal.cats.values[0] = 0x00010001;
  principal.cats.values[1] = 0x00020003;
  principal.isCommissioning = true;
  chip::app::ConcreteDataAttributePath path(3, cluster, member);
  path.mExpanded = true;
  path.mDataVersion.SetValue(99);
  chip::app::DataModel::WriteAttributeRequest request(path, principal);
  request.writeFlags.Set(chip::app::DataModel::WriteFlags::kTimed);
  return CaptureBridgeRequest(request);
}

bool SameMetadata(const BridgeRequestMetadata &left, const BridgeRequestMetadata &right) {
  return left.operation == right.operation && left.endpoint == right.endpoint &&
      left.cluster == right.cluster && left.member == right.member &&
      left.principal.fabricIndex == right.principal.fabricIndex &&
      left.principal.authMode == right.principal.authMode &&
      left.principal.subject == right.principal.subject &&
      left.principal.cats.values == right.principal.cats.values &&
      left.principal.isCommissioning == right.principal.isCommissioning &&
      left.expanded == right.expanded && left.timed == right.timed &&
      left.fabric_filtered == right.fabric_filtered &&
      left.allows_large_payload == right.allows_large_payload &&
      left.list_operation == right.list_operation && left.list_index == right.list_index &&
      left.data_version == right.data_version;
}

template <class Encode>
void CheckWrite(BridgeRequestMetadata metadata, Encode encode, CHIP_ERROR expected_error,
                bool tried, BridgeWriteScalar expected_value = std::uint16_t{0},
                unsigned foreign = 0) {
  // Attribute data is a context field inside the SDK write's outer Structure.
  std::uint8_t bytes[64]{};
  chip::TLV::TLVWriter writer;
  writer.Init(bytes);
  chip::TLV::TLVType outer;
  Require(writer.StartContainer(chip::TLV::AnonymousTag(), chip::TLV::kTLVType_Structure, outer) ==
                  CHIP_NO_ERROR &&
              encode(writer) == CHIP_NO_ERROR && writer.EndContainer(outer) == CHIP_NO_ERROR &&
              writer.Finalize() == CHIP_NO_ERROR,
          "write fixture encoding");
  chip::TLV::TLVReader reader;
  reader.Init(bytes, writer.GetLengthWritten());
  Require(reader.Next() == CHIP_NO_ERROR && reader.EnterContainer(outer) == CHIP_NO_ERROR &&
              reader.Next() == CHIP_NO_ERROR,
          "write fixture positioning");
  auto principal = metadata.principal;
  if (foreign == 1) principal.fabricIndex = 9;
  if (foreign == 2) principal.authMode = chip::Access::AuthMode::kPase;
  if (foreign == 3) principal.subject = 43;
  if (foreign == 4) principal.cats.values[0] ^= 1;
  if (foreign == 5) principal.isCommissioning = false;
  chip::app::AttributeValueDecoder decoder(reader, principal);
  Handoff custody({7});
  BridgeAttributeWrite result;
  result.ticket.id = 999;
  result.request.member = 77;
  result.deadline_ms = 123;
  result.value = std::uint16_t{123};
  const auto error = StartBridgeWrite(custody, metadata, decoder, 100, 600, result);
  if (error != expected_error || decoder.TriedDecode() != tried) {
    std::cerr << "write mismatch cluster " << metadata.cluster << " attribute " << metadata.member
              << " expected " << expected_error.AsInteger() << " actual " << error.AsInteger()
              << " tried " << decoder.TriedDecode() << '\n';
  }
  Require(error == expected_error && decoder.TriedDecode() == tried,
          "write refusal or decoder access changed");
  if (error == CHIP_NO_ERROR) {
    const auto captured = metadata;
    metadata = {};
    principal = {};
    std::fill(std::begin(bytes), std::end(bytes), 0);
    Require(result.value == expected_value && SameMetadata(result.request, captured) &&
                result.ticket.id == 1 && result.ticket.generation == Handoff::Generation{7} &&
                result.deadline_ms == 600 && custody.pending() == 1,
            "write payload, principal or metadata borrowed callback storage");
    Require(
        custody.Resolve(result.ticket, Handoff::Outcome::Completed, 101) == Handoff::Reply::Stored,
        "write result staging");
    Handoff::Outcome outcome = Handoff::Outcome::Unknown;
    Require(custody.Take(result.ticket, 102, outcome) == Handoff::Consume::Completed &&
                outcome == Handoff::Outcome::Completed && custody.pending() == 0,
            "write result consumed");
  } else {
    Require(result.ticket.id == 999 && result.request.member == 77 && result.deadline_ms == 123 &&
                result.value == BridgeWriteScalar{std::uint16_t{123}} && custody.pending() == 0,
            "refused write changed output or acquired custody");
  }
}

void VerifyValues() {
  using chip::TLV::ContextTag;
  const auto number = [](std::uint64_t value) {
    return [=](auto &writer) { return writer.Put(ContextTag(2), value); };
  };
  const auto null = [](auto &writer) { return writer.PutNull(ContextTag(2)); };
  const auto negative = [](auto &writer) { return writer.Put(ContextTag(2), std::int64_t{-1}); };
  const auto boolean = [](auto &writer) { return writer.Put(ContextTag(2), true); };
  const auto string = [](auto &writer) { return writer.PutString(ContextTag(2), "1"); };
  for (const auto &path :
       {std::make_pair(3U, 0U), std::make_pair(6U, 0x4001U), std::make_pair(6U, 0x4002U)}) {
    const auto metadata = Metadata(path.first, path.second);
    for (auto value : {0U, 65535U}) {
      CheckWrite(metadata, number(value), CHIP_NO_ERROR, true, std::uint16_t(value));
    }
    CheckWrite(metadata, number(65536), CHIP_ERROR_INVALID_INTEGER_VALUE, true);
    CheckWrite(metadata, null, CHIP_ERROR_WRONG_TLV_TYPE, true);
    CheckWrite(metadata, negative, CHIP_ERROR_WRONG_TLV_TYPE, true);
    CheckWrite(metadata, boolean, CHIP_ERROR_WRONG_TLV_TYPE, true);
    CheckWrite(metadata, string, CHIP_ERROR_WRONG_TLV_TYPE, true);
  }
  auto metadata = Metadata(6, 0x4003);
  for (auto value : {0U, 1U, 2U}) {
    CheckWrite(metadata, number(value), CHIP_NO_ERROR, true, std::optional<std::uint8_t>(value));
  }
  CheckWrite(metadata, null, CHIP_NO_ERROR, true, std::optional<std::uint8_t>{});
  for (auto value : {3U, 255U}) {
    CheckWrite(metadata, number(value), CHIP_IM_GLOBAL_STATUS(ConstraintError), true);
  }
  CheckWrite(metadata, number(256), CHIP_ERROR_INVALID_INTEGER_VALUE, true);
  CheckWrite(metadata, negative, CHIP_ERROR_WRONG_TLV_TYPE, true);
  CheckWrite(metadata, boolean, CHIP_ERROR_WRONG_TLV_TYPE, true);
  CheckWrite(metadata, string, CHIP_ERROR_WRONG_TLV_TYPE, true);
  for (unsigned foreign = 1; foreign <= 5; ++foreign) {
    CheckWrite(metadata, number(1), CHIP_ERROR_INVALID_ARGUMENT, false, std::uint16_t{0}, foreign);
  }
  metadata.member = 0;
  CheckWrite(metadata, boolean, CHIP_IM_GLOBAL_STATUS(UnsupportedWrite), false);
  metadata = Metadata(0x0402, 0);
  CheckWrite(metadata, number(1), CHIP_IM_GLOBAL_STATUS(UnsupportedWrite), false);
  metadata = Metadata(3, 0);
  for (auto endpoint : {0U, 1U, 2U, 65535U}) {
    metadata.endpoint = endpoint;
    CheckWrite(metadata, number(1), CHIP_ERROR_INVALID_ARGUMENT, false);
  }
  metadata = Metadata(3, 0);
  for (auto operation :
       {BridgeRequestMetadata::Operation::Read, BridgeRequestMetadata::Operation::Invoke}) {
    metadata.operation = operation;
    CheckWrite(metadata, number(1), CHIP_ERROR_INVALID_ARGUMENT, false);
  }
  metadata = Metadata(3, 0);
  for (auto list : {List::ReplaceAll, List::AppendItem, List::ReplaceItem, List::DeleteItem}) {
    metadata.list_operation = list;
    CheckWrite(metadata, number(1), CHIP_ERROR_INVALID_ARGUMENT, false);
  }
  std::cout << "SDK finite write scalar ownership and refusal passed\n" << std::flush;
}

void VerifyAdmission() {
  Handoff custody({7});
  const auto call = [&](bool valid_payload, std::uint64_t now, std::uint64_t deadline,
                        CHIP_ERROR expected, BridgeAttributeWrite &result) {
    const std::uint8_t bytes[] = {static_cast<std::uint8_t>(valid_payload ? 0x04 : 0x08), 1};
    chip::TLV::TLVReader reader;
    reader.Init(bytes, sizeof(bytes));
    Require(reader.Next() == CHIP_NO_ERROR, "write admission fixture positioning");
    const auto metadata = Metadata(3, 0);
    chip::app::AttributeValueDecoder decoder(reader, metadata.principal);
    const auto error = StartBridgeWrite(custody, metadata, decoder, now, deadline, result);
    Require(error == expected, "write custody admission error changed");
    if (error != CHIP_NO_ERROR) {
      Require(result.ticket.id == 999 && result.deadline_ms == 123 &&
                  std::get<std::uint16_t>(result.value) == 123,
              "refused write custody changed output");
    }
  };
  BridgeAttributeWrite sentinel;
  sentinel.ticket.id = 999;
  sentinel.deadline_ms = 123;
  sentinel.value = std::uint16_t{123};
  call(false, 100, 600, CHIP_ERROR_WRONG_TLV_TYPE, sentinel);
  Require(custody.pending() == 0, "malformed write acquired custody");
  call(true, 100, 100, CHIP_ERROR_INVALID_ARGUMENT, sentinel);
  call(true, 100, 601, CHIP_ERROR_INVALID_ARGUMENT, sentinel);
  std::array<BridgeAttributeWrite, Handoff::kCapacity> requests;
  for (std::size_t index = 0; index < requests.size(); ++index) {
    call(true, 100, 600, CHIP_NO_ERROR, requests[index]);
    Require(requests[index].ticket.id == index + 1 && requests[index].deadline_ms == 600 &&
                std::get<std::uint16_t>(requests[index].value) == 1,
            "write custody identity, payload or deadline changed");
  }
  call(true, 100, 600, CHIP_ERROR_BUSY, sentinel);
  Require(custody.Resolve(requests[0].ticket, Handoff::Outcome::Completed, 101) ==
              Handoff::Reply::Stored,
          "write completion not staged");
  call(true, 99, 599, CHIP_ERROR_INVALID_ARGUMENT, sentinel);
  call(true, 101, 601, CHIP_ERROR_BUSY, sentinel);
  call(true, 600, 1100, CHIP_ERROR_BUSY, sentinel);
  for (const auto &request : requests) {
    Handoff::Outcome outcome = Handoff::Outcome::Unknown;
    Require(custody.Take(request.ticket, 600, outcome) == Handoff::Consume::Completed &&
                outcome == Handoff::Outcome::TimedOut,
            "expired write completion revived");
  }
  BridgeAttributeWrite next;
  call(true, 600, 1100, CHIP_NO_ERROR, next);
  Require(next.ticket.id == 17, "failed write consumed a request identity");
  custody.Close();
  call(true, 600, 1100, CHIP_ERROR_INCORRECT_STATE, sentinel);
  Handoff::Outcome outcome = Handoff::Outcome::Unknown;
  Require(custody.Take(next.ticket, 600, outcome) == Handoff::Consume::Completed &&
              outcome == Handoff::Outcome::Closed && custody.pending() == 0,
          "closed write custody leaked");
  std::cout << "SDK finite write admission, staged credit and deadline passed\n" << std::flush;
}

} // namespace

void VerifyBridgeWrites() {
  VerifyValues();
  VerifyAdmission();
}

} // namespace wotex::matter::testing
