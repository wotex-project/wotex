defmodule Wotex.Lab.Graph.Interfaces do
  @moduledoc """
  The OpenAPI 3.2.0 and AsyncAPI 3.1.0 documents derived from the graph.

  The OpenAPI document describes the Lab HTTP control API implemented by the
  optional Workbench host: public scenario and metric catalogue reads,
  session-bound evidence and run reads, and the host-opted-in run mutations
  `startRun`, `cancelRun` and `approveDecision` with their `Idempotency-Key`
  header, closed request bodies and refusal statuses. The AsyncAPI document is an accepted fixture
  interface, not a running deployment. Neither replaces a Thing Description,
  and both carry explicit deployment status. The dialect versions are pinned
  here and validated by `bin/check_graph.exs`.

  `openapi/1` and `asyncapi/1` derive deterministic, string-keyed documents from
  an admitted `Wotex.Lab.Graph`. They perform no routing, server startup, schema
  publication, or network discovery; an optional host decides how and whether
  to expose the resulting documents.
  """

  @openapi_version "3.2.0"
  @asyncapi_version "3.1.0"

  @doc "The pinned OpenAPI dialect version."
  @spec openapi_version() :: String.t()
  def openapi_version, do: @openapi_version

  @doc "The pinned AsyncAPI dialect version."
  @spec asyncapi_version() :: String.t()
  def asyncapi_version, do: @asyncapi_version

  @doc "The Lab HTTP control API as an OpenAPI 3.2.0 document (a map)."
  @spec openapi(map()) :: map()
  def openapi(graph) do
    package = graph["package"]

    %{
      "openapi" => @openapi_version,
      "info" => %{
        "title" => "Wotex Lab control API",
        "version" => package["version"],
        "summary" => "Accepted control surface of an explicit Lab instance",
        "description" =>
          "Describes the Lab HTTP control API served by the optional Workbench host under " <>
            "/api/v1. Catalogue reads are public; evidence and run reads need a session " <>
            "bearer. Run mutations also need host opt-in, an Idempotency-Key and a deadline, " <>
            "and reach only the session room's simulated Things. The base library starts " <>
            "no endpoint.",
        "license" => %{"name" => "Apache-2.0", "identifier" => "Apache-2.0"}
      },
      "x-wotex-status" => status(graph, "WLB.07"),
      "x-wotex-deployment" => "optional-workbench-host",
      "x-wotex-source" => package["source_url"],
      "servers" => [%{"url" => "/api/v1", "description" => "Workbench host"}],
      "paths" => %{
        "/scenarios" => %{
          "get" => %{
            "operationId" => "listScenarios",
            "summary" => "List the admitted scenario descriptors",
            "responses" => %{
              "200" => json_response("Scenario descriptors", "#/components/schemas/ScenarioList")
            }
          }
        },
        "/scenarios/{id}" => %{
          "get" => %{
            "operationId" => "readScenario",
            "summary" => "Read one scenario descriptor",
            "parameters" => [id_parameter("id", "Scenario identifier", "^[a-z0-9][a-z0-9._:-]*$")],
            "responses" => %{
              "200" => json_response("A scenario descriptor", "#/components/schemas/Scenario"),
              "404" => json_response("Unknown scenario", "#/components/schemas/Error")
            }
          }
        },
        "/evidence/{record_id}" => %{
          "get" => %{
            "operationId" => "readEvidence",
            "summary" => "Read one evidence record by its content digest",
            "parameters" => [
              id_parameter("record_id", "sha256 digest of the record", "^sha256:[0-9a-f]{64}$")
            ],
            "responses" => %{
              "200" => json_response("An evidence record", "#/components/schemas/EvidenceRecord"),
              "400" => json_response("Malformed digest", "#/components/schemas/Error"),
              "401" => json_response("Bearer token required", "#/components/schemas/Error"),
              "403" => json_response("Session denied", "#/components/schemas/Error"),
              "404" => json_response("Unknown record", "#/components/schemas/Error")
            },
            "security" => [%{"sessionBearer" => []}]
          }
        },
        "/runs" => %{
          "post" => %{
            "operationId" => "startRun",
            "summary" => "Start an admitted experiment run in the session room",
            "x-wotex-opt-in" => "control_mutations",
            "parameters" => [%{"$ref" => "#/components/parameters/IdempotencyKey"}],
            "requestBody" => json_request("#/components/schemas/StartRunRequest"),
            "responses" => mutation_responses("201", "The started run"),
            "security" => [%{"sessionBearer" => []}]
          }
        },
        "/runs/{run_id}" => %{
          "get" => %{
            "operationId" => "readRun",
            "summary" => "Read one run retained by the session room",
            "parameters" => [%{"$ref" => "#/components/parameters/RunId"}],
            "responses" => %{
              "200" => json_response("A run projection", "#/components/schemas/Run"),
              "401" => json_response("Bearer token required", "#/components/schemas/Error"),
              "403" => json_response("Session denied", "#/components/schemas/Error"),
              "404" => json_response("Unknown run", "#/components/schemas/Error")
            },
            "security" => [%{"sessionBearer" => []}]
          }
        },
        "/runs/{run_id}/cancel" => %{
          "post" => %{
            "operationId" => "cancelRun",
            "summary" => "Cancel the pending decision of a run",
            "x-wotex-opt-in" => "control_mutations",
            "parameters" => [
              %{"$ref" => "#/components/parameters/RunId"},
              %{"$ref" => "#/components/parameters/IdempotencyKey"}
            ],
            "requestBody" => json_request("#/components/schemas/CancelRunRequest"),
            "responses" => mutation_responses("200", "The cancelled run"),
            "security" => [%{"sessionBearer" => []}]
          }
        },
        "/runs/{run_id}/approval" => %{
          "post" => %{
            "operationId" => "approveDecision",
            "summary" => "Approve the exactly named granted decision of a run",
            "description" =>
              "Every named field must equal the granted decision; the room policy then " <>
                "rechecks grant, expiry, watermark and state revision and dispatches the " <>
                "simulated Action at most once.",
            "x-wotex-opt-in" => "control_mutations",
            "parameters" => [
              %{"$ref" => "#/components/parameters/RunId"},
              %{"$ref" => "#/components/parameters/IdempotencyKey"}
            ],
            "requestBody" => json_request("#/components/schemas/ApprovalRequest"),
            "responses" => mutation_responses("200", "The dispatched run"),
            "security" => [%{"sessionBearer" => []}]
          }
        },
        "/metrics/catalogue" => %{
          "get" => %{
            "operationId" => "readMetricsCatalogue",
            "summary" => "Read the versioned metric catalogue",
            "description" =>
              "WLB.10 owns the metric catalogue; its implementation status is recorded " <>
                "in x-wotex-status for this revision.",
            "x-wotex-status" => status(graph, "WLB.10"),
            "responses" => %{
              "200" => json_response("Metric definitions", "#/components/schemas/MetricsCatalogue")
            }
          }
        }
      },
      "components" => %{
        "parameters" => %{
          "RunId" => %{
            "name" => "run_id",
            "in" => "path",
            "required" => true,
            "description" => "Run identifier retained by the session room",
            "schema" => %{"type" => "string", "minLength" => 1, "maxLength" => 64}
          },
          "IdempotencyKey" => %{
            "name" => "Idempotency-Key",
            "in" => "header",
            "required" => true,
            "description" =>
              "Caller-chosen identity; the room executes a key at most once and replays " <>
                "its retained outcome for an identical request.",
            "schema" => %{"type" => "string", "pattern" => "^[\\x21-\\x7E]{1,128}$"}
          }
        },
        "securitySchemes" => %{
          "sessionBearer" => %{
            "type" => "http",
            "scheme" => "bearer",
            "description" =>
              "An existing Workbench session token; it grants access only to that session's room."
          }
        },
        "schemas" => %{
          "Scenario" => %{
            "type" => "object",
            "required" => ["schema_version", "id", "title", "capabilities", "seed", "max_steps"],
            "properties" => %{
              "schema_version" => %{"type" => "string", "const" => "1.0.0"},
              "id" => %{"type" => "string", "pattern" => "^[a-z0-9][a-z0-9._:-]*$"},
              "title" => %{"type" => "string", "minLength" => 1, "maxLength" => 256},
              "capabilities" => %{
                "type" => "array",
                "minItems" => 1,
                "maxItems" => 64,
                "items" => %{"type" => "string"}
              },
              "seed" => %{"type" => "integer", "minimum" => 0, "maximum" => 4_294_967_295},
              "max_steps" => %{"type" => "integer", "minimum" => 1, "maximum" => 100_000}
            }
          },
          "ScenarioList" => %{
            "type" => "object",
            "required" => ["scenarios"],
            "properties" => %{
              "scenarios" => %{
                "type" => "array",
                "items" => %{"$ref" => "#/components/schemas/Scenario"}
              }
            }
          },
          "EvidenceRecord" => %{
            "type" => "object",
            "required" => [
              "schema_version",
              "scenario_id",
              "revision",
              "attempt",
              "source_tree_digest",
              "lock_digest",
              "dependencies",
              "assertions",
              "outcomes",
              "cleanup"
            ],
            "properties" => %{
              "schema_version" => %{"type" => "string", "const" => "1.0.0"},
              "scenario_id" => %{"type" => "string"},
              "revision" => %{"type" => "string"},
              "attempt" => %{"type" => "integer", "minimum" => 1},
              "source_tree_digest" => %{"$ref" => "#/components/schemas/Digest"},
              "lock_digest" => %{"$ref" => "#/components/schemas/Digest"},
              "dependencies" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "required" => ["name", "version", "archive"],
                  "properties" => %{
                    "name" => %{"type" => "string"},
                    "version" => %{"type" => "string"},
                    "archive" => %{
                      "oneOf" => [
                        %{"$ref" => "#/components/schemas/Digest"},
                        %{"type" => "string", "const" => "missing"}
                      ]
                    }
                  }
                }
              },
              "assertions" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "required" => ["id", "status"],
                  "properties" => %{
                    "id" => %{"type" => "string"},
                    "status" => %{
                      "type" => "string",
                      "enum" => ["pass", "fail", "unsupported", "not_run", "infrastructure_error"]
                    }
                  }
                }
              },
              "outcomes" => %{"type" => "object"},
              "cleanup" => %{
                "type" => "object",
                "required" => ["status"],
                "properties" => %{"status" => %{"type" => "string", "enum" => ["ok", "failed"]}}
              }
            }
          },
          "MetricsCatalogue" => %{
            "type" => "object",
            "required" => ["schema_version", "metrics"],
            "properties" => %{
              "schema_version" => %{"type" => "string"},
              "metrics" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "required" => ["name", "unit", "kind"],
                  "properties" => %{
                    "name" => %{"type" => "string"},
                    "unit" => %{"type" => "string"},
                    "kind" => %{
                      "type" => "string",
                      "enum" => ["counter", "gauge", "histogram"]
                    },
                    "dimensions" => %{"type" => "array", "items" => %{"type" => "string"}}
                  }
                }
              }
            }
          },
          "Run" => %{
            "type" => "object",
            "required" => [
              "id",
              "experiment",
              "attempt",
              "status",
              "started_at",
              "duration_ms",
              "record_digest",
              "assertions",
              "decision",
              "effect",
              "error"
            ],
            "properties" => %{
              "id" => %{"type" => "string"},
              "experiment" => %{"type" => "string"},
              "attempt" => %{"type" => "integer", "minimum" => 1},
              "status" => %{
                "type" => "string",
                "enum" => ["completed", "failed", "awaiting_approval", "dispatched", "cancelled"]
              },
              "started_at" => %{"type" => "string", "format" => "date-time"},
              "duration_ms" => %{"type" => "integer", "minimum" => 0},
              "record_digest" => %{
                "oneOf" => [%{"$ref" => "#/components/schemas/Digest"}, %{"type" => "null"}]
              },
              "assertions" => %{
                "type" => "array",
                "items" => %{
                  "type" => "object",
                  "required" => ["id", "status", "note"],
                  "properties" => %{
                    "id" => %{"type" => "string"},
                    "status" => %{"type" => "string", "enum" => ["pass", "fail", "not_run"]},
                    "note" => %{"type" => "string"}
                  }
                }
              },
              "decision" => %{
                "oneOf" => [%{"$ref" => "#/components/schemas/Decision"}, %{"type" => "null"}]
              },
              "effect" => %{"description" => "The simulated effect read back after dispatch"},
              "error" => %{
                "oneOf" => [
                  %{
                    "type" => "object",
                    "required" => ["code", "phase", "message"],
                    "properties" => %{
                      "code" => %{"type" => "string"},
                      "phase" => %{"type" => "string"},
                      "message" => %{"type" => "string"}
                    }
                  },
                  %{"type" => "null"}
                ]
              }
            }
          },
          "Decision" => %{
            "type" => "object",
            "required" => [
              "id",
              "status",
              "thing_id",
              "action_name",
              "input",
              "proposal_digest",
              "state_revision",
              "expires_at"
            ],
            "properties" => %{
              "id" => %{"type" => "string"},
              "status" => %{"type" => "string"},
              "thing_id" => %{"type" => "string"},
              "action_name" => %{"type" => "string"},
              "input" => %{"type" => "number"},
              "proposal_digest" => %{"$ref" => "#/components/schemas/Digest"},
              "state_revision" => %{"type" => "integer"},
              "expires_at" => %{"type" => "integer"}
            }
          },
          "StartRunRequest" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["experiment_id", "deadline_ms"],
            "properties" => %{
              "experiment_id" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
              "parameters" => %{
                "type" => "object",
                "maxProperties" => 16,
                "additionalProperties" => %{"type" => "string", "maxLength" => 32}
              },
              "deadline_ms" => %{"$ref" => "#/components/schemas/DeadlineMs"}
            }
          },
          "CancelRunRequest" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["deadline_ms"],
            "properties" => %{"deadline_ms" => %{"$ref" => "#/components/schemas/DeadlineMs"}}
          },
          "ApprovalRequest" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => [
              "decision_id",
              "thing_id",
              "action_name",
              "input",
              "proposal_digest",
              "state_revision",
              "expires_at",
              "deadline_ms"
            ],
            "properties" => %{
              "decision_id" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
              "thing_id" => %{"type" => "string", "minLength" => 1, "maxLength" => 256},
              "action_name" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
              "input" => %{"type" => "number"},
              "proposal_digest" => %{"$ref" => "#/components/schemas/Digest"},
              "state_revision" => %{"type" => "integer"},
              "expires_at" => %{"type" => "integer"},
              "deadline_ms" => %{"$ref" => "#/components/schemas/DeadlineMs"}
            }
          },
          "DeadlineMs" => %{"type" => "integer", "minimum" => 1, "maximum" => 30_000},
          "Digest" => %{"type" => "string", "pattern" => "^sha256:[0-9a-f]{64}$"},
          "Error" => %{
            "type" => "object",
            "required" => ["code", "phase", "message"],
            "properties" => %{
              "code" => %{"type" => "string"},
              "phase" => %{"type" => "string"},
              "path" => %{"type" => "string"},
              "message" => %{"type" => "string"}
            }
          }
        }
      }
    }
  end

  @doc "The reference MQTT Thing's event and command interface as an AsyncAPI 3.1.0 document (a map)."
  @spec asyncapi(map()) :: map()
  def asyncapi(graph) do
    package = graph["package"]
    fixture = Enum.find(graph["fixtures"], &(&1["id"] == "mqtt-room"))

    %{
      "asyncapi" => @asyncapi_version,
      "id" => "urn:wotex:lab:asyncapi:mqtt-room",
      "info" => %{
        "title" => "Wotex Lab reference MQTT Thing",
        "version" => package["version"],
        "description" =>
          "The exposed event and command interface of the MQTT room fixture consumed by " <>
            "the consume-mqtt and smart-room cookbooks. It describes accepted channels " <>
            "on a broker the host runs; it is not a deployment and does not replace the " <>
            "Thing Description, which remains the WoT contract.",
        "license" => %{"name" => "Apache-2.0"}
      },
      "defaultContentType" => "application/json",
      "x-wotex-status" => status(graph, "WLB.04"),
      "x-wotex-fixture" => fixture && fixture["id"],
      "x-wotex-fixture-digest" => fixture && fixture["input_sha256"],
      "x-wotex-deployment" => "none",
      "servers" => %{
        "disposableBroker" => %{
          "host" => "127.0.0.1:1883",
          "protocol" => "mqtt",
          "protocolVersion" => "5",
          "description" =>
            "A disposable eclipse-mosquitto:2 broker the host starts; the port is chosen " <>
              "by the host and every run uses its own topic prefix."
        }
      },
      "channels" => %{
        "temperature" => channel("properties/temperature", "TemperatureSample", "Cel"),
        "power" => channel("properties/power", "PowerSample", "W"),
        "target" => channel("properties/target", "TargetWrite", "Cel"),
        "setTarget" => channel("actions/set-target", "SetTargetInvocation", "Cel")
      },
      "operations" => %{
        "readTemperature" => operation("receive", "temperature", "readproperty", true),
        "observeTemperature" => operation("receive", "temperature", "observeproperty", false),
        "readPower" => operation("receive", "power", "readproperty", true),
        "writeTarget" => operation("send", "target", "writeproperty", false),
        "invokeSetTarget" => operation("send", "setTarget", "invokeaction", false)
      },
      "components" => %{
        "parameters" => %{
          "prefix" => %{
            "description" => "Per-run topic prefix chosen by the host, for example lab/cookbook/42."
          }
        },
        "messages" => %{
          "TemperatureSample" => message("A temperature reading in Celsius", "number", "Cel"),
          "PowerSample" => message("A power reading in watts", "number", "W"),
          "TargetWrite" => message("A target temperature written by a consumer", "number", "Cel"),
          "SetTargetInvocation" =>
            message("The setTarget Action input, bounded to [5, 35] by the TD", "number", "Cel")
        }
      }
    }
  end

  defp channel(suffix, message, unit) do
    %{
      "address" => "{prefix}/" <> suffix,
      "parameters" => %{"prefix" => %{"$ref" => "#/components/parameters/prefix"}},
      "messages" => %{message => %{"$ref" => "#/components/messages/" <> message}},
      "bindings" => %{"mqtt" => %{"bindingVersion" => "0.2.0"}},
      "x-wotex-unit" => unit
    }
  end

  defp operation(action, channel, wot_operation, retain) do
    %{
      "action" => action,
      "channel" => %{"$ref" => "#/channels/" <> channel},
      "summary" => "WoT " <> wot_operation,
      "x-wotex-operation" => wot_operation,
      "bindings" => %{"mqtt" => %{"qos" => 1, "retain" => retain, "bindingVersion" => "0.2.0"}}
    }
  end

  defp message(summary, type, unit) do
    %{
      "summary" => summary,
      "contentType" => "application/json",
      "payload" => %{"type" => type, "x-wotex-unit" => unit}
    }
  end

  defp status(graph, spec_id) do
    case Enum.find(graph["specifications"], &(&1["id"] == spec_id)) do
      nil ->
        %{"spec" => spec_id, "implementation_status" => "not_reported"}

      spec ->
        %{
          "spec" => spec_id,
          "implementation_status" => spec["implementation_status"],
          "evidence_status" => spec["evidence_status"],
          "adoption_status" => spec["adoption_status"]
        }
    end
  end

  defp json_request(ref) do
    %{
      "required" => true,
      "description" => "A closed JSON object of at most 4,096 bytes",
      "content" => %{"application/json" => %{"schema" => %{"$ref" => ref}}}
    }
  end

  defp mutation_responses(success, description) do
    replayed = %{
      "Idempotent-Replayed" => %{
        "description" => "Present with the value true when a retained outcome is replayed",
        "schema" => %{"type" => "string", "const" => "true"}
      }
    }

    refusals =
      Map.new(
        [
          {"400", "Malformed request, key or body"},
          {"401", "Bearer token required"},
          {"403", "Mutations disabled, origin refused or session denied"},
          {"404", "Unknown run"},
          {"409", "Room or policy refusal"},
          {"413", "Body exceeds 4,096 bytes"},
          {"415", "Body is not application/json"},
          {"422", "Unadmitted experiment or parameter, or reused key"},
          {"503", "Room unavailable"},
          {"504", "Deadline exceeded"}
        ],
        fn {status, text} ->
          {status, Map.put(json_response(text, "#/components/schemas/Error"), "headers", replayed)}
        end
      )

    limited =
      "Rate or concurrency limit reached"
      |> json_response("#/components/schemas/Error")
      |> Map.put("headers", %{
        "Retry-After" => %{
          "description" => "Seconds until the rate window resets",
          "schema" => %{"type" => "integer", "minimum" => 1}
        }
      })

    refusals
    |> Map.put("429", limited)
    |> Map.put(
      success,
      Map.put(json_response(description, "#/components/schemas/Run"), "headers", replayed)
    )
  end

  defp json_response(description, ref) do
    %{
      "description" => description,
      "content" => %{"application/json" => %{"schema" => %{"$ref" => ref}}}
    }
  end

  defp id_parameter(name, description, pattern) do
    %{
      "name" => name,
      "in" => "path",
      "required" => true,
      "description" => description,
      "schema" => %{"type" => "string", "pattern" => pattern}
    }
  end
end
