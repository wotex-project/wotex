// SPDX-License-Identifier: Apache-2.0
// The SDK-free value bounds of the Matter controller host: descriptor lookup
// and value conversion (native/src/value.cpp), Interaction Model request and
// response validation (native/src/interaction.cpp) and commissioning checks
// (native/src/commissioning.cpp), on the values the host converts for each
// SDK callback.
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <utility>
#include <vector>

#include <nanobench.h>

#include "wotex_matter/commissioning.hpp"
#include "wotex_matter/interaction.hpp"
#include "wotex_matter/value.hpp"

namespace {

using namespace wotex::matter;

constexpr std::uint64_t kFabric = 1;
constexpr std::uint64_t kNode = 0x1234;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "value_bounds: " << what << " failed\n";
  std::exit(1);
}

Element typed(ElementType type, std::uint64_t value = 0) {
  Element element;
  element.type = type;
  element.unsigned_value = value;
  return element;
}

Element tagged(ElementType type, std::uint8_t tag, std::uint64_t value = 0) {
  Element element = typed(type, value);
  element.tag = Tag{TagKind::Context, tag};
  return element;
}

// An Access Control List of `entries` entries, each granting one privilege to
// `subjects` operational node subjects and two cluster targets.
Element access_control_list(std::size_t entries, std::size_t subjects) {
  Element list = typed(ElementType::Array);
  for (std::size_t entry = 0; entry < entries; ++entry) {
    Element fields = typed(ElementType::Structure);
    fields.children.push_back(tagged(ElementType::U8, 1, entry == 0 ? 5 : 3));
    fields.children.push_back(tagged(ElementType::U8, 2, 2));
    Element subject_list = tagged(ElementType::Array, 3);
    for (std::size_t subject = 0; subject < subjects; ++subject)
      subject_list.children.push_back(
          typed(ElementType::U64, 0x770000 + (entry * subjects) + subject));
    fields.children.push_back(std::move(subject_list));
    Element targets = tagged(ElementType::Array, 4);
    for (const std::uint64_t cluster : {0x0006U, 0x0201U}) {
      Element target = typed(ElementType::Structure);
      target.children.push_back(tagged(ElementType::U32, 0, cluster));
      target.children.push_back(tagged(ElementType::U16, 1, 1));
      target.children.push_back(tagged(ElementType::Null, 2));
      targets.children.push_back(std::move(target));
    }
    fields.children.push_back(std::move(targets));
    list.children.push_back(std::move(fields));
  }
  return list;
}

// A read of the four Descriptor attributes on `endpoints` endpoints, with the
// response a node of that shape returns.
std::pair<InteractionRequest, InteractionResponse> descriptor_read(std::uint16_t endpoints) {
  InteractionRequest request;
  request.kind = InteractionKind::ReadAttributes;
  request.fabric_id = kFabric;
  request.node_id = kNode;
  request.timeout_ms = 30000;
  InteractionResponse response;
  response.ok = true;
  for (std::uint16_t endpoint = 0; endpoint < endpoints; ++endpoint) {
    for (std::uint32_t member = 0; member < 4; ++member) {
      request.paths.push_back({kFabric, kNode, endpoint, std::uint32_t{0x001D}, member});
      const ConcretePath path{kFabric, kNode, endpoint, 0x001D, member};
      Element value = typed(ElementType::Array);
      if (member == 0) {
        Element entry = typed(ElementType::Structure);
        entry.children.push_back(tagged(ElementType::U32, 0, endpoint == 0 ? 0x0016 : 0x0100));
        entry.children.push_back(tagged(ElementType::U16, 1, 3));
        value.children.push_back(std::move(entry));
      } else if (member == 3) {
        if (endpoint == 0)
          for (std::uint16_t part = 1; part < endpoints; ++part)
            value.children.push_back(typed(ElementType::U16, part));
      } else {
        for (const std::uint64_t cluster : {0x0003U, 0x0004U, 0x0006U, 0x001DU, 0x0039U, 0x0201U})
          value.children.push_back(typed(ElementType::U32, cluster));
      }
      PathResult result;
      result.path = path;
      result.attribute = AttributeData{path, std::move(value), 0x1000U + member};
      response.results.push_back(std::move(result));
    }
  }
  return {std::move(request), std::move(response)};
}

