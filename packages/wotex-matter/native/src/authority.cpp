#include "wotex_matter/authority.hpp"

#include <credentials/CHIPCert.h>
#include <lib/core/TLV.h>
#include <lib/support/CodeUtils.h>

#include <algorithm>
#include <cstring>
#include <limits>

namespace wotex::matter {
namespace {

constexpr char kRootKey[] = "wotex/authority/root-key";
constexpr char kRootCertificate[] = "wotex/authority/root-cert";
constexpr char kIpk[] = "wotex/authority/ipk";
constexpr std::uint32_t kValidityStart = 662688000;

CHIP_ERROR ReadValue(DurableStorage &storage, const char *key,
                     std::uint8_t *buffer, std::uint16_t expected_size) {
  std::uint16_t size = expected_size;
  ReturnErrorOnFailure(storage.SyncGetKeyValue(key, buffer, size));
  VerifyOrReturnError(size == expected_size, CHIP_ERROR_INVALID_ARGUMENT);
  return CHIP_NO_ERROR;
}

CHIP_ERROR ReadVector(DurableStorage &storage, const char *key,
                      std::vector<std::uint8_t> &value,
                      std::size_t maximum_size) {
  value.assign(maximum_size, 0);
  std::uint16_t size = static_cast<std::uint16_t>(value.size());
  ReturnErrorOnFailure(storage.SyncGetKeyValue(key, value.data(), size));
  VerifyOrReturnError(size > 0 && size <= maximum_size,
                      CHIP_ERROR_INVALID_ARGUMENT);
  value.resize(size);
  return CHIP_NO_ERROR;
}

CHIP_ERROR WriteValue(DurableStorage &storage, const char *key,
                      chip::ByteSpan value) {
  VerifyOrReturnError(value.size() > 0 &&
                          value.size() <= std::numeric_limits<std::uint16_t>::max(),
                      CHIP_ERROR_INVALID_ARGUMENT);
  return storage.SyncSetKeyValue(key, value.data(),
                                 static_cast<std::uint16_t>(value.size()));
}

CHIP_ERROR RandomPositive(std::uint64_t &value) {
  ReturnErrorOnFailure(chip::Crypto::DRBG_get_bytes(
      reinterpret_cast<std::uint8_t *>(&value), sizeof(value)));
  value &= static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());
  VerifyOrReturnError(value > 0, CHIP_ERROR_INTERNAL);
  return CHIP_NO_ERROR;
}

} // namespace

CHIP_ERROR RootAuthority::Init(DurableStorage &storage, AuthorityMode mode,
                               const ControllerIdentity &identity) {
  VerifyOrReturnError(!initialized_, CHIP_ERROR_INCORRECT_STATE);
  storage_ = &storage;
  identity_ = identity;
  CHIP_ERROR error =
      mode == AuthorityMode::GenerateRoot ? Create(storage) : Load(storage);
  if (error != CHIP_NO_ERROR) {
    storage_ = nullptr;
    return error;
  }
  initialized_ = true;
  return CHIP_NO_ERROR;
}

