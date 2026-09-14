#ifndef WOTEX_MATTER_AUTHORITY_HPP
#define WOTEX_MATTER_AUTHORITY_HPP

#include "wotex_matter/storage.hpp"

#include <controller/OperationalCredentialsDelegate.h>
#include <crypto/CHIPCryptoPAL.h>

#include <array>
#include <cstdint>
#include <vector>

namespace wotex::matter {

class RootAuthority final
    : public chip::Controller::OperationalCredentialsDelegate {
 public:
  CHIP_ERROR Init(DurableStorage &storage, AuthorityMode mode,
                  const ControllerIdentity &identity);

  CHIP_ERROR GenerateControllerChain(
      const chip::Crypto::P256PublicKey &controller_public_key,
      std::vector<std::uint8_t> &noc, std::vector<std::uint8_t> &rcac);

  chip::ByteSpan root_certificate() const;
  const chip::Crypto::P256PublicKey &root_public_key() const;
  chip::Crypto::IdentityProtectionKeySpan ipk();

  CHIP_ERROR GenerateNOCChain(
      const chip::ByteSpan &csr_elements, const chip::ByteSpan &csr_nonce,
      const chip::ByteSpan &attestation_signature,
      const chip::ByteSpan &attestation_challenge, const chip::ByteSpan &dac,
      const chip::ByteSpan &pai,
      chip::Callback::Callback<chip::Controller::OnNOCChainGeneration>
          *on_completion) override;

  void SetNodeIdForNextNOCRequest(chip::NodeId node_id) override;
  void SetFabricIdForNextNOCRequest(chip::FabricId fabric_id) override;

 private:
  CHIP_ERROR Create(DurableStorage &storage);
  CHIP_ERROR Load(DurableStorage &storage);
  CHIP_ERROR IssueNoc(const chip::Crypto::P256PublicKey &public_key,
                      chip::NodeId node_id, chip::FabricId fabric_id,
                      std::vector<std::uint8_t> &noc);

  DurableStorage *storage_{nullptr};
  ControllerIdentity identity_;
  chip::Crypto::P256Keypair root_key_;
  std::vector<std::uint8_t> root_certificate_;
  std::array<std::uint8_t,
             chip::Crypto::CHIP_CRYPTO_SYMMETRIC_KEY_LENGTH_BYTES>
      ipk_{};
  chip::NodeId next_node_id_{chip::kUndefinedNodeId};
  chip::FabricId next_fabric_id_{chip::kUndefinedFabricId};
  bool node_requested_{false};
  bool fabric_requested_{false};
  bool initialized_{false};
  std::vector<std::uint8_t> callback_noc_;
};

} // namespace wotex::matter

#endif
