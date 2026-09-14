    // Test-only control preserves the SDK's real attribute/event implementation.
    if (name == "WotexSetReachable")
    {
        VerifyOrDie(self->mJsonValue.isMember("Reachable") && self->mJsonValue["Reachable"].isBool());
        TempSensor1.SetReachable(self->mJsonValue["Reachable"].asBool());
        ChipLogProgress(NotSpecified, "Wotex reachability control applied");
    }
    else if (name == "SimulateConfigurationVersionChange")