CHIP_ERROR RootAuthority::Create(DurableStorage &storage) {
  std::array<std::uint8_t, 1> existing{};
  for (const char *key : {kRootKey, kRootCertificate, kIpk}) {
    std::uint16_t size = static_cast<std::uint16_t>(existing.size());
    const CHIP_ERROR error = storage.SyncGetKeyValue(key, existing.data(), size);
    VerifyOrReturnError(
        error == CHIP_ERROR_PERSISTED_STORAGE_VALUE_NOT_FOUND,
        CHIP_ERROR_INCORRECT_STATE);
  }

  ReturnErrorOnFailure(
      root_key_.Initialize(chip::Crypto::ECPKeyTarget::ECDSA));
  chip::Crypto::P256SerializedKeypair serialized;
  ReturnErrorOnFailure(root_key_.Serialize(serialized));

  std::uint64_t root_id = 0;
  std::uint64_t serial = 0;
  ReturnErrorOnFailure(RandomPositive(root_id));
  ReturnErrorOnFailure(RandomPositive(serial));

  chip::Credentials::ChipDN root_dn;
  ReturnErrorOnFailure(root_dn.AddAttribute_MatterRCACId(root_id));
  ReturnErrorOnFailure(root_dn.AddAttribute_MatterFabricId(identity_.fabric_id));
  chip::Credentials::X509CertRequestParams request{
      static_cast<std::int64_t>(serial), kValidityStart,
      chip::Credentials::kNullCertTime, root_dn, root_dn};

  root_certificate_.assign(chip::Credentials::kMaxDERCertLength, 0);
  chip::MutableByteSpan certificate(root_certificate_.data(),
                                    root_certificate_.size());
  ReturnErrorOnFailure(
      chip::Credentials::NewRootX509Cert(request, root_key_, certificate));
  root_certificate_.resize(certificate.size());
  ReturnErrorOnFailure(chip::Crypto::DRBG_get_bytes(ipk_.data(), ipk_.size()));

  ReturnErrorOnFailure(WriteValue(
      storage, kRootKey, chip::ByteSpan(serialized.Bytes(), serialized.Length())));
  ReturnErrorOnFailure(WriteValue(storage, kRootCertificate,
                                  chip::ByteSpan(root_certificate_.data(),
                                                 root_certificate_.size())));
  ReturnErrorOnFailure(
      WriteValue(storage, kIpk, chip::ByteSpan(ipk_.data(), ipk_.size())));
  return CHIP_NO_ERROR;
}

CHIP_ERROR RootAuthority::Load(DurableStorage &storage) {
  chip::Crypto::P256SerializedKeypair serialized;
  std::uint16_t serialized_size =
      static_cast<std::uint16_t>(serialized.Capacity());
  ReturnErrorOnFailure(storage.SyncGetKeyValue(
      kRootKey, serialized.Bytes(), serialized_size));
  ReturnErrorOnFailure(serialized.SetLength(serialized_size));
  ReturnErrorOnFailure(root_key_.Deserialize(serialized));

  ReturnErrorOnFailure(ReadVector(storage, kRootCertificate,
                                  root_certificate_,
                                  chip::Credentials::kMaxDERCertLength));
  ReturnErrorOnFailure(ReadValue(storage, kIpk, ipk_.data(),
                                 static_cast<std::uint16_t>(ipk_.size())));

  chip::Crypto::P256PublicKey certificate_key;
  ReturnErrorOnFailure(chip::Crypto::ExtractPubkeyFromX509Cert(
      chip::ByteSpan(root_certificate_.data(), root_certificate_.size()),
      certificate_key));
  VerifyOrReturnError(
      std::memcmp(certificate_key.ConstBytes(), root_key_.Pubkey().ConstBytes(),
                  certificate_key.Length()) == 0,
      CHIP_ERROR_INVALID_ARGUMENT);
  return CHIP_NO_ERROR;
}

CHIP_ERROR RootAuthority::IssueNoc(
    const chip::Crypto::P256PublicKey &public_key, chip::NodeId node_id,
    chip::FabricId fabric_id, std::vector<std::uint8_t> &noc) {
  VerifyOrReturnError(initialized_ && fabric_id == identity_.fabric_id &&
                          chip::IsOperationalNodeId(node_id),
                      CHIP_ERROR_INVALID_ARGUMENT);

  chip::Credentials::ChipDN issuer_dn;
  ReturnErrorOnFailure(chip::Credentials::ExtractSubjectDNFromX509Cert(
      chip::ByteSpan(root_certificate_.data(), root_certificate_.size()),
      issuer_dn));
  chip::Credentials::ChipDN noc_dn;
  ReturnErrorOnFailure(noc_dn.AddAttribute_MatterFabricId(fabric_id));
  ReturnErrorOnFailure(noc_dn.AddAttribute_MatterNodeId(node_id));
  std::uint64_t serial = 0;
  ReturnErrorOnFailure(RandomPositive(serial));
  chip::Credentials::X509CertRequestParams request{
      static_cast<std::int64_t>(serial), kValidityStart,
      chip::Credentials::kNullCertTime, noc_dn, issuer_dn};

  noc.assign(chip::Credentials::kMaxDERCertLength, 0);
  chip::MutableByteSpan output(noc.data(), noc.size());
  ReturnErrorOnFailure(chip::Credentials::NewNodeOperationalX509Cert(
      request, public_key, root_key_, output));
  noc.resize(output.size());
  return CHIP_NO_ERROR;
}

