// SPDX-License-Identifier: Apache-2.0
// Bounded serialization and nonblocking FIFO output. The executable owns its
// SIGPIPE policy and descriptor lifetime. SDK callbacks only enqueue frames.
#pragma once
#include "frame.hpp"
#include <cerrno>
#include <deque>
#include <fcntl.h>
#include <map>
#include <memory>
#include <optional>
#include <ostream>
#include <streambuf>
#include <unistd.h>

namespace wotex::ble {
class EncodedFrame {
  std::string bytes_;
  explicit EncodedFrame(std::string bytes) : bytes_(std::move(bytes)) {}
  class Buffer : public std::streambuf {
    std::string value_;
    std::size_t limit_;
  protected:
    std::streamsize xsputn(const char *bytes, std::streamsize count) override {
      if (count < 0 || static_cast<std::size_t>(count) > limit_ - value_.size()) throw InvalidFrame();
      value_.append(bytes, static_cast<std::size_t>(count)); return count;
    }
    int_type overflow(int_type value) override {
      if (traits_type::eq_int_type(value, traits_type::eof())) return traits_type::not_eof(value);
      if (value_.size() == limit_) throw InvalidFrame();
      value_.push_back(traits_type::to_char_type(value)); return value;
    }
  public:
    explicit Buffer(std::size_t limit) : limit_(limit) {}
    std::string take() { return std::move(value_); }
  };
  static void validate(const Json &value) {
    std::vector<std::pair<const Json *, unsigned>> pending{{&value, 1}};
    unsigned visited = 0;
    while (!pending.empty()) {
      const auto [item, depth] = pending.back(); pending.pop_back();
      if (++visited > 4096 || depth > 8 || item->is_binary() || item->is_discarded() ||
          (item->is_number_float() && !std::isfinite(item->get<double>()))) throw InvalidFrame();
      if (item->is_structured()) {
        if (item->size() > 1024 || item->size() > 4096 - visited - pending.size()) throw InvalidFrame();
        for (const auto &child : *item) pending.emplace_back(&child, depth + 1);
      }
    }
  }
public:
  static EncodedFrame from(const Json &value, std::size_t limit = max_line) {
    if (!limit || limit > max_line) throw InvalidFrame();
    validate(value); Buffer buffer(limit); std::ostream output(&buffer);
    output.exceptions(std::ios_base::badbit | std::ios_base::failbit);
    try { output << value; output.put('\n'); }
    catch (...) { throw InvalidFrame(); }
    return EncodedFrame(buffer.take());
  }
  const std::string &bytes() const { return bytes_; }
  std::size_t size() const { return bytes_.size(); }
};

class NativeOutput {
  struct Generation {};
public:
  class ReplySlot {
    friend class NativeOutput;
    std::weak_ptr<const Generation> generation_;
    std::uint64_t identifier_ = 0;
    ReplySlot(const std::shared_ptr<const Generation> &generation, std::uint64_t identifier)
      : generation_(generation), identifier_(identifier) {}
  public:
    ReplySlot() = default;
  };
private:
  enum class Lane { reply, control, report };
  struct Frame { EncodedFrame encoded; Lane lane; std::uint64_t slot; };
  std::shared_ptr<const Generation> generation_ = std::make_shared<const Generation>();
  std::map<std::uint64_t, bool> slots_;
  std::deque<Frame> frames_;
  std::uint64_t sequence_ = 0, admitted_report_ = 0, transmitted_report_ = 0;
  std::size_t offset_ = 0, control_count_ = 0, report_count_ = 0, report_bytes_ = 0, bytes_ = 0;
  auto slot(const ReplySlot &slot) {
    return slot.generation_.lock() == generation_ ? slots_.find(slot.identifier_) : slots_.end();
  }
  void transmitted() {
    const auto &frame = frames_.front(); bytes_ -= frame.encoded.size();
    if (frame.lane == Lane::reply) slots_.erase(frame.slot);
    else if (frame.lane == Lane::control) --control_count_;
    else {
      --report_count_; report_bytes_ -= frame.encoded.size();
      if (frame.slot) transmitted_report_ = frame.slot;
    }
    frames_.pop_front(); offset_ = 0;
  }
public:
  static constexpr std::size_t reply_limit = 64, control_limit = 256, control_frame_limit = 4096;
  static constexpr std::size_t report_limit = 64, report_byte_limit = 1048576;
  NativeOutput() = default;
  NativeOutput(const NativeOutput &) = delete;
  NativeOutput &operator=(const NativeOutput &) = delete;
  std::optional<ReplySlot> reserve_reply() {
    if (slots_.size() == reply_limit || sequence_ == UINT64_MAX) return std::nullopt;
    const auto identifier = ++sequence_; slots_.emplace(identifier, false);
    return ReplySlot(generation_, identifier);
  }
  bool release_reply(const ReplySlot &ticket) {
    const auto found = slot(ticket);
    if (found == slots_.end() || found->second) return false;
    slots_.erase(found); return true;
  }
  bool reply(const ReplySlot &ticket, const EncodedFrame &frame) {
    const auto found = slot(ticket);
    if (found == slots_.end() || found->second) return false;
    frames_.push_back({frame, Lane::reply, found->first});
    bytes_ += frame.size(); found->second = true; return true;
  }
  bool control(const EncodedFrame &frame) {
    if (frame.size() > control_frame_limit || control_count_ == control_limit) return false;
    frames_.push_back({frame, Lane::control, 0}); bytes_ += frame.size(); ++control_count_; return true;
  }
  bool report(const EncodedFrame &frame, std::uint64_t sequence = 0) {
    if ((sequence && sequence <= admitted_report_) || report_count_ == report_limit || frame.size() > report_byte_limit - report_bytes_) return false;
    frames_.push_back({frame, Lane::report, sequence});
    if (sequence) admitted_report_ = sequence;
    bytes_ += frame.size(); report_bytes_ += frame.size(); ++report_count_; return true;
  }
  // Each turn has at most 64 write attempts and 65536 bytes. A full pipe returns
  // immediately with all ownership/accounting intact, so control can still run.
  void flush(int descriptor, std::size_t budget = 65536) {
    const int flags = ::fcntl(descriptor, F_GETFL);
    if (flags < 0 || !(flags & O_NONBLOCK) || budget == 0 || budget > 65536) throw std::runtime_error("invalid_output");
    for (unsigned attempts = 0; attempts < 64 && budget && !frames_.empty(); ++attempts) {
      const auto &frame = frames_.front().encoded.bytes();
      const auto count = std::min(budget, frame.size() - offset_);
      const auto written = ::write(descriptor, frame.data() + offset_, count);
      if (written < 0) {
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) return;
        throw std::runtime_error("output_closed");
      }
      if (!written) throw std::runtime_error("output_closed");
      offset_ += static_cast<std::size_t>(written); budget -= static_cast<std::size_t>(written);
      if (offset_ == frame.size()) transmitted();
    }
  }
  std::size_t pending_frames() const { return frames_.size(); }
  std::size_t retained_bytes() const { return bytes_; }
  std::size_t reply_reservations() const { return slots_.size(); }
  std::size_t control_frames() const { return control_count_; }
  std::size_t report_frames() const { return report_count_; }
  std::size_t report_bytes() const { return report_bytes_; }
  std::uint64_t transmitted_report_sequence() const { return transmitted_report_; }
};
} // namespace wotex::ble
