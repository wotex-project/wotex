#include "wotex_matter/bridge_storage.hpp"
#include "wotex_matter/sdk_storage.hpp"

#include <credentials/TestOnlyLocalCertificateAuthority.h>
#include <crypto/CHIPCryptoPAL.h>
#include <lib/support/CHIPMem.h>

#include <array>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <unistd.h>

namespace {

using namespace wotex::matter;
using CertElement = chip::Credentials::OperationalCertificateStore::CertChainElement;

void Require(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
}

void RequireSuccess(CHIP_ERROR error, const char *message) {
  Require(error == CHIP_NO_ERROR, message);
}

class TemporaryDirectory final {
 public:
  TemporaryDirectory() {
    std::array<char, 64> pattern{};
    const std::string prefix = "/tmp/wotex-matter-sdk-bridge-store.XXXXXX";
    std::copy(prefix.begin(), prefix.end(), pattern.begin());
    const char *created = mkdtemp(pattern.data());
    Require(created != nullptr, "temporary directory creation failed");
    root_ = created;
  }
  ~TemporaryDirectory() { std::filesystem::remove_all(root_); }
  std::string Store() const { return root_ + "/bridge"; }

 private:
  std::string root_;
};

void RequireSignature(SdkStorageBinding &binding, const chip::Crypto::P256PublicKey &public_key) {
  constexpr std::array<std::uint8_t, 4> message{1, 2, 3, 4};
  chip::Crypto::P256ECDSASignature signature;
  RequireSuccess(
      binding.operational_keystore().SignWithOpKeypair(1, chip::ByteSpan(message), signature),
      "SDK operational signature failed");
  RequireSuccess(public_key.ECDSA_validate_msg_signature(message.data(), message.size(), signature),
                 "SDK persisted operational key changed");
}

void RequireCertificate(SdkStorageBinding &binding, CertElement element, chip::ByteSpan expected) {
  std::array<std::uint8_t, chip::Credentials::kMaxCHIPCertLength> bytes{};
  chip::MutableByteSpan certificate(bytes);
  RequireSuccess(binding.certificate_store().GetCertificate(1, element, certificate),
                 "SDK persisted certificate read failed");
  Require(certificate.data_equal(expected), "SDK persisted certificate changed");
}

void TestSdkKeystoreCertificateAndEndpointRestart() {
  TemporaryDirectory temporary;
  const BridgeIdentity identity{"bridge", std::string(64, 'a'), 0xFFF1, 0x8001};
  std::unique_ptr<BridgeStorage> storage;
  RequireSuccess(BridgeStorage::Open(temporary.Store(), StorageMode::CreateNew, identity, storage),
                 "SDK bridge store creation failed");
  SdkStorageBinding binding;
  RequireSuccess(binding.Init(*storage), "SDK binding initialization failed");
  Require(binding.Init(*storage) == CHIP_ERROR_INCORRECT_STATE,
          "SDK binding admitted two initializations");
  std::array<std::uint8_t, chip::Crypto::kMIN_CSR_Buffer_Size> csr_bytes{};
  chip::MutableByteSpan csr(csr_bytes);
  RequireSuccess(binding.operational_keystore().NewOpKeypairForFabric(1, csr),
                 "SDK CSR creation failed");
  chip::Crypto::P256PublicKey public_key;
  RequireSuccess(chip::Crypto::VerifyCertificateSigningRequest(csr.data(), csr.size(), public_key),
                 "SDK CSR verification failed");
  RequireSuccess(binding.operational_keystore().ActivateOpKeypairForFabric(1, public_key),
                 "SDK operational key activation failed");
  RequireSuccess(binding.operational_keystore().CommitOpKeypairForFabric(1),
                 "SDK operational key persistence failed");
  // This authority exists only in the native test executable and generates its
  // keys at runtime. The server store neither creates a CA nor selects a fabric.
  chip::Credentials::TestOnlyLocalCertificateAuthority authority;
  authority.Init().GenerateNocChain(1, 0x1234, public_key);
  RequireSuccess(authority.GetStatus(), "ephemeral test certificate generation failed");
  RequireSuccess(binding.certificate_store().AddNewTrustedRootCertForFabric(1, authority.GetRcac()),
                 "SDK root certificate admission failed");
  RequireSuccess(binding.certificate_store().AddNewOpCertsForFabric(1, authority.GetNoc(),
                                                                    authority.GetIcac()),
                 "SDK operational certificate admission failed");
  RequireSuccess(binding.certificate_store().CommitOpCertsForFabric(1),
                 "SDK certificate persistence failed");
  BridgeEndpoint endpoint;
  RequireSuccess(storage->Allocate("light", BridgedDeviceType::OnOffLight, endpoint),
                 "light allocation failed");
  Require(endpoint.endpoint == 3, "first light endpoint changed");
  RequireSuccess(storage->Allocate("sensor", BridgedDeviceType::TemperatureSensor, endpoint),
                 "sensor allocation failed");
  Require(endpoint.endpoint == 4, "first sensor endpoint changed");
  RequireSuccess(storage->Remove("light"), "light removal failed");
  RequireSignature(binding, public_key);
  RequireCertificate(binding, CertElement::kRcac, authority.GetRcac());
  RequireCertificate(binding, CertElement::kNoc, authority.GetNoc());
  csr = chip::MutableByteSpan(csr_bytes);
  RequireSuccess(binding.operational_keystore().NewOpKeypairForFabric(2, csr),
                 "pending CSR creation failed");
  Require(binding.operational_keystore().HasPendingOpKeypair(), "pending key was not retained");
  binding.Finish();
  binding.Finish();
  Require(!binding.operational_keystore().HasPendingOpKeypair(),
          "SDK finish retained a pending key");
  storage.reset();
  RequireSuccess(
      BridgeStorage::Open(temporary.Store(), StorageMode::OpenExisting, identity, storage),
      "SDK bridge store restart failed");
  RequireSuccess(binding.Init(*storage), "SDK binding restart failed");
  Require(binding.operational_keystore().HasOpKeypairForFabric(1),
          "restart lost the operational key");
  Require(!binding.operational_keystore().HasOpKeypairForFabric(2),
          "restart persisted an uncommitted key");
  RequireSignature(binding, public_key);
  RequireCertificate(binding, CertElement::kRcac, authority.GetRcac());
  RequireCertificate(binding, CertElement::kNoc, authority.GetNoc());
  RequireSuccess(storage->Allocate("light", BridgedDeviceType::OnOffLight, endpoint),
                 "light re-add failed");
  Require(endpoint.endpoint == 5, "SDK restart reused a tombstoned endpoint");
  RequireSuccess(storage->Lookup("sensor", endpoint), "SDK restart lost the sensor");
  Require(endpoint.endpoint == 4 && endpoint.device_type == BridgedDeviceType::TemperatureSensor,
          "SDK restart changed the sensor endpoint or Device Type");
  RequireSuccess(binding.certificate_store().RemoveOpCertsForFabric(1),
                 "SDK fabric certificate removal failed");
  RequireSuccess(binding.operational_keystore().RemoveOpKeypairForFabric(1),
                 "SDK fabric key removal failed");
  binding.Finish();
  storage.reset();
  RequireSuccess(
      BridgeStorage::Open(temporary.Store(), StorageMode::OpenExisting, identity, storage),
      "SDK fabric removal restart failed");
  // RAII teardown must finish the SDK resources before releasing their delegate.
  {
    SdkStorageBinding restarted;
    RequireSuccess(restarted.Init(*storage), "SDK final binding initialization failed");
    Require(!restarted.operational_keystore().HasOpKeypairForFabric(1),
            "revoked key survived restart");
    Require(!restarted.certificate_store().HasCertificateForFabric(1, CertElement::kNoc),
            "revoked certificate survived restart");
    RequireSuccess(storage->Lookup("light", endpoint), "fabric removal erased endpoint custody");
    Require(endpoint.endpoint == 5, "fabric removal rebound an endpoint");
  }
  storage.reset();
}

} // namespace

int main() {
  if (chip::Platform::MemoryInit() != CHIP_NO_ERROR) return 1;
  int result = 0;
  try {
    TestSdkKeystoreCertificateAndEndpointRestart();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    result = 1;
  }
  chip::Platform::MemoryShutdown();
  return result;
}