CHIP_ERROR RootAuthority::GenerateControllerChain(
    const chip::Crypto::P256PublicKey &controller_public_key,
    std::vector<std::uint8_t> &noc, std::vector<std::uint8_t> &rcac) {
  ReturnErrorOnFailure(IssueNoc(controller_public_key,
                                identity_.controller_node_id,
                                identity_.fabric_id, noc));
  rcac = root_certificate_;
  return CHIP_NO_ERROR;
}

chip::ByteSpan RootAuthority::root_certificate() const {
  return chip::ByteSpan(root_certificate_.data(), root_certificate_.size());
}

const chip::Crypto::P256PublicKey &RootAuthority::root_public_key() const {
  return root_key_.Pubkey();
}

chip::Crypto::IdentityProtectionKeySpan RootAuthority::ipk() {
  return chip::Crypto::IdentityProtectionKeySpan(ipk_.data());
}

void RootAuthority::SetNodeIdForNextNOCRequest(chip::NodeId node_id) {
  next_node_id_ = node_id;
  node_requested_ = true;
}

void RootAuthority::SetFabricIdForNextNOCRequest(chip::FabricId fabric_id) {
  next_fabric_id_ = fabric_id;
  fabric_requested_ = true;
}

CHIP_ERROR RootAuthority::GenerateNOCChain(
    const chip::ByteSpan &csr_elements, const chip::ByteSpan &csr_nonce,
    const chip::ByteSpan &attestation_signature,
    const chip::ByteSpan &attestation_challenge, const chip::ByteSpan &dac,
    const chip::ByteSpan &pai,
    chip::Callback::Callback<chip::Controller::OnNOCChainGeneration>
        *on_completion) {
  (void) pai;
  VerifyOrReturnError(initialized_ && node_requested_ && fabric_requested_ &&
                          next_fabric_id_ == identity_.fabric_id &&
                          chip::IsOperationalNodeId(next_node_id_) &&
                          csr_nonce.size() == chip::Controller::kCSRNonceLength &&
                          !attestation_signature.empty() &&
                          !attestation_challenge.empty() && !dac.empty() &&
                          on_completion != nullptr,
                      CHIP_ERROR_INVALID_ARGUMENT);

  chip::TLV::TLVReader reader;
  reader.Init(csr_elements);
  if (reader.GetType() == chip::TLV::kTLVType_NotSpecified) {
    ReturnErrorOnFailure(reader.Next());
  }
  ReturnErrorOnFailure(reader.Expect(chip::TLV::kTLVType_Structure,
                                     chip::TLV::AnonymousTag()));
  chip::TLV::TLVType container;
  ReturnErrorOnFailure(reader.EnterContainer(container));
  ReturnErrorOnFailure(reader.Next(chip::TLV::kTLVType_ByteString,
                                   chip::TLV::ContextTag(1)));
  const chip::ByteSpan csr(reader.GetReadPoint(), reader.GetLength());
  ReturnErrorOnFailure(reader.ExitContainer(container));

  chip::Crypto::P256PublicKey public_key;
  ReturnErrorOnFailure(chip::Crypto::VerifyCertificateSigningRequest(
      csr.data(), csr.size(), public_key));
  ReturnErrorOnFailure(
      IssueNoc(public_key, next_node_id_, next_fabric_id_, callback_noc_));

  node_requested_ = false;
  fabric_requested_ = false;
  on_completion->mCall(on_completion->mContext, CHIP_NO_ERROR,
                       chip::ByteSpan(callback_noc_.data(), callback_noc_.size()),
                       chip::ByteSpan(),
                       chip::ByteSpan(root_certificate_.data(),
                                      root_certificate_.size()),
                       chip::MakeOptional(ipk()), chip::Optional<chip::NodeId>());
  return CHIP_NO_ERROR;
}

} // namespace wotex::matter