InteractionRequest write_request(Element value) {
  InteractionRequest request;
  request.kind = InteractionKind::Write;
  request.fabric_id = kFabric;
  request.node_id = kNode;
  request.timeout_ms = 30000;
  request.paths.push_back(
      {kFabric, kNode, std::uint16_t{0}, std::uint32_t{0x001F}, std::uint32_t{0}});
  request.value = std::move(value);
  return request;
}

} // namespace

int main() {
  ankerl::nanobench::Bench bench;
  bench.title("value bounds").warmup(100).minEpochTime(std::chrono::milliseconds(20));

  bench.unit("value").run("convert OnOff boolean", [] {
    const Conversion conversion = convert_value(MemberKind::Attribute, 0x0006, 0x0000,
                                                Operation::Read, NativeValue::boolean(true));
    check(conversion.error == ConversionError::None && conversion.element.has_value(),
          "boolean conversion");
  });

  bench.unit("value").run("convert and validate setpoint i16", [] {
    const Conversion conversion = convert_value(
        MemberKind::Attribute, 0x0201, 0x0012, Operation::Write, NativeValue::signed_integer(2150));
    check(conversion.element.has_value(), "setpoint conversion");
    check(validate_element(MemberKind::Attribute, 0x0201, 0x0012, Operation::Write,
                           *conversion.element) == ConversionError::None,
          "setpoint validation");
  });

  const NativeValue server_list = NativeValue::identifier_list({0x0003, 0x0004, 0x0005, 0x0006,
                                                                0x0008, 0x001D, 0x001E, 0x0028,
                                                                0x0039, 0x0201, 0x0402, 0x0406});
  bench.unit("value").run("convert and validate ServerList 12 clusters", [&] {
    const Conversion conversion = convert_value(MemberKind::Attribute, 0x001D, 0x0001,
                                                Operation::Read, server_list);
    check(conversion.element.has_value() && conversion.element->children.size() == 12,
          "cluster list conversion");
    check(validate_element(MemberKind::Attribute, 0x001D, 0x0001, Operation::Read,
                           *conversion.element) == ConversionError::None,
          "cluster list validation");
  });

  std::vector<std::uint32_t> parts;
  for (std::uint32_t endpoint = 1; endpoint <= 64; ++endpoint) parts.push_back(endpoint);
  const NativeValue parts_list = NativeValue::identifier_list(parts);
  bench.unit("value").run("convert and validate PartsList 64 endpoints", [&] {
    const Conversion conversion = convert_value(MemberKind::Attribute, 0x001D, 0x0003,
                                                Operation::Read, parts_list);
    check(conversion.element.has_value() && conversion.element->children.size() == 64,
          "parts list conversion");
    check(validate_element(MemberKind::Attribute, 0x001D, 0x0003, Operation::Read,
                           *conversion.element) == ConversionError::None,
          "parts list validation");
  });

  const InteractionRequest acl_write = write_request(access_control_list(4, 4));
  bench.unit("request").run("validate ACL write 4 entries x 4 subjects", [&] {
    check(valid_interaction_request(acl_write), "ACL write validation");
  });

  const std::pair<InteractionRequest, InteractionResponse> read = descriptor_read(16);
  check(read.first.paths.size() == kMaximumInteractionPaths, "descriptor read paths");
  bench.unit("request").run("validate Descriptor read 64 paths and response", [&] {
    check(valid_interaction_request(read.first), "descriptor read request");
    check(valid_interaction_response(read.first, read.second), "descriptor read response");
  });

  const CommissioningRequest commissioning{kNode, 20202021, 3840, 60000};
  const CommissioningWindowRequest window{kNode, 180, 10000, 2600, 30000};
  const CommissioningWindowResponse opened{
      true, std::nullopt, kNode, 34120287, 2600, 180, "34970112332", "MT:Y.K9042C00KA0648G00"};
  bench.unit("request").run("validate commissioning request and window response", [&] {
    check(valid_commissioning_request(commissioning), "commissioning request");
    check(valid_commissioning_window_request(window), "window request");
    check(valid_commissioning_window_response(window, opened), "window response");
  });

  return 0;
}
