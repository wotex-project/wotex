#include "wotex_matter/bridge_bootstrap.hpp"
#include "bridge_sdk_bootstrap_fixture.hpp"
#include <credentials/examples/DeviceAttestationCredsExample.h>
#include <credentials/examples/ExampleDACs.h>
#include <lib/support/CHIPMem.h>
#include <platform/logging/LogV.h>
#include <nlohmann/json.hpp>
#include <cassert>
#include <cstdarg>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <iostream>
#include <new>
#include <sys/stat.h>
#include <unistd.h>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error Development bootstrap composition must remain a separate test build.
#endif

namespace {
class ClosedCommissioningFixture final : public chip::DeviceLayer::CommissionableDataProvider {
 public:
  CHIP_ERROR GetSetupDiscriminator(std::uint16_t &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR SetSetupDiscriminator(std::uint16_t) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR GetSpake2pIterationCount(std::uint32_t &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR GetSpake2pSalt(chip::MutableByteSpan &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR GetSpake2pVerifier(chip::MutableByteSpan &, std::size_t &) override {
    return CHIP_ERROR_INCORRECT_STATE;
  }
  CHIP_ERROR GetSetupPasscode(std::uint32_t &) override { return CHIP_ERROR_INCORRECT_STATE; }
  CHIP_ERROR SetSetupPasscode(std::uint32_t) override { return CHIP_ERROR_INCORRECT_STATE; }
};
long allocation_failure = -1;
struct SecretArray {
  void *value{nullptr};
  std::size_t size{0};
};
std::array<SecretArray, 8> secret_arrays{};
bool observe_arrays = false;
unsigned observed_arrays = 0;
void Free(void *value) {
  for (auto &array : secret_arrays) {
    if (!array.value || array.value != value) continue;
    for (std::size_t i = 0; i < array.size; ++i)
      assert(static_cast<const unsigned char *>(value)[i] == 0);
    array = {};
    ++observed_arrays;
  }
  std::free(value);
}
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
void *operator new[](std::size_t size) {
  auto *value = ::operator new(size);
  if (observe_arrays && (size == 97 || size == 35)) {
    bool recorded = false;
    for (auto &array : secret_arrays) {
      if (array.value) continue;
      array = {value, size};
      recorded = true;
      break;
    }
    assert(recorded);
  }
  return value;
}
void *operator new(std::size_t size, const std::nothrow_t &) noexcept {
  try {
    return ::operator new(size);
  } catch (const std::bad_alloc &) {
    return nullptr;
  }
}
void *operator new[](std::size_t size, const std::nothrow_t &) noexcept {
  try {
    return ::operator new[](size);
  } catch (const std::bad_alloc &) {
    return nullptr;
  }
}
void operator delete(void *value) noexcept { Free(value); }
void operator delete[](void *value) noexcept { Free(value); }
void operator delete(void *value, std::size_t) noexcept { Free(value); }
void operator delete[](void *value, std::size_t) noexcept { Free(value); }
void operator delete(void *value, const std::nothrow_t &) noexcept { Free(value); }
void operator delete[](void *value, const std::nothrow_t &) noexcept { Free(value); }

namespace {
void Write(const std::string &path, const void *bytes, std::size_t size) {
  const int file = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
  assert(file >= 0 && write(file, bytes, size) == static_cast<ssize_t>(size));
  assert(close(file) == 0 && chmod(path.c_str(), 0600) == 0);
}
void LogPayload(const char *message, ...) {
  va_list arguments;
  va_start(arguments, message);
  chip::Logging::Platform::LogV("caller-module-canary", 0, message, arguments);
  va_end(arguments);
}

}
int main(int argc, char **argv) {
  const std::string_view mode = argc == 1 ? "normal" : argv[1];
  using namespace chip;
  using namespace wotex::matter;
  using R = BootstrapLoad;
  assert(Platform::MemoryInit() == CHIP_NO_ERROR);
  static ClosedCommissioningFixture closed;
  DeviceLayer::SetCommissionableDataProvider(&closed);
  int formatted = 77;
  LogPayload("caller-path-and-secret-canary: %s%n", "caller-payload-canary", &formatted);
  assert(formatted == 77);
  LogPayload(nullptr);
  char path[] = "/tmp/wotex-bootstrap-private-XXXXXX";
  assert(mkdtemp(path));
  const auto root = std::filesystem::canonical(path).string();
  std::array<std::uint8_t, 600> dac{}, pai{};
  std::array<std::uint8_t, 4096> cd{};
  MutableByteSpan dac_span(dac), pai_span(pai), cd_span(cd);
  auto *example = Credentials::Examples::GetExampleDACProvider();
  assert(example->GetDeviceAttestationCert(dac_span) == CHIP_NO_ERROR);
  assert(example->GetProductAttestationIntermediateCert(pai_span) == CHIP_NO_ERROR);
  assert(example->GetCertificationDeclaration(cd_span) == CHIP_NO_ERROR);
  Crypto::P256SerializedKeypair key;
  assert(key.SetLength(97) == CHIP_NO_ERROR);
  std::memcpy(key.Bytes(), DevelopmentCerts::kDacPublicKey.data(), 65);
  std::memcpy(key.Bytes() + 65, DevelopmentCerts::kDacPrivateKey.data(), 32);
  Write(root + "/dac", dac_span.data(), dac_span.size());
  Write(root + "/pai", pai_span.data(), pai_span.size());
  Write(root + "/cd", cd_span.data(), cd_span.size());
  Write(root + "/key", key.Bytes(), key.Length());
  std::string setup("WMCSET1\0", 8);
  const auto append = [&](std::uint32_t value, unsigned count) {
    while (count != 0) setup += static_cast<char>(value >> (--count * 8));
  };
  append(20202021, 4);
  append(3840, 2);
  append(1000, 4);
  append(16, 1);
  setup += std::string(16, static_cast<char>(0xA5));
  Write(root + "/setup", setup.data(), setup.size());
  nlohmann::json configuration = {
      {"schema", "wotex.matter.bridge-bootstrap@1"},
      {"sdk_revision", "250a9e6c50ee2068107f3c4808b680f5f2925415"},
      {"model_sha256", "dd8b1a870f1cfa89b609e70ff342e4f3d61525ae49bbbea27cf112d1bca0b671"},
      {"bridge_id", "00ff"},
      {"vendor_id", 0xFFF1},
      {"product_id", 0x8001},
      {"vendor_name", "consumer"},
      {"product_name", "explicit bridge"},
      {"hardware_version", 1},
      {"hardware_version_string", "explicit hardware"},
      {"store_path", root + "/store"},
      {"store_mode", "new"},
      {"interface", "lo"},
      {"port", 5540},
      {"commissioning_window_seconds", 0},
      {"dac_path", root + "/dac"},
      {"pai_path", root + "/pai"},
      {"declaration_path", root + "/cd"},
      {"key_path", root + "/key"},
      {"commissioning_path", root + "/setup"},
      {"devices",
       nlohmann::json::array({{{"thing_id", "0001"},
                               {"device_type", 256},
                               {"node_label", "configured light"},
                               {"minimum_temperature", nullptr},
                               {"maximum_temperature", nullptr}},
                              {{"thing_id", "0002"},
                               {"device_type", 770},
                               {"node_label", "configured sensor"},
                               {"minimum_temperature", -1000},
                               {"maximum_temperature", 4000}}})}};
  const auto encoded = configuration.dump();
  Write(root + "/configuration", encoded.data(), encoded.size());
  auto *original = Credentials::GetDeviceAttestationCredentialsProvider();
  std::unique_ptr<BridgeBootstrap> owner;
  assert(LoadBootstrap(root + "/configuration", owner) == R::Loaded && owner && owner->credentials);
  assert(Credentials::GetDeviceAttestationCredentialsProvider() == original);
  assert(DeviceLayer::GetCommissionableDataProvider() == &closed);
  auto *unchanged = owner.get();
  for (const auto &name : {"configuration", "dac", "pai", "cd", "key", "setup"}) {
    const auto source = root + "/" + name;
    const auto moved = source + ".held";
    assert(rename(source.c_str(), moved.c_str()) == 0);
    observe_arrays = true;
    const auto loaded = LoadBootstrap(root + "/configuration", owner);
    observe_arrays = false;
    assert(loaded == R::File && owner.get() == unchanged);
    for (const auto &array : secret_arrays) assert(!array.value);
    assert(Credentials::GetDeviceAttestationCredentialsProvider() == original);
    assert(DeviceLayer::GetCommissionableDataProvider() == &closed);
    assert(rename(moved.c_str(), source.c_str()) == 0);
  }
  constexpr char malformed[] = "{}";
  Write(root + "/configuration", malformed, sizeof(malformed) - 1);
  assert(LoadBootstrap(root + "/configuration", owner) == R::Configuration &&
         owner.get() == unchanged);
  Write(root + "/configuration", encoded.data(), encoded.size());
  Write(root + "/setup", setup.data(), setup.size() - 1);
  assert(LoadBootstrap(root + "/configuration", owner) == R::Credentials &&
         owner.get() == unchanged);
  Write(root + "/setup", setup.data(), setup.size());
  const auto master = root + "/configuration";
  bool succeeded = false;
  unsigned allocation_refusals = 0;
  for (long point = 0; point < 256; ++point) {
    allocation_failure = point;
    observe_arrays = true;
    const auto loaded = LoadBootstrap(master, owner);
    observe_arrays = false;
    allocation_failure = -1;
    for (const auto &array : secret_arrays) assert(!array.value);
    if (loaded == R::Loaded) {
      succeeded = true;
      break;
    }
    assert(loaded == R::NoMemory && owner.get() == unchanged);
    assert(Credentials::GetDeviceAttestationCredentialsProvider() == original);
    assert(DeviceLayer::GetCommissionableDataProvider() == &closed);
    ++allocation_refusals;
  }
  assert(succeeded && allocation_refusals > 0 && observed_arrays >= 2);
  unchanged = owner.get();
  assert(chmod((root + "/key").c_str(), 0644) == 0);
  assert(LoadBootstrap(root + "/configuration", owner) == R::File && owner.get() == unchanged);
  assert(chmod((root + "/key").c_str(), 0600) == 0);
  setup[8] = setup[9] = setup[10] = setup[11] = 0;
  Write(root + "/setup", setup.data(), setup.size());
  observe_arrays = true;
  const auto refused = LoadBootstrap(root + "/configuration", owner);
  observe_arrays = false;
  assert(refused == R::Credentials && owner.get() == unchanged);
  for (const auto &array : secret_arrays) assert(!array.value);
  key.Clear();
  Crypto::ClearSecretData(reinterpret_cast<std::uint8_t *>(setup.data()), setup.size());
  for (const auto &name : {"key", "setup", "dac", "pai", "cd", "configuration"})
    assert(unlink((root + "/" + name).c_str()) == 0);
  std::uint32_t pin = 0;
  assert(owner->credentials->GetSetupPasscode(pin) == CHIP_NO_ERROR && pin == 20202021);
  Crypto::ClearSecretData(reinterpret_cast<std::uint8_t *>(&pin), sizeof(pin));
  std::array<std::uint8_t, 64> signature{};
  MutableByteSpan signature_span(signature);
  constexpr std::uint8_t message[] = "explicit bootstrap test";
  assert(owner->credentials->SignWithDeviceAttestationKey(ByteSpan(message, sizeof(message) - 1),
                                                          signature_span) == CHIP_NO_ERROR);
  if (mode == "window" || mode == "expiry")
    owner->configuration->commissioning_window_seconds = 180;
  OwnedBootstrapLifecycle(*owner, closed, mode, allocation_failure);
  owner.reset();
  std::filesystem::remove_all(root);
  Platform::MemoryShutdown();
  std::cout << "owned SDK bootstrap resource lifecycle passed\n";
}
