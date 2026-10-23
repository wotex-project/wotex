# All reference-room and island-story sample data is authored here.
# Run `mix seed` after editing; runtime reads only the generated JSON.
actuator =
  :wotex_lab
  |> Application.app_dir("priv/fixtures/loopback/thing-description.json")
  |> File.read!()
  |> JSON.decode!()

thermostat = %{
  "@context" => Wotex.td_context_1_1(),
  "id" => "urn:wotex:lab:workbench:thermostat",
  "title" => "Simulated thermostat",
  "security" => ["nosec_sc"],
  "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
  "properties" => %{
    "temperature" => %{
      "type" => "number",
      "unit" => "Cel",
      "readOnly" => true,
      "observable" => true,
      "forms" => [
        %{
          "href" => "sim-thermostat://thermostat/temperature",
          "op" => ["readproperty", "observeproperty", "unobserveproperty"]
        }
      ]
    }
  }
}

meter = %{
  "@context" => Wotex.td_context_1_1(),
  "id" => "urn:wotex:lab:workbench:meter",
  "title" => "Simulated energy meter",
  "security" => ["nosec_sc"],
  "securityDefinitions" => %{"nosec_sc" => %{"scheme" => "nosec"}},
  "properties" => %{
    "power" => %{
      "type" => "number",
      "unit" => "W",
      "readOnly" => true,
      "observable" => true,
      "forms" => [
        %{
          "href" => "sim-meter://meter/power",
          "op" => ["readproperty", "observeproperty", "unobserveproperty"]
        }
      ]
    }
  }
}

room = %{
  "schema" => "wotex-lab-room-seed/v1",
  "things" => [
    %{
      "key" => "thermostat",
      "scheme" => "sim-thermostat",
      "state" => %{"temperature" => 21.5},
      "document" => thermostat
    },
    %{
      "key" => "meter",
      "scheme" => "sim-meter",
      "state" => %{"power" => 2_500.0},
      "document" => meter
    },
    %{
      "key" => "actuator",
      "scheme" => "loopback",
      "state" => %{"temperature" => 20.0, "target" => 21.0},
      "document" => actuator
    }
  ]
}

canvas = %{
  "label" => "Connected Things",
  "nodes" => [
    %{
      "id" => "thing-thermostat",
      "kind" => "thing",
      "title" => "Thermostat",
      "identity" => thermostat["id"],
      "value" => "21.5",
      "unit" => "°C",
      "status" => "Read",
      "detail" => "Storybook sample",
      "x" => 160,
      "y" => 235
    },
    %{
      "id" => "process-smart-room",
      "kind" => "process",
      "title" => "Smart room",
      "identity" => "smart_room",
      "value" => "",
      "unit" => "",
      "status" => "Idle",
      "detail" => "",
      "x" => 520,
      "y" => 365
    }
  ],
  "edges" => [
    %{
      "id" => "temperature",
      "source" => "thing-thermostat",
      "target" => "process-smart-room",
      "label" => "temperature · °C",
      "kind" => "input",
      "target_handle" => "temperature"
    }
  ]
}

chart = %{
  "title" => "Room temperature",
  "series" => [%{"id" => "temperature", "label" => "Temperature °C"}],
  "points" => [
    %{"key" => "one", "label" => "09:00", "values" => %{"temperature" => 20.4}},
    %{"key" => "two", "label" => "10:00", "values" => %{"temperature" => 21.1}},
    %{"key" => "three", "label" => "11:00", "values" => %{"temperature" => 20.8}}
  ]
}

grid = %{
  "label" => "Discovered Things",
  "columns" => [
    %{"key" => "name", "label" => "Thing"},
    %{"key" => "protocol", "label" => "Protocol"}
  ],
  "rows" => [
    %{"key" => "sensor", "values" => %{"name" => "Lab sensor", "protocol" => "CoAP"}},
    %{"key" => "relay", "values" => %{"name" => "Bench relay", "protocol" => "Modbus"}}
  ]
}

tabs = %{
  "label" => "Run evidence",
  "selected" => "metrics",
  "tabs" => [
    %{"id" => "metrics", "label" => "Metrics", "content" => "Bounded measurements"},
    %{"id" => "logs", "label" => "Logs", "content" => "Structured runtime events"},
    %{"id" => "traces", "label" => "Traces", "content" => "Causal operation spans"}
  ]
}

