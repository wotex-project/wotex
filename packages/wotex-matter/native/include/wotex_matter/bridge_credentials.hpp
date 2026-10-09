#ifndef WOTEX_MATTER_BRIDGE_CREDENTIALS_HPP
#define WOTEX_MATTER_BRIDGE_CREDENTIALS_HPP

#include <credentials/DeviceAttestationCredsProvider.h>
#include <crypto/CHIPCryptoPAL.h>
#include <platform/CommissionableDataProvider.h>

#include <memory>
#include <vector>

namespace wotex::matter {

// Borrowed only during Create. The caller owns and clears the input key and
// passcode; this owner retains its own SDK key and bounded PASE verifier.
// No default, example credential, random salt or provider installation occurs.
struct BridgeAttestationMaterial {
  chip::ByteSpan dac;
  chip::ByteSpan pai;
  chip::ByteSpan certification_declaration;
  chip::ByteSpan serialized_keypair;
};
struct BridgeCommissioningMaterial {
  std::uint32_t passcode;
  std::uint16_t discriminator;
  std::uint32_t iterations;
  chip::ByteSpan salt;
};

// One explicitly configured native lifetime. The SDK owner installs these two
// provider interfaces before platform/server startup and retires their global
// references before destruction. Calls are serialized by the SDK stack owner.
// Format, VID/PID and key possession checks do not establish a trusted PAA chain,
// Certification Declaration validity, certification or peer interoperability.
class SdkBridgeCredentials final : public chip::Credentials::DeviceAttestationCredentialsProvider,
                                   public chip::DeviceLayer::CommissionableDataProvider {
 public:
  static constexpr std::size_t kMaximumCertificateBytes = 600;
  static constexpr std::size_t kMaximumDeclarationBytes = 4096;
  static constexpr std::size_t kMaximumSigningBytes = 4096;
  static CHIP_ERROR Create(std::uint16_t vendor, std::uint16_t product,
                           const BridgeAttestationMaterial &attestation,
                           const BridgeCommissioningMaterial &commissioning,
                           std::unique_ptr<SdkBridgeCredentials> &result) noexcept;
  ~SdkBridgeCredentials() override;
  SdkBridgeCredentials(const SdkBridgeCredentials &) = delete;
  SdkBridgeCredentials &operator=(const SdkBridgeCredentials &) = delete;

  // Idempotently denies every getter/signing call and clears retained secrets.
  // No SDK caller may concurrently access or retain a reference during retirement.
  void Retire() noexcept;
  CHIP_ERROR GetCertificationDeclaration(chip::MutableByteSpan &output) override;
  CHIP_ERROR GetFirmwareInformation(chip::MutableByteSpan &output) override;
  CHIP_ERROR GetDeviceAttestationCert(chip::MutableByteSpan &output) override;
  CHIP_ERROR GetProductAttestationIntermediateCert(chip::MutableByteSpan &output) override;
  CHIP_ERROR SignWithDeviceAttestationKey(const chip::ByteSpan &message,
                                          chip::MutableByteSpan &output) override;
  CHIP_ERROR GetSetupDiscriminator(std::uint16_t &value) override;
  CHIP_ERROR SetSetupDiscriminator(std::uint16_t value) override;
  CHIP_ERROR GetSpake2pIterationCount(std::uint32_t &value) override;
  CHIP_ERROR GetSpake2pSalt(chip::MutableByteSpan &output) override;
  CHIP_ERROR GetSpake2pVerifier(chip::MutableByteSpan &output, std::size_t &length) override;
  CHIP_ERROR GetSetupPasscode(std::uint32_t &value) override;
  CHIP_ERROR SetSetupPasscode(std::uint32_t value) override;

 private:
  SdkBridgeCredentials() = default;
  CHIP_ERROR Init(std::uint16_t vendor, std::uint16_t product,
                  const BridgeAttestationMaterial &attestation,
                  const BridgeCommissioningMaterial &commissioning);
  CHIP_ERROR Copy(chip::ByteSpan bytes, chip::MutableByteSpan &output) const;
  std::vector<std::uint8_t> dac_, pai_, declaration_;
  chip::Crypto::P256Keypair key_;
  chip::Crypto::SensitiveDataBuffer<chip::Crypto::kSpake2p_VerifierSerialized_Length> verifier_;
  chip::Crypto::SensitiveDataBuffer<chip::Crypto::kSpake2p_Max_PBKDF_Salt_Length> salt_;
  std::uint32_t passcode_{0}, iterations_{0};
  std::uint16_t discriminator_{0};
  bool active_{false};
};

} // namespace wotex::matter
#endif
