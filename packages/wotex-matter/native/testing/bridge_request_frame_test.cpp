#include "wotex_matter/bridge_request_frame.hpp"
#include "wotex_matter/bridge_input.hpp"

#include <lib/core/TLVWriter.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <cassert>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <limits>
#include <new>

namespace {
std::atomic<bool> allocation_failure{false};
}
void *operator new(std::size_t size) {
  if (allocation_failure.exchange(false)) throw std::bad_alloc();
  if (auto *memory = std::malloc(size == 0 ? 1 : size)) return memory;
  throw std::bad_alloc();
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *memory) noexcept { std::free(memory); }
void operator delete[](void *memory) noexcept { std::free(memory); }
void operator delete(void *memory, std::size_t) noexcept { std::free(memory); }
void operator delete[](void *memory, std::size_t) noexcept { std::free(memory); }

using namespace wotex::matter;
namespace {
using Encode = BridgeRequestEncode;
using Json = nlohmann::json;
using RequestOperation = BridgeRequestMetadata::Operation;
constexpr auto maximum = std::numeric_limits<std::uint64_t>::max();
struct Fixture {
  BridgeConsumerHandoff::Ticket ticket;
  BridgeRequestMetadata request;
  BridgeFabricScope scope;
  std::string thing{std::string("\0\xff", 2)};
  Fixture() {
    ticket.generation.fill(0xff);
    ticket.id = maximum;
    request.endpoint = 3;
    request.cluster = 6;
    request.member = 0;
    request.principal.fabricIndex = 254;
    request.principal.authMode = chip::Access::AuthMode::kCase;
    request.principal.subject = maximum;
    request.principal.cats.values = {1, 0, std::numeric_limits<std::uint32_t>::max()};
    request.principal.isCommissioning = true;
    scope.principal = request.principal;
    scope.epoch = scope.fabric_id = maximum;
    scope.bridge_node = 0xFFFFFFEFFFFFFFFFULL;
    scope.root.fill(0xff);
    scope.root[0] = 4;
    scope.noc_sha256.fill(0xff);
  }
  BridgeInvocation Invoke() const {
    BridgeInvocation result;
    result.ticket = ticket;
    result.request = request;
    result.request.operation = RequestOperation::Invoke;
    result.deadline_ms = maximum;
    result.arguments = {21, 24};
    return result;
  }
  BridgeAttributeWrite Write() const {
    BridgeAttributeWrite result;
    result.ticket = ticket;
    result.request = request;
    result.request.operation = RequestOperation::Write;
    result.request.member = 0x4001;
    result.deadline_ms = maximum;
    result.value = std::uint16_t{65535};
    return result;
  }
};
std::vector<std::uint8_t> Arguments(std::size_t payload, std::size_t depth, std::size_t leaves) {
  std::vector<std::uint8_t> result(65537);
  chip::TLV::TLVWriter writer;
  writer.Init(result.data(), static_cast<std::uint32_t>(result.size()));
  std::array<chip::TLV::TLVType, 25> containers{};
  for (std::size_t index = 0; index < depth; ++index)
    assert(writer.StartContainer(index == 0 ? chip::TLV::AnonymousTag() : chip::TLV::ContextTag(0),
                                 chip::TLV::kTLVType_Structure,
                                 containers[index]) == CHIP_NO_ERROR);
  if (payload != 0) {
    const std::vector<std::uint8_t> value(payload, 0xff);
    assert(writer.PutBytes(chip::TLV::ContextTag(0), value.data(),
                           static_cast<std::uint32_t>(value.size())) == CHIP_NO_ERROR);
  }
  for (std::size_t index = 0; index < leaves; ++index)
    assert(writer.Put(chip::TLV::ContextTag(0), true) == CHIP_NO_ERROR);
  for (auto index = depth; index != 0; --index)
    assert(writer.EndContainer(containers[index - 1]) == CHIP_NO_ERROR);
  assert(writer.Finalize() == CHIP_NO_ERROR);
  result.resize(writer.GetLengthWritten());
  return result;
}
void Emit(const std::string &frame) {
  assert(frame.back() == '\n' && frame.size() <= 262144 && frame.find('\0') == std::string::npos);
  const auto decoded = Json::parse(frame);
  assert(decoded.size() == 15 && decoded["backend"] == "matter-bridge" &&
         decoded["type"] == "request" && decoded["id"] == std::to_string(maximum) &&
         decoded["deadline_ms"] == std::to_string(maximum));
  std::cout << "bridge request fixture: " << frame;
}
void Valid() {
  // Synthetic principal/scope values test owned representations, not
  // authenticated transport, current ACLs or consumer policy.
  Fixture fixture;
  std::string output;
  fixture.request.expanded = fixture.request.fabric_filtered =
      fixture.request.allows_large_payload = true;
  assert(EncodeBridgeReadFrame(fixture.ticket, fixture.request, fixture.scope, maximum,
                               fixture.thing, output) == Encode::Encoded);
  Emit(output);
  fixture.request.principal.authMode = chip::Access::AuthMode::kGroup;
  fixture.scope.principal = fixture.request.principal;
  assert(EncodeBridgeReadFrame(fixture.ticket, fixture.request, fixture.scope, maximum,
                               fixture.thing, output) == Encode::Encoded);
  Emit(output);
  fixture = Fixture{};
  auto write = fixture.Write();
  write.request.expanded = write.request.timed = true;
  write.request.data_version = std::numeric_limits<std::uint32_t>::max();
  for (const auto &[cluster, member] :
       {std::pair<std::uint32_t, std::uint32_t>{3, 0}, {6, 0x4001}, {6, 0x4002}}) {
    write.request.cluster = cluster;
    write.request.member = member;
    assert(EncodeBridgeWriteFrame(write, fixture.scope, fixture.thing, output) == Encode::Encoded);
    Emit(output);
  }
  write.request.cluster = 6;
  write.request.member = 0x4003;
  for (const auto &value : {std::optional<std::uint8_t>{}, std::optional<std::uint8_t>{0},
                            std::optional<std::uint8_t>{1}, std::optional<std::uint8_t>{2}}) {
    write.value = value;
    assert(EncodeBridgeWriteFrame(write, fixture.scope, fixture.thing, output) == Encode::Encoded);
    Emit(output);
  }
  auto invocation = fixture.Invoke();
  invocation.request.timed = true;
  for (const auto &bytes : {std::vector<std::uint8_t>{21, 24}, Arguments(65530, 1, 0),
                            Arguments(0, 24, 0), Arguments(0, 1, 4095)}) {
    invocation.arguments = bytes;
    assert(EncodeBridgeInvokeFrame(invocation, fixture.scope, fixture.thing, output) ==
           Encode::Encoded);
    Emit(output);
    assert(Json::parse(output)["payload"]["value"].get<std::string>().size() == bytes.size() * 2);
  }
  const auto owned = output;
  invocation.arguments.assign(2, 0xff);
  fixture.thing.assign(256, 'x');
  assert(output == owned);
}
void Refusals() {
  Fixture fixture;
  std::string output("unchanged");
  const auto read = [&](const Fixture &input) {
    return EncodeBridgeReadFrame(input.ticket, input.request, input.scope, maximum, input.thing,
                                 output);
  };
  for (unsigned field = 0; field != 19; ++field) {
    auto invalid = fixture;
    switch (field) {
    case 0:
      invalid.ticket.id = 0;
      break;
    case 1:
      invalid.thing.clear();
      break;
    case 2:
      invalid.thing.assign(257, 'x');
      break;
    case 3:
      invalid.request.endpoint = 2;
      break;
    case 4:
      invalid.request.cluster = 0x8000;
      break;
    case 5:
      invalid.request.member = 0x5000;
      break;
    case 6:
      invalid.request.timed = true;
      break;
    case 7:
      invalid.request.data_version = 1;
      break;
    case 8:
      invalid.request.list_operation =
          chip::app::ConcreteDataAttributePath::ListOperation::ReplaceAll;
      break;
    case 9:
      invalid.request.list_index = 1;
      break;
    case 10:
      invalid.scope.principal.subject = 1;
      break;
    case 11:
      invalid.scope.principal.cats.values[1] = 1;
      break;
    case 12:
      invalid.scope.principal.isCommissioning = false;
      break;
    case 13:
      invalid.scope.epoch = 0;
      break;
    case 14:
      invalid.scope.fabric_id = 0;
      break;
    case 15:
      invalid.scope.bridge_node = maximum;
      break;
    case 16:
      invalid.scope.root[0] = 0;
      break;
    case 17:
      invalid.request.principal.authMode = chip::Access::AuthMode::kPase;
      break;
    case 18:
      invalid.request.principal.fabricIndex = 0;
      break;
    default:
      std::abort();
    }
    assert(read(invalid) == Encode::Malformed && output == "unchanged");
  }
  assert(EncodeBridgeReadFrame(fixture.ticket, fixture.request, fixture.scope, 0, fixture.thing,
                               output) == Encode::Malformed);
  fixture.thing.assign(256, static_cast<char>(0xff));
  assert(read(fixture) == Encode::Encoded);
  const auto owned = Json::parse(output);
  assert(owned["thing"].get<std::string>().size() == 512);
  auto invocation = fixture.Invoke();
  for (const auto &bytes : {Arguments(65531, 1, 0), Arguments(0, 25, 0), Arguments(0, 1, 4096)}) {
    invocation.arguments = bytes;
    output = "unchanged";
    assert(EncodeBridgeInvokeFrame(invocation, fixture.scope, fixture.thing, output) ==
               Encode::Oversized &&
           output == "unchanged");
  }
  for (const auto &bytes : {std::vector<std::uint8_t>{},
                            {20},
                            {21},
                            {53, 0, 24},
                            {21, 24, 20},
                            {21, 25, 24},
                            {21, 49, 0, 255, 255, 24}}) {
    invocation.arguments = bytes;
    assert(EncodeBridgeInvokeFrame(invocation, fixture.scope, fixture.thing, output) ==
               Encode::Malformed &&
           output == "unchanged");
  }
  invocation = fixture.Invoke();
  invocation.request.expanded = true;
  assert(EncodeBridgeInvokeFrame(invocation, fixture.scope, fixture.thing, output) ==
             Encode::Malformed &&
         output == "unchanged");
  auto write = fixture.Write();
  write.value = std::optional<std::uint8_t>{3};
  write.request.member = 0x4003;
  assert(EncodeBridgeWriteFrame(write, fixture.scope, fixture.thing, output) == Encode::Malformed &&
         output == "unchanged");
  write = fixture.Write();
  write.request.fabric_filtered = true;
  assert(EncodeBridgeWriteFrame(write, fixture.scope, fixture.thing, output) == Encode::Malformed &&
         output == "unchanged");
}
void Allocation() {
  Fixture fixture;
  auto write = fixture.Write();
  auto invoke = fixture.Invoke();
  std::string output("unchanged");
  allocation_failure = true;
  assert(EncodeBridgeReadFrame(fixture.ticket, fixture.request, fixture.scope, maximum,
                               fixture.thing, output) == Encode::NoMemory &&
         output == "unchanged" && !allocation_failure);
  allocation_failure = true;
  assert(EncodeBridgeWriteFrame(write, fixture.scope, fixture.thing, output) == Encode::NoMemory &&
         output == "unchanged" && !allocation_failure);
  allocation_failure = true;
  assert(EncodeBridgeInvokeFrame(invoke, fixture.scope, fixture.thing, output) ==
             Encode::NoMemory &&
         output == "unchanged" && !allocation_failure);
}
void Results(const char *path) {
  std::ifstream input(path);
  assert(input.is_open());
  BridgeConsumerHandoff::Generation generation;
  generation.fill(0xff);
  constexpr std::array<BridgeConsumerHandoff::Outcome, 4> outcomes{
      BridgeConsumerHandoff::Outcome::Completed, BridgeConsumerHandoff::Outcome::Denied,
      BridgeConsumerHandoff::Outcome::Failed, BridgeConsumerHandoff::Outcome::Unknown};
  std::string line;
  std::size_t count = 0;
  while (std::getline(input, line)) {
    assert(count < 8 && line.size() < 512);
    BridgeResultFrame result;
    assert(DecodeBridgeResultFrame(line, generation, result) == BridgeResultDecode::Decoded &&
           result.ticket.generation == generation &&
           result.ticket.id == (count % 2 == 0 ? 1 : maximum) &&
           result.outcome == outcomes[count / 2]);
    ++count;
  }
  assert(count == 8 && input.eof());
}
void ArgumentResults(const char *path) {
  std::ifstream input(path);
  assert(input.is_open());
  Fixture fixture;
  auto invocation = fixture.Invoke();
  std::string line;
  std::size_t count = 0, accepted = 0, refused = 0;
  while (std::getline(input, line)) {
    assert(count < 85 && line.size() < 1024);
    const auto cell = Json::parse(line);
    assert(cell.size() == 2 && cell["valid"].is_boolean());
    invocation.arguments = cell["bytes"].get<std::vector<std::uint8_t>>();
    std::string output("unchanged");
    const auto result = EncodeBridgeInvokeFrame(invocation, fixture.scope, fixture.thing, output);
    if (cell["valid"].get<bool>()) {
      assert(result == Encode::Encoded);
      ++accepted;
    } else {
      assert(result == Encode::Malformed && output == "unchanged");
      ++refused;
    }
    ++count;
  }
  assert(count == 85 && accepted != 0 && refused != 0 && input.eof());
  std::cout << "bridge argument fixtures: 85 passed\n";
}
}
int main(int argc, char **argv) {
  if (argc != 3) return 2;
  Valid();
  Refusals();
  Allocation();
  Results(argv[1]);
  ArgumentResults(argv[2]);
  std::cout << "bridge paired request/result codec and allocation boundaries passed\n";
}
