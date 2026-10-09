#include "sdk_bridge_credentials_test.hpp"

#include <credentials/examples/DeviceAttestationCredsExample.h>
#include <credentials/examples/ExampleDACs.h>
#include <setup_payload/SetupPayload.h>
#include <array>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <new>
#include <stdexcept>

#ifndef WOTEX_MATTER_BRIDGE_TESTING
#error Explicit development credentials require a separate test build.
#endif

namespace {
std::atomic<int> allocation_failure{-1};
}
// Fault injection belongs only to this test executable. Fail actual factory
// allocations, never retain a production hook or change an SDK allocator.
void *operator new(std::size_t size) {
  if (allocation_failure.load() >= 0 && allocation_failure.fetch_sub(1) == 0) {
    allocation_failure = -1;
    throw std::bad_alloc();
  }
  if (auto *memory = std::malloc(size == 0 ? 1 : size)) return memory;
  throw std::bad_alloc();
}
void *operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void *memory) noexcept { std::free(memory); }
void operator delete[](void *memory) noexcept { std::free(memory); }
void operator delete(void *memory, std::size_t) noexcept { std::free(memory); }
void operator delete[](void *memory, std::size_t) noexcept { std::free(memory); }

namespace wotex::matter::testing {
namespace {
using namespace chip;
using namespace chip::Crypto;
void Require(bool condition, const char *stage) {
  if (!condition) throw std::runtime_error(stage);
}
struct Fixture {
  std::array<std::uint8_t, SdkBridgeCredentials::kMaximumCertificateBytes> dac{}, pai{};
  std::array<std::uint8_t, SdkBridgeCredentials::kMaximumDeclarationBytes> declaration{};
  std::array<std::uint8_t, kSpake2p_Min_PBKDF_Salt_Length> salt{};
  P256SerializedKeypair key;
  BridgeAttestationMaterial attestation;
  BridgeCommissioningMaterial commissioning{};

