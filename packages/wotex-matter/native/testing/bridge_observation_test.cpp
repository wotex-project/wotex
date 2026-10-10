#include "wotex_matter/bridge_observation.hpp"
#include <nlohmann/json.hpp>
#include <fstream>
#include <cassert>
#include <iostream>
#include <limits>
#include <cstdlib>
#include <new>

namespace {
long allocation_failure = -1;
}
void *operator new(std::size_t size) {
  if (allocation_failure == 0) {
    allocation_failure = -1;
    throw std::bad_alloc();
  }
  if (allocation_failure > 0) --allocation_failure;
  if (auto *value = std::malloc(size ? size : 1)) return value;
  throw std::bad_alloc();
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *value) noexcept { std::free(value); }
void operator delete[](void *value) noexcept { std::free(value); }
void operator delete(void *value, std::size_t) noexcept { std::free(value); }
void operator delete[](void *value, std::size_t) noexcept { std::free(value); }

namespace {
using namespace wotex::matter;
std::string GenerationHex(const BridgeConsumerHandoff::Generation &generation) {
  constexpr char hex[] = "0123456789abcdef";
  std::string result;
  for (const auto byte : generation) {
    result += hex[byte >> 4];
    result += hex[byte & 15];
  }
  return result;
}
bool DecodeChecked(std::string_view frame, const BridgeConsumerHandoff::Generation &generation,
                   BridgeObservationFrame &output) {
  const auto decoded = DecodeBridgeObservationFrame(frame, generation, output);
  if (decoded == BridgeObservationDecode::NoMemory) throw std::bad_alloc();
  return decoded == BridgeObservationDecode::Decoded;
}
std::string ReceiptChecked(const BridgeConsumerHandoff::Generation &generation, std::uint64_t id,
                           bool applied) {
  std::string result;
  const auto encoded = EncodeBridgeObservationReceipt(
      generation, id,
      applied ? BridgeObservationOutcome::Applied : BridgeObservationOutcome::Refused, result);
  if (encoded == BridgeObservationEncode::NoMemory) throw std::bad_alloc();
  assert(encoded == BridgeObservationEncode::Encoded);
  return result;
}
void Paired(const char *path) {
  std::ifstream input(path);
  assert(input.is_open());
  BridgeConsumerHandoff::Generation generation;
  generation.fill(0xff);
  std::string frame;
  unsigned count = 0;
  while (std::getline(input, frame)) {
    assert(count < 8);
    BridgeObservationFrame observation;
    assert(DecodeBridgeObservationFrame(frame + "\n", generation, observation) ==
           BridgeObservationDecode::Decoded);
    assert(observation.id == (count % 2 == 0 ? 1 : std::numeric_limits<std::uint64_t>::max()));
    assert(observation.thing == std::string("\0\xff", 2) && observation.endpoint == 3);
    assert(observation.value.reachable == (count / 2 % 2 == 0));
    assert(observation.value.on_off ==
           (count < 4 ? std::optional<bool>{count < 2} : std::optional<bool>{}));
    assert(observation.value.temperature ==
           (count < 4 ? std::optional<std::int16_t>{}
                      : std::optional<std::int16_t>{
                            static_cast<std::int16_t>(count < 6 ? -32767 : 32767)}));
    ++count;
  }
  assert(count == 8 && input.eof());
  for (const auto outcome : {BridgeObservationOutcome::Applied, BridgeObservationOutcome::Refused})
    for (const auto id : {std::uint64_t{1}, std::numeric_limits<std::uint64_t>::max()}) {
      std::string output;
      assert(EncodeBridgeObservationReceipt(generation, id, outcome, output) ==
             BridgeObservationEncode::Encoded);
      std::cout << "bridge observation receipt fixture: " << output;
    }
}
}

