// SPDX-License-Identifier: Apache-2.0
// The process owner of the OPC UA host (priv/native/owner.c with output.c,
// ipc.c and json_codec.c) on an open Session: a request line is framed, parsed,
// admitted and prepared; the next tick dispatches it, completes it and emits the
// reply through the credited output queue to a nonblocking pipe; the driver
// reads the reply and returns one credit control per reply line, as the BEAM
// host does. The SDK is replaced by an in-process service that completes every
// dispatched operation on the same tick, so only the owner's own work is
// measured. The unit is one request.
#include <chrono>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <nanobench.h>

extern "C" {
#include "owner.h"
}

namespace {

void check(bool result, const char *what) {
  if (result) return;
  std::cerr << "owner: " << what << " failed\n";
  std::exit(1);
}

// The in-process service: every prepared operation completes on its dispatch tick.
struct Service {
  int64_t now = 1000;
  uint64_t dispatched = 0;
  bool pending[WOP_OWNER_OPERATIONS] = {};
};

Service *service_of(void *context) { return static_cast<Service *>(context); }

int64_t service_clock(void *context) { return service_of(context)->now; }

bool service_open(void *, yyjson_val *, int64_t, WopFailure *) { return true; }

WopCompletion service_opened(void *, yyjson_mut_doc *document, yyjson_mut_val *result,
                             WopFailure *) {
  yyjson_mut_val *namespaces = yyjson_mut_arr(document);
  return namespaces &&
          yyjson_mut_arr_add_str(document, namespaces, "http://opcfoundation.org/UA/") &&
          yyjson_mut_arr_add_str(document, namespaces, "urn:example:opcua:plant") &&
          yyjson_mut_obj_add_real(document, result, "session_timeout_ms", 60000.0) &&
          yyjson_mut_obj_add_val(document, result, "namespace_array", namespaces)
      ? WOP_COMPLETION_SUCCESS
      : WOP_COMPLETION_TERMINAL;
}

bool service_prepare(void *, const WopOperation *, yyjson_val *parameters, WopFailure *) {
  return yyjson_is_obj(parameters) && yyjson_obj_get(parameters, "node_id") != nullptr;
}

bool service_dispatch(void *context, const WopOperation *operation, uint32_t timeout_ms,
                      WopFailure *) {
  Service *service = service_of(context);
  service->pending[operation->index] = true;
  ++service->dispatched;
  return timeout_ms > 0;
}

// A Read completes with a Double DataValue, a Write with its status.
WopCompletion service_complete(void *context, const WopOperation *operation,
                               yyjson_mut_doc *document, yyjson_mut_val **result, WopFailure *) {
  service_of(context)->pending[operation->index] = false;
  yyjson_mut_val *value = yyjson_mut_obj(document);
  if (operation->kind == WOP_OPERATION_WRITE) {
    *result = value;
    return value && yyjson_mut_obj_add_uint(document, value, "status", 0) ? WOP_COMPLETION_SUCCESS
                                                                          : WOP_COMPLETION_TERMINAL;
  }
  yyjson_mut_val *variant = yyjson_mut_obj(document);
  const bool built = value && variant &&
      yyjson_mut_obj_add_str(document, variant, "type", "Double") &&
      yyjson_mut_obj_add_bool(document, variant, "array", false) &&
      yyjson_mut_obj_add_real(document, variant, "value", 21.5) &&
      yyjson_mut_obj_add_bool(document, value, "has_value", true) &&
      yyjson_mut_obj_add_val(document, value, "value", variant) &&
      yyjson_mut_obj_add_uint(document, value, "status", 0) &&
      yyjson_mut_obj_add_sint(document, value, "source_timestamp", 133000000000000000LL) &&
      yyjson_mut_obj_add_sint(document, value, "server_timestamp", 133000000000000001LL);
  *result = value;
  return built ? WOP_COMPLETION_SUCCESS : WOP_COMPLETION_TERMINAL;
}

void service_cancel(void *, const WopOperation *) {}

void service_retire(void *context, const WopOperation *operation) {
  service_of(context)->pending[operation->index] = false;
}

bool service_released(void *context, const WopOperation *operation) {
  return !service_of(context)->pending[operation->index];
}

bool service_step(void *, int, WopFailure *) { return true; }

bool service_close(void *) { return true; }

// The request envelope the BEAM host writes (Wotex.OPCUA.Native.Frame).
std::string request(const std::string &id, const std::string &operation,
                    const std::string &parameters) {
  return R"({"version":1,"generation":1,"id":")" + id + R"(","operation":")" + operation +
      R"(","parameters":)" + parameters + R"(,"timeout_ms":5000,"deadline_ms":86400000})" + "\n";
}

std::string read_line(unsigned index) {
  return request("read-" + std::to_string(100000 + index), "read",
                 R"({"node_id":"ns=2;s=plant/line-4/oven-2/temperature","index_range":null})");
}

std::string write_line() {
  std::string values;
  for (unsigned i = 0; i < 1024; ++i) values += (i ? ",21.625" : "21.625");
  return request("write-100000", "write",
                 R"({"node_id":"ns=2;s=plant/line-4/oven-2/profile","index_range":null,)"
                 R"("value":{"type":"Double","array":true,"value":[)" +
                     values + "]}}");
}

