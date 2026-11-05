# The complete 1024-proposal and canonical-envelope cases retain their full
# bounds under coverage. Limit competing cases so the minimum CI runtime does
# not spend their deadlines contending for CPU and garbage collection.
ExUnit.start(max_cases: 2)
Code.require_file("support/input_fixtures.exs", __DIR__)
Code.require_file("support/driver_host.exs", __DIR__)
Code.require_file("support/source_truth_oracle.exs", __DIR__)
Code.require_file("support/source_transition_oracle.exs", __DIR__)
