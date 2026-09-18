// SPDX-License-Identifier: Apache-2.0
// Discovery paging of the BLE native host (priv/bluez/native/pages.hpp) over
// a validated snapshot: parsing of the page request and construction of the
// bounded page reply, which re-encodes the reply after each added
// characteristic to stay within the frame bound. A 16-characteristic
// snapshot fits one page; the first 64-entry page of 256 characteristics
// issues a cursor; the 1,024-characteristic maximum is walked in 16 pages.
// Every snapshot is a new discovery generation. Cursor tokens come from a
// counter instead of the host's OS random source. Each operation is one page.
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>
#include <nanobench.h>

#include "pages.hpp"

namespace {
using wotex::ble::Json;
using wotex::ble::NativePages;
using wotex::ble::PageRequest;

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "pages: " << what << " failed\n";
  std::exit(1);
}

std::string token(std::uint64_t counter) {
  static constexpr char digits[] = "0123456789abcdef";
  std::string result(32, '0');
  for (std::size_t index = 32; counter != 0 && index != 0; counter >>= 4)
    result[--index] = digits[counter & 15];
  return result;
}

Json characteristic(unsigned index) {
  const std::string service = "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF/service" +
      std::to_string(index / 8);
  return {{"service_uuid", "0000181a-0000-1000-8000-00805f9b34fb"},
          {"characteristic_uuid", "00002a6e-0000-1000-8000-00805f9b34fb"},
          {"service_path", service},
          {"object_path", service + "/char" + std::to_string(index)},
          {"handle", index + 1},
          {"flags", {"read", "notify"}},
          {"generation", 1}};
}

Json snapshot(unsigned count) {
  Json result = Json::array();
  for (unsigned index = 0; index < count; ++index) result.push_back(characteristic(index));
  return result;
}

// One discover request: its parameters are parsed as the host parses them.
Json page(NativePages &pages, const Json &cursor, const Json &characteristics,
          std::uint64_t generation) {
  return pages.page(PageRequest::from(Json{{"cursor", cursor}}), "12", characteristics, generation);
}

} // namespace

int main() {
  std::uint64_t issued = 0;
  NativePages pages([&issued] { return token(++issued); });
  std::uint64_t generation = 0;
  const Json small = snapshot(16);
  const Json medium = snapshot(256);
  const Json maximal = snapshot(1024);

  ankerl::nanobench::Bench bench;
  bench.title("discovery pages").unit("page").warmup(20).minEpochTime(std::chrono::milliseconds(20));

  bench.run("one page of 16 characteristics", [&] {
    const Json result = page(pages, nullptr, small, ++generation);
    check(result.at("characteristics").size() == 16 && result.at("cursor").is_null(), "page");
  });
  bench.run("first page of 256 characteristics, new cursor", [&] {
    const Json result = page(pages, nullptr, medium, ++generation);
    check(result.at("characteristics").size() == 64 && result.at("cursor").is_string(), "page");
  });
  bench.batch(16).run("walk 1,024 characteristics in 16 pages", [&] {
    Json cursor;
    std::size_t count = 0, walked = 0;
    ++generation;
    do {
      const Json result = page(pages, cursor, maximal, generation);
      cursor = result.at("cursor");
      walked += result.at("characteristics").size();
      ++count;
    } while (!cursor.is_null());
    check(count == 16 && walked == 1024, "walk");
  });
  check(pages.retained_cursors() <= 1024, "cursor bound");
  return 0;
}