int main(int argc, char **argv) {
  if (argc != 1 && argc != 2) return 2;
  if (argc == 2) Paired(argv[1]);
  using Json = nlohmann::json;
  using namespace wotex::matter;
  const wotex::matter::BridgeConsumerHandoff::Generation generation{1};
  const Json body{{"v", 1},
                  {"backend", "matter-bridge"},
                  {"type", "observation"},
                  {"generation", GenerationHex(generation)},
                  {"id", "1"},
                  {"thing", "0001"},
                  {"endpoint", 3},
                  {"reachable", true},
                  {"on_off", false},
                  {"temperature", nullptr}};
  BridgeObservationFrame result;
  const auto decode = [&](const Json &value) {
    return DecodeChecked(value.dump() + "\n", generation, result);
  };
  assert(decode(body));
  assert(result.id == 1 && result.thing == std::string("\0\1", 2) && result.endpoint == 3);
  assert(result.value.reachable && result.value.on_off == false && !result.value.temperature);
  auto maximal = body;
  maximal["id"] = std::to_string(std::numeric_limits<std::uint64_t>::max());
  maximal["thing"] = std::string(512, 'a');
  maximal["endpoint"] = 65534;
  maximal["on_off"] = nullptr;
  maximal["temperature"] = 32767;
  assert(decode(maximal) && result.id == std::numeric_limits<std::uint64_t>::max() &&
         result.thing.size() == 256 && result.value.temperature == 32767);
  for (const auto temperature : {-32767, 0, 32767}) {
    auto value = body;
    value["temperature"] = temperature;
    assert(decode(value) && result.value.temperature == temperature);
  }
  const auto refused = [&](const Json &value) {
    result.id = 77;
    result.thing = "preserved";
    result.endpoint = 99;
    result.value = {true, true, 100};
    assert(!decode(value));
    assert(result.id == 77 && result.thing == "preserved" && result.endpoint == 99 &&
           result.value.reachable && result.value.on_off == true &&
           result.value.temperature == 100);
  };
  for (const auto &key : {"v", "backend", "type", "generation", "id", "thing", "endpoint",
                          "reachable", "on_off", "temperature"}) {
    auto value = body;
    value.erase(key);
    refused(value);
  }
  for (const Json &id :
       {Json("0"), Json("01"), Json("-1"), Json("18446744073709551616"), Json(1), Json(nullptr)}) {
    auto value = body;
    value["id"] = id;
    refused(value);
  }
  for (const Json &version : {Json(true), Json(1.0), Json(2), Json(nullptr)}) {
    auto value = body;
    value["v"] = version;
    refused(value);
  }
  for (const Json &endpoint : {Json(2), Json(65535), Json(3.0), Json(true), Json(nullptr)}) {
    auto value = body;
    value["endpoint"] = endpoint;
    refused(value);
  }
  for (const Json &temperature : {Json(-32768), Json(32768), Json(0.0), Json(true), Json("0")}) {
    auto value = body;
    value["temperature"] = temperature;
    refused(value);
  }
  for (const auto &thing : {"", "0", "0A", "zz"}) {
    auto value = body;
    value["thing"] = thing;
    refused(value);
  }
  auto value = body;
  value["thing"] = std::string(514, '0');
  refused(value);
  value = body;
  value["extra"] = 0;
  refused(value);
  value = body;
  value["reachable"] = 1;
  refused(value);
  value = body;
  value["on_off"] = 0;
  refused(value);
  value = body;
  value["generation"] = std::string(32, '0');
  refused(value);
  value = body;
  value["type"] = "result";
  refused(value);
  auto encoded = body.dump();
  encoded.pop_back();
  assert(!DecodeChecked(encoded + ",\"v\":1}\n", generation, result));
  assert(!DecodeChecked(encoded + ",\"\\u0076\":1}\n", generation, result));
  assert(!DecodeChecked(body.dump(), generation, result));
  assert(!DecodeChecked(body.dump() + "\r\n", generation, result));
  assert(!DecodeChecked(std::string(1024, ' ') + body.dump() + "\n", generation, result));
  assert(!DecodeChecked("{\"v\":{}}\n", generation, result));
  assert(!DecodeChecked("[]\n", generation, result));
  const auto receipt = Json::parse(ReceiptChecked(generation, 1, true));
  assert(receipt.size() == 6 && receipt["type"] == "observation-receipt" && receipt["id"] == "1" &&
         receipt["outcome"] == "applied");
  assert(Json::parse(ReceiptChecked(generation, 2, false))["outcome"] == "refused");
  const auto frame = body.dump() + "\n";
  bool decoded = false, received = false;
  unsigned refusal_count = 0;
  for (long point = 0; point < 256; ++point) {
    result.id = 77;
    result.thing = "preserved";
    result.endpoint = 99;
    result.value = {true, true, 100};
    allocation_failure = point;
    const auto status = DecodeBridgeObservationFrame(frame, generation, result);
    allocation_failure = -1;
    if (status == BridgeObservationDecode::Decoded) {
      decoded = true;
      break;
    }
    ++refusal_count;
    assert(status == BridgeObservationDecode::NoMemory && result.id == 77 &&
           result.thing == "preserved" && result.endpoint == 99 && result.value.reachable &&
           result.value.on_off == true && result.value.temperature == 100);
  }
  assert(decoded && refusal_count > 1);
  refusal_count = 0;
  for (long point = 0; point < 256; ++point) {
    std::string output = "preserved";
    allocation_failure = point;
    const auto status = EncodeBridgeObservationReceipt(generation, 1,
                                                       BridgeObservationOutcome::Applied, output);
    allocation_failure = -1;
    if (status == BridgeObservationEncode::Encoded) {
      assert(Json::parse(output) == receipt);
      received = true;
      break;
    }
    ++refusal_count;
    assert(status == BridgeObservationEncode::NoMemory && output == "preserved");
  }
  assert(received && refusal_count > 1);
  auto padded = frame.substr(0, frame.size() - 1);
  padded.append(1023 - padded.size(), ' ');
  padded += '\n';
  assert(padded.size() == 1024 &&
         DecodeBridgeObservationFrame(padded, generation, result) ==
             BridgeObservationDecode::Decoded);
  result.id = 77;
  result.thing = "preserved";
  assert(DecodeBridgeObservationFrame(padded + " ", generation, result) ==
         BridgeObservationDecode::Oversized);
  assert(result.id == 77 && result.thing == "preserved");
  // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange): deliberately forge an unsupported scoped-enum value to verify structured refusal.
  const auto forged = static_cast<BridgeObservationOutcome>(99);
  for (const auto outcome : {BridgeObservationOutcome::Applied, forged}) {
    std::string output = "preserved";
    const auto id = outcome == BridgeObservationOutcome::Applied ? 0U : 1U;
    assert(EncodeBridgeObservationReceipt(generation, id, outcome, output) ==
           BridgeObservationEncode::Malformed);
    assert(output == "preserved");
  }
  std::cout << "bounded observation codec preserves refusal and exact receipt roles\n";
  std::cout << "observation decode and receipt allocation cutpoints preserve caller output\n";
}
