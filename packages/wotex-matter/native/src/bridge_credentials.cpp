#include "wotex_matter/bridge_credentials.hpp"

#include <setup_payload/SetupPayload.h>
#include <cstring>
#include <new>

namespace wotex::matter {
namespace {
bool Bounded(chip::ByteSpan bytes, std::size_t maximum) {
  return !bytes.empty() && bytes.size() <= maximum && bytes.data() != nullptr;
}
// The SDK verifier value is a plain struct; clear it even on generation failure.
struct PrivateVerifier {
  chip::Crypto::Spake2pVerifier value{};
  ~PrivateVerifier() {
    chip::Crypto::ClearSecretData(reinterpret_cast<std::uint8_t *>(&value), sizeof(value));
  }
};
}

CHIP_ERROR SdkBridgeCredentials::Create(std::uint16_t vendor, std::uint16_t product,
                                        const BridgeAttestationMaterial &attestation,
                                        const BridgeCommissioningMaterial &commissioning,
                                        std::unique_ptr<SdkBridgeCredentials> &result) noexcept {
  try {
    std::unique_ptr<SdkBridgeCredentials> owned(new SdkBridgeCredentials);
    const auto error = owned->Init(vendor, product, attestation, commissioning);
    if (error != CHIP_NO_ERROR) return error;
    result = std::move(owned);
    return CHIP_NO_ERROR;
  } catch (const std::bad_alloc &) {
    return CHIP_ERROR_NO_MEMORY;
  }
}

CHIP_ERROR SdkBridgeCredentials::Init(std::uint16_t vendor, std::uint16_t product,
                                      const BridgeAttestationMaterial &attestation,
                                      const BridgeCommissioningMaterial &commissioning) {
  using namespace chip;
  using namespace chip::Crypto;
  if (vendor == 0 || !Bounded(attestation.dac, kMaximumCertificateBytes) ||
      !Bounded(attestation.pai, kMaximumCertificateBytes) ||
      !Bounded(attestation.certification_declaration, kMaximumDeclarationBytes) ||
      attestation.serialized_keypair.size() != P256SerializedKeypair::Capacity() ||
      attestation.serialized_keypair.data() == nullptr ||
      !SetupPayload::IsValidSetupPIN(commissioning.passcode) ||
      commissioning.discriminator > 4095 ||
      commissioning.iterations < kSpake2p_Min_PBKDF_Iterations ||
      commissioning.iterations > kSpake2p_Max_PBKDF_Iterations ||
      !Bounded(commissioning.salt, kSpake2p_Max_PBKDF_Salt_Length) ||
      commissioning.salt.size() < kSpake2p_Min_PBKDF_Salt_Length)
    return CHIP_ERROR_INVALID_ARGUMENT;
  ReturnErrorOnFailure(
      VerifyAttestationCertificateFormat(attestation.dac, AttestationCertType::kDAC));
  ReturnErrorOnFailure(
      VerifyAttestationCertificateFormat(attestation.pai, AttestationCertType::kPAI));
  AttestationCertVidPid dac_identity, pai_identity;
  ReturnErrorOnFailure(ExtractVIDPIDFromX509Cert(attestation.dac, dac_identity));
  ReturnErrorOnFailure(ExtractVIDPIDFromX509Cert(attestation.pai, pai_identity));
  if (!dac_identity.mVendorId.HasValue() || !dac_identity.mProductId.HasValue() ||
      static_cast<std::uint16_t>(dac_identity.mVendorId.Value()) != vendor ||
      dac_identity.mProductId.Value() != product || !pai_identity.mVendorId.HasValue() ||
      static_cast<std::uint16_t>(pai_identity.mVendorId.Value()) != vendor ||
      (pai_identity.mProductId.HasValue() && pai_identity.mProductId.Value() != product))
    return CHIP_ERROR_INVALID_ARGUMENT;
  P256PublicKey public_key;
  ReturnErrorOnFailure(ExtractPubkeyFromX509Cert(attestation.dac, public_key));
  P256SerializedKeypair serialized;
  ReturnErrorOnFailure(serialized.SetLength(attestation.serialized_keypair.size()));
  std::memcpy(serialized.Bytes(), attestation.serialized_keypair.data(), serialized.Length());
  ReturnErrorOnFailure(key_.Deserialize(serialized));
  if (std::memcmp(public_key.ConstBytes(), key_.Pubkey().ConstBytes(), public_key.Length()) != 0)
    return CHIP_ERROR_INVALID_ARGUMENT;
  // Deserialize may import a public/private pair without proving they agree.
  // Sign and verify against the DAC's key before exposing this provider.
  constexpr std::uint8_t challenge[] = "wotex-matter-bridge-key-possession-v1";
  P256ECDSASignature signature;
  ReturnErrorOnFailure(key_.ECDSA_sign_msg(challenge, sizeof(challenge) - 1, signature));
  ReturnErrorOnFailure(
      public_key.ECDSA_validate_msg_signature(challenge, sizeof(challenge) - 1, signature));
  PrivateVerifier generated;
  ReturnErrorOnFailure(generated.value.Generate(commissioning.iterations, commissioning.salt,
                                                commissioning.passcode));
  MutableByteSpan verifier(verifier_.Bytes(), verifier_.Capacity());
  ReturnErrorOnFailure(generated.value.Serialize(verifier));
  ReturnErrorOnFailure(verifier_.SetLength(verifier.size()));
  ReturnErrorOnFailure(salt_.SetLength(commissioning.salt.size()));
  std::memcpy(salt_.Bytes(), commissioning.salt.data(), salt_.Length());
  dac_.assign(attestation.dac.begin(), attestation.dac.end());
  pai_.assign(attestation.pai.begin(), attestation.pai.end());
  declaration_.assign(attestation.certification_declaration.begin(),
                      attestation.certification_declaration.end());
  passcode_ = commissioning.passcode;
  discriminator_ = commissioning.discriminator;
  iterations_ = commissioning.iterations;
  active_ = true;
  return CHIP_NO_ERROR;
}

SdkBridgeCredentials::~SdkBridgeCredentials() { Retire(); }
void SdkBridgeCredentials::Retire() noexcept {
  active_ = false;
  key_.Clear();
  verifier_.Clear();
  salt_.Clear();
  chip::Crypto::ClearSecretData(reinterpret_cast<std::uint8_t *>(&passcode_), sizeof(passcode_));
  iterations_ = 0;
  discriminator_ = 0;
}
CHIP_ERROR SdkBridgeCredentials::Copy(chip::ByteSpan bytes, chip::MutableByteSpan &output) const {
  if (!active_) return CHIP_ERROR_INCORRECT_STATE;
  // The pinned SDK copy helper calls memcpy even for an empty/null source.
  // Empty firmware information is explicit; avoid an invalid pointer argument.
  if (bytes.empty()) {
    output.reduce_size(0);
    return CHIP_NO_ERROR;
  }
  return chip::CopySpanToMutableSpan(bytes, output);
}
CHIP_ERROR SdkBridgeCredentials::GetCertificationDeclaration(chip::MutableByteSpan &output) {
  return Copy(chip::ByteSpan(declaration_.data(), declaration_.size()), output);
}
CHIP_ERROR SdkBridgeCredentials::GetFirmwareInformation(chip::MutableByteSpan &output) {
  return Copy(chip::ByteSpan(), output);
}
CHIP_ERROR SdkBridgeCredentials::GetDeviceAttestationCert(chip::MutableByteSpan &output) {
  return Copy(chip::ByteSpan(dac_.data(), dac_.size()), output);
}
CHIP_ERROR SdkBridgeCredentials::GetProductAttestationIntermediateCert(
    chip::MutableByteSpan &output) {
  return Copy(chip::ByteSpan(pai_.data(), pai_.size()), output);
}
CHIP_ERROR SdkBridgeCredentials::SignWithDeviceAttestationKey(const chip::ByteSpan &message,
                                                              chip::MutableByteSpan &output) {
  if (!active_) return CHIP_ERROR_INCORRECT_STATE;
  if (!Bounded(message, kMaximumSigningBytes)) return CHIP_ERROR_INVALID_ARGUMENT;
  if (output.size() < chip::Crypto::kP256_ECDSA_Signature_Length_Raw)
    return CHIP_ERROR_BUFFER_TOO_SMALL;
  chip::Crypto::P256ECDSASignature signature;
  ReturnErrorOnFailure(key_.ECDSA_sign_msg(message.data(), message.size(), signature));
  return chip::CopySpanToMutableSpan(chip::ByteSpan(signature.ConstBytes(), signature.Length()),
                                     output);
}
CHIP_ERROR SdkBridgeCredentials::GetSetupDiscriminator(std::uint16_t &value) {
  if (!active_) return CHIP_ERROR_INCORRECT_STATE;
  value = discriminator_;
  return CHIP_NO_ERROR;
}
CHIP_ERROR SdkBridgeCredentials::SetSetupDiscriminator(std::uint16_t) {
  return active_ ? CHIP_ERROR_NOT_IMPLEMENTED : CHIP_ERROR_INCORRECT_STATE;
}
CHIP_ERROR SdkBridgeCredentials::GetSpake2pIterationCount(std::uint32_t &value) {
  if (!active_) return CHIP_ERROR_INCORRECT_STATE;
  value = iterations_;
  return CHIP_NO_ERROR;
}
CHIP_ERROR SdkBridgeCredentials::GetSpake2pSalt(chip::MutableByteSpan &output) {
  return Copy(salt_.Span(), output);
}
CHIP_ERROR SdkBridgeCredentials::GetSpake2pVerifier(chip::MutableByteSpan &output,
                                                    std::size_t &length) {
  ReturnErrorOnFailure(Copy(verifier_.Span(), output));
  length = verifier_.Length();
  return CHIP_NO_ERROR;
}
CHIP_ERROR SdkBridgeCredentials::GetSetupPasscode(std::uint32_t &value) {
  if (!active_) return CHIP_ERROR_INCORRECT_STATE;
  value = passcode_;
  return CHIP_NO_ERROR;
}
CHIP_ERROR SdkBridgeCredentials::SetSetupPasscode(std::uint32_t) {
  return active_ ? CHIP_ERROR_NOT_IMPLEMENTED : CHIP_ERROR_INCORRECT_STATE;
}

} // namespace wotex::matter
