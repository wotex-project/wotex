defmodule Wotex.Lab.Graph.Interfaces do
  @moduledoc """
  The OpenAPI 3.2.0 and AsyncAPI 3.1.0 documents derived from the graph.

  The OpenAPI document describes the minimal Lab HTTP control API implemented
  by the optional Workbench host (list scenarios, read an evidence record,
  read the metrics catalogue). The AsyncAPI document is an accepted fixture
  interface, not a running deployment. Neither replaces a Thing Description,
  and both carry explicit deployment status. The dialect versions are pinned
  here and validated by `bin/check_graph.exs`.
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
          "Describes the read-only Lab HTTP control API served by the optional Workbench " <>
            "host under /api/v1. The base library starts no endpoint. Writes and Actions " <>
            "remain outside this surface.",
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