components = %{
  "button" => %{
    "Primary" => %{"label" => "Primary action"},
    "Loading" => %{"label" => "Loading", "loading" => true},
    "Disabled" => %{"label" => "Unavailable", "disabled" => true},
    "Danger" => %{"label" => "Delete", "variant" => "danger"}
  },
  "callout" => %{
    "Note" => %{"title" => "Read this first", "kind" => "note"},
    "Warning" => %{"title" => "Review before continuing", "kind" => "warning"}
  },
  "chart" => %{
    "Populated" => %{
      "title" => "Throughput",
      "series" => [%{"id" => "requests", "label" => "Requests"}],
      "points" => [
        %{"key" => "one", "label" => "09:00", "values" => %{"requests" => 20}},
        %{"key" => "two", "label" => "10:00", "values" => %{"requests" => 48}}
      ]
    },
    "Empty" => %{"title" => "Throughput", "series" => [], "points" => []}
  },
  "checkbox" => %{
    "Checked" => %{
      "id" => "alerts",
      "name" => "alerts",
      "label" => "Send alerts",
      "checked" => true
    }
  },
  "data-grid" => %{
    "Populated" => %{
      "label" => "Records",
      "columns" => [%{"key" => "name", "label" => "Name"}, %{"key" => "state", "label" => "State"}],
      "rows" => [
        %{"key" => "one", "values" => %{"name" => "First", "state" => "Ready"}},
        %{"key" => "two", "values" => %{"name" => "Second", "state" => "Waiting"}}
      ]
    },
    "Empty" => %{"label" => "Records", "columns" => [], "rows" => []}
  },
  "data-table" => %{
    "Populated" => %{
      "caption" => "Example records",
      "columns" => [%{"key" => "name", "label" => "Name"}, %{"key" => "state", "label" => "State"}],
      "rows" => [%{"key" => "one", "values" => %{"name" => "First", "state" => "Ready"}}]
    },
    "Empty" => %{"caption" => "Example records", "columns" => [], "rows" => []}
  },
  "dialog" => %{"Open" => %{"id" => "example-dialog", "title" => "Example dialog", "open" => true}},
  "disclosure" => %{"Open" => %{"summary" => "More information", "open" => true}},
  "field" => %{
    "Default" => %{"id" => "name", "name" => "name", "label" => "Name"},
    "Invalid" => %{
      "id" => "email",
      "name" => "email",
      "label" => "Email",
      "value" => "invalid",
      "error" => "Enter a valid address"
    }
  },
  "filter" => %{
    "Default" => %{
      "legend" => "Filter results",
      "fields" => [
        %{"name" => "query", "label" => "Contains"},
        %{
          "name" => "state",
          "label" => "State",
          "options" => [
            %{"label" => "Any", "value" => ""},
            %{"label" => "Ready", "value" => "ready"}
          ]
        }
      ]
    }
  },
  "icon-button" => %{
    "Default" => %{"label" => "Open search", "icon" => "search"},
    "Disabled" => %{"label" => "Unavailable", "icon" => "close", "disabled" => true}
  },
  "inspector" => %{
    "Open" => %{
      "title" => "Record details",
      "open" => true,
      "fields" => [
        %{"label" => "State", "value" => "Ready"},
        %{"label" => "Owner", "value" => "Example"}
      ]
    }
  },
  "legend" => %{
    "Default" => %{
      "label" => "Series",
      "items" => [%{"id" => "requests", "label" => "Requests", "color" => "#3457d5"}]
    },
    "Empty" => %{"label" => "Series", "items" => []}
  },
  "link" => %{
    "Internal" => %{"href" => "/guide", "label" => "Read the guide"},
    "External" => %{"href" => "https://example.test/docs", "label" => "External documentation"}
  },
  "menu" => %{
    "Open" => %{
      "label" => "Actions",
      "open" => true,
      "items" => [%{"id" => "view", "label" => "View"}, %{"id" => "remove", "label" => "Remove"}]
    }
  },
  "navigation" => %{
    "CurrentPage" => %{
      "label" => "Documentation",
      "current" => "/guide",
      "items" => [
        %{"id" => "home", "title" => "Home", "path" => "/"},
        %{"id" => "guide", "title" => "Guide", "path" => "/guide"}
      ]
    }
  },
  "panel" => %{"Default" => %{"title" => "Summary"}},
  "progress" => %{
    "Determinate" => %{"label" => "Upload progress", "value" => 64},
    "Indeterminate" => %{"label" => "Working"}
  },
  "radio-group" => %{
    "Default" => %{
      "name" => "density",
      "legend" => "Density",
      "value" => "comfortable",
      "options" => [
        %{"label" => "Comfortable", "value" => "comfortable"},
        %{"label" => "Compact", "value" => "compact"}
      ]
    }
  },
  "select" => %{
    "Default" => %{
      "id" => "region",
      "name" => "region",
      "label" => "Region",
      "value" => "eu",
      "options" => [
        %{"label" => "Europe", "value" => "eu"},
        %{"label" => "Americas", "value" => "us"}
      ]
    }
  },
  "state" => %{
    "Disconnected" => %{
      "title" => "Disconnected",
      "message" => "Reconnect to resume.",
      "state" => "disconnected"
    }
  },
  "status-badge" => %{
    "Success" => %{"label" => "Ready", "kind" => "success"},
    "Danger" => %{"label" => "Failed", "kind" => "danger"}
  },
  "tabs" => %{
    "Default" => %{
      "label" => "Example sections",
      "tabs" => [
        %{"id" => "summary", "label" => "Summary", "content" => "Readable summary"},
        %{"id" => "details", "label" => "Details", "content" => "Readable details"}
      ]
    }
  },
  "toast" => %{"Success" => %{"message" => "Changes saved", "kind" => "success"}},
  "tooltip" => %{"Default" => %{"text" => "Additional context"}}
}

%{
  "room" => room,
  "components" => components,
  "islands" => %{
    "canvas" => %{"connected" => canvas, "empty" => %{canvas | "nodes" => [], "edges" => []}},
    "chart" => %{"connected" => chart, "empty" => %{chart | "series" => [], "points" => []}},
    "data-grid" => %{"connected" => grid, "empty" => %{grid | "columns" => [], "rows" => []}},
    "tabs" => %{"connected" => tabs}
  }
}
