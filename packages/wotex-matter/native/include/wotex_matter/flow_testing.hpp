#ifndef WOTEX_MATTER_FLOW_TESTING_HPP
#define WOTEX_MATTER_FLOW_TESTING_HPP

#ifndef WOTEX_MATTER_FLOW_TESTING
#error "Process-flow instrumentation belongs only to its test executable"
#endif

#include <cstddef>
#include <string>

namespace wotex::matter::flow_testing {

std::string EncodeReport(const std::string &frame);
void ObserveCredit(std::size_t queued, std::size_t queued_bytes,
                   std::size_t outstanding, std::size_t outstanding_bytes);
void ObserveOutput(const std::string &frame, std::size_t report_frames,
                   std::size_t report_bytes, std::size_t control_frames,
                   std::size_t control_bytes, std::size_t reply_frames,
                   std::size_t reply_bytes);

} // namespace wotex::matter::flow_testing

#endif