std::string base64(std::size_t bytes) {
  static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string text;
  for (std::size_t i = 0; i < bytes / 3 * 4; ++i) text.push_back(alphabet[(i * 7U) % 64U]);
  if (bytes % 3 == 1) text += "AA==";
  if (bytes % 3 == 2) text += "AAA=";
  return text;
}

std::string envelope(std::size_t bytes) {
  return R"({"type":"bytes","base64":")" + base64(bytes) + R"("})";
}

std::string open_line() {
  return request("open-1", "open",
                 R"({"endpoint":"opc.tcp://plc.example:4840",)"
                 R"("security_policy":"http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256",)"
                 R"("security_mode":"SignAndEncrypt","client_uri":"urn:example:opcua:client",)"
                 R"("server_uri":"urn:example:opcua:server","certificate":)" +
                     envelope(1024) + R"(,"private_key":)" + envelope(1218) +
                     R"(,"server_certificate":)" + envelope(1024) + R"(,"trust_certificate":)" +
                     envelope(812) + R"(,"crl":)" + envelope(461) +
                     R"(,"authentication":{"type":"anonymous"},"session_timeout_ms":60000})");
}

// The owner, its service and both ends of its output pipe.
class Host {
 public:
  Host() {
    const WopService callbacks = {
        &service_,        service_open,   service_opened, service_prepare,  service_dispatch,
        service_complete, service_cancel, service_retire, service_released, service_step,
        service_close,    nullptr,        nullptr};
    check(pipe(pipe_) == 0, "pipe");
    for (const int descriptor : pipe_) {
      const int flags = fcntl(descriptor, F_GETFL);
      check(flags >= 0 && fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0, "nonblocking pipe");
    }
    check(wop_owner_init(&owner_, &callbacks, service_clock, &service_), "wop_owner_init");
    owner_.output_descriptor = pipe_[1];
    check(wop_owner_ready(&owner_, "bench", service_.now), "wop_owner_ready");
    check(wop_output_flush(&owner_.output, pipe_[1]) == WOP_OUTPUT_OK, "ready flush");
    check(drain().size() == 1, "ready line");
    input("{\"version\":1,\"generation\":1,\"event\":\"credit\",\"sequence\":1,"
          "\"messages\":16,\"bytes\":262144}\n");
    input(open_line());
    wop_owner_tick(&owner_, 0);
    replies(1);
    check(owner_.session == WOP_OWNER_OPEN, "open Session");
  }
  ~Host() {
    wop_owner_shutdown(&owner_);
    wop_owner_clear(&owner_);
    close(pipe_[0]);
    close(pipe_[1]);
  }
  Host(const Host &) = delete;
  Host &operator=(const Host &) = delete;
  Host(Host &&) = delete;
  Host &operator=(Host &&) = delete;

  void input(const std::string &bytes) {
    wop_owner_input(&owner_, bytes.data(), bytes.size());
    check(!owner_.finished, "owner input");
  }

  // One tick, then the `count` successful replies it emitted, each answered
  // by one credit control for that line.
  void exchange(std::size_t count) {
    wop_owner_tick(&owner_, 0);
    replies(count);
    check(owner_.occupied == 0, "released slots");
  }

  uint64_t dispatched() const { return service_.dispatched; }

 private:
  std::vector<std::size_t> drain() {
    std::vector<std::size_t> lines;
    for (;;) {
      const ssize_t count = read(pipe_[0], buffer_ + used_, sizeof(buffer_) - used_);
      if (count > 0) {
        used_ += static_cast<std::size_t>(count);
        continue;
      }
      if (count < 0 && errno == EINTR) continue;
      break;
    }
    std::size_t start = 0;
    for (std::size_t i = 0; i < used_; ++i) {
      if (buffer_[i] != '\n') continue;
      lines.push_back(i + 1 - start);
      start = i + 1;
    }
    std::memmove(buffer_, buffer_ + start, used_ - start);
    used_ -= start;
    return lines;
  }

  void replies(std::size_t count) {
    const std::vector<std::size_t> lines = drain();
    check(lines.size() == count && !owner_.finished, "reply lines");
    for (const std::size_t size : lines) {
      input("{\"version\":1,\"generation\":1,\"event\":\"credit\",\"sequence\":" +
            std::to_string(++credit_sequence_) +
            ",\"messages\":1,\"bytes\":" + std::to_string(size) + "}\n");
    }
  }

  Service service_;
  WopOwner owner_{};
  int pipe_[2] = {-1, -1};
  char buffer_[1 << 16] = {};
  std::size_t used_ = 0;
  uint64_t credit_sequence_ = 1;
};

} // namespace

int main() {
  auto host = std::make_unique<Host>();
  const std::string read = read_line(0);
  const std::string write = write_line();
  std::string pipelined;
  for (unsigned i = 0; i < 16; ++i) pipelined += read_line(i);

  ankerl::nanobench::Bench bench;
  bench.title("owner").unit("request").warmup(20).minEpochTime(std::chrono::milliseconds(20));
  bench.run("Read: request, tick, reply and credit", [&] {
    host->input(read);
    host->exchange(1);
  });
  bench.run("Write of 1024 Doubles (" + std::to_string(write.size()) + " B request)", [&] {
    host->input(write);
    host->exchange(1);
  });
  bench.batch(16).run("16 pipelined Reads in one input read, one tick", [&] {
    host->input(pipelined);
    host->exchange(16);
  });
  check(host->dispatched() > 0, "dispatched operations");
  return 0;
}