  Fixture() {
    auto *example = Credentials::Examples::GetExampleDACProvider();
    MutableByteSpan dac_span(dac), pai_span(pai), declaration_span(declaration);
    Require(example->GetDeviceAttestationCert(dac_span) == CHIP_NO_ERROR &&
                example->GetProductAttestationIntermediateCert(pai_span) == CHIP_NO_ERROR &&
                example->GetCertificationDeclaration(declaration_span) == CHIP_NO_ERROR,
            "explicit test attestation material");
    Require(key.SetLength(key.Capacity()) == CHIP_NO_ERROR &&
                DevelopmentCerts::kDacPublicKey.size() == kP256_PublicKey_Length &&
                DevelopmentCerts::kDacPrivateKey.size() == kP256_PrivateKey_Length,
            "explicit test key shape");
    std::memcpy(key.Bytes(), DevelopmentCerts::kDacPublicKey.data(), kP256_PublicKey_Length);
    std::memcpy(key.Bytes() + kP256_PublicKey_Length, DevelopmentCerts::kDacPrivateKey.data(),
                kP256_PrivateKey_Length);
    attestation = {dac_span, pai_span, declaration_span, key.Span()};
    for (unsigned attempt = 0; attempt < 32; ++attempt) {
      Require(DRBG_get_bytes(reinterpret_cast<std::uint8_t *>(&commissioning.passcode),
                             sizeof(commissioning.passcode)) == CHIP_NO_ERROR,
              "explicit test passcode");
      commissioning.passcode = commissioning.passcode % 99999998U + 1U;
      if (SetupPayload::IsValidSetupPIN(commissioning.passcode)) break;
    }
    Require(SetupPayload::IsValidSetupPIN(commissioning.passcode) &&
                DRBG_get_bytes(salt.data(), salt.size()) == CHIP_NO_ERROR,
            "explicit test commissioning material");
    commissioning.discriminator = 3840;
    commissioning.iterations = kSpake2p_Min_PBKDF_Iterations;
    commissioning.salt = ByteSpan(salt);
  }
  ~Fixture() {
    ClearSecretData(reinterpret_cast<std::uint8_t *>(&commissioning.passcode),
                    sizeof(commissioning.passcode));
  }
};
}

std::unique_ptr<SdkBridgeCredentials> CreateTestCredentials() {
  Fixture fixture;
  std::unique_ptr<SdkBridgeCredentials> result;
  Require(SdkBridgeCredentials::Create(0xFFF1, 0x8001, fixture.attestation, fixture.commissioning,
                                       result) == CHIP_NO_ERROR,
          "explicit credential ownership");
  return result;
}

void TestCredentials() {
  Fixture fixture;
  auto *original_dac = Credentials::GetDeviceAttestationCredentialsProvider();
  auto *original_commissioning = DeviceLayer::GetCommissionableDataProvider();
  std::unique_ptr<SdkBridgeCredentials> owner;
  Require(SdkBridgeCredentials::Create(0xFFF1, 0x8001, fixture.attestation, fixture.commissioning,
                                       owner) == CHIP_NO_ERROR &&
              Credentials::GetDeviceAttestationCredentialsProvider() == original_dac &&
              DeviceLayer::GetCommissionableDataProvider() == original_commissioning,
          "credential creation installs no provider");
  auto *unchanged = owner.get();
  unsigned failures = 0;
  bool completed = false;
  for (int index = 0; index < 128; ++index) {
    allocation_failure = index;
    const auto status = SdkBridgeCredentials::Create(0xFFF1, 0x8001, fixture.attestation,
                                                     fixture.commissioning, owner);
    allocation_failure = -1;
    if (status == CHIP_NO_ERROR) {
      completed = true;
      unchanged = owner.get();
      break;
    }
    ++failures;
    Require(status == CHIP_ERROR_NO_MEMORY && owner.get() == unchanged,
            "real allocation refusal preserves credential owner");
  }
  Require(completed && failures > 0, "credential factory allocation cutpoints");
  const auto refuse = [&](const BridgeAttestationMaterial &attestation,
                          const BridgeCommissioningMaterial &commissioning,
                          std::uint16_t vendor = 0xFFF1, std::uint16_t product = 0x8001) {
    Require(SdkBridgeCredentials::Create(vendor, product, attestation, commissioning, owner) !=
                    CHIP_NO_ERROR &&
                owner.get() == unchanged,
            "credential refusal preserves owner");
  };
  refuse(fixture.attestation, fixture.commissioning, 0);
  refuse(fixture.attestation, fixture.commissioning, 0xFFF2);
  refuse(fixture.attestation, fixture.commissioning, 0xFFF1, 0x8002);
  for (unsigned field = 0; field < 4; ++field) {
    auto missing = fixture.attestation;
    if (field == 0) missing.dac = ByteSpan();
    if (field == 1) missing.pai = ByteSpan();
    if (field == 2) missing.certification_declaration = ByteSpan();
    if (field == 3) missing.serialized_keypair = ByteSpan();
    refuse(missing, fixture.commissioning);
  }
  auto malformed = fixture.attestation;
  malformed.dac = fixture.attestation.pai;
  refuse(malformed, fixture.commissioning);
  malformed = fixture.attestation;
  malformed.pai = fixture.attestation.dac;
  refuse(malformed, fixture.commissioning);
  malformed = fixture.attestation;
  malformed.dac = ByteSpan(fixture.dac.data(), fixture.attestation.dac.size() - 1);
  refuse(malformed, fixture.commissioning);
  std::array<std::uint8_t, SdkBridgeCredentials::kMaximumDeclarationBytes + 1> oversized{};
  malformed = fixture.attestation;
  malformed.certification_declaration = ByteSpan(oversized);
  refuse(malformed, fixture.commissioning);
  malformed = fixture.attestation;
  malformed.dac = ByteSpan(oversized.data(), SdkBridgeCredentials::kMaximumCertificateBytes + 1);
  refuse(malformed, fixture.commissioning);
  malformed = fixture.attestation;
  malformed.pai = malformed.dac;
  refuse(malformed, fixture.commissioning);
  P256SerializedKeypair other;
  P256Keypair other_key;
  Require(other_key.Initialize(ECPKeyTarget::ECDSA) == CHIP_NO_ERROR &&
              other_key.Serialize(other) == CHIP_NO_ERROR,
          "independent test key");
  malformed = fixture.attestation;
  malformed.serialized_keypair = other.Span();
  refuse(malformed, fixture.commissioning);
  // Keep the DAC public key but supply an unrelated valid private key. The
  // imported public/private shape alone must not establish key possession.
  std::memcpy(other.Bytes(), fixture.key.ConstBytes(), kP256_PublicKey_Length);
  refuse(malformed, fixture.commissioning);
  malformed.serialized_keypair = ByteSpan(fixture.key.ConstBytes(), fixture.key.Length() - 1);
  refuse(malformed, fixture.commissioning);
  for (std::uint32_t pin : {0U, 11111111U, 12345678U, 87654321U, 100000000U}) {
    auto invalid = fixture.commissioning;
    invalid.passcode = pin;
    refuse(fixture.attestation, invalid);
  }
  for (std::uint32_t count : {0U, 999U, 100001U}) {
    auto invalid = fixture.commissioning;
    invalid.iterations = count;
    refuse(fixture.attestation, invalid);
  }
  auto invalid = fixture.commissioning;
  invalid.discriminator = 4096;
  refuse(fixture.attestation, invalid);
  invalid = fixture.commissioning;
  for (std::size_t length : {0U, 15U, 33U}) {
    invalid.salt = ByteSpan(oversized.data(), length);
    refuse(fixture.attestation, invalid);
  }
  std::array<std::uint8_t, kSpake2p_Max_PBKDF_Salt_Length> maximum_salt{};
  auto maximum_commissioning = fixture.commissioning;
  maximum_commissioning.iterations = kSpake2p_Max_PBKDF_Iterations;
  maximum_commissioning.discriminator = 4095;
  maximum_commissioning.salt = ByteSpan(maximum_salt);
  auto maximum_attestation = fixture.attestation;
  maximum_attestation.certification_declaration = ByteSpan(fixture.declaration);
  std::unique_ptr<SdkBridgeCredentials> maximum_owner;
  Require(SdkBridgeCredentials::Create(0xFFF1, 0x8001, maximum_attestation, maximum_commissioning,
                                       maximum_owner) == CHIP_NO_ERROR,
          "maximum explicit credential bounds");
  std::uint16_t discriminator = 0;
  std::uint32_t count = 0, pin = 0;
  Require(owner->GetSetupDiscriminator(discriminator) == CHIP_NO_ERROR && discriminator == 3840 &&
              owner->GetSpake2pIterationCount(count) == CHIP_NO_ERROR && count == 1000 &&
              owner->GetSetupPasscode(pin) == CHIP_NO_ERROR &&
              pin == fixture.commissioning.passcode &&
              owner->SetSetupDiscriminator(0) == CHIP_ERROR_NOT_IMPLEMENTED &&
              owner->SetSetupPasscode(0) == CHIP_ERROR_NOT_IMPLEMENTED,
          "explicit immutable commissioning values");
  Spake2pVerifier expected{};
  Require(expected.Generate(count, fixture.commissioning.salt, pin) == CHIP_NO_ERROR,
          "independent expected verifier");
  std::array<std::uint8_t, kSpake2p_VerifierSerialized_Length> expected_bytes{}, actual_bytes{};
  MutableByteSpan expected_span(expected_bytes), actual_span(actual_bytes);
  std::size_t length = 999;
  Require(expected.Serialize(expected_span) == CHIP_NO_ERROR &&
              owner->GetSpake2pVerifier(actual_span, length) == CHIP_NO_ERROR &&
              length == actual_bytes.size() && actual_bytes == expected_bytes,
          "explicit verifier derivation");
  ClearSecretData(reinterpret_cast<std::uint8_t *>(&expected), sizeof(expected));
  ClearSecretData(expected_bytes.data(), expected_bytes.size());
  ClearSecretData(actual_bytes.data(), actual_bytes.size());
  ClearSecretData(reinterpret_cast<std::uint8_t *>(&pin), sizeof(pin));
  std::array<std::uint8_t, 1> sentinel{0xA5};
  MutableByteSpan tiny(sentinel);
  length = 999;
  Require(owner->GetSpake2pVerifier(tiny, length) == CHIP_ERROR_BUFFER_TOO_SMALL &&
              tiny.size() == 1 && sentinel[0] == 0xA5 && length == 999,
          "verifier refusal preserves caller output");
  std::array<std::uint8_t, 64> signature_bytes{};
  constexpr std::uint8_t message[] = "explicit bridge signing test";
  MutableByteSpan signature_span(signature_bytes);
  Require(owner->SignWithDeviceAttestationKey(ByteSpan(message), signature_span) == CHIP_NO_ERROR,
          "owned attestation signing");
  P256PublicKey public_key;
  P256ECDSASignature signature;
  Require(ExtractPubkeyFromX509Cert(fixture.attestation.dac, public_key) == CHIP_NO_ERROR &&
              signature.SetLength(signature_span.size()) == CHIP_NO_ERROR,
          "signature verification shape");
  std::memcpy(signature.Bytes(), signature_span.data(), signature_span.size());
  Require(
      public_key.ECDSA_validate_msg_signature(message, sizeof(message), signature) == CHIP_NO_ERROR,
      "signature verifies with DAC");
  Require(
      owner->SignWithDeviceAttestationKey(ByteSpan(message), tiny) == CHIP_ERROR_BUFFER_TOO_SMALL &&
          owner->SignWithDeviceAttestationKey(ByteSpan(), signature_span) ==
              CHIP_ERROR_INVALID_ARGUMENT &&
          owner->SignWithDeviceAttestationKey(ByteSpan(oversized), signature_span) ==
              CHIP_ERROR_INVALID_ARGUMENT,
      "signing bounds");
  std::array<std::uint8_t, SdkBridgeCredentials::kMaximumDeclarationBytes> bytes{};
  MutableByteSpan span(bytes);
  Require(owner->GetDeviceAttestationCert(span) == CHIP_NO_ERROR &&
              span.data_equal(fixture.attestation.dac),
          "owned DAC bytes");
  span = MutableByteSpan(bytes);
  Require(owner->GetProductAttestationIntermediateCert(span) == CHIP_NO_ERROR &&
              span.data_equal(fixture.attestation.pai),
          "owned PAI bytes");
  span = MutableByteSpan(bytes);
  Require(owner->GetCertificationDeclaration(span) == CHIP_NO_ERROR &&
              span.data_equal(fixture.attestation.certification_declaration),
          "explicit declaration bytes");
  span = MutableByteSpan(bytes);
  Require(
      owner->GetSpake2pSalt(span) == CHIP_NO_ERROR && span.data_equal(fixture.commissioning.salt),
      "explicit salt bytes");
  Require(owner->GetFirmwareInformation(span) == CHIP_NO_ERROR && span.empty(),
          "empty firmware information");
  MutableByteSpan empty;
  Require(owner->GetFirmwareInformation(empty) == CHIP_NO_ERROR && empty.empty(),
          "empty firmware information without storage");
  // Owned material survives complete destruction of its original borrowed bytes.
  const auto retained_dac = fixture.dac, retained_pai = fixture.pai;
  const auto retained_declaration = fixture.declaration;
  const auto retained_salt = fixture.salt;
  fixture.key.Clear();
  fixture.dac.fill(0);
  fixture.pai.fill(0);
  fixture.declaration.fill(0);
  fixture.salt.fill(0);
  signature_span = MutableByteSpan(signature_bytes);
  Require(owner->SignWithDeviceAttestationKey(ByteSpan(message), signature_span) == CHIP_NO_ERROR,
          "input key no longer borrowed");
  span = MutableByteSpan(bytes);
  Require(owner->GetDeviceAttestationCert(span) == CHIP_NO_ERROR &&
              span.data_equal(ByteSpan(retained_dac.data(), fixture.attestation.dac.size())),
          "input DAC no longer borrowed");
  span = MutableByteSpan(bytes);
  Require(owner->GetProductAttestationIntermediateCert(span) == CHIP_NO_ERROR &&
              span.data_equal(ByteSpan(retained_pai.data(), fixture.attestation.pai.size())),
          "input PAI no longer borrowed");
  span = MutableByteSpan(bytes);
  Require(owner->GetCertificationDeclaration(span) == CHIP_NO_ERROR &&
              span.data_equal(ByteSpan(retained_declaration.data(),
                                       fixture.attestation.certification_declaration.size())),
          "input declaration no longer borrowed");
  span = MutableByteSpan(bytes);
  Require(owner->GetSpake2pSalt(span) == CHIP_NO_ERROR && span.data_equal(ByteSpan(retained_salt)),
          "input salt no longer borrowed");
  owner->Retire();
  owner->Retire();
  discriminator = 99;
  count = pin = 99;
  tiny = MutableByteSpan(sentinel);
  Require(owner->GetSetupDiscriminator(discriminator) == CHIP_ERROR_INCORRECT_STATE &&
              discriminator == 99 &&
              owner->GetSpake2pIterationCount(count) == CHIP_ERROR_INCORRECT_STATE && count == 99 &&
              owner->GetSetupPasscode(pin) == CHIP_ERROR_INCORRECT_STATE && pin == 99 &&
              owner->SetSetupDiscriminator(0) == CHIP_ERROR_INCORRECT_STATE &&
              owner->SetSetupPasscode(0) == CHIP_ERROR_INCORRECT_STATE &&
              owner->GetDeviceAttestationCert(tiny) == CHIP_ERROR_INCORRECT_STATE &&
              owner->GetProductAttestationIntermediateCert(tiny) == CHIP_ERROR_INCORRECT_STATE &&
              owner->GetCertificationDeclaration(tiny) == CHIP_ERROR_INCORRECT_STATE &&
              owner->GetFirmwareInformation(tiny) == CHIP_ERROR_INCORRECT_STATE &&
              owner->GetSpake2pSalt(tiny) == CHIP_ERROR_INCORRECT_STATE &&
              owner->GetSpake2pVerifier(tiny, length) == CHIP_ERROR_INCORRECT_STATE &&
              length == 999 &&
              owner->SignWithDeviceAttestationKey(ByteSpan(message), tiny) ==
                  CHIP_ERROR_INCORRECT_STATE &&
              tiny.size() == 1 && sentinel[0] == 0xA5,
          "retired credential refusal preserves outputs");
  std::cout << "explicit bridge credential ownership and refusal passed\n";
}
} // namespace wotex::matter::testing
