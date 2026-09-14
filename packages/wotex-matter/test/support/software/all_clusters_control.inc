    // Test-only controls run on the SDK event loop through its named pipe.
    if (name == "WotexSetTemperature")
    {
        const auto & command = self->mJsonValue;
        VerifyOrDie(command.isMember("EndpointId") && command["EndpointId"].isUInt() &&
                    command["EndpointId"].asUInt() <= 0xFFFE);
        const auto endpoint = static_cast<EndpointId>(command["EndpointId"].asUInt());
        VerifyOrDie(command.isMember("LocalTemperature") && command["LocalTemperature"].isInt() &&
                    command["LocalTemperature"].asInt() >= -27315 && command["LocalTemperature"].asInt() <= 32767);
        VerifyOrDie(command.isMember("MeasuredValue"));
        DataModel::Nullable<int16_t> measured;
        if (!command["MeasuredValue"].isNull())
        {
            VerifyOrDie(command["MeasuredValue"].isInt() && command["MeasuredValue"].asInt() >= -27315 &&
                        command["MeasuredValue"].asInt() <= 32767);
            measured.SetNonNull(static_cast<int16_t>(command["MeasuredValue"].asInt()));
        }
        VerifyOrDie(Thermostat::Attributes::LocalTemperature::Set(
                        endpoint, static_cast<int16_t>(command["LocalTemperature"].asInt())) ==
                    Protocols::InteractionModel::Status::Success);
        VerifyOrDie(TemperatureMeasurement::SetMeasuredValue(endpoint, measured) == CHIP_NO_ERROR);
        ChipLogProgress(NotSpecified, "Wotex temperature control applied on endpoint %u", endpoint);
    }
    else if (name == "SoftwareFault")
